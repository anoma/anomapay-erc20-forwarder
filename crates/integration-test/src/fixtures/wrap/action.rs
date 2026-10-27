use std::ops::Add;
use std::time::Duration;

use alloy::primitives::{Address, B256, U256};
use anoma_pa_testkit::fixtures::action::ActionResource;
use anoma_pa_testkit::fixtures::identities;
use anoma_rm_risc0::merkle_path::MerklePath;
use anomapay_erc20_library::TransferLogic;

use super::resource;
use super::resource::Overrides;
use crate::fixtures::resource::created_persistent;
use crate::permit2::Permit2Data;
use crate::permit2::permit_witness_transfer_from_signature;
use anoma_pa_evm_integration_test::keychain::EvmSigner;

/// The resources of a wrap: the consumed ephemeral resource, whose forwarder call pulls the tokens
/// with a Permit2 signature of the sender (alice) over the action tree root, and the created
/// persistent resource of the sender.
pub fn resources(
    chain_id: u64,
    forwarder: Address,
    token: Address,
    quantity: u128,
    seed: u8,
    overrides: Overrides,
) -> anyhow::Result<[ActionResource; 2]> {
    let sender = identities::alice()?;
    let ethereum_account_addr = overrides
        .ethereum_account_addr
        .clone()
        .unwrap_or_else(|| sender.address().to_vec());

    let consumed = resource::consumed(&sender, forwarder, token, quantity, seed, &overrides);
    let amount = consumed.quantity;
    let created = created_persistent(
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
    let consumed = ActionResource::consumed(
        consumed,
        sender.nf_key.clone(),
        MerklePath::empty(),
        move |resource, action_tree_root| {
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
            Ok(TransferLogic::mint_resource_logic_with_permit(
                resource,
                action_tree_root,
                nf_key,
                forwarder.to_vec(),
                token.to_vec(),
                ethereum_account_addr,
                permit_nonce.to_be_bytes_vec(),
                permit_deadline.to_be_bytes_vec(),
                permit_sig,
            ))
        },
    );

    Ok([consumed, created])
}
