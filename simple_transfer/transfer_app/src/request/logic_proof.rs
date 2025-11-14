//! Defines helper functions to be used in creating transactions.

use crate::request::{ProofResult, ProveErr};
use arm::logic_proof::{LogicProver, LogicVerifier};
use tokio::task::JoinHandle;

/// Given a logic witness, returns a logic proof.
pub fn logic_proof<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> ProofResult<LogicVerifier> {
    transfer_logic
        .prove()
        .map_err(ProveErr::LogicProofCreateError)
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
#[allow(dead_code)]
pub fn logic_proof_asyncc<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> JoinHandle<ProofResult<LogicVerifier>> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || logic_proof(&transfer_logic_clone))
}
