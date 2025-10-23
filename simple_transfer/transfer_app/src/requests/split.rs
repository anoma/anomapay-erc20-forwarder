use crate::errors::TransactionError;
use crate::errors::TransactionError::{
    ActionError, DecodingError, DeltaProofCreateError, EncodingError, InvalidKeyChain,
    LogicProofCreateError, MerklePathError, MerkleProofError,
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
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::resource_logic::TrivialLogicWitness;
use arm::transaction::{Delta, Transaction};
use k256::AffinePoint;
use serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;
use transfer_library::TransferLogic;

#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq)]
pub struct SplitRequest {
    pub to_split_resource: JsonResource,
    pub created_resource: JsonResource,
    pub remainder_resource: JsonResource, // A second resource with the remaining quantity will be created for the owner.
    pub padding_resource: JsonResource, // A second resource with the remaining quantity will be created for the owner.
    #[serde_as(as = "Base64")]
    pub sender_nf_key: Vec<u8>,
    pub sender_verifying_key: AffinePoint,
    #[serde_as(as = "Base64")]
    pub auth_signature: Vec<u8>,
    pub owner_discovery_pk: AffinePoint,
    pub owner_encryption_pk: AffinePoint,
    pub receiver_discovery_pk: AffinePoint,
    pub receiver_encryption_pk: AffinePoint,
}

/// Execute a burn transaction from a burn request.
pub async fn split_from_request(
    request: SplitRequest,
    config: &AnomaPayConfig,
) -> Result<Transaction, TransactionError> {
    let to_split_resource: Resource =
        Expand::expand(request.to_split_resource).map_err(|_| DecodingError)?;
    let created_resource: Resource =
        Expand::expand(request.created_resource).map_err(|_| DecodingError)?;
    let padding_resource: Resource =
        Expand::expand(request.padding_resource).map_err(|_| DecodingError)?;
    let remainder_resource: Resource =
        Expand::expand(request.remainder_resource).map_err(|_| DecodingError)?;
    let receiver_discovery_pk = request.receiver_discovery_pk;
    let receiver_encryption_pk = request.receiver_encryption_pk;
    let sender_nf_key: NullifierKey = NullifierKey::from_bytes(request.sender_nf_key.as_slice());
    let sender_auth_verifying_key: AuthorizationVerifyingKey =
        AuthorizationVerifyingKey::from_affine(request.sender_verifying_key);

    let auth_signature: AuthorizationSignature =
        AuthorizationSignature::from_bytes(request.auth_signature.as_slice())
            .map_err(|_| EncodingError)?;

    ////////////////////////////////////////////////////////////////////////////
    // Create the action tree

    let padding_resource_nullifier = padding_resource
        .nullifier(&NullifierKey::default())
        .map_err(|_| InvalidKeyChain)?;

    let to_split_resource_nullifier = to_split_resource
        .nullifier(&sender_nf_key)
        .map_err(|_| InvalidKeyChain)?;

    let created_resource_commitment = created_resource.commitment();

    let remainder_resource_commitment = remainder_resource.commitment();

    let action_tree: MerkleTree = MerkleTree::new(vec![
        to_split_resource_nullifier,
        created_resource_commitment,
        padding_resource_nullifier,
        remainder_resource_commitment,
    ]);

    ////////////////////////////////////////////////////////////////////////////
    // Get the merkle proof for the resource being split and the padding resource.

    let merkle_proof_to_split = pa_merkle_path(config, to_split_resource.commitment())
        .await
        .map_err(|_| MerkleProofError)?;

    ////////////////////////////////////////////////////////////////////////////
    // Create compliance proof

    let compliance_witness_created = ComplianceWitness::from_resources_with_path(
        to_split_resource,
        sender_nf_key.clone(),
        merkle_proof_to_split,
        created_resource,
    );

    let compliance_unit_created_future = compliance_proof(&compliance_witness_created);
    let compliance_unit_created = compliance_unit_created_future.await?;

    let compliance_witness_remainder = ComplianceWitness::from_resources_with_path(
        padding_resource,
        NullifierKey::default(),
        MerklePath::default(),
        remainder_resource,
    );

    let compliance_unit_remainder_future = compliance_proof(&compliance_witness_remainder);
    let compliance_unit_remainder = compliance_unit_remainder_future.await?;

    ////////////////////////////////////////////////////////////////////////////
    // Create logic proof

    //--------------------------------------------------------------------------
    // to_split proof

    let to_split_resource_path = action_tree
        .generate_path(&to_split_resource_nullifier)
        .map_err(|_| MerklePathError)?;

    let to_split_logic_witness: TransferLogic = TransferLogic::consume_persistent_resource_logic(
        to_split_resource,
        to_split_resource_path.clone(),
        sender_nf_key.clone(),
        sender_auth_verifying_key,
        auth_signature,
    );

    let to_split_logic_proof_future = logic_proof(&to_split_logic_witness);
    let to_split_logic_proof = to_split_logic_proof_future.await?;

    //--------------------------------------------------------------------------
    // padding proof

    let padding_resource_path = action_tree
        .generate_path(&padding_resource_nullifier)
        .map_err(|_| MerklePathError)?;

    let padding_logic_witness = TrivialLogicWitness::new(
        padding_resource,
        padding_resource_path.clone(),
        NullifierKey::default(),
        true,
    );

    let padding_logic_proof_future = logic_proof(&padding_logic_witness);
    let padding_logic_proof = padding_logic_proof_future.await?;

    //--------------------------------------------------------------------------
    // created proof

    let created_resource_path = action_tree
        .generate_path(&created_resource_commitment)
        .map_err(|_| MerklePathError)?;

    let created_logic_witness = TransferLogic::create_persistent_resource_logic(
        created_resource,
        created_resource_path,
        &receiver_discovery_pk,
        receiver_encryption_pk,
    );

    let created_logic_proof_future = logic_proof(&created_logic_witness);
    let created_logic_proof = created_logic_proof_future.await?;

    //--------------------------------------------------------------------------
    // remainder proof

    let remainder_resource_path = action_tree
        .generate_path(&remainder_resource_commitment)
        .map_err(|_| MerklePathError)?;

    let remainder_logic_witness = TransferLogic::create_persistent_resource_logic(
        remainder_resource,
        remainder_resource_path,
        &receiver_discovery_pk,
        receiver_encryption_pk,
    );

    let remainder_logic_proof_future = logic_proof(&remainder_logic_witness);
    let remainder_logic_proof = remainder_logic_proof_future.await?;

    ////////////////////////////////////////////////////////////////////////////
    // Create actions for transaction

    let action: Action = Action::new(
        vec![compliance_unit_created, compliance_unit_remainder],
        vec![
            to_split_logic_proof,
            created_logic_proof,
            padding_logic_proof,
            remainder_logic_proof,
        ],
    )
    .map_err(|_| ActionError)?;

    let delta_witness: DeltaWitness = DeltaWitness::from_bytes_vec(&[
        compliance_witness_created.rcv,
        compliance_witness_remainder.rcv,
    ])
    .map_err(|_| LogicProofCreateError)?;

    let transaction = Transaction::create(vec![action], Delta::Witness(delta_witness));

    let transaction = transaction
        .generate_delta_proof()
        .map_err(|_| DeltaProofCreateError)?;

    verify_transaction(transaction.clone())?;
    Ok(transaction)
}
