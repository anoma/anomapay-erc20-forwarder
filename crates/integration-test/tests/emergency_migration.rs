//! Checks the draft emergency migrating ERC20 forwarder after the emergency upgrade: the protocol adapter executes
//! wraps, transfers and unwraps of emergency migrating resources, and the emergency migration of resources with a
//! vulnerable logic ref.

mod common;

use alloy::primitives::{B256, keccak256};
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::actors::default_signer;
use anoma_pa_evm_integration_test::state::chains::chain_id;
use anoma_pa_evm_integration_test::state::pa::pa_address;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::action;
use anoma_pa_testkit::fixtures::identities::{self, Keychain};
use anoma_pa_testkit::witness::ActionWitnesses;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_forwarder_bindings::generated::emergency_migrating_erc20_forwarder::EmergencyMigratingERC20Forwarder;
use anomapay_erc20_forwarder_integration_test::deploy::emergency_migrating_forwarder::upgrade_to_emergency_migrating_erc20_forwarder;
use anomapay_erc20_forwarder_integration_test::fixtures::emergency_migrating::{
    ephemeral, migrate, persistent,
};
use anomapay_erc20_forwarder_integration_test::fixtures::token::Token;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_anomapay_erc20_e2e;
use common::{commitment_path, execute_tx, prove_actions, setup_anomapay_erc20_local};
use rstest::*;

/// Upgrades the forwarder of `token` to the emergency migrating forwarder.
async fn upgrade<Env: Environment>(env: &Env, token: &Token) -> anyhow::Result<()> {
    upgrade_to_emergency_migrating_erc20_forwarder(
        default_signer(env)?,
        identities::alice()?.address(),
        pa_address(env)?,
        token.forwarder(),
    )
    .await
}

/// Proves and executes `action`.
async fn execute<Env: Environment>(env: &mut Env, action: &ActionWitnesses) -> anyhow::Result<()> {
    let tx = prove_actions(env, [action]).await?;
    execute_tx(env, tx).await
}

/// Wraps `quantity` tokens of `owner` into an emergency migrating resource.
async fn wrap<Env: Environment>(
    env: &mut Env,
    token: &Token,
    owner: &Keychain,
    quantity: u128,
) -> anyhow::Result<ActionWitnesses> {
    let wrap = action::build([
        ephemeral::consumed(
            owner,
            chain_id(env)?,
            token.forwarder(),
            token.address(),
            quantity,
            token.next_wrap_nonce(),
        ),
        persistent::created(owner, token.forwarder(), token.address(), quantity),
    ])?;
    execute(env, &wrap)
        .await
        .context("failed to execute the wrap")?;
    Ok(wrap)
}

/// Unwraps the emergency migrating resource `wrapped` of `owner` to the owner's account.
async fn unwrap<Env: Environment>(
    env: &mut Env,
    token: &Token,
    owner: &Keychain,
    wrapped: Resource,
) -> anyhow::Result<()> {
    let unwrap = action::build([
        persistent::consumed(owner, wrapped, commitment_path(env, wrapped.commitment())?),
        ephemeral::created(
            owner.address(),
            token.forwarder(),
            token.address(),
            wrapped.quantity,
        ),
    ])?;
    execute(env, &unwrap)
        .await
        .context("failed to execute the unwrap")
}

#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn execute_wraps_and_unwraps_tokens_after_the_emergency_upgrade<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let token = Token::new(&env, "example")?;
    let alice = identities::alice()?;
    upgrade(&env, &token).await?;

    let wrap = wrap(&mut env, &token, &alice, 1).await?;
    unwrap(&mut env, &token, &alice, wrap.resources()[1]).await
}

#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn execute_transfers_tokens_after_the_emergency_upgrade<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let token = Token::new(&env, "example")?;
    let alice = identities::alice()?;
    let bob = identities::bob()?;
    upgrade(&env, &token).await?;

    let wrapped = wrap(&mut env, &token, &alice, 1).await?.resources()[1];
    let transfer = action::build([
        persistent::consumed(
            &alice,
            wrapped,
            commitment_path(&env, wrapped.commitment())?,
        ),
        persistent::created(&bob, token.forwarder(), token.address(), wrapped.quantity),
    ])?;
    execute(&mut env, &transfer)
        .await
        .context("failed to execute the transfer")?;

    unwrap(&mut env, &token, &bob, transfer.resources()[1]).await
}

/// Alice wraps twice under the ERC20 logic ref, which the emergency upgrade makes a vulnerable logic ref. She then
/// migrates both resources to bob in one action, and bob unwraps the migrated tokens.
#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn execute_migrates_resources_of_a_vulnerable_logic_ref<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let token = Token::new(&env, "example")?;
    let alice = identities::alice()?;
    let bob = identities::bob()?;

    let mut vulnerable = Vec::new();
    for _ in 0..2 {
        let wrap = token
            .wrap(&alice, 1)
            .build(&env)
            .context("failed to build a wrap under the ERC20 logic ref")?;
        execute(&mut env, &wrap)
            .await
            .context("failed to execute a wrap under the ERC20 logic ref")?;
        vulnerable.push(wrap.resources()[1]);
    }
    upgrade(&env, &token).await?;

    let paths = vulnerable
        .iter()
        .map(|resource| commitment_path(&env, resource.commitment()))
        .collect::<anyhow::Result<Vec<_>>>()?;
    let migrate = action::build([
        migrate::consumed(
            &alice,
            token.forwarder(),
            token.address(),
            vulnerable.iter().copied().zip(paths).collect(),
            keccak256([token.address().as_slice(), b"emergency migrate"].concat()).0,
        ),
        persistent::created(
            &bob,
            token.forwarder(),
            token.address(),
            vulnerable.iter().map(|resource| resource.quantity).sum(),
        ),
    ])?;
    execute(&mut env, &migrate)
        .await
        .context("failed to execute the migration")?;

    let forwarder = EmergencyMigratingERC20Forwarder::new(token.forwarder(), default_signer(&env)?);
    for resource in &vulnerable {
        let nullifier = B256::from(<[u8; 32]>::from(resource.nullifier(&alice.nf_key)?));
        anyhow::ensure!(
            forwarder.isNullifierMigrated(nullifier).call().await?,
            "the forwarder records the nullifier {nullifier} as migrated"
        );
    }

    unwrap(&mut env, &token, &bob, migrate.resources()[1]).await
}
