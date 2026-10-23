//! Checks that the order constraints of the forwarder calls let a wrap pull the tokens that an unwrap of the same
//! transaction releases.

mod common;

use alloy::primitives::U256;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::actors::default_signer;
use anoma_pa_evm_integration_test::state::chains::chain_id;
use anoma_pa_testkit::environment::CommitmentTree;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::environment::ProtocolAdapter;
use anoma_pa_testkit::fixtures::identities;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_forwarder_integration_test::deploy::erc20_bindings::erc20_example;
use anomapay_erc20_forwarder_integration_test::fixtures::{unwrap, wrap};
use anomapay_erc20_forwarder_integration_test::state::erc20::erc20_address;
use anomapay_erc20_forwarder_integration_test::state::forwarder::erc20_forwarder_address;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_anomapay_erc20_e2e;
use common::{commitment_root, execute_tx, prove_actions, setup_anomapay_erc20_local};
use rstest::*;

/// The owner wraps its whole balance first, so the second wrap can only pull the tokens that the unwrap releases.
#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn execute_runs_a_wrap_after_the_unwrap_that_its_after_tags_name<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_address(&env)?;
    let token = erc20_address(&env, "example")?;
    let owner = identities::alice()?.address();
    let erc20 = erc20_example(token, default_signer(&env)?);

    let balance = erc20
        .balanceOf(owner)
        .call()
        .await
        .context("failed to read the balance of the owner")?;
    let quantity = u128::try_from(balance).context("the balance of the owner exceeds u128")?;
    let wrap = wrap::build(
        chain_id,
        forwarder,
        token,
        quantity,
        41,
        wrap::Overrides::default(),
    )
    .context("failed to build the first wrap action")?;
    let tx = prove_actions(&env, &[wrap.witnesses])
        .await
        .context("failed to prove the first wrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute the first wrap action")?;
    anyhow::ensure!(
        erc20.balanceOf(owner).call().await? == U256::ZERO,
        "the owner holds no tokens after the first wrap"
    );

    let unordered =
        prove_wrap_before_unwrap(&env, wrap.created_persistent, quantity, false).await?;
    let Err(error) = execute_tx(&mut env, unordered).await else {
        anyhow::bail!("the wrap must not pull tokens before the unwrap releases them");
    };
    anyhow::ensure!(
        format!("{error:#}").contains("TRANSFER_FROM_FAILED"),
        "without the constraint, the wrap runs first and Permit2 finds no tokens: {error:#}"
    );

    let before = commitment_root(&env)?;
    let ordered = prove_wrap_before_unwrap(&env, wrap.created_persistent, quantity, true).await?;
    execute_tx(&mut env, ordered)
        .await
        .context("failed to execute the wrap and the unwrap with the constraint")?;
    anyhow::ensure!(
        commitment_root(&env)? != before,
        "the transaction with the constraint adds its commitments"
    );

    anyhow::ensure!(
        erc20.balanceOf(owner).call().await? == U256::ZERO,
        "the second wrap pulls the tokens that the unwrap releases"
    );
    anyhow::ensure!(
        erc20.balanceOf(forwarder).call().await? == U256::from(quantity),
        "the forwarder holds the tokens of the second wrap"
    );

    Ok(())
}

/// Proves one transaction that lists a wrap of `quantity` tokens before the unwrap of `resource` to its owner. If
/// `ordered`, the wrap names the unwrap in its `after_tags`.
async fn prove_wrap_before_unwrap<Env: Environment>(
    env: &Env,
    resource: Resource,
    quantity: u128,
    ordered: bool,
) -> anyhow::Result<Env::Transaction> {
    let chain_id = chain_id(env)?;
    let forwarder = erc20_forwarder_address(env)?;
    let token = erc20_address(env, "example")?;

    let path = env
        .protocol_adapter()
        .commitment_tree()
        .path_to(resource.commitment())
        .context("failed to generate the unwrap merkle path")?;
    let unwrap = unwrap::build(
        resource,
        forwarder,
        token,
        47,
        Some(path),
        unwrap::Overrides {
            owner: Some(identities::alice()?),
            ..Default::default()
        },
    )
    .context("failed to build the unwrap action")?;

    let after_tags = if ordered {
        vec![unwrap.created_ephemeral.commitment()]
    } else {
        Vec::new()
    };
    let wrap = wrap::build(
        chain_id,
        forwarder,
        token,
        quantity,
        43,
        wrap::Overrides {
            after_tags,
            ..Default::default()
        },
    )
    .context("failed to build the second wrap action")?;

    prove_actions(env, &[wrap.witnesses, unwrap.witnesses])
        .await
        .context("failed to prove the wrap and the unwrap")
}
