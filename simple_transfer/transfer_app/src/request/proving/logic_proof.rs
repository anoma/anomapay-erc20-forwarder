//! Defines helper functions to create resource logic proofs.

use crate::request::proving::ProvingResult;
use crate::request::proving::witness_data::WitnessTypes;
use crate::time_it;
use arm::logic_proof::LogicVerifier;
#[cfg(not(test))]
use log::info;
#[cfg(test)]
use println as info;
use tokio::task::JoinHandle;

/// Create a logic proof based on a logic proof witness.
///
/// This function is blocking and cannot be used safely in an asynchronous
/// context. Use `logic_proof_async` instead.
fn logic_proof(transfer_logic: WitnessTypes) -> ProvingResult<LogicVerifier> {
    time_it!("logic proof", transfer_logic.prove())
}
/// Given a logic witness, returns a logic proof.
pub fn logic_proof_async(transfer_logic: WitnessTypes) -> JoinHandle<ProvingResult<LogicVerifier>> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || logic_proof(transfer_logic_clone))
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
