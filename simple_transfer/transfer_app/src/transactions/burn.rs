//! Module that defines functions to burn a resource

use crate::evm::indexer::pa_merkle_path;
use crate::helpers::verify_transaction;
use crate::transactions::burn::BurnError::{
    BurnedResourceLogicProofGenerationError, BurnedResourceMerkleProofNotFound,
    BurnedResourceNotInActionTree, ComplianceProofGenerationError, CreatedResourceLogicProofError,
    CreatedResourceNotInActionTree, DeltaProofGenerationError, DeltaWitnessGenerationError,
    InvalidLogicProofsInAction, InvalidSenderNullifierKey, ProofGenerationError,
    TransactionVerificationError,
};
use crate::transactions::helpers::{compliance_proof_asyncc, logic_proof_asyncc};
use crate::AnomaPayConfig;
use alloy::primitives::Address;
use arm::action::Action;
use arm::action_tree::MerkleTree;
use arm::authorization::{AuthorizationSignature, AuthorizationVerifyingKey};
use arm::compliance::ComplianceWitness;
use arm::delta_proof::DeltaWitness;
use arm::merkle_path::MerklePath;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::transaction::{Delta, Transaction};
use tokio::try_join;
use transfer_library::TransferLogic;

// A custom type alias for functions that generate transfer transactions.
pub type BurnResult<T> = Result<T, BurnError>;

// Set of errors that can occur during the creation of a transfer transaction.
#[derive(Debug, Clone)]
pub enum BurnError {
    // The user provided an invalid sender nullifier key
    InvalidSenderNullifierKey,
    // The merkle proof for the burned resource was not found.
    BurnedResourceMerkleProofNotFound,
    // There was an issue generating the logic proof for the burned resource.
    BurnedResourceLogicProofGenerationError,
    // The burned resource is not present in the action tree
    BurnedResourceNotInActionTree,
    // An error occurred generating the compliance proof
    ComplianceProofGenerationError,
    // The created resource for this burn transaction was not found in the action tree
    CreatedResourceNotInActionTree,
    // Error generating the logic proof for the created resource
    CreatedResourceLogicProofError,
    // The action could ont be created
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
pub struct BurnParameters {
    pub burned_resource: Resource,
    pub created_resource: Resource,
    pub burner_nullifier_key: NullifierKey,
    pub burner_auth_verifying_key: AuthorizationVerifyingKey,
    pub burner_address: Address,
    pub auth_signature: AuthorizationSignature,
    pub token_address: Address,
}

impl BurnParameters {
    // Create the action tree for these parameters.
    pub fn action_tree(&self) -> BurnResult<MerkleTree> {
        // Compute the nullifier for the transferred resource.
        let burnt_resource_nullifier = self
            .burned_resource
            .nullifier(&self.burner_nullifier_key)
            .map_err(|_| InvalidSenderNullifierKey)?;

        Ok(MerkleTree::new(vec![
            burnt_resource_nullifier,
            self.created_resource.commitment(),
        ]))
    }

    // Fetches the merkle proof for the burned resource.
    // This ensures that the resource that's being burned actually exists.
    pub async fn merkle_proof_burned(&self, config: &AnomaPayConfig) -> BurnResult<MerklePath> {
        pa_merkle_path(config, self.burned_resource.commitment())
            .await
            .map_err(|_| BurnedResourceMerkleProofNotFound)
    }

    // Creates the compliance witness for the parameters.
    // The compliance witness is created based on the burned
    // resource and created resource.
    pub fn compliance_witness(&self, merkle_proof: MerklePath) -> ComplianceWitness {
        ComplianceWitness::from_resources_with_path(
            self.burned_resource,
            self.burner_nullifier_key.clone(),
            merkle_proof,
            self.created_resource,
        )
    }

    // Generate the witness for the logic proof for the burned resource.
    pub fn burned_resource_logic_witness(
        &self,
        action_tree: &MerkleTree,
    ) -> BurnResult<TransferLogic> {
        // Compute the nullifier for the transferred resource.
        let burned_resource_nullifier = self
            .burned_resource
            .nullifier(&self.burner_nullifier_key)
            .map_err(|_| InvalidSenderNullifierKey)?;

        // Compute the merkle path of the consumed resource in the action tree
        let burned_resource_path = action_tree
            .generate_path(&burned_resource_nullifier)
            .map_err(|_| BurnedResourceNotInActionTree)?;

        Ok(TransferLogic::consume_persistent_resource_logic(
            self.burned_resource,
            burned_resource_path,
            self.burner_nullifier_key.clone(),
            self.burner_auth_verifying_key,
            self.auth_signature,
        ))
    }

    // Generate the logic witness for the created resource.
    // Notice that this is a simple resource, n
    pub fn created_resource_logic_witness(
        &self,
        config: &AnomaPayConfig,
        action_tree: &MerkleTree,
    ) -> BurnResult<TransferLogic> {
        // Compute the merkle path of the created resource in the action tree
        let created_resource_path = action_tree
            .generate_path(&self.created_resource.commitment())
            .map_err(|_| CreatedResourceNotInActionTree)?;

        Ok(TransferLogic::burn_resource_logic(
            self.created_resource,
            created_resource_path,
            config.forwarder_address.to_vec(),
            self.token_address.to_vec(),
            self.burner_address.to_vec(),
        ))
    }
    pub async fn generate_transaction(&self, config: &AnomaPayConfig) -> BurnResult<Transaction> {
        // Generate the action tree for the resources in this transaction.
        let action_tree = self.action_tree()?;

        // Fetch the merkle path for the resource being burned
        let merkle_proof_burned_resource = self.merkle_proof_burned(config).await?;

        // Generate the compliance proof
        let compliance_witness = self.compliance_witness(merkle_proof_burned_resource);

        // Generate resource logic witness for the transferred resource
        let burned_resource_logic_witness = self.burned_resource_logic_witness(&action_tree)?;

        // Generate the resource logic witness for the created resource
        let created_resource_logic_witness =
            self.created_resource_logic_witness(config, &action_tree)?;

        // Generate the proof concurrently
        let (compliance_unit, burned_resource_logic_proof, created_resource_logic_proof) =
            try_join!(
                compliance_proof_asyncc(&compliance_witness),
                logic_proof_asyncc(&burned_resource_logic_witness),
                logic_proof_asyncc(&created_resource_logic_witness)
            )
            .map_err(|_| ProofGenerationError)?;

        let compliance_unit = compliance_unit.map_err(|_| ComplianceProofGenerationError)?;
        let burned_resource_logic_proof =
            burned_resource_logic_proof.map_err(|_| BurnedResourceLogicProofGenerationError)?;
        let created_resource_logic_proof =
            created_resource_logic_proof.map_err(|_| CreatedResourceLogicProofError)?;

        // Create the action based on the three proofs.
        let action: Action = Action::new(
            vec![compliance_unit],
            vec![burned_resource_logic_proof, created_resource_logic_proof],
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
