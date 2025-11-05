//! Module that defines helper functions to create split transactions.

use crate::evm::indexer::pa_merkle_path;
use crate::helpers::verify_transaction;
use crate::transactions::helpers::{compliance_proof_async, logic_proof_async};
use crate::transactions::split::SplitError::{
    ComplianceProofGenerationError, CreatedResourceLogicProofError, CreatedResourceNotInActionTree,
    DeltaProofGenerationError, DeltaWitnessGenerationError, InvalidLogicProofsInAction,
    InvalidSenderNullifierKey, PaddingResourceLogicProofError, PaddingResourceNotInActionTree,
    RemainderResourceLogicProofError, RemainderResourceNotInActionTree,
    SplitResourceMerkleProofNotFound, ToSplitResourceLogicProofError,
    ToSplitResourceNotInActionTree, TransactionVerificationError,
};
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
use transfer_library::TransferLogic;

// A custom type alias for functions that generate split transactions.
pub type SplitResult<T> = Result<T, SplitError>;

// Set of errors that can occur during the creation of a split transaction.
#[derive(Debug, Clone)]
pub enum SplitError {
    // The user provided an invalid sender nullifier key
    InvalidSenderNullifierKey,
    // The merkle proof for the resource being transferred did not exist or was not fetched.
    SplitResourceMerkleProofNotFound,
    // An error occurred generating the compliance proof
    ComplianceProofGenerationError,
    // An error occurred generating the logic proof for the transferred resource
    ToSplitResourceLogicProofError,
    // An error occurred generating the logic proof for the created resource.
    CreatedResourceLogicProofError,
    // An error occurred generating the proof for the padding resource
    PaddingResourceLogicProofError,
    // An error occurred for the remainder resource logic proof
    RemainderResourceLogicProofError,
    // The created resource was not found in the action tree.
    CreatedResourceNotInActionTree,
    ToSplitResourceNotInActionTree,
    RemainderResourceNotInActionTree,
    PaddingResourceNotInActionTree,
    // The logic proofs were not valid inputs to create an action
    InvalidLogicProofsInAction,
    // Failed to create the delta witness for the given actions.
    DeltaWitnessGenerationError,
    // Failed to generate the delta proof for the transaction
    DeltaProofGenerationError,
    // The created transaction failed to verify.
    TransactionVerificationError,
}

/// Defines a struct that holds all the necessary values to create a split transaction.
pub struct SplitParameters {
    // The resource that has to be split into the remainder and created resource.
    pub to_split_resource: Resource,
    // The resource that will take part of the to split resource.
    pub created_resource: Resource,
    // The resource that holds the remainder of the to_split resource after taking out the created resource.
    pub remainder_resource: Resource,
    // The padding resource to balance the consumed and created resources.
    pub padding_resource: Resource,
    // The nullifier key for the resource being split.
    pub sender_nullifier_key: NullifierKey,
    // The auth verifying key of the owner of the to split resource.
    pub sender_auth_verifying_key: AuthorizationVerifyingKey,
    // The signature of the user who wants to split
    pub auth_signature: AuthorizationSignature,
    // The discovery and encryption keypair of the receiver.
    pub receiver_discovery_pk: AffinePoint,
    pub receiver_encryption_pk: AffinePoint,
    pub sender_discovery_pk: AffinePoint,
    pub sender_encryption_pk: AffinePoint,
}

impl SplitParameters {
    // Create the action tree for these parameters.
    fn action_tree(&self) -> SplitResult<MerkleTree> {
        let padding_resource_nullifier = self
            .padding_resource
            .nullifier(&NullifierKey::default())
            .map_err(|_| InvalidSenderNullifierKey)?;

        let to_split_resource_nullifier = self
            .to_split_resource
            .nullifier(&self.sender_nullifier_key)
            .map_err(|_| InvalidSenderNullifierKey)?;

        Ok(MerkleTree::new(vec![
            to_split_resource_nullifier,
            self.created_resource.commitment(),
            padding_resource_nullifier,
            self.remainder_resource.commitment(),
        ]))
    }

    // Fetches the merkle proof for the resource being split.
    // This ensures that the resource that's being split actually exists.
    async fn merkle_proof_to_split(&self, config: &AnomaPayConfig) -> SplitResult<MerklePath> {
        pa_merkle_path(config, self.to_split_resource.commitment())
            .await
            .map_err(|_| SplitResourceMerkleProofNotFound)
    }

    // Creates the compliance witness for the split resource.
    fn compliance_witness_created(&self, merkle_proof: MerklePath) -> ComplianceWitness {
        ComplianceWitness::from_resources_with_path(
            self.to_split_resource,
            self.sender_nullifier_key.clone(),
            merkle_proof,
            self.created_resource,
        )
    }

    // Creates the compliance witness for the padding resource.
    fn compliance_witness_remainder(&self) -> ComplianceWitness {
        ComplianceWitness::from_resources_with_path(
            self.padding_resource,
            NullifierKey::default(),
            MerklePath::default(),
            self.remainder_resource,
        )
    }

    // Create the logic proof for the to split resource.
    fn logic_proof_split_resource(&self, action_tree: &MerkleTree) -> SplitResult<TransferLogic> {
        let to_split_resource_nullifier = self
            .to_split_resource
            .nullifier(&self.sender_nullifier_key)
            .map_err(|_| InvalidSenderNullifierKey)?;

        // Compute the nullifier for the transferred resource.
        let to_split_resource_path = action_tree
            .generate_path(&to_split_resource_nullifier)
            .map_err(|_| ToSplitResourceNotInActionTree)?;

        Ok(TransferLogic::consume_persistent_resource_logic(
            self.to_split_resource,
            to_split_resource_path.clone(),
            self.sender_nullifier_key.clone(),
            self.sender_auth_verifying_key,
            self.auth_signature,
        ))
    }
    // Create the logic proof for the padding resource.
    fn logic_proof_padding_resource(
        &self,
        action_tree: &MerkleTree,
    ) -> SplitResult<TrivialLogicWitness> {
        let padding_resource_nullifier = self
            .padding_resource
            .nullifier(&NullifierKey::default())
            .map_err(|_| InvalidSenderNullifierKey)?;

        let padding_resource_path = action_tree
            .generate_path(&padding_resource_nullifier)
            .map_err(|_| PaddingResourceNotInActionTree)?;

        Ok(TrivialLogicWitness::new(
            self.padding_resource,
            padding_resource_path.clone(),
            NullifierKey::default(),
            true,
        ))
    }

    // Create the logic proof for the created resource.
    fn logic_proof_created_resource(&self, action_tree: &MerkleTree) -> SplitResult<TransferLogic> {
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

    // Create the logic proof for the remainder resource.
    fn logic_proof_remainder_resource(
        &self,
        action_tree: &MerkleTree,
    ) -> SplitResult<TransferLogic> {
        let remainder_resource_path = action_tree
            .generate_path(&self.remainder_resource.commitment())
            .map_err(|_| RemainderResourceNotInActionTree)?;

        Ok(TransferLogic::create_persistent_resource_logic(
            self.remainder_resource,
            remainder_resource_path,
            &self.sender_discovery_pk,
            self.sender_encryption_pk,
        ))
    }

    pub async fn generate_transaction(&self, config: &AnomaPayConfig) -> SplitResult<Transaction> {
        // Generate the action tree for the resources in this transaction.
        let action_tree = self.action_tree()?;

        // Fetch the merkle path for the resource being split
        let merkle_proof_transferred_resource = self.merkle_proof_to_split(config).await?;

        // Generate the compliance proof for the resource to split
        let compliance_witness_created =
            self.compliance_witness_created(merkle_proof_transferred_resource);
        let compliance_unit_created = compliance_proof_async(&compliance_witness_created)
            .await
            .map_err(|_| ComplianceProofGenerationError)?;

        // Generate the compliance proof for the padding resource
        let compliance_witness_remainder = self.compliance_witness_remainder();
        let compliance_unit_remainder = compliance_proof_async(&compliance_witness_remainder)
            .await
            .map_err(|_| ComplianceProofGenerationError)?;

        // Create the logic proofs for the 4 resources.
        let created_logic_witness = self.logic_proof_created_resource(&action_tree)?;
        let created_logic_proof = logic_proof_async(&created_logic_witness)
            .await
            .map_err(|_| CreatedResourceLogicProofError)?;

        let padding_logic_witness = self.logic_proof_padding_resource(&action_tree)?;
        let padding_logic_proof = logic_proof_async(&padding_logic_witness)
            .await
            .map_err(|_| PaddingResourceLogicProofError)?;

        let remainder_logic_witness = self.logic_proof_remainder_resource(&action_tree)?;
        let remainder_logic_proof = logic_proof_async(&remainder_logic_witness)
            .await
            .map_err(|_| RemainderResourceLogicProofError)?;

        let to_split_logic_witness = self.logic_proof_split_resource(&action_tree)?;
        let to_split_logic_proof = logic_proof_async(&to_split_logic_witness)
            .await
            .map_err(|_| ToSplitResourceLogicProofError)?;

        // Create the action based on the three proofs.
        let action: Action = Action::new(
            vec![compliance_unit_created, compliance_unit_remainder],
            vec![
                to_split_logic_proof,
                created_logic_proof,
                padding_logic_proof,
                remainder_logic_proof,
            ],
        )
        .map_err(|_| InvalidLogicProofsInAction)?;

        // Create the delta proof for this transaction.
        let delta_witness: DeltaWitness = DeltaWitness::from_bytes_vec(&[
            compliance_witness_created.rcv,
            compliance_witness_remainder.rcv,
        ])
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
