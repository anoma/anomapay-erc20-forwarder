#![cfg(test)]
use crate::errors::TransactionError;
use crate::errors::TransactionError::{InvalidKeyChain, InvalidNullifierSizeError};
use crate::tests::helpers::{create_permit_signature, label_ref, random_nonce, value_ref_created, value_ref_ephemeral_burn, value_ref_ephemeral_mint};
use crate::transactions::burn::BurnParameters;
use crate::transactions::mint::MintParameters;
use crate::transactions::split::SplitParameters;
use crate::transactions::transfer::TransferParameters;
use crate::user::Keychain;
use crate::AnomaPayConfig;
use alloy::hex::ToHexExt;
use alloy::primitives::{address, Address};
use arm::action_tree::MerkleTree;
use arm::authorization::AuthorizationSignature;
use arm::compliance::INITIAL_ROOT;
use arm::logic_proof::LogicProver;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;
use arm::Digest;
use transfer_library::TransferLogic;

// this is the token address for USDC on Sepolia. In this example we assume the user wants to
// transfer USDC.
pub(crate) const TOKEN_ADDRESS_SEPOLIA_USDC: Address =
    address!("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");

pub(crate) const DEFAULT_DEADLINE: u64 = 1893456000;

/// Helper function to create the keychain for alice.
/// Alice has a private key and can create minting transactions.
/// The address and private key for alice are read from the environment to test actual submission
/// to sepolia.
pub fn alice_keychain(config: &AnomaPayConfig) -> Keychain {
    Keychain::alice(
        config.hot_wallet_address.encode_hex(),
        Some(config.hot_wallet_private_key.clone()),
    )
}

/// Helper function to geneate the keychain for bob.
/// Bob has no private key and is always the recipient of resources.
///
/// bob also has a fixed address, as opposed to alice.
/// Alice her address is read from the environment as it is used to submit tranasctions to sepolia.
pub fn bob_keychain() -> Keychain {
    Keychain::bob(None)
}

/// Creates an example of MintParameters to be used in tests.
/// The given minter keychain will create one resource with quantity 2.
pub async fn mint_parameters_example(
    minter: Keychain,
    config: &AnomaPayConfig,
) -> Result<MintParameters, TransactionError> {
    // Use the empty initial root for this mint transaction.
    // Ideally we use the real latest root, however.
    let latest_commitment_tree_root: Digest = *INITIAL_ROOT;

    // Amount of the resource to mint.
    let amount: u128 = 2;

    // Construct the ephemeral resource
    let nonce = random_nonce();
    let consumed_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: amount,
        value_ref: value_ref_ephemeral_mint(&minter),
        is_ephemeral: true,
        nonce,
        nk_commitment: minter.nf_key.commit(),
        rand_seed: random_nonce(),
    };

    let consumed_resource_nullifier = consumed_resource
        .nullifier(&minter.nf_key)
        .map_err(|_| InvalidKeyChain)?;

    let created_resource_nonce = consumed_resource_nullifier
        .as_bytes()
        .try_into()
        .map_err(|_| InvalidNullifierSizeError)?;

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

    Ok(MintParameters {
        created_resource,
        consumed_resource,
        consumed_resource_nullifier,
        latest_commitment_tree_root,
        user_address: minter.evm_address.to_vec(),
        permit_signature: permit_signature.into(),
        discovery_pk: minter.discovery_pk,
        encryption_pk: minter.encryption_pk,
        permit_deadline: 1893456000,
        permit_nonce: created_resource_nonce.into(),
        token_address: TOKEN_ADDRESS_SEPOLIA_USDC.to_vec(),
        forwarder_contract_address: config.forwarder_address.to_vec(),
        consumed_nullifier_key: minter.nf_key,
        created_resource_commitment: created_resource.commitment(),
    })
}

/// Create an example of TransferParameters based on the given keychain and resource.
/// The resource will be transferred from the sender to the receiver.
pub async fn transfer_parameters_example(
    sender: Keychain,
    receiver: Keychain,
    config: &AnomaPayConfig,
    to_transfer_resource: Resource,
) -> Result<TransferParameters, TransactionError> {
    let transferred_resource_nullifier = to_transfer_resource.nullifier(&sender.nf_key).unwrap();

    let nonce = transferred_resource_nullifier
        .as_bytes()
        .try_into()
        .map_err(|_| InvalidNullifierSizeError)?;

    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: to_transfer_resource.quantity,
        value_ref: value_ref_created(&receiver),
        is_ephemeral: false,
        nonce,
        nk_commitment: receiver.nf_key.commit(),
        rand_seed: [7u8; 32],
    };

    let action_tree: MerkleTree = MerkleTree::new(vec![
        transferred_resource_nullifier,
        created_resource.commitment(),
    ]);

    let action_tree_root: Digest = action_tree.root();

    let transferred_resource = to_transfer_resource;
    let sender_nullifier_key = sender.clone().nf_key;
    let sender_auth_verifying_key = sender.clone().auth_verifying_key();
    let auth_signature = sender.auth_signing_key.sign(action_tree_root.as_bytes());
    let receiver_discovery_pk = receiver.discovery_pk;
    let receiver_encryption_pk = receiver.encryption_pk;

    Ok(TransferParameters {
        transferred_resource,
        created_resource,
        sender_nullifier_key,
        sender_auth_verifying_key,
        auth_signature,
        receiver_discovery_pk,
        receiver_encryption_pk,
    })
}

/// Create an example of the BurnParameters request based on a keychain and a resource to be burned.
pub async fn burn_parameters_example(
    burner: Keychain,
    config: &AnomaPayConfig,
    to_burn_resource: Resource,
) -> Result<BurnParameters, TransactionError> {
    // to burn a resource, we need the nullifier of that resource.
    let burned_resource_nullifier = to_burn_resource
        .nullifier(&burner.nf_key)
        .map_err(|_| InvalidKeyChain)?;

    ////////////////////////////////////////////////////////////////////////////
    // Construct the ephemeral resource to create

    let nonce = burned_resource_nullifier.as_bytes().try_into().unwrap();

    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: to_burn_resource.quantity,
        value_ref: value_ref_ephemeral_burn(&burner),
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

    ////////////////////////////////////////////////////////////////////////////
    // Create the permit signature

    let auth_signature: AuthorizationSignature =
        burner.auth_signing_key.sign(action_tree_root.as_bytes());

    Ok(BurnParameters {
        burned_resource: to_burn_resource,
        created_resource,
        burner_nullifier_key: burner.clone().nf_key,
        burner_auth_verifying_key: burner.clone().auth_verifying_key(),
        burner_address: burner.evm_address,
        auth_signature,
        token_address: TOKEN_ADDRESS_SEPOLIA_USDC,
    })
}

/// Create an example of a SplitParameters struct based on a sender, receiver, and a resource to be split.
pub async fn split_parameters_example(
    sender: Keychain,
    receiver: Keychain,
    config: &AnomaPayConfig,
    to_split_resource: Resource,
) -> Result<SplitParameters, TransactionError> {
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
        .map_err(|_| InvalidKeyChain)?;

    let to_split_resource_nullifier = to_split_resource
        .nullifier(&sender.nf_key)
        .map_err(|_| InvalidKeyChain)?;

    ////////////////////////////////////////////////////////////////////////////
    // Construct the resource for the receiver

    let nonce = to_split_resource_nullifier
        .as_bytes()
        .try_into()
        .map_err(|_| InvalidNullifierSizeError)?;

    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: 1,
        value_ref: value_ref_created(&receiver),
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
        .map_err(|_| InvalidNullifierSizeError)?;

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

    let action_tree_root: Digest = action_tree.root();
    let auth_signature: AuthorizationSignature =
        sender.auth_signing_key.sign(action_tree_root.as_bytes());

    Ok(SplitParameters {
        to_split_resource,
        created_resource,
        remainder_resource,
        padding_resource,
        sender_nullifier_key: sender.clone().nf_key,
        sender_auth_verifying_key: sender.auth_verifying_key(),
        auth_signature,
        receiver_discovery_pk: receiver.discovery_pk,
        receiver_encryption_pk: receiver.encryption_pk,
        sender_discovery_pk: sender.discovery_pk,
        sender_encryption_pk: sender.encryption_pk,
    })
}
