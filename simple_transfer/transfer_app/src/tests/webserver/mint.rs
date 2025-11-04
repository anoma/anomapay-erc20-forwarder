#![cfg(test)]

use crate::requests::mint::{handle_mint_request, MintRequest};
use crate::requests::Expand;
use crate::tests::fixtures::{alice_keychain, mint_parameters_example};
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use serial_test::serial;

/// Create an example request to mint a resource.
pub async fn create_mint_request(config: &AnomaPayConfig, alice: Keychain) -> MintRequest {
    // Create an example of mint parameters for alice.
    let mint_parameters = mint_parameters_example(alice.clone(), config)
        .await
        .expect("failed to create MintParameters");

    // Create a request
    MintRequest {
        consumed_resource: mint_parameters.consumed_resource.simplify(),
        created_resource: mint_parameters.created_resource.simplify(),
        latest_cm_tree_root: mint_parameters
            .latest_commitment_tree_root
            .as_bytes()
            .to_vec(),
        consumed_nf_key: mint_parameters.consumed_nullifier_key.inner().to_vec(),
        forwarder_addr: config.forwarder_address.to_vec(),
        token_addr: mint_parameters.token_address.to_vec(),
        user_addr: mint_parameters.user_address.to_vec(),
        permit_nonce: mint_parameters.permit_nonce.to_vec(),
        permit_deadline: mint_parameters.permit_deadline,
        permit_sig: mint_parameters.permit_signature.clone(),
        created_discovery_pk: mint_parameters.discovery_pk,
        created_encryption_pk: mint_parameters.encryption_pk,
    }
}

#[tokio::test]
#[serial(submit_evm)]
async fn test_mint_request() {
    let config = load_config().expect("failed to load config in test");
    let alice = alice_keychain(&config);

    // Create the request.
    let request = create_mint_request(&config, alice).await;

    // Process the request
    let result = handle_mint_request(request, &config).await;
    assert!(result.is_ok());
}
