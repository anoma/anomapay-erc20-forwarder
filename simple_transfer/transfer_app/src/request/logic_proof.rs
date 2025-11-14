//! Defines helper functions to create resource logic proofs.

use crate::request::{ProofResult, ProveErr};
use arm::logic_proof::{LogicProver, LogicVerifier};
use tokio::task::JoinHandle;

/// Given a logic witness, returns a logic proof.
///
/// This function is not safe to be used in async contexts. Use
/// `logic_proof_async` instead.
pub fn logic_proof<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> ProofResult<LogicVerifier> {
    transfer_logic
        .prove()
        .map_err(ProveErr::LogicProofCreateError)
}

/// Given a logic witness, returns a logic proof.
pub fn logic_proof_async<T: LogicProver + Send + 'static>(
    transfer_logic: &T,
) -> JoinHandle<ProofResult<LogicVerifier>> {
    let transfer_logic_clone = transfer_logic.clone();
    tokio::task::spawn_blocking(move || logic_proof(&transfer_logic_clone))
}
