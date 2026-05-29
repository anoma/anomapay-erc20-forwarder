mod common;

use anoma_pa_evm_integration_test::state::chains::chain_id;
use anoma_pa_testkit::assert::{Needle, expect_integration_panic};
use anoma_pa_testkit::environment::CommitmentTree;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::environment::ProtocolAdapter;
use anoma_pa_testkit::fixtures::identities;
use anomapay_erc20_forwarder_integration_test::fixtures::{transfer, unwrap, wrap};
use anomapay_erc20_forwarder_integration_test::state::erc20::addresses::erc20_address;
use anomapay_erc20_forwarder_integration_test::state::forwarder::addresses::erc20_forwarder_v1_address;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_anomapay_erc20_e2e;
use common::{commitment_root, execute_tx, prove_actions, setup_anomapay_erc20_local};
use rstest::*;

#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn happy_wrap_transfer_unwrap<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_v1_address(&env)?;
    let token = erc20_address(&env, "example")?;

    let before = commitment_root(&env)?;

    let wrap = wrap::build(
        chain_id,
        forwarder,
        token,
        1,
        11,
        wrap::Overrides::default(),
    )
    .await
    .context("failed to build wrap action")?;
    let tx = prove_actions(&env, &[wrap.witnesses])
        .await
        .context("failed to prove wrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute wrap action")?;

    let transfer_path = env
        .protocol_adapter()
        .commitment_tree()
        .path_to(wrap.created_persistent.commitment())
        .context("failed to generate transfer merkle path")?;

    let transfer = transfer::build(
        wrap.created_persistent,
        forwarder,
        token,
        17,
        Some(transfer_path),
        transfer::Overrides::default(),
    )
    .context("failed to build transfer action")?;
    let tx = prove_actions(&env, &[transfer.witnesses])
        .await
        .context("failed to prove transfer action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute transfer action")?;

    let unwrap_path = env
        .protocol_adapter()
        .commitment_tree()
        .path_to(transfer.created_persistent.commitment())
        .context("failed to generate unwrap merkle path")?;

    let unwrap = unwrap::build(
        transfer.created_persistent,
        forwarder,
        token,
        21,
        Some(unwrap_path),
        unwrap::Overrides::default(),
    )
    .context("failed to build unwrap action")?;
    let tx = prove_actions(&env, &[unwrap.witnesses])
        .await
        .context("failed to prove unwrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute unwrap action")?;

    let after = commitment_root(&env)?;
    anyhow::ensure!(before != after, "commitment tree root must change");

    Ok(())
}

// Ports `transfer_web::tests::e2e::{v1,v2}::test_wrap_unwrap`: the same identity
// wraps and then directly unwraps, without an intermediate transfer.
#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn happy_wrap_unwrap<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_v1_address(&env)?;
    let token = erc20_address(&env, "example")?;

    let before = commitment_root(&env)?;

    let wrap = wrap::build(
        chain_id,
        forwarder,
        token,
        1,
        41,
        wrap::Overrides::default(),
    )
    .await
    .context("failed to build wrap action")?;
    let tx = prove_actions(&env, &[wrap.witnesses])
        .await
        .context("failed to prove wrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute wrap action")?;

    let unwrap_path = env
        .protocol_adapter()
        .commitment_tree()
        .path_to(wrap.created_persistent.commitment())
        .context("failed to generate unwrap merkle path")?;

    // Unwrap as the original wrapper (same owner), mirroring the source test.
    let unwrap = unwrap::build(
        wrap.created_persistent,
        forwarder,
        token,
        47,
        Some(unwrap_path),
        unwrap::Overrides {
            owner: Some(identities::alice()?),
            ..Default::default()
        },
    )
    .context("failed to build unwrap action")?;
    let tx = prove_actions(&env, &[unwrap.witnesses])
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
async fn transfer_negative_invalid_permit_signature_len<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
    #[case] assert_err: impl FnOnce(anyhow::Result<Env::Transaction>) -> anyhow::Result<()>,
) -> anyhow::Result<()> {
    let env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_v1_address(&env)?;
    let token = erc20_address(&env, "example")?;

    let bad = wrap::build(
        chain_id,
        forwarder,
        token,
        1,
        23,
        wrap::Overrides::invalid_permit_signature_length(),
    )
    .await
    .context("failed to build invalid wrap action")?;

    assert_err(prove_actions(&env, &[bad.witnesses]).await)
}

#[rstest]
#[case::local(
    setup_anomapay_erc20_local(),
    expect_integration_panic(Needle::Static("Invalid signature"))
)]
#[tokio::test]
async fn transfer_negative_invalid_auth_signature<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
    #[case] assert_err: impl FnOnce(anyhow::Result<Env::Transaction>) -> anyhow::Result<()>,
) -> anyhow::Result<()> {
    let env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let forwarder = erc20_forwarder_v1_address(&env)?;
    let token = erc20_address(&env, "example")?;

    let wrap = wrap::build(
        chain_id,
        forwarder,
        token,
        1,
        31,
        wrap::Overrides::default(),
    )
    .await
    .context("failed to build wrap action")?;

    let bad = transfer::build(
        wrap.created_persistent,
        forwarder,
        token,
        37,
        None,
        transfer::Overrides::invalid_auth_signature(),
    )
    .context("failed to build invalid transfer action")?;

    assert_err(prove_actions(&env, &[bad.witnesses]).await)
}
