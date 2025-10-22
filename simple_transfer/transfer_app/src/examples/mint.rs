use crate::errors::TransactionError;
use crate::errors::TransactionError::{EncodingError, InvalidKeyChain, InvalidNullifierSizeError};
use crate::examples::shared::{
    create_permit_signature, label_ref, random_nonce, value_ref, value_ref_created,
};
use crate::examples::{DEFAULT_AMOUNT, DEFAULT_DEADLINE, TOKEN_ADDRESS_SEPOLIA_USDC};
use crate::requests::mint::CreateRequest;
use crate::requests::Expand;
use crate::user::Keychain;
use crate::AnomaPayConfig;
use alloy::hex::ToHexExt;
use arm::action_tree::MerkleTree;
use arm::compliance::INITIAL_ROOT;
use arm::evm::CallType;
use arm::logic_proof::LogicProver;
use arm::resource::Resource;
use arm::utils::words_to_bytes;
use arm::Digest;
use serde_json::to_string_pretty;
use transfer_library::TransferLogic;

/// The value ref for an ephemeral resource in a minting transaction has to hold the calltype. A
/// minting transaction means you create a resource, and consume an ephemeral resource. Therefore
/// the consumed ephemeral resource needs to have the wrapping calltype.
pub fn value_ref_ephemeral_mint(minter: &Keychain) -> Digest {
    value_ref(CallType::Wrap, minter.evm_address.as_ref())
}

/// Creates a json string for a mint request example.
pub async fn json_example_mint_request(
    config: &AnomaPayConfig,
) -> Result<String, TransactionError> {
    let alice = Keychain::alice(
        config.hot_wallet_address.encode_hex(),
        Some(config.hot_wallet_private_key.clone()),
    );

    let create_request = mint_request_example(alice, DEFAULT_AMOUNT as u128, config).await?;
    let json_str = to_string_pretty(&create_request).map_err(|_| EncodingError)?;
    Ok(json_str)
}

/// Creates an example of a mint request
pub async fn mint_request_example(
    minter: Keychain,
    amount: u128,
    config: &AnomaPayConfig,
) -> Result<CreateRequest, TransactionError> {
    // A minting transaction does not consume existing resources, so there is no need to get the
    // commitment tree root for anything, and the initial root can be used.
    let latest_commitment_tree_root: Vec<u32> = INITIAL_ROOT.as_words().to_vec();

    ////////////////////////////////////////////////////////////////////////////
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

    // create the nullifier for the created resource.
    // why do we use the nullifier based on the nullifier key from the minter here?
    // I presume because we used the commitment based off of this key for the ephemeral resource.
    // therefore the nullifier for the ephemeral resource is also derived from the nullifier key?
    let consumed_resource_nullifier = consumed_resource
        .nullifier(&minter.nf_key)
        .map_err(|_| InvalidKeyChain)?;

    ////////////////////////////////////////////////////////////////////////////
    // Construct the created resource

    // The nonce for the created resource must be the consumed resource's nullifier. The consumed
    // resource is the ephemeral resource that was created above.
    let nonce = consumed_resource_nullifier
        .as_bytes()
        .try_into()
        .map_err(|_| InvalidNullifierSizeError)?;

    let created_resource = Resource {
        logic_ref: TransferLogic::verifying_key(),
        label_ref: label_ref(config, TOKEN_ADDRESS_SEPOLIA_USDC),
        quantity: amount,
        value_ref: value_ref_created(&minter),
        is_ephemeral: false,
        nonce,
        nk_commitment: minter.nf_key.commit(),
        rand_seed: [6u8; 32],
    };

    let created_resource_commitment: Digest = created_resource.commitment();

    ////////////////////////////////////////////////////////////////////////////
    // Create the action tree

    let action_tree: MerkleTree = MerkleTree::new(vec![
        consumed_resource_nullifier,
        created_resource_commitment,
    ]);

    ////////////////////////////////////////////////////////////////////////////
    // Create the permit signature

    let minter_private_key = minter.private_key.ok_or(InvalidKeyChain)?;

    let nullifier: [u8; 32] = consumed_resource_nullifier.into();

    let permit_signature = create_permit_signature(
        &minter_private_key,
        action_tree.clone(),
        nullifier,
        amount,
        config,
        TOKEN_ADDRESS_SEPOLIA_USDC,
        DEFAULT_DEADLINE,
    )
    .await;

    Ok(CreateRequest {
        consumed_resource: consumed_resource.simplify(),
        created_resource: created_resource.simplify(),
        latest_cm_tree_root: words_to_bytes(latest_commitment_tree_root.as_slice()).to_vec(),
        consumed_nf_key: minter.nf_key.inner().to_vec(),
        forwarder_addr: config.forwarder_address.to_vec(),
        token_addr: TOKEN_ADDRESS_SEPOLIA_USDC.to_vec(),
        user_addr: minter.evm_address.to_vec(),
        permit_nonce: nonce.to_vec(),
        permit_deadline: DEFAULT_DEADLINE,
        permit_sig: permit_signature.as_bytes().to_vec(),
        created_discovery_pk: minter.discovery_pk,
        created_encryption_pk: minter.encryption_pk,
    })
}
