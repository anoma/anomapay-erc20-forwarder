#![cfg(test)]

use crate::evm::evm_calls::pa_submit_transaction;
use crate::tests::fixtures::{alice_keychain, bob_keychain, transfer_parameters_example};
use crate::tests::transactions::mint::submit_mint_transaction;
use crate::transactions::transfer::{TransferParameters, TransferResult};
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use arm::transaction::Transaction;
use serial_test::serial;

/// Create a mint transaction, and then transfer the resource to another user.
async fn create_transfer_transaction(
    config: &AnomaPayConfig,
    alice: Keychain,
    bob: Keychain,
) -> (TransferParameters, TransferResult<Transaction>) {
    // Create a mint transaction and submit it to have a resource to transfer.
    let (mint_parameters, _transaction) = submit_mint_transaction(config, alice.clone()).await;

    // Transfer the minted resource to bob.
    let transfer_parameters = transfer_parameters_example(
        alice.clone(),
        bob.clone(),
        config,
        mint_parameters.created_resource,
    )
    .await;

    let transaction = transfer_parameters.generate_transaction(config).await;
    println!("{:?}", transaction);
    assert!(transaction.is_ok());

    (transfer_parameters, transaction)
}

/// Create a transfer transaction and submit it.
async fn submit_transfer_transaction(
    config: &AnomaPayConfig,
    alice: Keychain,
    bob: Keychain,
) -> (TransferParameters, TransferResult<Transaction>) {
    let (transfer_parameters, transaction) = create_transfer_transaction(config, alice, bob).await;

    // Submit the transaction
    let submit_result = pa_submit_transaction(transaction.clone().unwrap()).await;
    assert!(submit_result.is_ok());

    (transfer_parameters, transaction)
}

#[tokio::test]
#[serial]
async fn test_create_transfer_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);
    let bob = bob_keychain();
    let _ = create_transfer_transaction(&config, alice, bob).await;
}

#[tokio::test]
#[serial]
async fn test_submit_transfer_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);
    let bob = bob_keychain();
    let _ = submit_transfer_transaction(&config, alice, bob).await;
}
