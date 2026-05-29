use alloy::primitives::Address;
use anoma_rm_risc0::action_tree::MerkleTree as ArmTree;
use anoma_rm_risc0::compliance::ComplianceWitness;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::resource::Resource;
use anoma_rm_risc0_gadgets::authority::AuthoritySignature;
use transfer_witness::AUTH_SIGNATURE_DOMAIN;
use transfer_witness::ForwarderInfo;
use transfer_witness::LabelInfo;
use transfer_witness::TokenTransferWitness;
use transfer_witness::ValueInfo;
use transfer_witness::call_type::CallType;

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
            transfer_witness::calculate_value_ref_from_ethereum_account_addr(ethereum_account_addr),
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

    let consumed_logic = TokenTransferWitness::new(
        consumed,
        true,
        action_tree_root,
        Some(owner.nf_key.clone()),
        Some(auth_sig),
        None,
        None,
        None,
        Some(ValueInfo {
            auth_pk: owner.auth_verifying_key(),
            encryption_pk: owner.encryption_pk,
        }),
    );

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
        }),
        Some(LabelInfo {
            forwarder_addr: forwarder.to_vec(),
            erc20_token_addr: token.to_vec(),
        }),
        None,
    );

    let compliance = match merkle_path {
        Some(path) => ComplianceWitness::from_resources_with_path(
            consumed,
            owner.nf_key.clone(),
            path,
            created,
        ),
        None => ComplianceWitness::from_resources(
            consumed,
            *anoma_rm_risc0::compliance::INITIAL_ROOT,
            owner.nf_key.clone(),
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
        created_ephemeral: created,
    })
}
