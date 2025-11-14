use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::delta_proof::DeltaWitness;
use arm::logic_proof::{LogicProver, LogicVerifier};
use arm::transaction::{Delta, Transaction};
use arm::Digest;
use arm::{action::Action, action_tree::MerkleTree};

use crate::request::compliance_proof::compliance_proof_async;
use crate::request::logic_proof::logic_proof_async;
use crate::request::resources::{Consumed, Created};
use crate::request::{
    ProvingError::{
        self, AsyncError, ComplianceProofGenerationError, DeltaProofGenerationError,
        LogicProofGenerationError, TransactionVerificationError,
    },
    ProvingResult,
};
use crate::AnomaPayConfig;

/// The `Parameters` struct holds all the information required to generate a
/// transaction for a user. To generate a transaction all that is required is a
/// list of consumed resource and their meta data, and a list of created
/// resources and their meta data.
pub struct Parameters<T: LogicProver + Send + 'static> {
    pub created_resources: Vec<Created<T>>,
    pub consumed_resources: Vec<Consumed<T>>,
    pub latest_commitment_tree_root: Digest,
}

impl<WitnessType: LogicProver + Send + 'static> Parameters<WitnessType> {
    #[allow(dead_code)]
    pub fn new(
        created_resources: Vec<Created<WitnessType>>,
        consumed_resources: Vec<Consumed<WitnessType>>,
        latest_commitment_tree_root: Digest,
    ) -> ProvingResult<Self> {
        if consumed_resources.len() != created_resources.len() {
            return Err(ProvingError::ConsumedAndCreatedResourceCountMismatch);
        }

        Ok(Self {
            created_resources,
            consumed_resources,
            latest_commitment_tree_root,
        })
    }

    pub(crate) fn compliance_witnesses(&self) -> ProvingResult<Vec<ComplianceWitness>> {
        let pairs: Vec<(Consumed<WitnessType>, Created<WitnessType>)> = self
            .consumed_resources
            .iter()
            .cloned()
            .zip(self.created_resources.iter().cloned())
            .collect();

        Ok(pairs
            .into_iter()
            .map(
                |(consumed, created): (Consumed<WitnessType>, Created<WitnessType>)| {
                    ComplianceWitness::from_resources(
                        consumed.resource,
                        self.latest_commitment_tree_root,
                        consumed.nullifier_key,
                        created.resource,
                    )
                },
            )
            .collect())
    }

    pub(crate) fn logic_witnesses(
        &self,
        config: &AnomaPayConfig,
    ) -> ProvingResult<Vec<WitnessType>> {
        let action_tree = self.action_tree()?;

        let mut created_logic_witnesses: Vec<WitnessType> = self
            .created_resources
            .iter()
            .map(|resource| resource.logic_witness(&action_tree, config))
            .collect::<ProvingResult<Vec<WitnessType>>>()?;

        let mut consumed_logic_witnesses: Vec<WitnessType> = self
            .consumed_resources
            .iter()
            .map(|r| r.logic_witness(&action_tree, config))
            .collect::<ProvingResult<Vec<WitnessType>>>()?;

        created_logic_witnesses.append(&mut consumed_logic_witnesses);

        Ok(created_logic_witnesses)
    }

    // Action tree is built on all the resources.
    fn action_tree(&self) -> ProvingResult<MerkleTree> {
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

        let action_tags = consumed_tags
            .into_iter()
            .zip(created_tags)
            .flat_map(|(consumed, created)| vec![consumed, created])
            .collect();

        Ok(MerkleTree::new(action_tags))
    }
    #[allow(dead_code)]
    pub async fn generate_transaction(
        &self,
        config: &AnomaPayConfig,
    ) -> ProvingResult<Transaction> {
        // Generate the compliance witness
        let compliance_witnesses: Vec<ComplianceWitness> = self.compliance_witnesses()?;

        // For each compliance witness, compute the compliance unit (i.e., proof).
        let mut compliance_units: Vec<ComplianceUnit> = vec![];
        for compliance_witness in compliance_witnesses.iter() {
            let compliance_unit = compliance_proof_async(compliance_witness)
                .await
                .map_err(|e| AsyncError(e.to_string()))?
                .map_err(|_| ComplianceProofGenerationError)?;

            compliance_units.push(compliance_unit);
        }

        // Generate the logic witnesses.
        let logic_witnesses: Vec<WitnessType> = self.logic_witnesses(config)?;

        // For each logic witness, compute the logic proof.
        let mut logic_proofs: Vec<LogicVerifier> = vec![];
        for logic_witness in logic_witnesses.into_iter() {
            let logic_proof = logic_proof_async(&logic_witness)
                .await
                .map_err(|e| AsyncError(e.to_string()))?
                .map_err(|_| LogicProofGenerationError)?;
            logic_proofs.push(logic_proof);
        }

        let action: Action = Action::new(compliance_units, logic_proofs).unwrap();

        let rcvs: Vec<Vec<u8>> = compliance_witnesses.iter().map(|w| w.rcv.clone()).collect();
        let delta_witness = DeltaWitness::from_bytes_vec(&rcvs).unwrap();

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
