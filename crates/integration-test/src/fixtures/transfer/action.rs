use alloy::primitives::Address;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;

use super::resource::Overrides;
use crate::fixtures::action::{self, Part};
use crate::fixtures::resource::{consumed_persistent, created_persistent};
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

/// The resources of a transfer: the sender's consumed persistent resource and
/// the receiver's created persistent resource.
pub struct Parts {
    pub consumed: Part,
    pub created: Part,
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
    let Parts { consumed, created } = parts(
        resource_to_transfer,
        forwarder,
        token,
        seed,
        merkle_path,
        overrides,
    )?;
    let action = action::build(vec![consumed, created])?;
    let [consumed_persistent, created_persistent] = <[Resource; 2]>::try_from(action.resources)
        .map_err(|resources| {
            anyhow::anyhow!("a transfer has 2 resources, not {}", resources.len())
        })?;

    Ok(ActionData {
        witnesses: action.witnesses,
        consumed_persistent,
        created_persistent,
    })
}

/// The resources of a transfer action, for an action that [`action::build`]
/// assembles from several kinds. The sender's signature covers the root of
/// that action.
pub fn parts(
    resource_to_transfer: Resource,
    forwarder: Address,
    token: Address,
    seed: u8,
    merkle_path: Option<MerklePath>,
    overrides: Overrides,
) -> anyhow::Result<Parts> {
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

    Ok(Parts {
        consumed: consumed_persistent(consumed, sender, merkle_path, overrides.auth_signature),
        created: created_persistent(
            &receiver,
            forwarder,
            token,
            consumed.quantity,
            [seed.wrapping_add(51); 32],
            overrides.created_nonce,
        ),
    })
}
