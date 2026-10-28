//! The ephemeral ERC20 resource, whose forwarder call moves tokens between an Ethereum account and
//! the forwarder. A wrap consumes it to pull the tokens. An unwrap creates it to release them.

use alloy::primitives::{Address, B256, U256};
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_testkit::fixtures::action::{ActionResource, ResourceToCreate};
use anoma_pa_testkit::fixtures::identities::Keychain;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::nullifier_key::NullifierKeyCommitment;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_library::TransferLogic;
use anomapay_erc20_witness::{calculate_label_ref, calculate_value_ref_from_ethereum_account_addr};

use crate::fixtures::CREATED_RAND_SEED;
use crate::logic;
use crate::permit2::{Permit2Data, permit_witness_transfer_from_signature};

/// The account and the Permit2 signature of [`consumed`], if not those of the owner.
#[derive(Clone, Debug, Default)]
pub struct Overrides {
    /// The account that the tokens come from. A contract that implements ERC-1271, such as the
    /// generic call forwarder, accepts any 65-byte `permit_signature`.
    pub ethereum_account_addr: Option<Address>,
    pub permit_signature: Option<Vec<u8>>,
}

/// An ephemeral resource of `owner` whose forwarder call pulls `quantity` tokens of `token` from
/// the owner's account into `forwarder`, with the owner's Permit2 signature over the action tree
/// root. `nonce` sets its nonce, its random fields and its Permit2 nonce.
pub fn consumed(
    owner: &Keychain,
    chain_id: u64,
    forwarder: Address,
    token: Address,
    quantity: u128,
    nonce: [u8; 32],
    overrides: Overrides,
) -> ActionResource {
    let Overrides {
        ethereum_account_addr,
        permit_signature,
    } = overrides;
    let ethereum_account_addr = ethereum_account_addr.unwrap_or_else(|| owner.address());
    let resource = Resource {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref(), token.as_ref()),
        quantity,
        value_ref: calculate_value_ref_from_ethereum_account_addr(ethereum_account_addr.as_ref()),
        is_ephemeral: true,
        nonce,
        nk_commitment: owner.nf_key.commit(),
        rand_seed: nonce,
    };
    let permit_nonce = U256::from_be_bytes(nonce);
    let permit_deadline = U256::MAX;
    let signer = owner.signer();
    let nf_key = owner.nf_key.clone();
    ActionResource::consumed(
        resource,
        owner.nf_key.clone(),
        MerklePath::empty(),
        move |resource, action_tree_root| {
            let permit_signature = match permit_signature {
                Some(permit_signature) => permit_signature,
                None => permit_witness_transfer_from_signature(
                    &signer,
                    Permit2Data {
                        chain_id,
                        token,
                        amount: U256::from(quantity),
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
                ethereum_account_addr.to_vec(),
                permit_nonce.to_be_bytes_vec(),
                permit_deadline.to_be_bytes_vec(),
                permit_signature,
            ))
        },
    )
}

/// An ephemeral resource whose forwarder call releases `quantity` tokens of `token` from
/// `forwarder` to `ethereum_account_addr`.
pub fn created(
    ethereum_account_addr: Address,
    forwarder: Address,
    token: Address,
    quantity: u128,
) -> ActionResource {
    let resource = ResourceToCreate {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref(), token.as_ref()),
        quantity,
        value_ref: calculate_value_ref_from_ethereum_account_addr(ethereum_account_addr.as_ref()),
        is_ephemeral: true,
        // No one consumes the resource, so any nullifier key commitment works.
        nk_commitment: NullifierKeyCommitment::default(),
        rand_seed: CREATED_RAND_SEED,
    };
    ActionResource::created(resource, move |resource, action_tree_root| {
        Ok(TransferLogic::burn_resource_logic(
            resource,
            action_tree_root,
            forwarder.to_vec(),
            token.to_vec(),
            ethereum_account_addr.to_vec(),
        ))
    })
}
