#![cfg(test)]

use crate::request::parameters::Parameters;
use crate::request::resources::{
    Consumed, ConsumedWitnessDataEnum, Created, CreatedWitnessDataEnum,
};
use crate::request::witness_data::token_transfer::{ConsumedPersistent, CreatedPersistent};
use crate::request::witness_data::trivial;
use crate::rpc::pa_submit_transaction;
use crate::tests::fixtures::{
    label_ref, random_nonce, user_with_private_key, user_without_private_key, value_ref_created,
    TOKEN_ADDRESS_SEPOLIA_USDC,
};
use crate::tests::request::mint::example_mint_transaction_submit;
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use arm::action_tree::MerkleTree;
use arm::logic_proof::LogicProver;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;
use arm::transaction::Transaction;
use arm::Digest;
use itertools::Itertools;
use transfer_library::TransferLogic;

#[tokio::test]
/// Test creation of a burn transaction.
/// This test verifies that the proofs are generated, and the transaction is valid.
async fn test_submit_transfer_transaction() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let sender = user_with_private_key(&config);
    let receiver = user_without_private_key();

    // Call the example submit function which submits a mint transaction.
    // This creates a resource for sender.
    let (parameters, _, hash) = example_mint_transaction_submit(sender.clone(), &config).await;
    println!("mint transaction hash: {}", hash);

    // Create a transfer transaction to the receiver.
    let to_transfer = parameters.created_resources[0].resource;
    let (_, _, hash) =
        example_transfer_transaction_submit(sender, receiver, &config, vec![to_transfer]).await;
    println!("transfer transaction hash: {}", hash)
}

#[ignore]
#[tokio::test]
/// Test creation of a burn transaction.
/// This test verifies that the proofs are generated, and the transaction is valid.
async fn test_create_transfer_transaction() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let sender = user_with_private_key(&config);
    let receiver = user_without_private_key();

    // Call the example submit function which submits a mint transaction.
    // This creates a resource for sender.
    let (parameters, _transaction, hash) =
        example_mint_transaction_submit(sender.clone(), &config).await;
    println!("mint transaction hash: {}", hash);

    // Create a transfer transaction to the receiver.
    let to_transfer = parameters.created_resources[0].resource;
    let (_parameters, transaction) =
        example_transfer_transaction(sender, receiver, &config, vec![to_transfer]).await;
    // Make sure the transaction verifies.
    transaction
        .verify()
        .expect("failed to verify burn transaction")
}

/// Create and submit a transfer transaction.
pub async fn example_transfer_transaction_submit(
    sender: Keychain,
    receiver: Keychain,
    config: &AnomaPayConfig,
    resources_to_transfer: Vec<Resource>,
) -> (Parameters, Transaction, String) {
    // Create a mint transaction.
    let (parameters, transaction) =
        example_transfer_transaction(sender, receiver, config, resources_to_transfer).await;

    // Submit the transaction.
    let tx_hash = pa_submit_transaction(transaction.clone())
        .await
        .expect("failed to submit ethereum transaction");

    println!("transfer transaction hash: {}", tx_hash);

    (parameters, transaction, tx_hash)
}

/// Create a transfer transaction.
pub async fn example_transfer_transaction(
    sender: Keychain,
    receiver: Keychain,
    config: &AnomaPayConfig,
    resources_to_transfer: Vec<Resource>,
) -> (Parameters, Transaction) {
    // Create a set of parameters that amount to a burn transaction.
    let parameters =
        example_transfer_parameters(sender, receiver, config, resources_to_transfer).await;

    // Create the transaction for these parameters.
    let transaction = parameters
        .generate_transaction(config)
        .await
        .expect("failed to generate transfer transaction");

    (parameters, transaction)
}

/// Creates an example `Parameters` struct that represents a transfer.
pub async fn example_transfer_parameters(
    sender: Keychain,
    receiver: Keychain,
    config: &AnomaPayConfig,
    resources_to_transfer: Vec<Resource>,
) -> Parameters {
    // ) {
    let mut resource_nullifiers = vec![];
    let mut quantity = 0;
    for resource in resources_to_transfer.iter().cloned() {
        let nullifier = resource.nullifier(&sender.nf_key).unwrap();
        resource_nullifiers.push(nullifier);
        quantity += resource.quantity;
    }

    // Create 1 resource for the receiver with the total sum of the sent resources.
    // The nonce of the resource is one of the nullifiers of the sent resources.
    // Arbitrary choice here is the first resource.
    let mut created_resources = vec![];
    let created_resource_nonce = resource_nullifiers[0]
        .as_bytes()
        .try_into()
        .expect("resource_nullifiers[0]  is not 32 bytes");

    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity,
        value_ref: value_ref_created(&receiver),
        is_ephemeral: false,
        nonce: created_resource_nonce,
        nk_commitment: receiver.nf_key.commit(),
        rand_seed: random_nonce(),
    };

    created_resources.push(created_resource);

    // If  `n` resources are sent, `n-1` padding resources are necessary to balance the transaction.
    // Each padding resource needs the nullifier of one of the consumed resources as its nonce.
    // A default padding resource. Each padding resource will have its nonce overwritten in the loop below.
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

    let mut padding_resources = vec![];

    // Create N-1 padding resources with a nullifier from one of the consumed resources.
    for resource in &resources_to_transfer[1..resources_to_transfer.len()] {
        let nonce = resource
            .nullifier(&sender.nf_key)
            .expect("failed to create nullifier from resource")
            .as_bytes()
            .try_into()
            .expect("resource nullifier  is not 32 bytes");

        let padding_resource = Resource {
            nonce,
            ..padding_resource
        };
        created_resources.push(padding_resource);
        padding_resources.push(padding_resource);
    }

    // The action tree will have the leaves of a consumed resource, created resource, etc.
    // [consumed, created, consumed, created, ...]
    let resources: Vec<Digest> = resources_to_transfer
        .clone()
        .into_iter()
        .map(|consumed: Resource| {
            consumed
                .nullifier(&sender.nf_key)
                .expect("failed to create nullifier for resource")
        })
        .interleave(
            created_resources
                .into_iter()
                .map(|created: Resource| created.commitment()),
        )
        .collect();
    let action_tree: MerkleTree = MerkleTree::new(resources);
    let action_tree_root: Digest = action_tree.root();

    // Construct the created resources with witness data.
    let mut consumed_resources_with_witness_data: Vec<Consumed> = vec![];
    for resource in resources_to_transfer.into_iter() {
        let consumed_witness_data = ConsumedPersistent {
            sender_authorization_signature: sender
                .auth_signing_key
                .sign(action_tree_root.as_bytes()),
            sender_authorization_verifying_key: sender.clone().auth_verifying_key(),
        };

        let consumed_resource: Consumed = Consumed {
            resource,
            nullifier_key: sender.clone().nf_key,
            witness_data: ConsumedWitnessDataEnum::Persistent(consumed_witness_data),
        };

        consumed_resources_with_witness_data.push(consumed_resource);
    }

    // Construct the created resources with witness data.
    let mut created_resources_with_witness_data: Vec<Created> = vec![];

    let created_witness_data = CreatedPersistent {
        receiver_discovery_public_key: receiver.discovery_pk,
        receiver_encryption_public_key: receiver.encryption_pk,
    };

    let created_resource = Created {
        resource: created_resource,
        witness_data: CreatedWitnessDataEnum::Persistent(created_witness_data),
    };
    created_resources_with_witness_data.push(created_resource);

    // add the padding resources
    for resource in padding_resources {
        let created_witness_data = trivial::CreatedEphemeral {};

        let created_resource = Created {
            resource,
            witness_data: CreatedWitnessDataEnum::TrivialEphemeral(created_witness_data),
        };
        created_resources_with_witness_data.push(created_resource);
    }

    Parameters {
        created_resources: created_resources_with_witness_data,
        consumed_resources: consumed_resources_with_witness_data,
    }
}
