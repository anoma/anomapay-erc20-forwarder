//! Defines helper functions to be used in creating transactions.

use crate::transactions::helpers::ProveErr::{ComplianceUnitCreateError, LogicProofCreateError};
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::logic_proof::{LogicProver, LogicVerifier};
use thiserror::Error;
use tokio::task::JoinHandle;

pub type ProofResult<T> = Result<T, ProveErr>;

#[derive(Error, Debug)]
pub enum ProveErr {
    #[error("Error creating compliance unit")]
    ComplianceUnitCreateError(arm::error::ArmError),
    #[error("Error creating logic proof: {0}")]
    LogicProofCreateError(arm::error::ArmError),
}

/// Create a compliance unit based on a compliance witness.
pub fn compliance_proof(compliance_witness: &ComplianceWitness) -> ProofResult<ComplianceUnit> {
    ComplianceUnit::create(compliance_witness).map_err(ComplianceUnitCreateError)
}

/// Given a compliance witness, generates a compliance unit.
pub async fn compliance_proof_async(
    compliance_witness: &ComplianceWitness,
) -> ProofResult<ComplianceUnit> {
    let compliance_witness_clone = compliance_witness.clone();
    tokio::task::spawn_blocking(move || compliance_proof(&compliance_witness_clone))
        .await
        .unwrap()
}

/// Given a logic witness, returns a logic proof.
pub fn logic_proof<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> ProofResult<LogicVerifier> {
    transfer_logic.prove().map_err(LogicProofCreateError)
}

/// Given a logic witness, returns a logic proof.
pub async fn logic_proof_async<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> ProofResult<LogicVerifier> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || logic_proof(&transfer_logic_clone))
        .await
        .unwrap()
}

/// Given a logic witness, returns a logic proof.
pub fn logic_proof_asyncc<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> JoinHandle<ProofResult<LogicVerifier>> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || logic_proof(&transfer_logic_clone))
}

/// Given a compliance witness, generates a compliance unit.
pub fn compliance_proof_asyncc(
    compliance_witness: &ComplianceWitness,
) -> JoinHandle<ProofResult<ComplianceUnit>> {
    let compliance_witness_clone = compliance_witness.clone();
    tokio::task::spawn_blocking(move || compliance_proof(&compliance_witness_clone))
}
