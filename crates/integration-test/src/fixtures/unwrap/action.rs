use alloy::primitives::Address;
use anoma_rm_risc0::action_tree::ActionTree as ArmTree;
use anoma_rm_risc0::compliance;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::{ConsumedResourceWitness, Resource, ResourceWitness};
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;
use anomapay_erc20_witness::AUTH_SIGNATURE_DOMAIN;
use anomapay_erc20_witness::ForwarderInfo;
use anomapay_erc20_witness::LabelInfo;
use anomapay_erc20_witness::OrderingInfo;
use anomapay_erc20_witness::TokenTransferWitness;
use anomapay_erc20_witness::call_type::CallType;

use super::resource;
use super::resource::Overrides;
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

    let consumed_nf = consumed.nullifier(&owner.nf_key)?;
    let created = resource::created(
        &owner,
        consumed_nf,
        forwarder,
        token,
        consumed.quantity,
        seed,
        &resource_overrides,
    )?;

    let action_tree_root = ArmTree::new(vec![consumed_nf, created.commitment()]).root()?;

    let auth_sig: AuthoritySignature = match overrides.auth_signature {
        Some(sig) => sig,
        None => owner
            .auth_signing_key
            .sign(AUTH_SIGNATURE_DOMAIN, action_tree_root.as_bytes()),
    };

    let consumed_logic = logic::consumed_persistent(consumed, action_tree_root, &owner, auth_sig);

    let created_logic = TokenTransferWitness::new(
        created,
        false,
        action_tree_root,
        None,
        None,
        None,
        Some(ForwarderInfo {
            call_type: CallType::Unwrap,
            ethereum_account_addr: overrides
                .ethereum_account_addr
                .clone()
                .unwrap_or_else(|| owner.address().to_vec()),
            permit_info: None,
            ordering_info: Some(OrderingInfo {
                after_tags: overrides.after_tags.clone(),
                before_tags: overrides.before_tags.clone(),
            }),
        }),
        Some(LabelInfo {
            forwarder_addr: forwarder.to_vec(),
            erc20_token_addr: token.to_vec(),
        }),
        None,
    );

    let consumed_witness = match merkle_path {
        Some(path) => {
            ConsumedResourceWitness::from_resource_with_path(consumed, owner.nf_key.clone(), path)
        }
        None => ConsumedResourceWitness::from_resource(consumed, owner.nf_key.clone()),
    };
    let compliance = compliance::from_resources(
        vec![
            ResourceWitness::Consumed(consumed_witness),
            ResourceWitness::Created(created),
        ],
        crate::fixtures::resource::kind_tree(),
    );

    Ok(ActionData {
        witnesses: ActionWitnesses {
            compliance_witness: Box::new(compliance),
            logic_witnesses: vec![consumed_logic, Box::new(logic::Witness::new(created_logic))],
        },
        consumed_persistent: consumed,
        created_ephemeral: created,
    })
}
