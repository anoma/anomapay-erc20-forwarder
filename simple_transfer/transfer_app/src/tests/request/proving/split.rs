#![cfg(test)]
//! Test the behavior of minting a resource.

use crate::request::proving::parameters::Parameters;
use crate::request::proving::resources::{
    Consumed, ConsumedWitnessDataEnum, Created, CreatedWitnessDataEnum,
};
use crate::request::proving::witness_data::{token_transfer, trivial};
use crate::rpc::pa_submit_transaction;
use crate::tests::fixtures::{
    TOKEN_ADDRESS_SEPOLIA_USDC, label_ref, random_nonce, user_with_private_key,
    user_without_private_key,
};
use crate::tests::request::proving::mint::example_mint_transaction_submit;
use crate::user::Keychain;
use crate::{AnomaPayConfig, load_config};
use arm::action_tree::MerkleTree;
use arm::logic_proof::LogicProver;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;
use arm::transaction::Transaction;
use arm_gadgets::authorization::AuthorizationSignature;
use risc0_zkvm::Digest;
use serial_test::serial;
use transfer_library::TransferLogic;
use transfer_witness::{AUTH_SIGNATURE_DOMAIN, ValueInfo, calculate_persistent_value_ref};

#[tokio::test]
#[serial]
/// Test creation of a burn transaction.
/// This test verifies that the proofs are generated, and the transaction is valid.
async fn test_submit_split_transaction() {
    dotenv::dotenv().ok();

    // Load the configuration parameters.
    let config = load_config().await.expect("failed to load config in test");
    // Create a keychain with a private key
    let sender = user_with_private_key(&config);
    let receiver = user_without_private_key();

    // Call the example submit function which submits a mint transaction.
    // This creates a resource for sender.
    let (parameters, _transaction, hash) =
        example_mint_transaction_submit(sender.clone(), &config).await;
    println!("mint transaction hash: {}", hash);

    // Create a transfer transaction to the receiver.
    let to_split = parameters.created_resources[0].resource;
    let (_, _, hash) = example_split_transaction_submit(sender, receiver, &config, to_split).await;

    println!("split transaction hash: {}", hash)
}

#[ignore]
#[tokio::test]
/// Test creation of a burn transaction.
/// This test verifies that the proofs are generated, and the transaction is valid.
async fn test_create_split_transaction() {
    dotenv::dotenv().ok();

    // Load the configuration parameters.
    let config = load_config().await.expect("failed to load config in test");
    // Create a keychain with a private key
    let sender = user_with_private_key(&config);
    let receiver = user_without_private_key();

    // Call the example submit function which submits a mint transaction.
    // This creates a resource for sender.
    let (parameters, _transaction, hash) =
        example_mint_transaction_submit(sender.clone(), &config).await;
    println!("mint transaction hash: {}", hash);

    // Create a transfer transaction to the receiver.
    let to_split = parameters.created_resources[0].resource;
    let (_parameters, transaction) =
        example_split_transaction(sender, receiver, &config, to_split).await;

    // Make sure the transaction verifies.
    transaction
        .verify()
        .expect("failed to verify burn transaction")
}

/// Create an example split transaction and submit it to the PA.
pub async fn example_split_transaction_submit(
    sender: Keychain,
    receiver: Keychain,
    config: &AnomaPayConfig,
    to_split_resource: Resource,
) -> (Parameters, Transaction, String) {
    // Create a mint transaction.
    let (parameters, transaction) =
        example_split_transaction(sender, receiver, config, to_split_resource).await;

    // Submit the transaction.
    let tx_hash = pa_submit_transaction(config, transaction.clone())
        .await
        .expect("failed to submit ethereum transaction");

    println!("split transaction hash: {}", tx_hash);

    (parameters, transaction, tx_hash)
}
/// Creates an example transaction for a split.
pub async fn example_split_transaction(
    sender: Keychain,
    receiver: Keychain,
    config: &AnomaPayConfig,
    to_split_resource: Resource,
) -> (Parameters, Transaction) {
    // Create a set of parameters that amount to a transfer transaction.
    let parameters = example_split_parameters(sender, receiver, config, to_split_resource).await;

    // Create the transaction for these parameters.
    let transaction = parameters
        .generate_transaction(config)
        .await
        .expect("failed to generate split transaction");

    (parameters, transaction)
}
/// Creates example split parameters.
pub async fn example_split_parameters(
    sender: Keychain,
    receiver: Keychain,
    config: &AnomaPayConfig,
    to_split_resource: Resource,
) -> Parameters {
    let remainder = to_split_resource.quantity - 1;

    // In a split, we need a balanced transaction. That means if we create two resources, we have
    // to consume two as well. This empty resource is called a padding resource.
    // This resource does not need the resource logic of the simple transfer either, so we use
    // the trivial logic.
    let padding_resource = Resource {
        logic_ref: TrivialLogicWitness::verifying_key(),
        label_ref: Digest::default(),
        quantity: 0,
        value_ref: Digest::default(),
        is_ephemeral: true,
        nonce: random_nonce(),
        nk_commitment: NullifierKey::default().commit(),
        rand_seed: [0u8; 32],
    };

    let padding_resource_nullifier = padding_resource
        .nullifier(&NullifierKey::default())
        .expect("could not create nullifier for padding resource with given nullifier key");

    let to_split_resource_nullifier = to_split_resource
        .nullifier(&sender.nf_key)
        .expect("failed to create nullifier for to_split_resource with given nullifier key");

    ////////////////////////////////////////////////////////////////////////////
    // Construct the resource for the receiver

    let nonce = to_split_resource_nullifier
        .as_bytes()
        .try_into()
        .expect("to_split_resource_nullifier is not 32 bytes");

    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: 1,
        value_ref: calculate_persistent_value_ref(&ValueInfo {
            auth_pk: receiver.auth_verifying_key(),
            encryption_pk: receiver.encryption_pk,
        }),
        is_ephemeral: false,
        nonce,
        nk_commitment: receiver.nf_key.commit(),
        rand_seed: [7u8; 32],
    };

    let created_resource_commitment = created_resource.commitment();

    ////////////////////////////////////////////////////////////////////////////
    // Construct the remainder resource

    let nonce = padding_resource_nullifier
        .as_bytes()
        .try_into()
        .expect("padding_resource_nullifier is not 32 bytes");

    let remainder_resource = Resource {
        quantity: remainder,
        nonce,
        ..to_split_resource
    };

    let remainder_resource_commitment = remainder_resource.commitment();

    ////////////////////////////////////////////////////////////////////////////
    // Create the action tree

    let action_tree: MerkleTree = MerkleTree::new(vec![
        to_split_resource_nullifier,
        created_resource_commitment,
        padding_resource_nullifier,
        remainder_resource_commitment,
    ]);

    ////////////////////////////////////////////////////////////////////////////
    // Create the permit signature

    let action_tree_root: Digest = action_tree.root().expect("failed to get action tree root");
    let auth_signature: AuthorizationSignature = sender
        .auth_signing_key
        .sign(AUTH_SIGNATURE_DOMAIN, action_tree_root.as_bytes());

    ////////////////////////////////////////////////////////////////////////////
    // Create the parameters

    // Padding resource
    let padding_witness_data = trivial::ConsumedEphemeral {};
    let padding = Consumed {
        resource: padding_resource,
        nullifier_key: NullifierKey::default(),
        witness_data: ConsumedWitnessDataEnum::TrivialEphemeral(padding_witness_data),
    };

    // To split resource
    let to_split_witness_data = token_transfer::ConsumedPersistent {
        sender_authorization_verifying_key: sender.auth_verifying_key(),
        sender_encryption_public_key: sender.encryption_pk,
        sender_authorization_signature: auth_signature,
    };
    let to_split = Consumed {
        resource: to_split_resource,
        nullifier_key: sender.clone().nf_key,
        witness_data: ConsumedWitnessDataEnum::Persistent(to_split_witness_data),
    };

    // Created resource
    let created_witness_data = token_transfer::CreatedPersistent {
        receiver_discovery_public_key: receiver.discovery_pk,
        receiver_authorization_verifying_key: receiver.auth_verifying_key(),
        receiver_encryption_public_key: receiver.encryption_pk,
        token_contract_address: TOKEN_ADDRESS_SEPOLIA_USDC,
    };
    let created = Created {
        resource: created_resource,
        witness_data: CreatedWitnessDataEnum::Persistent(created_witness_data),
    };

    // Remainder resource
    let remainder_witness_data = token_transfer::CreatedPersistent {
        receiver_discovery_public_key: sender.discovery_pk,
        receiver_authorization_verifying_key: sender.auth_verifying_key(),
        receiver_encryption_public_key: sender.encryption_pk,
        token_contract_address: TOKEN_ADDRESS_SEPOLIA_USDC,
    };
    let remainder = Created {
        resource: remainder_resource,
        witness_data: CreatedWitnessDataEnum::Persistent(remainder_witness_data),
    };

    Parameters {
        created_resources: vec![created, remainder],
        consumed_resources: vec![to_split, padding],
    }
}
