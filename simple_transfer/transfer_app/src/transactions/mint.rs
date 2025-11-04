//! Module that defines helper functions to create mint transactions.

use crate::errors::TransactionError::{
    ActionError, ActionTreeError, DeltaProofCreateError, LogicProofCreateError, MerklePathError,
    ProofGenerationError,
};
use crate::transactions::helpers::{compliance_proof_asyncc, logic_proof_asyncc, TxResult};
use alloy::primitives::U256;
use arm::action::Action;
use arm::action_tree::MerkleTree;
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::delta_proof::DeltaWitness;
use arm::logic_proof::LogicVerifier;
use arm::nullifier_key::NullifierKey;
use arm::resource::Resource;
use arm::transaction::{Delta, Transaction};
use arm::Digest;
use k256::AffinePoint;
use tokio::try_join;
use transfer_library::TransferLogic;
use crate::helpers::verify_transaction;

/// Defines a struct that holds all the necessary values to create a mint transaction.
#[derive(Debug)]
pub struct MintParameters {
    // The resource that is being minted.
    pub created_resource: Resource,
    // The ephemeral resource to be consumed.
    pub consumed_resource: Resource,
    // The nullifier key of the user who wants to mint a resource.
    pub consumed_nullifier_key: NullifierKey,
    // The commitment to the created resource
    pub created_resource_commitment: Digest,
    // The nullifier of the consumed resource
    pub consumed_resource_nullifier: Digest,
    // The commitment tree root of the merkle tree that holds the resources.
    // This is a mint request, so this is the initial root.
    // For more anonimity, this can be the actual latest root, however.
    pub latest_commitment_tree_root: Digest,
    // Ethereum address of the user that wants to mint.
    pub user_address: Vec<u8>,
    // The permit2 signature that allows the PA to transfer out of the user's account.
    pub permit_signature: Vec<u8>,
    // The discovery key of the user. This is the public key that can decrypt the resource from the indexer.
    pub discovery_pk: AffinePoint,
    // The public encryption key of the user to encrypt the resource.
    pub encryption_pk: AffinePoint,
    // The permit2 deadline.
    pub permit_deadline: u64,
    // The nonce used to generate the permit2 signature.
    pub permit_nonce: Vec<u8>,
    // The address of the token that is being wrapped (e.g., USDC)
    pub token_address: Vec<u8>,
    // The address of the forwarder contract
    pub forwarder_contract_address: Vec<u8>,
}

impl MintParameters {
    // Create the action tree for these parameters.
    fn action_tree(&self) -> MerkleTree {
        MerkleTree::new(vec![
            self.consumed_resource_nullifier,
            self.created_resource_commitment,
        ])
    }

    // Creates the compliance witness for the parameters.
    // The compliance witness is created based on the consumed
    // resource and created resource.
    fn compliance_witness(&self) -> ComplianceWitness {
        ComplianceWitness::from_resources(
            self.consumed_resource,
            self.latest_commitment_tree_root,
            self.consumed_nullifier_key.clone(),
            self.created_resource,
        )
    }

    // Create the resource logic witness to generate the resource logic proof for the consumed resource.
    fn consumed_logic_witness(&self, action_tree: &MerkleTree) -> TxResult<TransferLogic> {
        // compute the resource path from the action tree for the consumed resource.
        let consumed_resource_path = action_tree
            .generate_path(&self.consumed_resource_nullifier)
            .map_err(|_| MerklePathError)?;

        Ok(TransferLogic::mint_resource_logic_with_permit(
            self.consumed_resource,
            consumed_resource_path,
            self.consumed_nullifier_key.clone(),
            self.forwarder_contract_address.clone(),
            self.token_address.clone(),
            self.user_address.clone(),
            self.permit_nonce.clone(),
            U256::from(self.permit_deadline).to_be_bytes_vec(),
            self.permit_signature.clone(),
        ))
    }

    // Create the resource logic witness for the created resource.
    fn created_logic_witness(&self, action_tree: &MerkleTree) -> TxResult<TransferLogic> {
        // compute the resource path from the action tree and created resource.
        let created_resource_path = action_tree
            .generate_path(&self.created_resource_commitment)
            .map_err(|_| ActionTreeError)?;

        Ok(TransferLogic::create_persistent_resource_logic(
            self.created_resource,
            created_resource_path,
            &self.discovery_pk,
            self.encryption_pk,
        ))
    }

    // Generates a transaction for a MintParameters.
    pub async fn generate_transaction(&self) -> TxResult<Transaction> {
        // Generate the action tree for the resources in this transaction.
        let action_tree = self.action_tree();

        // Generate the compliance proof
        let compliance_witness = self.compliance_witness();

        // Generate resource logic witness for the consumed resource
        let consumed_logic_witness = self.consumed_logic_witness(&action_tree)?;

        // Generate the resource logic witness for the created resource
        let created_logic_witness = self.created_logic_witness(&action_tree)?;

        // Generate the proofs
        let (consumed_logic_proof, compliance_unit, created_logic_proof) = try_join!(
            logic_proof_asyncc(&consumed_logic_witness),
            compliance_proof_asyncc(&compliance_witness),
            logic_proof_asyncc(&created_logic_witness)
        )
        .map_err(|_| ProofGenerationError)?;

        let created_logic_proof: LogicVerifier = created_logic_proof?;
        let compliance_unit: ComplianceUnit = compliance_unit?;
        let consumed_logic_proof: LogicVerifier = consumed_logic_proof?;

        // Create the action based on the three proofs.
        let action: Action = Action::new(
            vec![compliance_unit],
            vec![consumed_logic_proof, created_logic_proof],
        )
        .map_err(|_| ActionError)?;

        // Create the delta proof for this transaction.
        let delta_witness =
            DeltaWitness::from_bytes(&compliance_witness.rcv).map_err(|_| LogicProofCreateError)?;

        // Create the transaction object
        let transaction = Transaction::create(vec![action], Delta::Witness(delta_witness));

        // Generate the delta proof
        let transaction = transaction
            .generate_delta_proof()
            .map_err(|_| DeltaProofCreateError)?;

        // Verify the transaction before returning. If it does not verify, something went wrong.
        verify_transaction(transaction.clone())?;

        Ok(transaction)
    }
}
