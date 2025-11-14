//! Contains logic to generate compliance proofs for compliance witnesses.
use crate::request::ProvingError::ComplianceProofGenerationError;
use crate::request::ProvingResult;
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use chrono::Local;
use tokio::task::JoinHandle;

/// Create a compliance unit based on a compliance witness.
///
/// This function is blocking and cannot be used safely in an asynchronous
/// context. Use `compliance_proof_async` instead.
pub fn compliance_proof(compliance_witness: &ComplianceWitness) -> ProvingResult<ComplianceUnit> {
    let now = Local::now();
    println!("started compliance proof {}", now.format("%H:%M:%S"));
    let compliance_unit =
        ComplianceUnit::create(compliance_witness).map_err(|_| ComplianceProofGenerationError);
    let now = Local::now();
    println!("started compliance proof {}", now.format("%H:%M:%S"));
    compliance_unit
}

/// Given a compliance witness, generates a compliance unit.
pub fn compliance_proof_async(
    compliance_witness: &ComplianceWitness,
) -> JoinHandle<ProvingResult<ComplianceUnit>> {
    let compliance_witness_clone = compliance_witness.clone();
    tokio::task::spawn_blocking(move || compliance_proof(&compliance_witness_clone))
}

/// Given a list of compliance witnesses, computes the proofs concurrently.
pub async fn compliance_proofs_async(
    compliance_witnesses: Vec<ComplianceWitness>,
) -> ProvingResult<Vec<ComplianceUnit>> {
    let handles: Vec<_> = compliance_witnesses
        .into_iter()
        .map(|witness| compliance_proof_async(&witness))
        .collect();

    let results: Vec<_> = futures::future::join_all(handles).await;

    results
        .into_iter()
        .map(|join_result| join_result.expect("Task panicked"))
        .collect()
}
