#![cfg(test)]
//! Test the behavior of minting a resource.

use crate::request::proving::parameters::Parameters;
use crate::request::proving::resources::{
    Consumed, ConsumedWitnessDataEnum, Created, CreatedWitnessDataEnum,
};
use crate::request::proving::witness_data::token_transfer::{
    ConsumedEphemeral, CreatedPersistent, Permit2Data,
};
use crate::rpc::pa_submit_transaction;
use crate::tests::fixtures::{
    create_permit_signature, label_ref, random_nonce, user_with_private_key,
    value_ref_ephemeral_consumed, DEFAULT_DEADLINE, TOKEN_ADDRESS_SEPOLIA_USDC,
};
use crate::user::Keychain;
use crate::{load_config, AnomaPayConfig};
use arm::action_tree::MerkleTree;
use arm::logic_proof::LogicProver;
use arm::resource::Resource;
use arm::transaction::Transaction;
use transfer_library::TransferLogic;
use transfer_witness::{calculate_persistent_value_ref, ValueInfo};

#[ignore]
#[tokio::test]
/// Test creation of a mint transaction.
/// This test verifies that the proofs are generated, and the transaction is valid.
async fn test_create_mint_transaction() {
    dotenv::dotenv().ok();

    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let user = user_with_private_key(&config);

    // Create a mint transaction.
    let (_parameters, transaction) = example_mint_transaction(user, &config).await;

    // Make sure the transaction verifies.
    transaction
        .verify()
        .expect("failed to verify mint transaction")
}

#[tokio::test]
/// Test submitting a mint transaction to the protocol adapter.
/// This requires an account with private key to actually submit to ethereum.
pub async fn test_submit_mint_transaction() {
    // Load the configuration parameters.
    let config = load_config().expect("failed to load config in test");
    // Create a keychain with a private key
    let user = user_with_private_key(&config);

    // Call the example submit function which submits a mint transaction.
    let (_parameters, _transaction, hash) = example_mint_transaction_submit(user, &config).await;
    println!("mint transaction hash: {}", hash)
}

/// Creates and submits a minting transaction for the given user.
pub async fn example_mint_transaction_submit(
    user: Keychain,
    config: &AnomaPayConfig,
) -> (Parameters, Transaction, String) {
    // Create a mint transaction.
    let (parameters, transaction) = example_mint_transaction(user, config).await;

    // Submit the transaction.
    let tx_hash = pa_submit_transaction(config, transaction.clone())
        .await
        .expect("failed to submit ethereum transaction");

    println!("mint transaction hash: {}", tx_hash);

    (parameters, transaction, tx_hash)
}

/// Creates an example transaction that mints 1 resource for the given user.
async fn example_mint_transaction(
    user: Keychain,
    config: &AnomaPayConfig,
) -> (Parameters, Transaction) {
    // Create a set of parameters that amount to a mint transaction.
    let parameters = example_mint_parameters(user, config, 1).await;

    // Create the transaction for these parameters.
    let transaction = parameters
        .generate_transaction(config)
        .await
        .expect("failed to generate mint transaction");

    (parameters, transaction)
}

/// Creates an example value of `Parameters` that represents a mint transaction.
pub async fn example_mint_parameters(
    minter: Keychain,
    config: &AnomaPayConfig,
    amount: u128,
) -> Parameters {
    // Construct the ephemeral resource
    let consumed_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: amount,
        value_ref: value_ref_ephemeral_consumed(&minter),
        is_ephemeral: true,
        nonce: random_nonce(),
        nk_commitment: minter.nf_key.commit(),
        rand_seed: random_nonce(),
    };

    let consumed_resource_nullifier = consumed_resource
        .nullifier(&minter.nf_key)
        .expect("failed to create nullifier for consumed resource");

    let created_resource_nonce = consumed_resource_nullifier
        .as_bytes()
        .try_into()
        .expect("consumed resource nullifier is not 32 bytes");

    let value_info = ValueInfo {
       auth_pk: minter.auth_verifying_key(),
         encryption_pk: minter.encryption_pk,
    };

    // Construct the created resource (i.e., the one that wraps our tokens)
    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: amount,
        value_ref: calculate_persistent_value_ref(&value_info),
        is_ephemeral: false,
        nonce: created_resource_nonce,
        nk_commitment: minter.nf_key.commit(),
        rand_seed: [6u8; 32],
    };

    // Create the action tree for the resources
    let action_tree: MerkleTree = MerkleTree::new(vec![
        consumed_resource_nullifier,
        created_resource.commitment(),
    ]);

    // Create the permit2 signature.

    let permit_signature = create_permit_signature(
        &minter.private_key.clone().unwrap(),
        action_tree.clone(),
        consumed_resource_nullifier.into(),
        amount,
        config,
        TOKEN_ADDRESS_SEPOLIA_USDC,
        DEFAULT_DEADLINE,
    )
    .await;

    // Create the resources with witness data attached.
    let consumed_witness_data = ConsumedEphemeral {
        sender_wallet_address: minter.evm_address,

        token_contract_address: TOKEN_ADDRESS_SEPOLIA_USDC,
        permit2_data: Permit2Data {
            signature: permit_signature.into(),
            deadline: DEFAULT_DEADLINE,
            nonce: created_resource_nonce.into(),
        },
    };

    let consumed_resource = Consumed {
        resource: consumed_resource,
        nullifier_key: minter.clone().nf_key,
        witness_data: ConsumedWitnessDataEnum::Ephemeral(consumed_witness_data),
    };

    let created_witness_data = CreatedPersistent {
        receiver_discovery_public_key: minter.discovery_pk,
        receiver_authorization_verifying_key: minter.clone().auth_verifying_key(),
        receiver_encryption_public_key: minter.encryption_pk,
        token_contract_address: TOKEN_ADDRESS_SEPOLIA_USDC,
    };

    let created_resource = Created {
        resource: created_resource,
        witness_data: CreatedWitnessDataEnum::Persistent(created_witness_data),
    };

    Parameters {
        created_resources: vec![created_resource],
        consumed_resources: vec![consumed_resource],
    }
}
