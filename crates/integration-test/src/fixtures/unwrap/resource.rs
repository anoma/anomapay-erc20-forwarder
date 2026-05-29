use alloy::primitives::Address;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::resource::Resource;
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;
use anyhow::Context;
use transfer_witness::calculate_label_ref;
use transfer_witness::calculate_value_ref_from_ethereum_account_addr;

use crate::logic;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_testkit::fixtures::identities::Keychain;

// No `Debug`: `Keychain` is not `Debug` (it holds signing keys).
#[derive(Clone, Default)]
pub struct Overrides {
    /// The identity that owns — and thus nullifies — the consumed resource
    /// (defaults to bob, the receiver of the transfer-bridged flows; a
    /// same-owner wrap→unwrap passes the original wrapper).
    pub owner: Option<Keychain>,
    pub quantity: Option<u128>,
    pub created_value_ref: Option<Digest>,
    pub created_label_ref: Option<Digest>,
    pub created_is_ephemeral: Option<bool>,
    /// Ethereum account the unwrapped tokens are released to (defaults to the
    /// owner's own address).
    pub ethereum_account_addr: Option<Vec<u8>>,
    pub auth_signature: Option<AuthoritySignature>,
}

impl Overrides {
    pub fn invalid_created_non_ephemeral() -> Self {
        Self {
            created_is_ephemeral: Some(false),
            ..Self::default()
        }
    }

    pub fn invalid_value_ref() -> Self {
        Self {
            created_value_ref: Some(Digest::default()),
            ..Self::default()
        }
    }
}

pub(super) fn created(
    owner: &Keychain,
    consumed_nullifier: Digest,
    forwarder: Address,
    token: Address,
    quantity: u128,
    seed: u8,
    overrides: &Overrides,
) -> anyhow::Result<Resource> {
    let nonce: [u8; 32] = consumed_nullifier
        .as_bytes()
        .try_into()
        .context("nullifier must be 32 bytes")?;

    let label_ref = overrides
        .created_label_ref
        .unwrap_or(calculate_label_ref(forwarder.as_ref(), token.as_ref()));
    let value_ref =
        overrides
            .created_value_ref
            .unwrap_or(calculate_value_ref_from_ethereum_account_addr(
                owner.address().as_ref(),
            ));

    Ok(Resource {
        logic_ref: logic::verifying_key(),
        label_ref,
        quantity: overrides.quantity.unwrap_or(quantity),
        value_ref,
        is_ephemeral: overrides.created_is_ephemeral.unwrap_or(true),
        nonce,
        nk_commitment: owner.nf_key.commit(),
        rand_seed: [seed.wrapping_add(71); 32],
    })
}
