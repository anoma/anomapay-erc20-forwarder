use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    ActionError, ActionTreeError, ComplianceUnitCreateError, DecodingError, DeltaProofCreateError,
    InvalidKeyChain, LogicProofCreateError, MerklePathError,
};
use crate::examples::shared::verify_transaction;

use crate::requests::resource::JsonResource;
use crate::requests::Expand;
use crate::AnomaPayConfig;
use alloy::primitives::U256;
use arm::action::Action;
use arm::action_tree::MerkleTree;
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::delta_proof::DeltaWitness;
use arm::logic_proof::LogicProver;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::transaction::{Delta, Transaction};
use arm::utils::bytes_to_words;
use arm::Digest;
use k256::AffinePoint;
use serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;
use std::thread;
use transfer_library::TransferLogic;

/// Defines the payload sent to the API to execute a minting request on /api/minting.
#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq)]
pub struct CreateRequest {
    pub consumed_resource: JsonResource,
    pub created_resource: JsonResource,
    #[serde_as(as = "Base64")]
    pub latest_cm_tree_root: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub consumed_nf_key: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub forwarder_addr: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub token_addr: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub user_addr: Vec<u8>,
    #[serde_as(as = "Base64")]
    pub permit_nonce: Vec<u8>,
    pub permit_deadline: u64,
    #[serde_as(as = "Base64")]
    pub permit_sig: Vec<u8>,
    pub created_discovery_pk: AffinePoint,
    pub created_encryption_pk: AffinePoint,
}

/// Hanldes a mint request
pub fn mint_from_request(
    request: CreateRequest,
    config: &AnomaPayConfig,
) -> Result<(Resource, Transaction), TransactionError> {
    let created_resource: Resource =
        Expand::expand(request.created_resource).map_err(|_| DecodingError)?;
    let consumed_resource: Resource =
        Expand::expand(request.consumed_resource).map_err(|_| DecodingError)?;
    let consumed_nf_key: NullifierKey =
        NullifierKey::from_bytes(request.consumed_nf_key.as_slice());

    let created_resource_commitment = created_resource.commitment();
    let consumed_resource_nullifier: Digest = consumed_resource
        .nullifier(&consumed_nf_key)
        .map_err(|_| InvalidKeyChain)?;

    let latest_commitment_tree_root: Digest =
        bytes_to_words(request.latest_cm_tree_root.as_slice())
            .try_into()
            .map_err(|_| DecodingError)?;

    let user_address = request.user_addr;
    let nonce = request.permit_nonce;

    let token_address = request.token_addr;
    let permit_signature = request.permit_sig;
    let discovery_pk: AffinePoint = request.created_discovery_pk;
    let encryption_pk: AffinePoint = request.created_encryption_pk;
    let permit_deadline = request.permit_deadline;

    ////////////////////////////////////////////////////////////////////////////
    // Create the action tree

    let action_tree: MerkleTree = MerkleTree::new(vec![
        consumed_resource_nullifier,
        created_resource_commitment,
    ]);

    ////////////////////////////////////////////////////////////////////////////
    // Create compliance proof

    let compliance_witness = ComplianceWitness::from_resources(
        consumed_resource,
        latest_commitment_tree_root,
        consumed_nf_key.clone(),
        created_resource,
    );

    // generate the proof in a separate thread
    let compliance_witness_clone = compliance_witness.clone();
    let compliance_unit =
        thread::spawn(move || ComplianceUnit::create(&compliance_witness_clone.clone()))
            .join()
            .map_err(|e| {
                println!("prove thread panic: {:?}", e);
                ComplianceUnitCreateError
            })?
            .map_err(|e| {
                println!("proving error: {:?}", e);
                ComplianceUnitCreateError
            })?;

    ////////////////////////////////////////////////////////////////////////////
    // Create logic proof

    let consumed_resource_path = action_tree
        .generate_path(&consumed_resource_nullifier)
        .map_err(|_| MerklePathError)?;

    let consumed_logic_witness: TransferLogic = TransferLogic::mint_resource_logic_with_permit(
        consumed_resource,
        consumed_resource_path,
        consumed_nf_key,
        config.forwarder_address.to_vec(),
        token_address,
        user_address,
        nonce.to_vec(),
        U256::from(permit_deadline).to_be_bytes_vec(),
        permit_signature,
    );

    // generate the proof in a separate thread
    let consumed_logic_witness_clone = consumed_logic_witness.clone();
    let consumed_logic_proof = thread::spawn(move || consumed_logic_witness_clone.prove())
        .join()
        .map_err(|e| {
            println!("prove thread panic: {:?}", e);
            LogicProofCreateError
        })?
        .map_err(|e| {
            println!("proving error: {:?}", e);
            LogicProofCreateError
        })?;

    let created_resource_path = action_tree
        .generate_path(&created_resource_commitment)
        .map_err(|_| ActionTreeError)?;

    let created_logic_witness = TransferLogic::create_persistent_resource_logic(
        created_resource,
        created_resource_path,
        &discovery_pk,
        encryption_pk,
    );

    // generate the proof in a separate thread
    // this is due to bonsai being non-blocking or something. there is a feature flag for bonsai
    // that allows it to be non-blocking or vice versa, but this is to figure out.
    let created_logic_witness_clone = created_logic_witness.clone();
    let created_logic_proof = thread::spawn(move || created_logic_witness_clone.prove())
        .join()
        .map_err(|e| {
            println!("prove thread panic: {:?}", e);
            LogicProofCreateError
        })?
        .map_err(|e| {
            println!("proving error: {:?}", e);
            LogicProofCreateError
        })?;

    ////////////////////////////////////////////////////////////////////////////
    // Create actions for transaction

    let action: Action = Action::new(
        vec![compliance_unit],
        vec![consumed_logic_proof, created_logic_proof],
    )
    .map_err(|_| ActionError)?;

    let delta_witness =
        DeltaWitness::from_bytes(&compliance_witness.rcv).map_err(|_| LogicProofCreateError)?;
    let transaction = Transaction::create(vec![action], Delta::Witness(delta_witness));

    let transaction = transaction
        .generate_delta_proof()
        .map_err(|_| DeltaProofCreateError)?;

    verify_transaction(transaction.clone())?;
    Ok((created_resource, transaction))
}
