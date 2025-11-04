//! Module that defines helper functions to create transfer transactions.

use crate::evm::indexer::pa_merkle_path;
use crate::transactions::helpers::{compliance_proof_asyncc, logic_proof_asyncc};
use crate::transactions::transfer::TransferError::{
    ComplianceProofGenerationError, CreatedResourceLogicProofError, CreatedResourceNotInActionTree,
    DeltaProofGenerationError, DeltaWitnessGenerationError, InvalidLogicProofsInAction,
    InvalidSenderNullifierKey, ProofGenerationError, TransactionVerificationError,
    TransferredResourceLogicProofError, TransferredResourceMerkleProofNotFound,
    TransferredResourceNotInActionTree,
};
use crate::AnomaPayConfig;
use arm::action::Action;
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::delta_proof::DeltaWitness;
use arm::logic_proof::LogicVerifier;
use arm::merkle_path::MerklePath;
use arm::transaction::Delta;
use arm::{
    action_tree::MerkleTree,
    authorization::{AuthorizationSignature, AuthorizationVerifyingKey},
    nullifier_key::NullifierKey,
    resource::Resource,
    transaction::Transaction,
};
use k256::AffinePoint;
use tokio::try_join;
use transfer_library::TransferLogic;
use crate::helpers::verify_transaction;

// A custom type alias for functions that generate transfer transactions.
pub type TransferResult<T> = Result<T, TransferError>;

// Set of errors that can occur during the creation of a transfer transaction.
#[derive(Debug, Clone)]
pub enum TransferError {
    // The user provided an invalid sender nullifier key
    InvalidSenderNullifierKey,
    // The merkle proof for the resource being transferred did not exist or was not fetched.
    TransferredResourceMerkleProofNotFound,
    // The resource nullifier was not found in the action tree for the transaction.
    TransferredResourceNotInActionTree,
    // An error occurred generating the compliance proof
    ComplianceProofGenerationError,
    // An error occurred generating the logic proof for the transferred resource
    TransferredResourceLogicProofError,
    // An error occurred generating the logic proof for the created resource.
    CreatedResourceLogicProofError,
    // The created resource was not found in the action tree.
    CreatedResourceNotInActionTree,
    // The logic proofs were not valid inputs to create an action
    InvalidLogicProofsInAction,
    // Failed to create the delta witness for the given actions.
    DeltaWitnessGenerationError,
    // Failed to generate the delta proof for the transaction
    DeltaProofGenerationError,
    // The created transaction failed to verify.
    TransactionVerificationError,
    ProofGenerationError,
}

#[derive(Debug)]
pub struct TransferParameters {
    pub transferred_resource: Resource,
    pub created_resource: Resource,
    pub sender_nullifier_key: NullifierKey,
    pub sender_auth_verifying_key: AuthorizationVerifyingKey,
    pub auth_signature: AuthorizationSignature,
    pub receiver_discovery_pk: AffinePoint,
    pub receiver_encryption_pk: AffinePoint,
}
impl TransferParameters {
    // Create the action tree for these parameters.
    fn _action_tree(&self) -> TransferResult<MerkleTree> {
        // Compute the nullifier for the transferred resource.
        let transferred_resource_nullifier = self
            .transferred_resource
            .nullifier(&self.sender_nullifier_key)
            .map_err(|_| InvalidSenderNullifierKey)?;

        Ok(MerkleTree::new(vec![
            transferred_resource_nullifier,
            self.created_resource.commitment(),
        ]))
    }

    // Fetches the merkle proof for the transferred resource.
    // This ensures that the resource that's being transferred actually exists.
    async fn _merkle_proof_transferred(
        &self,
        config: &AnomaPayConfig,
    ) -> TransferResult<MerklePath> {
        pa_merkle_path(config, self.transferred_resource.commitment())
            .await
            .map_err(|_| TransferredResourceMerkleProofNotFound)
    }

    // Creates the compliance witness for the parameters.
    // The compliance witness is created based on the consumed
    // resource and created resource.
    fn _compliance_witness(&self, merkle_proof: MerklePath) -> ComplianceWitness {
        ComplianceWitness::from_resources_with_path(
            self.transferred_resource,
            self.sender_nullifier_key.clone(),
            merkle_proof,
            self.created_resource,
        )
    }

    // Generate the witness for the logic proof for the transferred resource.
    fn _transferred_resource_logic_witness(
        &self,
        action_tree: &MerkleTree,
    ) -> TransferResult<TransferLogic> {
        // Compute the nullifier for the transferred resource.
        let transferred_resource_nullifier = self
            .transferred_resource
            .nullifier(&self.sender_nullifier_key)
            .map_err(|_| InvalidSenderNullifierKey)?;

        // Compute the merkle path of the consumed resource in the action tree
        let transferred_resource_path = action_tree
            .generate_path(&transferred_resource_nullifier)
            .map_err(|_| TransferredResourceNotInActionTree)?;

        Ok(TransferLogic::consume_persistent_resource_logic(
            self.transferred_resource,
            transferred_resource_path,
            self.sender_nullifier_key.clone(),
            self.sender_auth_verifying_key,
            self.auth_signature,
        ))
    }

    // Generate the witness for the logic proof for the created resource.
    fn _created_resource_logic_witness(
        &self,
        action_tree: &MerkleTree,
    ) -> TransferResult<TransferLogic> {
        // Create the merklepath for the resource being created in the action tree.
        let created_resource_path = action_tree
            .generate_path(&self.created_resource.commitment())
            .map_err(|_| CreatedResourceNotInActionTree)?;

        Ok(TransferLogic::create_persistent_resource_logic(
            self.created_resource,
            created_resource_path,
            &self.receiver_discovery_pk,
            self.receiver_encryption_pk,
        ))
    }
    pub async fn generate_transaction(
        &self,
        config: &AnomaPayConfig,
    ) -> TransferResult<Transaction> {
        // Generate the action tree for the resources in this transaction.
        let action_tree = self._action_tree()?;

        // Fetch the merkle path for the resource being transferred
        let merkle_proof_transferred_resource = self._merkle_proof_transferred(config).await?;

        // Generate the compliance proof
        let compliance_witness = self._compliance_witness(merkle_proof_transferred_resource);

        // Generate resource logic witness for the transferred resource
        let transferred_logic_witness = self._transferred_resource_logic_witness(&action_tree)?;

        // Generate the resource logic witness for the created resource
        let created_logic_witness = self._created_resource_logic_witness(&action_tree)?;

        let (compliance_unit, transferred_logic_proof, created_logic_proof) = try_join!(
            compliance_proof_asyncc(&compliance_witness),
            logic_proof_asyncc(&transferred_logic_witness),
            logic_proof_asyncc(&created_logic_witness)
        )
        .map_err(|_| ProofGenerationError)?;

        let compliance_unit: ComplianceUnit =
            compliance_unit.map_err(|_| ComplianceProofGenerationError)?;
        let transferred_logic_proof: LogicVerifier =
            transferred_logic_proof.map_err(|_| TransferredResourceLogicProofError)?;
        let created_logic_proof: LogicVerifier =
            created_logic_proof.map_err(|_| CreatedResourceLogicProofError)?;

        // Create the action based on the three proofs.
        let action: Action = Action::new(
            vec![compliance_unit],
            vec![transferred_logic_proof, created_logic_proof],
        )
        .map_err(|_| InvalidLogicProofsInAction)?;

        // Create the delta proof for this transaction
        let delta_witness = DeltaWitness::from_bytes(&compliance_witness.rcv)
            .map_err(|_| DeltaWitnessGenerationError)?;

        // Create the transaction object
        let transaction = Transaction::create(vec![action], Delta::Witness(delta_witness));

        // Generate the delta proof
        let transaction = transaction
            .generate_delta_proof()
            .map_err(|_| DeltaProofGenerationError)?;

        // Verify the transaction before returning. If it does not verify, something went wrong.
        verify_transaction(transaction.clone()).map_err(|_| TransactionVerificationError)?;

        Ok(transaction)
    }
}
