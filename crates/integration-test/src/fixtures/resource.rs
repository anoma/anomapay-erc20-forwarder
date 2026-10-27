//! The persistent ERC20 resource and its action resources — created by wrap and transfer, consumed
//! by transfer and unwrap.

use alloy::primitives::Address;
use anoma_pa_testkit::fixtures::action::{ActionResource, ResourceToCreate};
use anoma_pa_testkit::fixtures::identities::Keychain;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;
use anomapay_erc20_library::TransferLogic;
use anomapay_erc20_witness::AUTH_SIGNATURE_DOMAIN;
use anomapay_erc20_witness::ValueInfo;
use anomapay_erc20_witness::calculate_label_ref;
use anomapay_erc20_witness::calculate_persistent_value_ref;

use crate::logic;

/// The persistent ERC20 resource of `owner` to create: label committed to (forwarder, token),
/// value committed to the owner's auth and encryption keys.
pub(crate) fn persistent(
    owner: &Keychain,
    forwarder: Address,
    token: Address,
    quantity: u128,
    rand_seed: [u8; 32],
) -> ResourceToCreate {
    ResourceToCreate {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref(), token.as_ref()),
        quantity,
        value_ref: calculate_persistent_value_ref(&ValueInfo {
            auth_pk: owner.auth_verifying_key(),
            encryption_pk: owner.encryption_pk,
        }),
        is_ephemeral: false,
        nk_commitment: owner.nf_key.commit(),
        rand_seed,
    }
}

/// A created persistent resource of `owner`.
pub(crate) fn created_persistent(
    owner: &Keychain,
    forwarder: Address,
    token: Address,
    quantity: u128,
    rand_seed: [u8; 32],
) -> ActionResource {
    let discovery_pk = owner.discovery_pk;
    let auth_pk = owner.auth_verifying_key();
    let encryption_pk = owner.encryption_pk;
    ActionResource::created(
        persistent(owner, forwarder, token, quantity, rand_seed),
        move |resource, action_tree_root| {
            Ok(TransferLogic::create_persistent_resource_logic(
                resource,
                action_tree_root,
                &discovery_pk,
                auth_pk,
                encryption_pk,
                forwarder.to_vec(),
                token.to_vec(),
            ))
        },
    )
}

/// A consumed persistent resource of `owner`. The owner signs the action tree root, unless
/// `auth_signature` is set. `None` is an empty `merkle_path`.
pub(crate) fn consumed_persistent(
    resource: Resource,
    owner: Keychain,
    merkle_path: Option<MerklePath>,
    auth_signature: Option<AuthoritySignature>,
) -> ActionResource {
    let nf_key = owner.nf_key.clone();
    ActionResource::consumed(
        resource,
        nf_key,
        merkle_path.unwrap_or_else(MerklePath::empty),
        move |resource, action_tree_root| {
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
        },
    )
}
