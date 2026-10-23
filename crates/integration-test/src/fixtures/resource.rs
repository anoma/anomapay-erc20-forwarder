//! Shared constructor for the persistent token-transfer resource — created by
//! wrap and transfer, consumed by transfer and unwrap.

use alloy::primitives::Address;
use anoma_rm_risc0::kind_tree::KindTree;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_witness::ValueInfo;
use anomapay_erc20_witness::calculate_label_ref;
use anomapay_erc20_witness::calculate_persistent_value_ref;
use std::sync::LazyLock;

use crate::logic;
use anoma_pa_testkit::fixtures::identities::Keychain;

static EMPTY_KIND_TREE: LazyLock<KindTree> = LazyLock::new(KindTree::empty);

/// The kind tree the fixtures prove against: the loaded one, or the empty tree
/// if none is loaded. The e2e setup loads none; a test that needs an alias loads its tree first.
pub(crate) fn kind_tree() -> &'static KindTree {
    anoma_rm_risc0::constants::global_kind_tree().unwrap_or(&EMPTY_KIND_TREE)
}

/// The persistent token-transfer resource: label committed to
/// (forwarder, token), value committed to the owner's auth + encryption keys.
/// [`super::action::build`] sets its nonce.
pub(crate) fn persistent(
    owner: &Keychain,
    forwarder: Address,
    token: Address,
    quantity: u128,
    rand_seed: [u8; 32],
) -> Resource {
    Resource {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref(), token.as_ref()),
        quantity,
        value_ref: calculate_persistent_value_ref(&ValueInfo {
            auth_pk: owner.auth_verifying_key(),
            encryption_pk: owner.encryption_pk,
        }),
        is_ephemeral: false,
        nonce: [0; 32],
        nk_commitment: owner.nf_key.commit(),
        rand_seed,
    }
}
