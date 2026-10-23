use std::ops::Add;
use std::time::Duration;

use alloy::primitives::{Address, B256, U256};
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_witness::EncryptionInfo;
use anomapay_erc20_witness::ForwarderInfo;
use anomapay_erc20_witness::LabelInfo;
use anomapay_erc20_witness::PermitInfo;
use anomapay_erc20_witness::TokenTransferWitness;
use anomapay_erc20_witness::ValueInfo;
use anomapay_erc20_witness::call_type::CallType;

use super::resource;
use super::resource::Overrides;
use crate::fixtures::action::{self, Logic, Part};
use crate::fixtures::resource::persistent;
use crate::logic;
use crate::permit2::Permit2Data;
use crate::permit2::permit_witness_transfer_from_signature;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_testkit::fixtures::identities;
use anoma_pa_testkit::witness::{ActionWitnesses, LogicWitness};

/// The derived data of a built wrap action: the action witnesses plus the
/// ephemeral resource it consumes and the persistent wrapped resource it
/// creates.
pub struct ActionData {
    pub witnesses: ActionWitnesses,
    pub consumed_ephemeral: Resource,
    pub created_persistent: Resource,
}

/// The resources of a wrap: the consumed ephemeral resource, whose forwarder
/// call pulls the tokens, and the created persistent resource.
pub struct Parts {
    pub consumed: Part,
    pub created: Part,
}

/// Build a wrap action: the sender (alice) consumes an ephemeral resource
/// authorized by a Permit2 signature and creates a persistent wrapped
/// resource.
pub fn build(
    chain_id: u64,
    forwarder: Address,
    token: Address,
    quantity: u128,
    seed: u8,
    overrides: Overrides,
) -> anyhow::Result<ActionData> {
    let Parts { consumed, created } = parts(chain_id, forwarder, token, quantity, seed, overrides)?;
    let action = action::build(vec![consumed, created])?;
    let [consumed_ephemeral, created_persistent] = <[Resource; 2]>::try_from(action.resources)
        .map_err(|resources| anyhow::anyhow!("a wrap has 2 resources, not {}", resources.len()))?;

    Ok(ActionData {
        witnesses: action.witnesses,
        consumed_ephemeral,
        created_persistent,
    })
}

/// The resources of a wrap action, for an action that [`action::build`]
/// assembles from several kinds. The Permit2 signature covers the root of that
/// action.
pub fn parts(
    chain_id: u64,
    forwarder: Address,
    token: Address,
    quantity: u128,
    seed: u8,
    overrides: Overrides,
) -> anyhow::Result<Parts> {
    let sender = identities::alice()?;
    let ethereum_account_addr = overrides
        .ethereum_account_addr
        .clone()
        .unwrap_or_else(|| sender.address().to_vec());
    let amount = overrides.quantity.unwrap_or(quantity);

    let consumed = resource::consumed(&sender, forwarder, token, quantity, seed, &overrides);
    let created = persistent(
        &sender,
        forwarder,
        token,
        amount,
        [seed.wrapping_add(33); 32],
    );

    let permit_nonce = resource::random_permit_nonce(seed);
    let permit_deadline = U256::from(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock is before the Unix epoch")
            .add(Duration::from_mins(15))
            .as_secs(),
    );
    let Overrides {
        permit_signature, ..
    } = overrides;
    let signer = sender.signer();
    let nf_key = sender.nf_key.clone();
    let consumed_logic: Logic = Box::new(
        move |resource: Resource,
              action_tree_root: Digest|
              -> anyhow::Result<Box<dyn LogicWitness>> {
            let permit_sig = match permit_signature {
                Some(bytes) => bytes,
                None => permit_witness_transfer_from_signature(
                    &signer,
                    Permit2Data {
                        chain_id,
                        token,
                        amount: U256::from(amount),
                        nonce: permit_nonce,
                        deadline: permit_deadline,
                        spender: forwarder,
                        action_tree_root: B256::from_slice(action_tree_root.as_bytes()),
                    },
                )?
                .into(),
            };
            Ok(Box::new(logic::Witness::new(TokenTransferWitness::new(
                resource,
                true,
                action_tree_root,
                Some(nf_key),
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
                    ordering_info: None,
                }),
                Some(LabelInfo {
                    forwarder_addr: forwarder.to_vec(),
                    erc20_token_addr: token.to_vec(),
                }),
                None,
            ))))
        },
    );

    let discovery_pk = sender.discovery_pk;
    let value_info = ValueInfo {
        auth_pk: sender.auth_verifying_key(),
        encryption_pk: sender.encryption_pk,
    };
    let created_logic: Logic = Box::new(
        move |resource: Resource,
              action_tree_root: Digest|
              -> anyhow::Result<Box<dyn LogicWitness>> {
            Ok(Box::new(logic::Witness::new(TokenTransferWitness::new(
                resource,
                false,
                action_tree_root,
                None,
                None,
                Some(EncryptionInfo::new(&discovery_pk)),
                None,
                Some(LabelInfo {
                    forwarder_addr: forwarder.to_vec(),
                    erc20_token_addr: token.to_vec(),
                }),
                Some(value_info),
            ))))
        },
    );

    Ok(Parts {
        consumed: Part::Consumed {
            resource: consumed,
            nf_key: sender.nf_key.clone(),
            merkle_path: None,
            logic: consumed_logic,
        },
        created: Part::Created {
            resource: created,
            nonce: None,
            logic: created_logic,
        },
    })
}
