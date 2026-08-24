use std::ops::Add;
use std::time::Duration;

use alloy::primitives::{Address, B256, U256};
use anoma_rm_risc0::action_tree::MerkleTree as ArmTree;
use anoma_rm_risc0::compliance::ComplianceWitness;
use anoma_rm_risc0::resource::Resource;
use transfer_witness::EncryptionInfo;
use transfer_witness::ForwarderInfo;
use transfer_witness::LabelInfo;
use transfer_witness::PermitInfo;
use transfer_witness::TokenTransferWitness;
use transfer_witness::ValueInfo;
use transfer_witness::call_type::CallType;

use super::resource;
use super::resource::Overrides;
use crate::fixtures::resource::persistent;
use crate::logic;
use crate::permit2::Permit2Data;
use crate::permit2::permit_witness_transfer_from_signature;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_testkit::fixtures::identities;
use anoma_pa_testkit::witness::ActionWitnesses;

/// The derived data of a built wrap action: the action witnesses plus the
/// ephemeral resource it consumes and the persistent wrapped resource it
/// creates.
pub struct ActionData {
    pub witnesses: ActionWitnesses,
    pub consumed_ephemeral: Resource,
    pub created_persistent: Resource,
}

/// Build a wrap action: the sender (alice) consumes an ephemeral resource
/// authorized by a Permit2 signature and creates a persistent wrapped
/// resource.
pub async fn build(
    chain_id: u64,
    forwarder: Address,
    token: Address,
    quantity: u128,
    seed: u8,
    overrides: Overrides,
) -> anyhow::Result<ActionData> {
    let sender = identities::alice()?;
    let ethereum_account_addr = overrides
        .ethereum_account_addr
        .clone()
        .unwrap_or_else(|| sender.address().to_vec());

    let consumed = resource::consumed(&sender, forwarder, token, quantity, seed, &overrides);
    let consumed_nf = consumed.nullifier(&sender.nf_key)?;
    let created = persistent(
        &sender,
        consumed_nf,
        forwarder,
        token,
        overrides.quantity.unwrap_or(quantity),
        [seed.wrapping_add(33); 32],
    )?;

    let action_tree_root = ArmTree::new(vec![consumed_nf, created.commitment()]).root()?;

    let permit_nonce = resource::random_permit_nonce(seed);
    let permit_deadline = U256::from(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock is before the Unix epoch")
            .add(Duration::from_mins(15))
            .as_secs(),
    );
    let permit_sig = match overrides.permit_signature {
        Some(bytes) => bytes,
        None => permit_witness_transfer_from_signature(
            &sender.signer(),
            Permit2Data {
                chain_id,
                token,
                amount: U256::from(overrides.quantity.unwrap_or(quantity)),
                nonce: permit_nonce,
                deadline: permit_deadline,
                spender: forwarder,
                action_tree_root: B256::from_slice(action_tree_root.as_bytes()),
            },
        )
        .await?
        .into(),
    };

    let consumed_logic = TokenTransferWitness::new(
        consumed,
        true,
        action_tree_root,
        Some(sender.nf_key.clone()),
        None,
        None,
        Some(ForwarderInfo {
            call_type: CallType::Wrap,
            ethereum_account_addr,
            permit_info: Some(PermitInfo {
                permit_nonce: permit_nonce.to_be_bytes_vec(),
                permit_deadline: permit_deadline.to_be_bytes_vec(),
                permit_sig,
            }),
        }),
        Some(LabelInfo {
            forwarder_addr: forwarder.to_vec(),
            erc20_token_addr: token.to_vec(),
        }),
        None,
    );

    let created_logic = TokenTransferWitness::new(
        created,
        false,
        action_tree_root,
        None,
        None,
        Some(EncryptionInfo::new(&sender.discovery_pk)),
        None,
        Some(LabelInfo {
            forwarder_addr: forwarder.to_vec(),
            erc20_token_addr: token.to_vec(),
        }),
        Some(ValueInfo {
            auth_pk: sender.auth_verifying_key(),
            encryption_pk: sender.encryption_pk,
        }),
    );

    let compliance = ComplianceWitness::from_resources(
        consumed,
        *anoma_rm_risc0::compliance::INITIAL_ROOT,
        sender.nf_key.clone(),
        created,
    );

    Ok(ActionData {
        witnesses: ActionWitnesses {
            compliance_witnesses: vec![Box::new(compliance)],
            logic_witnesses: vec![
                Box::new(logic::Witness::new(consumed_logic)),
                Box::new(logic::Witness::new(created_logic)),
            ],
        },
        consumed_ephemeral: consumed,
        created_persistent: created,
    })
}
