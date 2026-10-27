//! Checks that the protocol adapter executes ERC20 actions that consume or create several resources:
//! a wrap for two owners, a merge, a split, and an unwrap of two resources.

mod common;

use alloy::primitives::U256;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::actors::default_signer;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::identities;
use anoma_pa_testkit::witness::ActionWitnesses;
use anomapay_erc20_forwarder_integration_test::deploy::erc20_bindings::erc20_example;
use anomapay_erc20_forwarder_integration_test::fixtures::token::Token;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_anomapay_erc20_e2e;
use common::{execute_tx, prove_actions, setup_anomapay_erc20_local};
use rstest::*;

/// Alice wraps tokens into resources of alice and bob. A merge turns them into one resource of bob,
/// and a split turns that into resources of alice and bob again. An unwrap of both releases the
/// tokens to bob.
#[rstest]
#[case::local(setup_anomapay_erc20_local())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_anomapay_erc20_e2e()))]
#[tokio::test]
async fn execute_splits_and_merges_wrapped_tokens<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let token = Token::new(&env, "example")?;
    let erc20 = erc20_example(token.address(), default_signer(&env)?);
    let alice = identities::alice()?;
    let bob = identities::bob()?;
    let quantity = 10;
    let alice_quantity = 6;
    let bob_quantity = quantity - alice_quantity;

    let alice_balance = erc20.balanceOf(alice.address()).call().await?;
    let bob_balance = erc20.balanceOf(bob.address()).call().await?;
    let forwarder_balance = erc20.balanceOf(token.forwarder()).call().await?;

    let wrap = token
        .wrap(&alice, quantity)
        .split(&bob, bob_quantity)
        .build(&env)
        .context("failed to build the wrap")?;
    prove_and_execute(&mut env, &wrap)
        .await
        .context("failed to prove and execute the wrap")?;
    anyhow::ensure!(
        erc20.balanceOf(token.forwarder()).call().await?
            == forwarder_balance + U256::from(quantity),
        "the wrap pulls the tokens of both created resources into the forwarder"
    );

    let merge = token
        .transfer([(&alice, wrap.resources()[1]), (&bob, wrap.resources()[2])])
        .to(&bob)
        .build(&env)
        .context("failed to build the merge")?;
    prove_and_execute(&mut env, &merge)
        .await
        .context("failed to prove and execute the merge")?;

    let split = token
        .transfer((&bob, merge.resources()[2]))
        .split(&alice, alice_quantity)
        .build(&env)
        .context("failed to build the split")?;
    prove_and_execute(&mut env, &split)
        .await
        .context("failed to prove and execute the split")?;

    let unwrap = token
        .unwrap([(&bob, split.resources()[1]), (&alice, split.resources()[2])])
        .build(&env)
        .context("failed to build the unwrap")?;
    prove_and_execute(&mut env, &unwrap)
        .await
        .context("failed to prove and execute the unwrap")?;

    anyhow::ensure!(
        erc20.balanceOf(alice.address()).call().await? == alice_balance - U256::from(quantity),
        "alice pays the wrapped tokens"
    );
    anyhow::ensure!(
        erc20.balanceOf(bob.address()).call().await? == bob_balance + U256::from(quantity),
        "bob receives the unwrapped tokens"
    );
    anyhow::ensure!(
        erc20.balanceOf(token.forwarder()).call().await? == forwarder_balance,
        "the unwrap releases all tokens of the wrap"
    );

    Ok(())
}

async fn prove_and_execute<Env: Environment>(
    env: &mut Env,
    witnesses: &ActionWitnesses,
) -> anyhow::Result<()> {
    let tx = prove_actions(env, [witnesses]).await?;
    execute_tx(env, tx).await
}
