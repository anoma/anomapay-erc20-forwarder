//! The persistent token-transfer resource and its parts — created by wrap and
//! transfer, consumed by transfer and unwrap.

use alloy::primitives::Address;
use anoma_rm_risc0::kind_tree::KindTree;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;
use anomapay_erc20_library::TransferLogic;
use anomapay_erc20_witness::AUTH_SIGNATURE_DOMAIN;
use anomapay_erc20_witness::ValueInfo;
use anomapay_erc20_witness::calculate_label_ref;
use anomapay_erc20_witness::calculate_persistent_value_ref;
use std::sync::LazyLock;

use crate::fixtures::action::Part;
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

/// The created part of a persistent resource of `owner`. `nonce` replaces the
/// nonce that [`super::action::build`] derives.
pub(crate) fn created_persistent(
    owner: &Keychain,
    forwarder: Address,
    token: Address,
    quantity: u128,
    rand_seed: [u8; 32],
    nonce: Option<[u8; 32]>,
) -> Part {
    let discovery_pk = owner.discovery_pk;
    let auth_pk = owner.auth_verifying_key();
    let encryption_pk = owner.encryption_pk;
    Part::Created {
        resource: persistent(owner, forwarder, token, quantity, rand_seed),
        nonce,
        logic: Box::new(move |resource, action_tree_root| {
            Ok(Box::new(logic::Witness::new(
                TransferLogic::create_persistent_resource_logic(
                    resource,
                    action_tree_root,
                    &discovery_pk,
                    auth_pk,
                    encryption_pk,
                    forwarder.to_vec(),
                    token.to_vec(),
                )
                .witness,
            )))
        }),
    }
}

/// The consumed part of a persistent resource of `owner`. The owner signs the
/// action tree root, unless `auth_signature` is set.
pub(crate) fn consumed_persistent(
    resource: Resource,
    owner: Keychain,
    merkle_path: Option<MerklePath>,
    auth_signature: Option<AuthoritySignature>,
) -> Part {
    Part::Consumed {
        resource,
        nf_key: owner.nf_key.clone(),
        merkle_path,
        logic: Box::new(move |resource, action_tree_root| {
            let auth_sig = auth_signature.unwrap_or_else(|| {
                owner
                    .auth_signing_key
                    .sign(AUTH_SIGNATURE_DOMAIN, action_tree_root.as_bytes())
            });
            Ok(logic::consumed_persistent(
                resource,
                action_tree_root,
                &owner,
                auth_sig,
            ))
        }),
    }
}
