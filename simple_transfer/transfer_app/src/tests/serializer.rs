#![cfg(test)]
//! Tests the serialize and deserialize functionality of the endpoint.

use crate::{
    load_config,
    request::parameters::Parameters,
    tests::{
        fixtures::{user_with_private_key, user_without_private_key},
        request::{
            burn::example_burn_parameters, mint::example_mint_parameters,
            split::example_split_parameters, transfer::example_transfer_parameters,
        },
    },
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

#[tokio::test]
/// Test serialization of a burn request.
///
/// A burn parameters is created, serialized, and deserialized. The values
/// should be exactly the same.
async fn serialize_burn() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let user = user_with_private_key(&config);

    // Create an arbitrary resource with mint parameters.
    let mint_parameters = example_mint_parameters(user.clone(), &config, 1).await;

    // Create an example of Parameters that represent a minting transaction.
    let minted_resource = mint_parameters.created_resources[0].resource;
    let burn_parameters = example_burn_parameters(user.clone(), &config, minted_resource).await;

    let json_string =
        serde_json::to_string(&burn_parameters).expect("failed to serialize Parameters");

    let burn_parameters_deserialized: Parameters =
        serde_json::from_str(&json_string).expect("failed to deserialize Parameters");

    assert!(burn_parameters == burn_parameters_deserialized);
}

#[tokio::test]
/// Test serialization of a split request.
///
/// A split parameters is created, serialized, and deserialized. The values
/// should be exactly the same.
async fn serialize_split() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let user = user_with_private_key(&config);
    let other_user = user_without_private_key();

    // Create an arbitrary resource with mint parameters.
    let mint_parameters = example_mint_parameters(user.clone(), &config, 1).await;
    let minted_resource = mint_parameters.created_resources[0].resource;

    // Create an example of Parameters that represent a minting transaction.
    let parameters =
        example_split_parameters(user.clone(), other_user.clone(), &config, minted_resource).await;

    let json_string = serde_json::to_string(&parameters).expect("failed to serialize Parameters");
    let parameters_deserialized: Parameters =
        serde_json::from_str(&json_string).expect("failed to deserialize Parameters");

    assert!(parameters == parameters_deserialized);
}

#[tokio::test]
/// Test serialization of a split request.
///
/// A split parameters is created, serialized, and deserialized. The values
/// should be exactly the same.
async fn serialize_transfer() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let user = user_with_private_key(&config);
    let other_user = user_without_private_key();

    // Create an arbitrary resource with mint parameters.
    let mint_parameters = example_mint_parameters(user.clone(), &config, 1).await;
    let minted_resource = mint_parameters.created_resources[0].resource;

    // Create an example of Parameters that represent a minting transaction.
    let parameters = example_transfer_parameters(
        user.clone(),
        other_user.clone(),
        &config,
        vec![minted_resource],
    )
    .await;

    let json_string = serde_json::to_string(&parameters).expect("failed to serialize Parameters");
    let parameters_deserialized: Parameters =
        serde_json::from_str(&json_string).expect("failed to deserialize Parameters");

    assert!(parameters == parameters_deserialized);
}
