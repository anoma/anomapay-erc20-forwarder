//! One action from resources of any kind, in the order of a list. The protocol adapter processes the resources of an
//! action in this order, so the list also sets the order of their forwarder calls.

use anoma_pa_testkit::witness::{ActionWitnesses, LogicWitness};
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::action_tree::ActionTree;
use anoma_rm_risc0::compliance;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::nullifier_key::NullifierKey;
use anoma_rm_risc0::resource::{ConsumedResourceWitness, Resource, ResourceWitness};
use anyhow::Context;

use super::resource::kind_tree;

/// Builds the logic witness of a resource from the resource and the root of its action tree.
pub type Logic = Box<dyn FnOnce(Resource, Digest) -> anyhow::Result<Box<dyn LogicWitness>>>;

/// A resource of an action and the function that builds its logic witness.
pub enum Part {
    /// A consumed resource and the key that nullifies it. A `merkle_path` of `None` proves against the initial root.
    Consumed {
        resource: Resource,
        nf_key: NullifierKey,
        merkle_path: Option<MerklePath>,
        logic: Logic,
    },
    /// A created resource. [`build`] derives its nonce, unless `nonce` is set.
    Created {
        resource: Resource,
        nonce: Option<[u8; 32]>,
        logic: Logic,
    },
}

/// The derived data of a built action: the action witnesses and the resources in the order of the parts.
pub struct ActionData {
    pub witnesses: ActionWitnesses,
    pub resources: Vec<Resource>,
}

/// Builds one action from `parts`, in this order. The nonce of a created resource derives from its index among the
/// created resources and from the consumed nullifiers, both in this order.
pub fn build(parts: Vec<Part>) -> anyhow::Result<ActionData> {
    let nullifiers = parts
        .iter()
        .filter_map(|part| match part {
            Part::Consumed {
                resource, nf_key, ..
            } => Some(resource.nullifier(nf_key)),
            Part::Created { .. } => None,
        })
        .collect::<Result<Vec<Digest>, _>>()
        .context("failed to compute the consumed nullifiers")?;

    let mut created_index = 0;
    let mut resources = Vec::with_capacity(parts.len());
    let mut tags = Vec::with_capacity(parts.len());
    for part in &parts {
        match part {
            Part::Consumed {
                resource, nf_key, ..
            } => {
                tags.push(resource.nullifier(nf_key)?);
                resources.push(*resource);
            }
            Part::Created {
                resource, nonce, ..
            } => {
                let mut created = *resource;
                created.nonce = match nonce {
                    Some(nonce) => *nonce,
                    None => Resource::derive_nonce_from_nullifiers(created_index, &nullifiers)
                        .with_context(|| {
                            format!(
                                "failed to derive the nonce of created resource {created_index}"
                            )
                        })?,
                };
                created_index += 1;
                tags.push(created.commitment());
                resources.push(created);
            }
        }
    }
    let action_tree_root = ActionTree::new(tags)
        .root()
        .context("failed to compute the action tree root")?;

    let mut resource_witnesses = Vec::with_capacity(parts.len());
    let mut logic_witnesses = Vec::with_capacity(parts.len());
    for (position, (part, &resource)) in parts.into_iter().zip(&resources).enumerate() {
        let logic = match part {
            Part::Consumed {
                nf_key,
                merkle_path,
                logic,
                ..
            } => {
                resource_witnesses.push(ResourceWitness::Consumed(match merkle_path {
                    Some(path) => {
                        ConsumedResourceWitness::from_resource_with_path(resource, nf_key, path)
                    }
                    None => ConsumedResourceWitness::from_resource(resource, nf_key),
                }));
                logic
            }
            Part::Created { logic, .. } => {
                resource_witnesses.push(ResourceWitness::Created(resource));
                logic
            }
        };
        logic_witnesses.push(logic(resource, action_tree_root).with_context(|| {
            format!("failed to build the logic witness of resource {position}")
        })?);
    }

    Ok(ActionData {
        witnesses: ActionWitnesses {
            compliance_witness: Box::new(compliance::from_resources(
                resource_witnesses,
                kind_tree(),
            )),
            logic_witnesses,
        },
        resources,
    })
}
