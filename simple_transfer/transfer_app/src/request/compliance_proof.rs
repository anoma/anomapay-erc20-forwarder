//! Contains logic to generate compliance proofs for compliance witnesses.
use crate::request::{ProofResult, ProveErr};
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use tokio::task::JoinHandle;

/// Create a compliance unit based on a compliance witness.
///
/// This function is blocking and cannot be used safely in an asynchronous
/// context. Use `compliance_proof_async` instead.
pub fn compliance_proof(compliance_witness: &ComplianceWitness) -> ProofResult<ComplianceUnit> {
    ComplianceUnit::create(compliance_witness).map_err(ProveErr::ComplianceUnitCreateError)
}

/// Given a compliance witness, generates a compliance unit.
pub fn compliance_proof_async(
    compliance_witness: &ComplianceWitness,
) -> JoinHandle<ProofResult<ComplianceUnit>> {
    let compliance_witness_clone = compliance_witness.clone();
    tokio::task::spawn_blocking(move || compliance_proof(&compliance_witness_clone))
}
