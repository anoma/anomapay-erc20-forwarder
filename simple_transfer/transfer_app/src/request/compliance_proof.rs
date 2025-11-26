//! Contains logic to generate compliance proofs for compliance witnesses.
use crate::request::ProvingError::ComplianceProofGenerationError;
use crate::request::ProvingResult;
use arm::compliance::ComplianceWitness;
use arm::compliance_unit::ComplianceUnit;
use arm::proving_system::ProofType;
use tokio::task::JoinHandle;

#[cfg(not(test))]
use log::info;
#[cfg(test)]
use println as info;

#[macro_export]
/// Times the execution of an expression to print out the duration for debugging purposes and logging.
macro_rules! time_it {
    ($name:expr, $body:expr) => {{
        let start = chrono::Local::now();
        info!("start {} {}", $name, start.format("%H:%M:%S"));
        let result = $body;
        let end = chrono::Local::now();
        let duration = end.signed_duration_since(start);
        info!(
            "end {} {} (took {:.2}s)",
            $name,
            end.format("%H:%M:%S"),
            duration.num_milliseconds() as f64 / 1000.0
        );
        result
    }};
}

/// Create a compliance unit based on a compliance witness.
///
/// This function is blocking and cannot be used safely in an asynchronous
/// context. Use `compliance_proof_async` instead.
pub fn compliance_proof(compliance_witness: &ComplianceWitness) -> ProvingResult<ComplianceUnit> {
    time_it!(
        "compliance proof",
        ComplianceUnit::create(compliance_witness, ProofType::Groth16).map_err(|_| ComplianceProofGenerationError)
    )
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
