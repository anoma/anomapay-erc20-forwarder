#![cfg(test)]
//! Contains fixtures to generate test data in the test suite.

use crate::tests::permit2::{permit_witness_transfer_from_signature, Permit2Data};
use crate::user::Keychain;
use crate::AnomaPayConfig;
use alloy::hex::ToHexExt;
use alloy::primitives::{address, Address, Signature, B256, U256};
use alloy::signers::local::PrivateKeySigner;
use arm::action_tree::MerkleTree;
use arm::compliance::INITIAL_ROOT;
use arm::evm::CallType;
use rand::Rng;
use risc0_zkvm::sha::{Digest, Impl, Sha256};

pub const TOKEN_ADDRESS_SEPOLIA_USDC: Address =
    address!("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");

pub const DEFAULT_DEADLINE: u64 = 1893456000;

/// Return the default intial root.
pub fn default_commitment_tree_root() -> Digest {
    *INITIAL_ROOT
}

/// Creates a keychain to represent a user.
pub fn user_with_private_key(config: &AnomaPayConfig) -> Keychain {
    Keychain::alice(
        config.hot_wallet_address.encode_hex(),
        Some(config.hot_wallet_private_key.clone()),
    )
}

/// Generates a random nonce. A nonce is an array of 32 8-byte integers.
pub fn random_nonce() -> [u8; 32] {
    let mut rng = rand::thread_rng();
    let nonce: [u8; 32] = rng.gen();
    nonce
}

/// The label ref for a resource in the AnomaPay backend uniquely identifies the resource. This
/// value allows us to distinguish between wrapped USDC or USDT tokens, for example. The
/// forwarder contract is used for multiple tokens, so the tuple (forwarder address, token
/// contract) uniquely identifies a resource.
pub fn label_ref(config: &AnomaPayConfig, token_address: Address) -> Digest {
    *Impl::hash_bytes(&[config.forwarder_address.to_vec(), token_address.to_vec()].concat())
}
pub fn value_ref(call_type: CallType, user_addr: &[u8]) -> Digest {
    let mut data = vec![call_type as u8];
    data.extend_from_slice(user_addr);
    *Impl::hash_bytes(&data)
}

/// The value ref for an ephemeral resource in a minting transaction has to hold the calltype. A
/// minting transaction means you create a resource, and consume an ephemeral resource. Therefore
/// the consumed ephemeral resource needs to have the wrapping calltype.
pub fn value_ref_ephemeral_consumed(user: &Keychain) -> Digest {
    value_ref(CallType::Wrap, user.evm_address.as_ref())
}

/// The value ref for a created resource in a mint transaction needs to hold the verifying key of
/// the owner of the resource. This can be any persons' verifying key, but in this case we use
/// the verifying key of the person who mints the transaction.
///
/// The value ref for a created resource in a transfer transaction is the verifying key of the
/// receiver.
///
/// The intuition here is that the value ref defines the owner of the resource.
pub fn value_ref_created(keychain: &Keychain) -> Digest {
    *Impl::hash_bytes(&keychain.auth_verifying_key().to_bytes())
}

/// Create a permit2 signature for a transaction.
pub async fn create_permit_signature(
    private_key: &PrivateKeySigner,
    action_tree: MerkleTree,
    nullifier: [u8; 32],
    amount: u128,
    config: &AnomaPayConfig,
    token_address: Address,
    deadline: u64,
) -> Signature {
    let action_tree_root: Digest = action_tree.root();
    let action_tree_encoded: &[u8] = action_tree_root.as_ref();

    let x = Permit2Data {
        chain_id: 11155111,
        token: token_address,
        amount: U256::from(amount),
        nonce: U256::from_be_bytes(nullifier),
        deadline: U256::from(deadline),
        spender: config.forwarder_address,
        action_tree_root: B256::from_slice(action_tree_encoded),
    };

    permit_witness_transfer_from_signature(private_key, x).await
}
