//! Defines helper functions to create resource logic proofs.

use crate::request::witness_data::WitnessTypes;
use crate::request::ProvingResult;
use arm::logic_proof::LogicVerifier;
use tokio::task::JoinHandle;

/// Given a logic witness, returns a logic proof.
pub fn logic_proof_async(transfer_logic: WitnessTypes) -> JoinHandle<ProvingResult<LogicVerifier>> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || transfer_logic_clone.prove())
}

/// Given a list of logic witnesses, computes the proof concurrently.
pub async fn logic_proofs_async(
    transfer_logics: Vec<WitnessTypes>,
) -> ProvingResult<Vec<LogicVerifier>> {
    let handles: Vec<_> = transfer_logics.into_iter().map(logic_proof_async).collect();

    let results: Vec<_> = futures::future::join_all(handles).await;

    results
        .into_iter()
        .map(|join_result| join_result.expect("Task panicked"))
        .collect()
}
