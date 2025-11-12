#![cfg(test)]

use crate::evm::evm_calls::pa_submit_transaction;
use crate::tests::fixtures::{alice_keychain, bob_keychain, burn_parameters_example};
use crate::tests::transactions::mint::submit_mint_transaction;
use crate::tests::transactions::split::submit_split_transaction_for;
use crate::transactions::burn::{BurnParameters, BurnResult};
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use arm::resource::Resource;
use arm::transaction::Transaction;
use serial_test::serial;

pub async fn create_burn_transaction(
    config: &AnomaPayConfig,
    alice: Keychain,
) -> (BurnParameters, BurnResult<Transaction>) {
    // Create a mint transaction and submit it to have a resource to transfer.
    let (mint_parameters, _transaction) = submit_mint_transaction(config, alice.clone()).await;

    // Transfer the minted resource to bob.
    let burn_parameters =
        burn_parameters_example(alice.clone(), config, mint_parameters.created_resource)
            .await
            .expect("failed to create BurnParameters");

    let transaction = burn_parameters.generate_transaction(config).await;
    println!("{:?}", transaction);
    assert!(transaction.is_ok());

    (burn_parameters, transaction)
}

pub async fn create_burn_transaction_for(
    config: &AnomaPayConfig,
    alice: Keychain,
    to_burn: Resource,
) -> (BurnParameters, BurnResult<Transaction>) {
    // Create a mint transaction and submit it to have a resource to transfer.

    // Transfer the minted resource to bob.
    let burn_parameters = burn_parameters_example(alice.clone(), config, to_burn)
        .await
        .expect("failed to create BurnParameters");

    let transaction = burn_parameters.generate_transaction(config).await;
    println!("{:?}", transaction);
    assert!(transaction.is_ok());

    (burn_parameters, transaction)
}

pub async fn submit_burn_transaction_for(
    config: &AnomaPayConfig,
    alice: Keychain,
    to_burn: Resource,
) -> (BurnParameters, BurnResult<Transaction>) {
    let (burn_parameters, transaction) = create_burn_transaction_for(config, alice, to_burn).await;

    // Submit the transaction
    let submit_result = pa_submit_transaction(transaction.clone().unwrap()).await;
    assert!(submit_result.is_ok());

    (burn_parameters, transaction)
}

/// Create a burn transaction and submit it.
async fn submit_burn_transaction(
    config: &AnomaPayConfig,
    alice: Keychain,
) -> (BurnParameters, BurnResult<Transaction>) {
    let (burn_parameters, transaction) = create_burn_transaction(config, alice).await;

    // Submit the transaction
    let submit_result = pa_submit_transaction(transaction.clone().unwrap()).await;
    assert!(submit_result.is_ok());

    (burn_parameters, transaction)
}

/// Creates a mint, a split, and then burns for both alice and bob.
async fn submit_mint_split_burn_transactions(
    config: &AnomaPayConfig,
    alice: Keychain,
    bob: Keychain,
) -> (BurnParameters, BurnResult<Transaction>) {
    // create a mint for Alice.
    // Alice has 2.
    let (mint_parameters, _transaction) = submit_mint_transaction(config, alice.clone()).await;

    // Split alice's resource to herself and bob.
    // Alice has 1, Bob has 1.
    let (split_parameters, _transaction) =
        submit_split_transaction_for(config, alice.clone(), bob, mint_parameters.created_resource)
            .await;

    // Burn the token from Alice.
    // Alice has 0, bob has 1.
    let (burn_parameters, transaction) =
        submit_burn_transaction_for(config, alice.clone(), split_parameters.remainder_resource)
            .await;

    (burn_parameters, transaction)
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_create_burn_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);

    let _ = create_burn_transaction(&config, alice).await;
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_submit_burn_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);

    let _ = submit_burn_transaction(&config, alice).await;
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_submit_mint_split_burn_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);
    let bob = bob_keychain();

    let _ = submit_mint_split_burn_transactions(&config, alice, bob).await;
}
