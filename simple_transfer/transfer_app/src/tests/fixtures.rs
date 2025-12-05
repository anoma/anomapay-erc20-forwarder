#![cfg(test)]
//! Contains fixtures to generate test data in the test suite.

use crate::AnomaPayConfig;
use crate::rpc::named_chain_from_config;
use crate::tests::permit2::{Permit2Data, permit_witness_transfer_from_signature};
use crate::user::Keychain;
use alloy::hex::ToHexExt;
use alloy::primitives::{Address, B256, Signature, U256, address};
use alloy::signers::local::PrivateKeySigner;
use arm::action_tree::MerkleTree;
use erc20_forwarder_bindings::addresses::erc20_forwarder_address;
use rand::Rng;
use risc0_zkvm::sha::{Digest, Impl, Sha256};

pub const TOKEN_ADDRESS_SEPOLIA_USDC: Address =
    address!("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");

pub const DEFAULT_DEADLINE: u64 = 1893456000;

/// Creates a keychain to represent a user.
pub fn user_with_private_key(config: &AnomaPayConfig) -> Keychain {
    Keychain::alice(
        config.hot_wallet_private_key.address().encode_hex(),
        Some(config.hot_wallet_private_key.clone()),
    )
}

/// Creates a keychain to represent a user.
pub fn user_without_private_key() -> Keychain {
    Keychain::bob(None)
}

/// Generates a random nonce. A nonce is an array of 32 8-byte integers.
pub fn random_nonce() -> [u8; 32] {
    let mut rng = rand::rng();
    let nonce: [u8; 32] = rng.random();
    nonce
}

/// The label ref for a resource in the AnomaPay backend uniquely identifies the resource. This
/// value allows us to distinguish between wrapped USDC or USDT tokens, for example. The
/// forwarder contract is used for multiple tokens, so the tuple (forwarder address, token
/// contract) uniquely identifies a resource.
pub fn label_ref(config: &AnomaPayConfig, erc20_token_addr: Address) -> Digest {
    let named_chain = named_chain_from_config(config).unwrap();
    let forwarder_address = erc20_forwarder_address(&named_chain).unwrap();

    *Impl::hash_bytes(&[forwarder_address.to_vec(), erc20_token_addr.to_vec()].concat())
}

/// Create a permit2 signature for a transaction.
pub async fn create_permit_signature(
    private_key: &PrivateKeySigner,
    action_tree: MerkleTree,
    nullifier: [u8; 32],
    amount: u128,
    config: &AnomaPayConfig,
    erc20_token: Address,
    deadline: u64,
) -> Signature {
    let action_tree_root: Digest = action_tree
        .root()
        .expect("failed to create action tree root");
    let action_tree_encoded: &[u8] = action_tree_root.as_ref();

    let named_chain = named_chain_from_config(config).unwrap();

    let x = Permit2Data {
        chain_id: 11155111,
        token: erc20_token,
        amount: U256::from(amount),
        nonce: U256::from_be_bytes(nullifier),
        deadline: U256::from(deadline),
        spender: erc20_forwarder_address(&named_chain).unwrap(),
        action_tree_root: B256::from_slice(action_tree_encoded),
    };

    permit_witness_transfer_from_signature(private_key, x).await
}
