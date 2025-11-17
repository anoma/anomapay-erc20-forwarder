#![cfg(test)]
//! Test the behavior of minting a resource.

use crate::ethereum::pa_submit_transaction;
use crate::request::parameters::Parameters;
use crate::request::resources::{Consumed, Created};
use crate::request::witness_data::token_transfer::{ConsumedPersistent, CreatedEphemeral};
use crate::tests::fixtures::{
     label_ref, random_nonce, user_with_private_key,
    value_ref_ephemeral_created, TOKEN_ADDRESS_SEPOLIA_USDC,
};
use crate::tests::request::mint::example_mint_transaction_submit;
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use arm::action_tree::MerkleTree;
use arm::authorization::AuthorizationSignature;
use arm::logic_proof::LogicProver;
use arm::resource::Resource;
use arm::transaction::Transaction;
use arm::Digest;
use transfer_library::TransferLogic;

#[ignore]
#[tokio::test]
/// Test creation of a burn transaction.
/// This test verifies that the proofs are generated, and the transaction is valid.
async fn test_create_burn_transaction() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let user = user_with_private_key(&config);

    // Call the example submit function which submits a mint transaction.
    let (parameters, _transaction, hash) = example_mint_transaction_submit(user.clone(), &config).await;
    println!("mint transaction hash: {}", hash);

    // Create a burn transaction for the just minted resource.
    let minted_resource = parameters.created_resources[0].resource;
    let (_parameters, transaction) = example_burn_transaction(user, &config, minted_resource).await;

    // Make sure the transaction verifies.
    transaction.verify().expect("failed to verify burn transaction")
}

#[tokio::test]
/// Test submitting a burn transaction to the protocol adapter.
/// This requires an account with private key to actually submit to ethereum.
pub async fn test_submit_burn_transaction() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let user = user_with_private_key(&config);

    // Call the example submit function which submits a mint transaction.
    let (parameters, _transaction, _hash) = example_mint_transaction_submit(user.clone(), &config).await;

    // Submit a burn transaction.
    let minted_resource = parameters.created_resources[0].resource;
    let (_parameters, _transaction, hash) = example_burn_transaction_submit(user, &config, minted_resource).await;
    println!("burn transaction hash: {}", hash)
}


/// Creates and submits a burning transaction for the given user.
pub async fn example_burn_transaction_submit(
    user: Keychain,
    config: &AnomaPayConfig,
    resource: Resource,
) -> (Parameters, Transaction, String) {
    // Create a mint transaction.
    let (parameters, transaction) = example_burn_transaction(user, config, resource).await;

    // Submit the transaction.
    let tx_hash = pa_submit_transaction(transaction.clone())
        .await
        .expect("failed to submit ethereum transaction");

    println!("burn transaction hash: {}", tx_hash);

    (parameters, transaction, tx_hash)
}

/// Creates an example of a burn transaction that burns a given resource.
pub async fn example_burn_transaction(
    user: Keychain,
    config: &AnomaPayConfig,
    resource: Resource,
) -> (Parameters, Transaction) {
    // Create a set of parameters that amount to a burn transaction.
    let parameters = example_burn_parameters(user, config, resource).await;

    // Create the transaction for these parameters.
    let transaction = parameters
        .generate_transaction(config)
        .await
        .expect("failed to generate burn transaction");

    (parameters, transaction)
}

/// Creates an example value of `Parameters` that represents a burn transaction.
async fn example_burn_parameters(
    burner: Keychain,
    config: &AnomaPayConfig,
    to_burn_resource: Resource,
) -> Parameters {
    // to burn a resource, we need the nullifier of that resource.
    let burned_resource_nullifier = to_burn_resource
        .nullifier(&burner.nf_key)
        .expect("could not create nullifier for burned resource with given nullifier key");

    ////////////////////////////////////////////////////////////////////////////
    // Construct the ephemeral resource to create

    let nonce = burned_resource_nullifier.as_bytes().try_into().unwrap();

    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: to_burn_resource.quantity,
        value_ref: value_ref_ephemeral_created(&burner),
        is_ephemeral: true,
        nonce,
        nk_commitment: burner.nf_key.commit(),
        rand_seed: random_nonce(),
    };

    let created_resource_commitment = created_resource.commitment();

    ////////////////////////////////////////////////////////////////////////////
    // Create the action tree

    let action_tree: MerkleTree =
        MerkleTree::new(vec![burned_resource_nullifier, created_resource_commitment]);

    let action_tree_root: Digest = action_tree.root();

    let auth_signature: AuthorizationSignature =
        burner.auth_signing_key.sign(action_tree_root.as_bytes());

    // Construct the CreatedResource
    let created_witness_data = CreatedEphemeral {
        token_contract_address: TOKEN_ADDRESS_SEPOLIA_USDC,
        receiver_wallet_address: burner.evm_address,
    };

    let created_resource = Created {
        resource: created_resource,
        witness_data: Box::new(created_witness_data),
    };

    // Create the ConsumedResource
    let consumed_witness_data = ConsumedPersistent {
        sender_authorization_signature: auth_signature,
        sender_authorization_verifying_key: burner.clone().auth_verifying_key(),
    };

    let consumed_resource = Consumed {
        resource: to_burn_resource,
        nullifier_key: burner.nf_key,
        witness_data: Box::new(consumed_witness_data),
    };

    // get the latest commitment tree path.
    Parameters {
        created_resources: vec![created_resource],
        consumed_resources: vec![consumed_resource],
    }
}
