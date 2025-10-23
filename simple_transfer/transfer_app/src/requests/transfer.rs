use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    ActionError, ActionTreeError, DecodingError, DeltaProofCreateError, EncodingError,
    InvalidKeyChain, LogicProofCreateError, MerkleProofError,
};
use crate::evm::indexer::pa_merkle_path;
use crate::examples::shared::verify_transaction;
use crate::requests::resource::JsonResource;
use crate::requests::{compliance_proof, logic_proof, Expand};
use crate::AnomaPayConfig;
use arm::action::Action;
use arm::action_tree::MerkleTree;
use arm::authorization::{AuthorizationSignature, AuthorizationVerifyingKey};
use arm::compliance::ComplianceWitness;
use arm::delta_proof::DeltaWitness;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::transaction::{Delta, Transaction};
use k256::AffinePoint;
use serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;
use transfer_library::TransferLogic;

/// Struct to hold the fields for a transfer request to the api.
#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq)]
pub struct TransferRequest {
    pub transferred_resource: JsonResource,
    pub created_resource: JsonResource,
    #[serde_as(as = "Base64")]
    pub sender_nf_key: Vec<u8>,
    pub sender_verifying_key: AffinePoint,
    #[serde_as(as = "Base64")]
    pub auth_signature: Vec<u8>,
    pub receiver_discovery_pk: AffinePoint,
    pub receiver_encryption_pk: AffinePoint,
}

/// Handles an incoming transfer request
pub async fn transfer_from_request(
    request: TransferRequest,
    config: &AnomaPayConfig,
) -> Result<(Resource, Transaction), TransactionError> {
    // convert some bytes into their proper data structure from the request.
    let transferred_resource: Resource =
        Expand::expand(request.transferred_resource).map_err(|_| DecodingError)?;
    let created_resource: Resource =
        Expand::expand(request.created_resource).map_err(|_| DecodingError)?;
    let sender_nf_key: NullifierKey = NullifierKey::from_bytes(request.sender_nf_key.as_slice());
    let sender_auth_verifying_key: AuthorizationVerifyingKey =
        AuthorizationVerifyingKey::from_affine(request.sender_verifying_key);
    let auth_signature: AuthorizationSignature =
        AuthorizationSignature::from_bytes(request.auth_signature.as_slice())
            .map_err(|_| EncodingError)?;

    let receiver_discovery_pk = request.receiver_discovery_pk;
    let receiver_encryption_pk = request.receiver_encryption_pk;

    let transferred_resource_commitment = transferred_resource.commitment();

    let merkle_proof = pa_merkle_path(config, transferred_resource_commitment)
        .await
        .map_err(|_| MerkleProofError)?;

    let transferred_resource_nullifier = transferred_resource
        .nullifier(&sender_nf_key)
        .map_err(|_| InvalidKeyChain)?;

    let created_resource_commitment = created_resource.commitment();

    ////////////////////////////////////////////////////////////////////////////
    // Create the action tree

    let action_tree: MerkleTree = MerkleTree::new(vec![
        transferred_resource_nullifier,
        created_resource_commitment,
    ]);

    ////////////////////////////////////////////////////////////////////////////
    // Create compliance proof

    let compliance_witness = ComplianceWitness::from_resources_with_path(
        transferred_resource,
        sender_nf_key.clone(),
        merkle_proof,
        created_resource,
    );

    // generate the proof in a separate thread
    let compliance_unit_future = compliance_proof(&compliance_witness);

    ////////////////////////////////////////////////////////////////////////////
    // Create logic proof

    let consumed_resource_path = action_tree
        .generate_path(&transferred_resource_nullifier)
        .map_err(|_| ActionTreeError)?;

    let transferred_logic_witness: TransferLogic = TransferLogic::consume_persistent_resource_logic(
        transferred_resource,
        consumed_resource_path,
        sender_nf_key.clone(),
        sender_auth_verifying_key,
        auth_signature,
    );
    let transferred_logic_proof_future = logic_proof(&transferred_logic_witness);

    let created_resource_path = action_tree
        .generate_path(&created_resource_commitment)
        .map_err(|_| ActionTreeError)?;

    let created_logic_witness: TransferLogic = TransferLogic::create_persistent_resource_logic(
        created_resource,
        created_resource_path,
        &receiver_discovery_pk,
        receiver_encryption_pk,
    );

    let created_logic_proof_future = logic_proof(&created_logic_witness);

    ////////////////////////////////////////////////////////////////////////////
    // Create actions for transaction

    let compliance_unit = compliance_unit_future.await?;
    let created_logic_proof = created_logic_proof_future.await?;
    let transferred_logic_proof = transferred_logic_proof_future.await?;

    let action: Action = Action::new(
        vec![compliance_unit],
        vec![transferred_logic_proof, created_logic_proof],
    )
    .map_err(|_| ActionError)?;

    ////////////////////////////////////////////////////////////////////////////
    // Create delta proof

    let delta_witness =
        DeltaWitness::from_bytes(&compliance_witness.rcv).map_err(|_| LogicProofCreateError)?;
    let transaction = Transaction::create(vec![action], Delta::Witness(delta_witness));

    let transaction = transaction
        .generate_delta_proof()
        .map_err(|_| DeltaProofCreateError)?;

    verify_transaction(transaction.clone())?;
    Ok((created_resource, transaction))
}
