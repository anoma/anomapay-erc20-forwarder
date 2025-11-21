//! Contains the `Parameters` struct and its implementations.
//!
//! The `Parameters` struct holds all the information required to generate a
//! transaction for a user. To generate a transaction all that is required is a
//! list of consumed and created resources with their associated,
//! application-specific witness data.

use crate::request::compliance_proof::compliance_proofs_async;
use crate::request::logic_proof::logic_proofs_async;
use crate::request::resources::{Consumed, Created};
use crate::request::witness_data::{ConsumedWitnessData, WitnessTypes};
use crate::request::ProvingError::ConsumedAndCreatedResourceCountMismatch;
use crate::request::{
    ProvingError::{DeltaProofGenerationError, TransactionVerificationError},
    ProvingResult,
};
use crate::AnomaPayConfig;
use arm::compliance::ComplianceWitness;
use arm::delta_proof::DeltaWitness;
use arm::merkle_path::MerklePath;
use arm::transaction::{Delta, Transaction};
use arm::Digest;
use arm::{action::Action, action_tree::MerkleTree};
use futures::future::try_join_all;
use serde::{Deserialize, Serialize};
use tokio::try_join;
use utoipa::ToSchema;

/// The `Parameters` struct holds all the necessary resources to generate a
/// transaction.
#[derive(ToSchema, Deserialize, Serialize, Clone, PartialEq)]
pub struct Parameters {
    /// the list of resources the transaction is expected to create.
    pub created_resources: Vec<Created>,
    /// The list of resources the transaction is expected to consume.
    pub consumed_resources: Vec<Consumed>,
}

impl Parameters {
    #[allow(dead_code)]
    /// Creates a new `Parameters` struct with the given lists of resources.
    /// The function asserts that both lists are equal in length or fails.
    pub fn new(
        created_resources: Vec<Created>,
        consumed_resources: Vec<Consumed>,
    ) -> ProvingResult<Self> {
        // The transaction has to be balanced. That is, equal amount of consumed
        // resources and created resources.
        if consumed_resources.len() != created_resources.len() {
            return Err(ConsumedAndCreatedResourceCountMismatch);
        }

        Ok(Self {
            created_resources,
            consumed_resources,
        })
    }

    /// Fetches the merkle proof for all the consumed resources.
    async fn merkle_proofs(&self, config: &AnomaPayConfig) -> ProvingResult<Vec<MerklePath>> {
        let futures = self.consumed_resources.iter().map(|consumed| {
            let commitment = consumed.resource.commitment();
            consumed.witness_data.merkle_path(config, commitment)
        });
        let merkle_proofs = try_join_all(futures).await?;

        Ok(merkle_proofs)
    }
    /// Create the compliance witnesses for the `Parameters`. Compliance
    /// witnesses are built using pairs of consumed and created resources. For
    /// each consumed resource a created resource is taken, and that pair is
    /// used to create a compliance witness.
    fn compliance_witnesses(
        &self,
        merkle_proofs: Vec<MerklePath>,
    ) -> ProvingResult<Vec<ComplianceWitness>> {
        type ResourcePair = (Consumed, Created);

        // Create a list of pairs of created and consumed resources.
        // Each pair will be used to create 1 compliance witness.
        let pairs: Vec<ResourcePair> = self
            .consumed_resources
            .iter()
            .cloned()
            .zip(self.created_resources.iter().cloned())
            .collect();

        let pairs: Vec<(ResourcePair, MerklePath)> = pairs
            .iter()
            .cloned()
            .zip(merkle_proofs.iter().cloned())
            .collect();

        Ok(pairs
            .into_iter()
            .map(|((consumed, created), path): (ResourcePair, MerklePath)| {
                ComplianceWitness::from_resources_with_path(
                    consumed.resource,
                    consumed.nullifier_key,
                    path,
                    created.resource,
                )
            })
            .collect())
    }

    /// Create the logic witnesses for all the resources. A logic witness is
    /// created for each resource.
    ///
    /// In total there will be len(created_resources) + len(consumed_resources)
    /// logic witnesses.
    fn logic_witnesses(&self, config: &AnomaPayConfig) -> ProvingResult<Vec<WitnessTypes>> {
        let action_tree = self.action_tree()?;

        // Create all the logic witnesses for the created resources.
        let mut created_logic_witnesses: Vec<WitnessTypes> = self
            .created_resources
            .iter()
            .map(|resource| resource.logic_witness(&action_tree, config))
            .collect::<ProvingResult<Vec<WitnessTypes>>>()?;

        // Create the logic witnesses for all the consumed resources.
        let mut consumed_logic_witnesses: Vec<WitnessTypes> = self
            .consumed_resources
            .iter()
            .map(|r| r.logic_witness(&action_tree, config))
            .collect::<ProvingResult<Vec<WitnessTypes>>>()?;

        // Append the created and consumed logic witnesses.
        created_logic_witnesses.append(&mut consumed_logic_witnesses);

        Ok(created_logic_witnesses)
    }

    // Builds the action tree for the resources. The action tree consists of all
    // the resources in the `Parameters`.
    fn action_tree(&self) -> ProvingResult<MerkleTree> {
        // To create the action tree, the tag of each resource is required. For
        // a consumed resource the tag is the nullifier. For a created resource
        // the tag is the commitment.
        let consumed_tags: ProvingResult<Vec<Digest>> = self
            .consumed_resources
            .iter()
            .map(|c| c.nullifier())
            .collect();
        let consumed_tags = consumed_tags?;

        let created_tags: Vec<Digest> = self
            .created_resources
            .iter()
            .map(|r| r.commitment())
            .collect();

        // The action tree expects a list of tags, but the leaves have to be
        // interleaved as consumed, created, consumed, created, etc. To achieve
        // this interleaving, zip the two lists and flatten them again.
        let action_tags = consumed_tags
            .into_iter()
            .zip(created_tags)
            .flat_map(|(consumed, created)| vec![consumed, created])
            .collect();

        Ok(MerkleTree::new(action_tags))
    }

    /// Generates a transaction for the given `Parameters` struct.
    #[allow(dead_code)]
    pub async fn generate_transaction(
        &self,
        config: &AnomaPayConfig,
    ) -> ProvingResult<Transaction> {
        // Compute the merkle proofs for all the consumed resources.
        let merkle_proofs = self.merkle_proofs(config).await?;
        // Generate the compliance witness
        let compliance_witnesses: Vec<ComplianceWitness> =
            self.compliance_witnesses(merkle_proofs)?;

        // Generate the logic witnesses.
        let logic_witnesses: Vec<WitnessTypes> = self.logic_witnesses(config)?;

        // Compute all the proofs concurrently
        let (compliance_units, logic_proofs) = try_join!(
            compliance_proofs_async(compliance_witnesses.clone()),
            logic_proofs_async(logic_witnesses)
        )?;

        // Create the action based on the compliance units and logic proofs.
        let action: Action = Action::new(compliance_units, logic_proofs).unwrap();

        // Compute the delta witness for the delta proof of this transaction.
        let rcvs: Vec<Vec<u8>> = compliance_witnesses.iter().map(|w| w.rcv.clone()).collect();
        let delta_witness = DeltaWitness::from_bytes_vec(&rcvs).unwrap();

        // Create the transaction that holds the action and the delta witness.
        let transaction = Transaction::create(vec![action], Delta::Witness(delta_witness));

        // Generate the delta proof
        let transaction = transaction
            .generate_delta_proof()
            .map_err(|_| DeltaProofGenerationError)?;

        // Verify the transaction before returning. If it does not verify, something went wrong.
        match transaction.clone().verify() {
            Ok(_) => Ok(transaction),
            Err(e) => {
                println!("error: {:?}", e);
                Err(TransactionVerificationError)
            }
        }
    }
}
