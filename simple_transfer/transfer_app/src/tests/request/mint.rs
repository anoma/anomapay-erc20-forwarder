#![cfg(test)]
//! Test the behavior of minting a resource.

use crate::tests::fixtures::{
    create_permit_signature, default_commitment_tree_root, label_ref, random_nonce,
    value_ref_created, value_ref_ephemeral_consumed, DEFAULT_DEADLINE, TOKEN_ADDRESS_SEPOLIA_USDC,
};
use crate::user::Keychain;
use crate::AnomaPayConfig;
use arm::action_tree::MerkleTree;
use arm::logic_proof::LogicProver;
use arm::resource::Resource;
use transfer_library::TransferLogic;

/// Mint parameters need one consumed ephemeral resource and one created
/// persistent resource.
async fn mint_parameters(minter: Keychain, config: &AnomaPayConfig, amount: u128) {
    // Use the default commitment tree root.
    let commitment_tree_root = default_commitment_tree_root();

    // Amount of the resource to mint.
    let amount: u128 = 2;

    // Construct the ephemeral resource
    let nonce = random_nonce();
    let consumed_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: amount,
        value_ref: value_ref_ephemeral_consumed(&minter),
        is_ephemeral: true,
        nonce,
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

    // Construct the created resource (i.e., the one that wraps our tokens)
    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: amount,
        value_ref: value_ref_created(&minter),
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
        &minter.private_key.unwrap(),
        action_tree.clone(),
        consumed_resource_nullifier.into(),
        amount,
        config,
        TOKEN_ADDRESS_SEPOLIA_USDC,
        DEFAULT_DEADLINE,
    )
    .await;
}
