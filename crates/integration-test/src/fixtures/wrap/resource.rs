use alloy::primitives::Address;
use alloy::primitives::U256;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::resource::Resource;
use transfer_witness::calculate_label_ref;
use transfer_witness::calculate_value_ref_from_ethereum_account_addr;

use crate::logic;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_testkit::fixtures::identities::Keychain;

#[derive(Clone, Debug, Default)]
pub struct Overrides {
    pub quantity: Option<u128>,
    pub consumed_value_ref: Option<Digest>,
    pub consumed_label_ref: Option<Digest>,
    pub consumed_is_ephemeral: Option<bool>,
    pub permit_signature: Option<Vec<u8>>,
    /// Ethereum account the wrapped tokens are pulled from (defaults to the
    /// wrapping identity's own address). Set this to wrap tokens held by a
    /// contract — e.g. the generic-call forwarder, which authorizes the Permit2
    /// transfer via ERC-1271, so any `permit_signature` is accepted.
    pub ethereum_account_addr: Option<Vec<u8>>,
}

impl Overrides {
    pub fn invalid_non_ephemeral_consumed() -> Self {
        Self {
            consumed_is_ephemeral: Some(false),
            ..Self::default()
        }
    }

    pub fn invalid_label_ref() -> Self {
        Self {
            consumed_label_ref: Some(Digest::default()),
            ..Self::default()
        }
    }

    pub fn invalid_permit_signature_length() -> Self {
        Self {
            permit_signature: Some(vec![7u8; 64]),
            ..Self::default()
        }
    }
}

pub(super) fn consumed(
    sender: &Keychain,
    forwarder: Address,
    token: Address,
    quantity: u128,
    seed: u8,
    overrides: &Overrides,
) -> Resource {
    let label_ref = overrides
        .consumed_label_ref
        .unwrap_or(calculate_label_ref(forwarder.as_ref(), token.as_ref()));
    let sender_addr = sender.address();
    let value_ref = overrides.consumed_value_ref.unwrap_or_else(|| {
        calculate_value_ref_from_ethereum_account_addr(
            overrides
                .ethereum_account_addr
                .as_deref()
                .unwrap_or(sender_addr.as_ref()),
        )
    });

    Resource {
        logic_ref: logic::verifying_key(),
        label_ref,
        quantity: overrides.quantity.unwrap_or(quantity),
        value_ref,
        is_ephemeral: overrides.consumed_is_ephemeral.unwrap_or(true),
        nonce: [seed; 32],
        nk_commitment: sender.nf_key.commit(),
        rand_seed: [seed.wrapping_add(17); 32],
    }
}

pub(super) fn random_permit_nonce(seed: u8) -> U256 {
    U256::from(seed as u64 + 1)
}
