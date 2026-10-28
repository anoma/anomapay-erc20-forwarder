//! Checks that the protocol adapter runs the forwarder calls of an action in the order of its resources, so that a
//! wrap can pull the tokens that an unwrap before it in the list releases.

mod common;

use alloy::primitives::U256;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::actors::default_signer;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::action::{self, ActionResource};
use anoma_pa_testkit::fixtures::identities::{self, Keychain};
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_forwarder_integration_test::deploy::erc20_bindings::erc20_example;
use anomapay_erc20_forwarder_integration_test::fixtures::token::Token;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_anomapay_erc20_e2e;
use common::{commitment_root, execute_tx, prove_actions, setup_anomapay_erc20_local};
use rstest::*;

/// The owner wraps its whole balance first, so the wrap of the action can only pull the tokens that the unwrap of the
/// same action releases.
#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn execute_runs_the_forwarder_calls_in_the_order_of_the_resources<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let token = Token::new(&env, "example")?;
    let owner = identities::alice()?;
    let erc20 = erc20_example(token.address(), default_signer(&env)?);

    let balance = erc20
        .balanceOf(owner.address())
        .call()
        .await
        .context("failed to read the balance of the owner")?;
    let quantity = u128::try_from(balance).context("the balance of the owner exceeds u128")?;
    let wrap = token
        .wrap(&owner, quantity)
        .build(&env)
        .context("failed to build the first wrap action")?;
    let wrapped = wrap.resources()[1];
    let tx = prove_actions(&env, [&wrap])
        .await
        .context("failed to prove the first wrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute the first wrap action")?;
    anyhow::ensure!(
        erc20.balanceOf(owner.address()).call().await? == U256::ZERO,
        "the owner holds no tokens after the first wrap"
    );

    let wrap_first = prove_unwrap_and_wrap(&env, &token, &owner, wrapped, quantity, false).await?;
    let Err(error) = execute_tx(&mut env, wrap_first).await else {
        anyhow::bail!("the wrap must not pull tokens before the unwrap releases them");
    };
    anyhow::ensure!(
        format!("{error:#}").contains("TRANSFER_FROM_FAILED"),
        "with the wrap first in the list, Permit2 finds no tokens: {error:#}"
    );

    let before = commitment_root(&env)?;
    let unwrap_first = prove_unwrap_and_wrap(&env, &token, &owner, wrapped, quantity, true).await?;
    execute_tx(&mut env, unwrap_first)
        .await
        .context("failed to execute the action with the unwrap first")?;
    anyhow::ensure!(
        commitment_root(&env)? != before,
        "the action with the unwrap first adds its commitments"
    );

    anyhow::ensure!(
        erc20.balanceOf(owner.address()).call().await? == U256::ZERO,
        "the wrap pulls the tokens that the unwrap releases"
    );
    anyhow::ensure!(
        erc20.balanceOf(token.forwarder()).call().await? == U256::from(quantity),
        "the forwarder holds the tokens of the wrap"
    );

    Ok(())
}

/// Proves one action that unwraps `resource` to `owner` and wraps `quantity` tokens of `owner`. The created resource
/// of the unwrap comes before the consumed resource of the wrap exactly if `unwrap_first`.
async fn prove_unwrap_and_wrap<Env: Environment>(
    env: &Env,
    token: &Token,
    owner: &Keychain,
    resource: Resource,
    quantity: u128,
    unwrap_first: bool,
) -> anyhow::Result<Env::Transaction> {
    let [unwrap_consumed, unwrap_created] =
        two_resources(token.unwrap((owner, resource)).resources(env)?)
            .context("the unwrap of one resource has two resources")?;
    let [wrap_consumed, wrap_created] = two_resources(token.wrap(owner, quantity).resources(env)?)
        .context("a wrap without splits has two resources")?;

    let resources = if unwrap_first {
        [unwrap_consumed, unwrap_created, wrap_consumed, wrap_created]
    } else {
        [unwrap_consumed, wrap_consumed, unwrap_created, wrap_created]
    };
    let witnesses = action::build(resources).context("failed to build the action")?;

    prove_actions(env, [&witnesses])
        .await
        .context("failed to prove the action")
}

fn two_resources(resources: Vec<ActionResource>) -> Option<[ActionResource; 2]> {
    resources.try_into().ok()
}
