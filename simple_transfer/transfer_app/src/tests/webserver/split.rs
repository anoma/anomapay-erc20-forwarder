#![cfg(test)]

use crate::requests::split::{handle_split_request, SplitRequest};
use crate::requests::Expand;
use crate::tests::fixtures::{alice_keychain, bob_keychain, split_parameters_example};
use crate::tests::transactions::mint::submit_mint_transaction;
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use serial_test::serial;

/// Create an example request to mint a resource.
pub async fn create_split_request(
    config: &AnomaPayConfig,
    alice: Keychain,
    bob: Keychain,
) -> SplitRequest {
    // To create a split request, a mint request has to be made first.
    let (mint_parameters, _transaction) = submit_mint_transaction(config, alice.clone()).await;

    // Create an example of mint parameters for alice.
    let split_parameters = split_parameters_example(
        alice.clone(),
        bob.clone(),
        config,
        mint_parameters.created_resource,
    )
    .await
    .expect("failed to create MintParameters");

    // Create a request
    SplitRequest {
        to_split_resource: split_parameters.to_split_resource.simplify(),
        created_resource: split_parameters.created_resource.simplify(),
        remainder_resource: split_parameters.remainder_resource.simplify(),
        padding_resource: split_parameters.padding_resource.simplify(),
        sender_nf_key: split_parameters.sender_nullifier_key.inner().to_vec(),
        sender_verifying_key: split_parameters
            .sender_auth_verifying_key
            .as_affine()
            .to_owned(),
        auth_signature: split_parameters.auth_signature.to_bytes(),
        owner_discovery_pk: split_parameters.sender_discovery_pk,
        owner_encryption_pk: split_parameters.sender_encryption_pk,
        receiver_discovery_pk: split_parameters.receiver_discovery_pk,
        receiver_encryption_pk: split_parameters.receiver_encryption_pk,
    }
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_split_request() {
    let config = load_config().expect("failed to load config in test");
    let alice = alice_keychain(&config);
    let bob = bob_keychain();

    // Create the request.
    let request = create_split_request(&config, alice, bob).await;

    // Process the request
    let result = handle_split_request(request, &config).await;
    assert!(result.is_ok());
}
