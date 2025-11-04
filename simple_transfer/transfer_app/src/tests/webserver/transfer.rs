#![cfg(test)]

use crate::requests::transfer::{handle_transfer_request, TransferRequest};
use crate::requests::Expand;
use crate::tests::fixtures::{alice_keychain, bob_keychain, transfer_parameters_example};
use crate::tests::transactions::mint::submit_mint_transaction;
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use serial_test::serial;

pub async fn create_transfer_request(
    config: &AnomaPayConfig,
    alice: Keychain,
    bob: Keychain,
) -> TransferRequest {
    // To create a transfer request, we need to mint for alice first.
    let (mint_parameters, _transaction) = submit_mint_transaction(config, alice.clone()).await;

    let x = transfer_parameters_example(
        alice.clone(),
        bob.clone(),
        config,
        mint_parameters.created_resource,
    )
    .await
    .expect("failed to create SplitParameters");

    TransferRequest {
        transferred_resource: x.transferred_resource.simplify(),
        created_resource: x.created_resource.simplify(),
        sender_nf_key: x.sender_nullifier_key.inner().to_owned(),
        sender_verifying_key: x.sender_auth_verifying_key.as_affine().to_owned(),
        auth_signature: x.auth_signature.to_bytes(),
        receiver_discovery_pk: x.receiver_discovery_pk,
        receiver_encryption_pk: x.receiver_encryption_pk,
    }
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_transfer_request() {
    let config = load_config().expect("failed to load config in test");
    let alice = alice_keychain(&config);
    let bob = bob_keychain();

    // Create the request.
    let request = create_transfer_request(&config, alice, bob).await;

    // Process the request
    let result = handle_transfer_request(request, &config).await;
    assert!(result.is_ok());
}
