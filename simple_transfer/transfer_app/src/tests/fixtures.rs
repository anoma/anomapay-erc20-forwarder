#![cfg(test)]

use crate::user::Keychain;
use crate::AnomaPayConfig;
use alloy::hex::ToHexExt;

/// Helper function to create the keychain for alice.
/// Alice has a private key and can create minting transactions.
/// The address and private key for alice are read from the environment to test actual submission
/// to sepolia.
pub fn alice_keychain(config: &AnomaPayConfig) -> Keychain {
    let keychain = Keychain::alice(
        config.hot_wallet_address.encode_hex(),
        Some(config.hot_wallet_private_key.clone()),
    );
    keychain
}

/// Helper function to geneate the keychain for bob.
/// Bob has no private key and is always the recipient of resources.
///
/// bob also has a fixed address, as opposed to alice.
/// Alice her address is read from the environment as it is used to submit tranasctions to sepolia.
pub fn bob_keychain() -> Keychain {
    Keychain::bob(None)
}
