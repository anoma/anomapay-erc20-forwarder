#![cfg(test)]

use crate::evm::evm_calls::pa_submit_transaction;
use crate::tests::fixtures::{alice_keychain, bob_keychain, split_parameters_example};
use crate::tests::transactions::mint::submit_mint_transaction;
use crate::transactions::split::{SplitParameters, SplitResult};
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use arm::resource::Resource;
use arm::transaction::Transaction;
use serial_test::serial;

/// Generates a split transaction for the given resource.
pub async fn create_split_transaction_for(
    config: &AnomaPayConfig,
    alice: Keychain,
    _bob: Keychain,
    to_split: Resource,
) -> (SplitParameters, SplitResult<Transaction>) {
    // The receiver is bob
    let bob = bob_keychain();

    // Transfer the minted resource to bob.
    let split_parameters = split_parameters_example(alice.clone(), bob.clone(), config, to_split)
        .await
        .expect("failed to create SplitParameters");

    let transaction = split_parameters.generate_transaction(config).await;
    println!("{:?}", transaction);
    assert!(transaction.is_ok());

    (split_parameters, transaction)
}

/// Generates a split transaction, but mints first to create the resource to be splitted instead.
pub async fn create_split_transaction(
    config: &AnomaPayConfig,
    alice: Keychain,
    bob: Keychain,
) -> (SplitParameters, SplitResult<Transaction>) {
    // Create a mint transaction and submit it to have a resource to transfer.
    let (mint_parameters, _transaction) = submit_mint_transaction(config, alice.clone()).await;

    create_split_transaction_for(config, alice, bob, mint_parameters.created_resource).await
}

/// Create a split transaction and submit it.
pub async fn submit_split_transaction(
    config: &AnomaPayConfig,
    alice: Keychain,
    bob: Keychain,
) -> (SplitParameters, SplitResult<Transaction>) {
    let (split_parameters, transaction) = create_split_transaction(config, alice, bob).await;

    // Submit the transaction
    let submit_result = pa_submit_transaction(transaction.clone().unwrap()).await;
    assert!(submit_result.is_ok());

    (split_parameters, transaction)
}

/// Create a split transaction for the given resource and submits it.
pub async fn submit_split_transaction_for(
    config: &AnomaPayConfig,
    alice: Keychain,
    bob: Keychain,
    to_split: Resource,
) -> (SplitParameters, SplitResult<Transaction>) {
    let (split_parameters, transaction) =
        create_split_transaction_for(config, alice, bob, to_split).await;

    // Submit the transaction
    let submit_result = pa_submit_transaction(transaction.clone().unwrap()).await;
    assert!(submit_result.is_ok());

    (split_parameters, transaction)
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_create_split_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);
    let bob = bob_keychain();

    let _ = create_split_transaction(&config, alice, bob).await;
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_submit_split_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);
    let bob = bob_keychain();

    let _ = submit_split_transaction(&config, alice, bob).await;
}
