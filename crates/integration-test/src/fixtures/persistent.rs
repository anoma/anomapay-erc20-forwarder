//! The persistent ERC20 resource, which holds wrapped tokens for an owner. Wraps and transfers
//! create it. Transfers and unwraps consume it.

use alloy::primitives::Address;
use anoma_pa_testkit::fixtures::action::{ActionResource, ResourceToCreate};
use anoma_pa_testkit::fixtures::identities::Keychain;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;
use anomapay_erc20_library::TransferLogic;
use anomapay_erc20_witness::{
    AUTH_SIGNATURE_DOMAIN, ValueInfo, calculate_label_ref, calculate_persistent_value_ref,
};

use crate::fixtures::CREATED_RAND_SEED;
use crate::logic;

/// The persistent `resource` of `owner`, consumed with the owner's signature over the action tree
/// root, or with `auth_signature` if set. `merkle_path` is the path of its commitment in the
/// commitment tree.
pub fn consumed(
    owner: &Keychain,
    resource: Resource,
    merkle_path: MerklePath,
    auth_signature: Option<AuthoritySignature>,
) -> ActionResource {
    let owner = owner.clone();
    ActionResource::consumed(
        resource,
        owner.nf_key.clone(),
        merkle_path,
        move |resource, action_tree_root| {
            let auth_signature = auth_signature.unwrap_or_else(|| {
                owner
                    .auth_signing_key
                    .sign(AUTH_SIGNATURE_DOMAIN, action_tree_root.as_bytes())
            });
            Ok(logic::consumed_persistent(
                resource,
                action_tree_root,
                &owner,
                auth_signature,
            ))
        },
    )
}

/// A persistent resource of `owner` that holds `quantity` tokens of `token` in `forwarder`.
pub fn created(
    owner: &Keychain,
    forwarder: Address,
    token: Address,
    quantity: u128,
) -> ActionResource {
    let auth_pk = owner.auth_verifying_key();
    let encryption_pk = owner.encryption_pk;
    let discovery_pk = owner.discovery_pk;
    let resource = ResourceToCreate {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref(), token.as_ref()),
        quantity,
        value_ref: calculate_persistent_value_ref(&ValueInfo {
            auth_pk,
            encryption_pk,
        }),
        is_ephemeral: false,
        nk_commitment: owner.nf_key.commit(),
        rand_seed: CREATED_RAND_SEED,
    };
    ActionResource::created(resource, move |resource, action_tree_root| {
        Ok(TransferLogic::create_persistent_resource_logic(
            resource,
            action_tree_root,
            &discovery_pk,
            auth_pk,
            encryption_pk,
            forwarder.to_vec(),
            token.to_vec(),
        ))
    })
}
