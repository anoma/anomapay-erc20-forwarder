//! The ephemeral migrate resource, whose forwarder call migrates persistent resources with a vulnerable logic ref after
//! the emergency upgrade: the forwarder records their nullifiers as migrated, and the action creates
//! [`super::persistent`] resources that hold their tokens.

use alloy::primitives::Address;
use anoma_pa_testkit::fixtures::action::ActionResource;
use anoma_pa_testkit::fixtures::identities::Keychain;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use anomapay_emergency_migrating_erc20_library::{
    EmergencyMigratingTransferLogic, MigrateEntryParams,
};
use anomapay_emergency_migrating_erc20_witness::EMERGENCY_MIGRATING_AUTH_SIGNATURE_DOMAIN;
use anomapay_erc20_witness::calculate_label_ref;

use crate::fixtures::emergency_migrating::verifying_key;

/// An ephemeral resource of `owner` whose forwarder call migrates `vulnerable`: persistent resources of `owner` with a
/// vulnerable logic ref that hold `token` in `forwarder`, each with the path of its commitment. The owner signs the
/// action tree root once for all of them. `nonce` sets its nonce and random seed.
pub fn consumed(
    owner: &Keychain,
    forwarder: Address,
    token: Address,
    vulnerable: Vec<(Resource, MerklePath)>,
    nonce: [u8; 32],
) -> ActionResource {
    let resource = Resource {
        logic_ref: verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref(), token.as_ref()),
        quantity: vulnerable
            .iter()
            .map(|(resource, _)| resource.quantity)
            .sum(),
        value_ref: Digest::default(),
        is_ephemeral: true,
        nonce,
        nk_commitment: owner.nf_key.commit(),
        rand_seed: nonce,
    };
    let owner = owner.clone();
    ActionResource::consumed(
        resource,
        owner.nf_key.clone(),
        MerklePath::empty(),
        move |resource, action_tree_root| {
            let auth_signature = owner.auth_signing_key.sign(
                EMERGENCY_MIGRATING_AUTH_SIGNATURE_DOMAIN,
                action_tree_root.as_bytes(),
            );
            let entries = vulnerable
                .into_iter()
                .map(|(resource, path)| MigrateEntryParams {
                    resource,
                    nf_key: owner.nf_key.clone(),
                    path,
                    auth_pk: owner.auth_verifying_key(),
                    encryption_pk: owner.encryption_pk,
                    forwarder_addr: forwarder.to_vec(),
                })
                .collect();
            Ok(EmergencyMigratingTransferLogic::migrate_resource_logic(
                resource,
                action_tree_root,
                owner.nf_key.clone(),
                forwarder.to_vec(),
                token.to_vec(),
                auth_signature,
                entries,
            ))
        },
    )
}
