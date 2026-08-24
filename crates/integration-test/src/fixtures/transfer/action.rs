use alloy::primitives::Address;
use anoma_rm_risc0::action_tree::MerkleTree as ArmTree;
use anoma_rm_risc0::compliance::ComplianceWitness;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use transfer_witness::AUTH_SIGNATURE_DOMAIN;
use transfer_witness::EncryptionInfo;
use transfer_witness::LabelInfo;
use transfer_witness::TokenTransferWitness;
use transfer_witness::ValueInfo;

use super::resource::Overrides;
use crate::fixtures::resource::persistent;
use crate::logic;
use anoma_pa_testkit::fixtures::identities;
use anoma_pa_testkit::witness::ActionWitnesses;

/// The derived data of a built transfer action: the action witnesses plus
/// the persistent resources it consumes (the sender's) and creates (the
/// receiver's).
pub struct ActionData {
    pub witnesses: ActionWitnesses,
    pub consumed_persistent: Resource,
    pub created_persistent: Resource,
}

/// Build a transfer action: the sender (alice) consumes `resource_to_transfer`
/// and creates a persistent resource owned by the receiver (bob). Pass the
/// consumed resource's `merkle_path` when it is already in the commitment
/// tree; `None` proves against the initial root.
pub fn build(
    resource_to_transfer: Resource,
    forwarder: Address,
    token: Address,
    seed: u8,
    merkle_path: Option<MerklePath>,
    overrides: Overrides,
) -> anyhow::Result<ActionData> {
    let sender = identities::alice()?;
    let receiver = identities::bob()?;

    let mut consumed = resource_to_transfer;
    if let Some(label_ref) = overrides.consumed_label_ref {
        consumed.label_ref = label_ref;
    }
    if let Some(value_ref) = overrides.consumed_value_ref {
        consumed.value_ref = value_ref;
    }
    if let Some(quantity) = overrides.quantity {
        consumed.quantity = quantity;
    }

    let consumed_nf = consumed.nullifier(&sender.nf_key)?;
    let created = persistent(
        &receiver,
        consumed_nf,
        forwarder,
        token,
        consumed.quantity,
        [seed.wrapping_add(51); 32],
    )?;

    let action_tree_root = ArmTree::new(vec![consumed_nf, created.commitment()]).root()?;

    let auth_sig = match overrides.auth_signature {
        Some(sig) => sig,
        None => sender
            .auth_signing_key
            .sign(AUTH_SIGNATURE_DOMAIN, action_tree_root.as_bytes()),
    };

    let consumed_logic = TokenTransferWitness::new(
        consumed,
        true,
        action_tree_root,
        Some(sender.nf_key.clone()),
        Some(auth_sig),
        None,
        None,
        None,
        Some(ValueInfo {
            auth_pk: sender.auth_verifying_key(),
            encryption_pk: sender.encryption_pk,
        }),
    );

    let created_logic = TokenTransferWitness::new(
        created,
        false,
        action_tree_root,
        None,
        None,
        Some(EncryptionInfo::new(&receiver.discovery_pk)),
        None,
        Some(LabelInfo {
            forwarder_addr: forwarder.to_vec(),
            erc20_token_addr: token.to_vec(),
        }),
        Some(ValueInfo {
            auth_pk: receiver.auth_verifying_key(),
            encryption_pk: receiver.encryption_pk,
        }),
    );

    let compliance = match merkle_path {
        Some(path) => ComplianceWitness::from_resources_with_path(
            consumed,
            sender.nf_key.clone(),
            path,
            created,
        ),
        None => ComplianceWitness::from_resources(
            consumed,
            *anoma_rm_risc0::compliance::INITIAL_ROOT,
            sender.nf_key.clone(),
            created,
        ),
    };

    Ok(ActionData {
        witnesses: ActionWitnesses {
            compliance_witnesses: vec![Box::new(compliance)],
            logic_witnesses: vec![
                Box::new(logic::Witness::new(consumed_logic)),
                Box::new(logic::Witness::new(created_logic)),
            ],
        },
        consumed_persistent: consumed,
        created_persistent: created,
    })
}
