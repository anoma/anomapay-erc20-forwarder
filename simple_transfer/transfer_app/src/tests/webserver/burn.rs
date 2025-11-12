#![cfg(test)]

use crate::requests::burn::{handle_burn_request, BurnRequest};
use crate::requests::Expand;
use crate::tests::fixtures::{alice_keychain, burn_parameters_example};
use crate::tests::transactions::mint::submit_mint_transaction;
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use serial_test::serial;

/// Create an example of a burn request coming in at the API.
pub async fn create_burn_request(config: &AnomaPayConfig, alice: Keychain) -> BurnRequest {
    // To create a burn request, a mint request has to be made first.
    let (mint_parameters, _transaction) = submit_mint_transaction(config, alice.clone()).await;

    let burn_parameters =
        burn_parameters_example(alice.clone(), config, mint_parameters.created_resource).await;

    BurnRequest {
        burned_resource: burn_parameters.burned_resource.simplify(),
        created_resource: burn_parameters.created_resource.simplify(),
        burner_nf_key: burn_parameters.burner_nullifier_key.inner().to_vec(),
        burner_verifying_key: burn_parameters
            .burner_auth_verifying_key
            .as_affine()
            .to_owned(),
        burner_address: burn_parameters.burner_address.to_vec(),
        auth_signature: burn_parameters.auth_signature.to_bytes(),
        token_addr: burn_parameters.token_address.to_vec(),
    }
}

#[tokio::test]
#[serial]
async fn test_burn_request() {
    let config = load_config().expect("failed to load config in test");
    let alice = alice_keychain(&config);

    // Create the request.
    let request = create_burn_request(&config, alice).await;

    println!("{:#?}", request);
    // Process the request
    let result = handle_burn_request(request, &config).await;
    assert!(result.is_ok());
}
