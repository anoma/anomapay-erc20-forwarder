use alloy::primitives::Address;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_library::TransferLogic;

use super::resource;
use super::resource::Overrides;
use crate::fixtures::action::{self, Logic, Part};
use crate::fixtures::resource::consumed_persistent;
use crate::logic;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_testkit::fixtures::identities;
use anoma_pa_testkit::witness::ActionWitnesses;

/// The derived data of a built unwrap action: the action witnesses plus
/// the persistent resource it consumes and the ephemeral resource it creates
/// to release the tokens.
pub struct ActionData {
    pub witnesses: ActionWitnesses,
    pub consumed_persistent: Resource,
    pub created_ephemeral: Resource,
}

/// The resources of an unwrap: the consumed persistent resource and the
/// created ephemeral resource, whose forwarder call releases the tokens.
pub struct Parts {
    pub consumed: Part,
    pub created: Part,
}

/// Build an unwrap action: the owner (`Overrides::owner`, defaulting to bob)
/// consumes `resource_to_unwrap` and creates an ephemeral resource releasing
/// the tokens to an Ethereum account. Pass the consumed resource's
/// `merkle_path` when it is already in the commitment tree; `None` proves
/// against the initial root.
pub fn build(
    resource_to_unwrap: Resource,
    forwarder: Address,
    token: Address,
    seed: u8,
    merkle_path: Option<MerklePath>,
    overrides: Overrides,
) -> anyhow::Result<ActionData> {
    let Parts { consumed, created } = parts(
        resource_to_unwrap,
        forwarder,
        token,
        seed,
        merkle_path,
        overrides,
    )?;
    let action = action::build(vec![consumed, created])?;
    let [consumed_persistent, created_ephemeral] = <[Resource; 2]>::try_from(action.resources)
        .map_err(|resources| {
            anyhow::anyhow!("an unwrap has 2 resources, not {}", resources.len())
        })?;

    Ok(ActionData {
        witnesses: action.witnesses,
        consumed_persistent,
        created_ephemeral,
    })
}

/// The resources of an unwrap action, for an action that [`action::build`]
/// assembles from several kinds. The owner's signature covers the root of that
/// action.
pub fn parts(
    resource_to_unwrap: Resource,
    forwarder: Address,
    token: Address,
    seed: u8,
    merkle_path: Option<MerklePath>,
    overrides: Overrides,
) -> anyhow::Result<Parts> {
    let owner = match overrides.owner.clone() {
        Some(owner) => owner,
        None => identities::bob()?,
    };

    let mut resource_overrides = overrides.clone();
    if resource_overrides.created_value_ref.is_none()
        && let Some(ethereum_account_addr) = resource_overrides.ethereum_account_addr.as_ref()
    {
        resource_overrides.created_value_ref = Some(
            anomapay_erc20_witness::calculate_value_ref_from_ethereum_account_addr(
                ethereum_account_addr,
            ),
        );
    }

    let mut consumed = resource_to_unwrap;
    if let Some(quantity) = overrides.quantity {
        consumed.quantity = quantity;
    }
    let created = resource::created(
        &owner,
        forwarder,
        token,
        consumed.quantity,
        seed,
        &resource_overrides,
    );

    let ethereum_account_addr = overrides
        .ethereum_account_addr
        .clone()
        .unwrap_or_else(|| owner.address().to_vec());
    let created_logic: Logic = Box::new(move |resource, action_tree_root| {
        Ok(Box::new(logic::Witness::new(
            TransferLogic::burn_resource_logic(
                resource,
                action_tree_root,
                forwarder.to_vec(),
                token.to_vec(),
                ethereum_account_addr,
            )
            .witness,
        )))
    });

    Ok(Parts {
        consumed: consumed_persistent(consumed, owner, merkle_path, overrides.auth_signature),
        created: Part::Created {
            resource: created,
            nonce: None,
            logic: created_logic,
        },
    })
}
