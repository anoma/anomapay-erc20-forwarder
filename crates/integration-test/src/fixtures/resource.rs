//! Shared constructor for the persistent token-transfer resource — created by
//! wrap and transfer, consumed by transfer and unwrap.

use alloy::primitives::Address;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::compliance::KindTableEntry;
use anoma_rm_risc0::resource::Resource;
use anyhow::Context;
use transfer_witness::ValueInfo;
use transfer_witness::calculate_label_ref;
use transfer_witness::calculate_persistent_value_ref;

use crate::logic;
use anoma_pa_testkit::fixtures::identities::Keychain;

/// The kind table the fixtures prove against. Empty, so every kind falls back to
/// hash-to-curve and the commitment matches the protocol adapter's initial
/// `_EMPTY_KIND_TABLE_COMMITMENT`. Proving against a non-empty table additionally
/// requires `init_kind_table_from_file` — `Transaction::verify` fails with
/// `KindTableNotLoaded` without it — and the adapter's stored commitment to agree.
pub(crate) fn kind_table() -> Vec<KindTableEntry> {
    Vec::new()
}

/// The persistent token-transfer resource: label committed to
/// (forwarder, token), value committed to the owner's auth + encryption keys,
/// nonce derived from the nullifier of the resource consumed alongside it.
pub(crate) fn persistent(
    owner: &Keychain,
    consumed_nullifier: Digest,
    forwarder: Address,
    token: Address,
    quantity: u128,
    rand_seed: [u8; 32],
) -> anyhow::Result<Resource> {
    let nonce = Resource::derive_nonce_from_nullifiers(0, &[consumed_nullifier])
        .context("failed to derive the created resource nonce")?;

    Ok(Resource {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref(), token.as_ref()),
        quantity,
        value_ref: calculate_persistent_value_ref(&ValueInfo {
            auth_pk: owner.auth_verifying_key(),
            encryption_pk: owner.encryption_pk,
        }),
        is_ephemeral: false,
        nonce,
        nk_commitment: owner.nf_key.commit(),
        rand_seed,
    })
}
