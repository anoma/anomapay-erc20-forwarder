use alloy::primitives::Address;
use anoma_pa_testkit::fixtures::action::ActionResource;
use anoma_pa_testkit::fixtures::identities;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;

use super::resource::Overrides;
use crate::fixtures::resource::{consumed_persistent, created_persistent};

/// The resources of a transfer: the consumed persistent resource of the sender (alice), signed
/// over the action tree root, and the created persistent resource of the receiver (bob). Pass the
/// `merkle_path` of the consumed resource when it is in the commitment tree.
pub fn resources(
    resource_to_transfer: Resource,
    forwarder: Address,
    token: Address,
    seed: u8,
    merkle_path: Option<MerklePath>,
    overrides: Overrides,
) -> anyhow::Result<[ActionResource; 2]> {
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

    Ok([
        consumed_persistent(consumed, sender, merkle_path, overrides.auth_signature),
        created_persistent(
            &receiver,
            forwarder,
            token,
            consumed.quantity,
            [seed.wrapping_add(51); 32],
        ),
    ])
}
