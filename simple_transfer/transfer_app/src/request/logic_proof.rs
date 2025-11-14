//! Defines helper functions to create resource logic proofs.

use crate::request::ProvingError::LogicProofGenerationError;
use crate::request::ProvingResult;
use crate::time_it;
use arm::logic_proof::{LogicProver, LogicVerifier};
#[cfg(not(test))]
use log::info;
#[cfg(test)]
use println as info;
use tokio::task::JoinHandle;

/// Given a logic witness, returns a logic proof.
///
/// This function is not safe to be used in async contexts. Use
/// `logic_proof_async` instead.
pub fn logic_proof<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> ProvingResult<LogicVerifier> {
    time_it!(
        "logic proof",
        transfer_logic
            .prove()
            .map_err(|_| LogicProofGenerationError)
    )
}

/// Given a logic witness, returns a logic proof.
pub fn logic_proof_async<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> JoinHandle<ProvingResult<LogicVerifier>> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || logic_proof(&transfer_logic_clone))
}

/// Given a list of logic witnesses, computes the proof concurrently.
pub async fn logic_proofs_async<T: LogicProver + Send + 'static>(
    transfer_logics: Vec<T>,
) -> ProvingResult<Vec<LogicVerifier>> {
    let handles: Vec<_> = transfer_logics
        .into_iter()
        .map(|logic| logic_proof_async(&logic))
        .collect();

    let results: Vec<_> = futures::future::join_all(handles).await;

    results
        .into_iter()
        .map(|join_result| join_result.expect("Task panicked"))
        .collect()
}
