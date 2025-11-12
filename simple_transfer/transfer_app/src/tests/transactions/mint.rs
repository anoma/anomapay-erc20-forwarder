#![cfg(test)]

use crate::evm::evm_calls::pa_submit_transaction;
use crate::tests::fixtures::{alice_keychain, mint_parameters_example};
use crate::transactions::helpers::TxResult;
use crate::transactions::mint::MintParameters;
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use arm::transaction::Transaction;
use serial_test::serial;

/// Create a mint transaction, and then transfer the resource to another user.
pub async fn create_mint_transaction(
    config: &AnomaPayConfig,
    alice: Keychain,
) -> (MintParameters, TxResult<Transaction>) {
    // Create an example of mint parameters for alice.
    let mint_parameters = mint_parameters_example(alice.clone(), config)
        .await
        .expect("failed to create MintParameters");

    let tx = mint_parameters.generate_transaction().await;
    assert!(tx.is_ok());

    (mint_parameters, tx)
}

/// Create a mint transaction and submit it.
/// These tests have to be serial because the
/// EVM might fail if two transactions are generated at the same time.
pub async fn submit_mint_transaction(
    config: &AnomaPayConfig,
    alice: Keychain,
) -> (MintParameters, TxResult<Transaction>) {
    let (mint_parameters, transaction) = create_mint_transaction(config, alice).await;

    // Submit the transaction
    let submit_result = pa_submit_transaction(transaction.clone().unwrap()).await;
    assert!(submit_result.is_ok());

    (mint_parameters, transaction)
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_create_mint_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);

    let _ = create_mint_transaction(&config, alice).await;
}

/// Create a mint transaction and submit it.
/// These tests have to be serial because the
/// EVM might fail if two transactions are generated at the same time.
#[tokio::test]
#[serial(submit_evm)]
async fn test_submit_mint_transaction() {
    let config = load_config().expect("failed to load config in test");
    // create a keychain with a private key
    let alice = alice_keychain(&config);

    let _ = submit_mint_transaction(&config, alice).await;
}
