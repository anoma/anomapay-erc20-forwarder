#![cfg(test)]
//! Tests the serialize and deserialize functionality of the endpoint.

use crate::{
    load_config,
    request::parameters::Parameters,
    tests::{fixtures::user_with_private_key, request::mint::example_mint_parameters},
};

#[tokio::test]
/// Test serialization of a mint request.
///
/// A mint parameters is created, serialized, and deserialized. The values
/// should be exactly the same.
async fn serialize_mint() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let user = user_with_private_key(&config);

    // Create an example of Parameters that represent a minting transaction.
    let parameters = example_mint_parameters(user.clone(), &config, 1).await;

    let json_string = serde_json::to_string(&parameters).expect("failed to serialize Parameters");
    let parameters_deserialized: Parameters =
        serde_json::from_str(&json_string).expect("failed to deserialize Parameters");

    assert!(parameters == parameters_deserialized);
}
