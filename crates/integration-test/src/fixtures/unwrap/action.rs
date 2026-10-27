use alloy::primitives::Address;
use anoma_pa_testkit::fixtures::action::ActionResource;
use anoma_pa_testkit::fixtures::identities;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_library::TransferLogic;

use super::resource;
use super::resource::Overrides;
use crate::fixtures::resource::consumed_persistent;
use anoma_pa_evm_integration_test::keychain::EvmSigner;

/// The resources of an unwrap: the consumed persistent resource of the owner
/// (`Overrides::owner`, defaulting to bob), signed over the action tree root, and the created
/// ephemeral resource, whose forwarder call releases the tokens to an Ethereum account. Pass the
/// `merkle_path` of the consumed resource when it is in the commitment tree.
pub fn resources(
    resource_to_unwrap: Resource,
    forwarder: Address,
    token: Address,
    seed: u8,
    merkle_path: Option<MerklePath>,
    overrides: Overrides,
) -> anyhow::Result<[ActionResource; 2]> {
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
    let created = ActionResource::created(created, move |resource, action_tree_root| {
        Ok(TransferLogic::burn_resource_logic(
            resource,
            action_tree_root,
            forwarder.to_vec(),
            token.to_vec(),
            ethereum_account_addr,
        ))
    });

    Ok([
        consumed_persistent(consumed, owner, merkle_path, overrides.auth_signature),
        created,
    ])
}
