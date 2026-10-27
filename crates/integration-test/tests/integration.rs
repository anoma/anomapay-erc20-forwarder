mod common;

use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::chains::chain_id;
use anoma_pa_testkit::assert::{Needle, expect_integration_panic};
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::{action, identities};
use anoma_rm_risc0::merkle_path::MerklePath;
use anomapay_erc20_forwarder_integration_test::fixtures::{ephemeral, persistent};
use anomapay_erc20_forwarder_integration_test::state::erc20::erc20_address;
use anomapay_erc20_forwarder_integration_test::state::forwarder::erc20_forwarder_address;
use anomapay_erc20_witness::AUTH_SIGNATURE_DOMAIN;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_anomapay_erc20_e2e;
use common::{
    commitment_path, commitment_root, execute_tx, prove_actions, setup_anomapay_erc20_local,
};
use rstest::*;

#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn execute_wraps_transfers_and_unwraps_tokens<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_address(&env)?;
    let token = erc20_address(&env, "example")?;
    let alice = identities::alice()?;
    let bob = identities::bob()?;
    let quantity = 1;

    let before = commitment_root(&env)?;

    let wrap = action::build([
        ephemeral::consumed(
            &alice,
            chain_id,
            forwarder,
            token,
            quantity,
            [11; 32],
            ephemeral::Overrides::default(),
        ),
        persistent::created(&alice, forwarder, token, quantity, 12),
    ])
    .context("failed to build wrap action")?;
    let tx = prove_actions(&env, [&wrap])
        .await
        .context("failed to prove wrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute wrap action")?;

    let wrapped = wrap.resources()[1];
    let transfer_path = commitment_path(&env, wrapped.commitment())
        .context("failed to generate transfer merkle path")?;

    let transfer = action::build([
        persistent::consumed(&alice, wrapped, transfer_path, None),
        persistent::created(&bob, forwarder, token, wrapped.quantity, 17),
    ])
    .context("failed to build transfer action")?;
    let tx = prove_actions(&env, [&transfer])
        .await
        .context("failed to prove transfer action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute transfer action")?;

    let transferred = transfer.resources()[1];
    let unwrap_path = commitment_path(&env, transferred.commitment())
        .context("failed to generate unwrap merkle path")?;

    let unwrap = action::build([
        persistent::consumed(&bob, transferred, unwrap_path, None),
        ephemeral::created(bob.address(), forwarder, token, transferred.quantity, 21),
    ])
    .context("failed to build unwrap action")?;
    let tx = prove_actions(&env, [&unwrap])
        .await
        .context("failed to prove unwrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute unwrap action")?;

    let after = commitment_root(&env)?;
    anyhow::ensure!(before != after, "commitment tree root must change");

    Ok(())
}

/// The owner of the wrap unwraps without a transfer.
#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn execute_wraps_and_unwraps_tokens<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_address(&env)?;
    let token = erc20_address(&env, "example")?;
    let alice = identities::alice()?;
    let quantity = 1;

    let before = commitment_root(&env)?;

    let wrap = action::build([
        ephemeral::consumed(
            &alice,
            chain_id,
            forwarder,
            token,
            quantity,
            [41; 32],
            ephemeral::Overrides::default(),
        ),
        persistent::created(&alice, forwarder, token, quantity, 42),
    ])
    .context("failed to build wrap action")?;
    let tx = prove_actions(&env, [&wrap])
        .await
        .context("failed to prove wrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute wrap action")?;

    let wrapped = wrap.resources()[1];
    let unwrap_path = commitment_path(&env, wrapped.commitment())
        .context("failed to generate unwrap merkle path")?;

    let unwrap = action::build([
        persistent::consumed(&alice, wrapped, unwrap_path, None),
        ephemeral::created(alice.address(), forwarder, token, wrapped.quantity, 47),
    ])
    .context("failed to build unwrap action")?;
    let tx = prove_actions(&env, [&unwrap])
        .await
        .context("failed to prove unwrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute unwrap action")?;

    let after = commitment_root(&env)?;
    anyhow::ensure!(before != after, "commitment tree root must change");

    Ok(())
}

#[rstest]
#[case::local(
    setup_anomapay_erc20_local(),
    expect_integration_panic(Needle::Static("Signature must be 65 bytes long"))
)]
#[tokio::test]
async fn prove_actions_errors_on_a_short_permit_signature<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
    #[case] assert_err: impl FnOnce(anyhow::Result<Env::Transaction>) -> anyhow::Result<()>,
) -> anyhow::Result<()> {
    let env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_address(&env)?;
    let token = erc20_address(&env, "example")?;
    let alice = identities::alice()?;
    let quantity = 1;

    let bad = action::build([
        ephemeral::consumed(
            &alice,
            chain_id,
            forwarder,
            token,
            quantity,
            [23; 32],
            ephemeral::Overrides::invalid_permit_signature_length(),
        ),
        persistent::created(&alice, forwarder, token, quantity, 24),
    ])
    .context("failed to build invalid wrap action")?;

    assert_err(prove_actions(&env, [&bad]).await)
}

#[rstest]
#[case::local(
    setup_anomapay_erc20_local(),
    expect_integration_panic(Needle::Static("Invalid signature"))
)]
#[tokio::test]
async fn prove_actions_errors_on_an_auth_signature_over_another_message<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
    #[case] assert_err: impl FnOnce(anyhow::Result<Env::Transaction>) -> anyhow::Result<()>,
) -> anyhow::Result<()> {
    let env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_address(&env)?;
    let token = erc20_address(&env, "example")?;
    let alice = identities::alice()?;
    let bob = identities::bob()?;
    let quantity = 1;

    let wrap = action::build([
        ephemeral::consumed(
            &alice,
            chain_id,
            forwarder,
            token,
            quantity,
            [31; 32],
            ephemeral::Overrides::default(),
        ),
        persistent::created(&alice, forwarder, token, quantity, 32),
    ])
    .context("failed to build wrap action")?;
    let wrapped = wrap.resources()[1];

    // The owner signs another message than the action tree root.
    let auth_signature = alice.auth_signing_key.sign(AUTH_SIGNATURE_DOMAIN, &[0; 32]);
    let bad = action::build([
        persistent::consumed(&alice, wrapped, MerklePath::empty(), Some(auth_signature)),
        persistent::created(&bob, forwarder, token, wrapped.quantity, 37),
    ])
    .context("failed to build invalid transfer action")?;

    assert_err(prove_actions(&env, [&bad]).await)
}
