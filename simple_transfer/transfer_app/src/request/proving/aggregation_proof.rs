//! Contains logic to generate compliance proofs for compliance witnesses.
use crate::request::proving::ProvingError::ProofAggregation;
use crate::request::proving::ProvingResult;
use crate::time_it;
use arm::aggregation::AggregationStrategy;
use arm::proving_system::ProofType;
use arm::transaction::Transaction;
use tokio::task::JoinHandle;

#[cfg(not(test))]
use log::info;
#[cfg(test)]
use println as info;

/// Create an aggregation proof based on a transaction. The aggregation proof is
/// generated in-place of the transaction so it has to be returned.
///
/// This function is blocking and cannot be used safely in an async context. Use
/// `aggregate_proof_async` instead.
fn aggregate_proofs(mut transaction: Transaction) -> JoinHandle<ProvingResult<Transaction>> {
    tokio::task::spawn_blocking(move || {
        time_it!("aggregate_proof", {
            transaction
                .aggregate_with_strategy(AggregationStrategy::Batch, ProofType::Groth16)
                .map_err(|err| ProofAggregation(err.to_string()))?;
            Ok(transaction)
        })
    })
}

/// Given a list of compliance witnesses, computes the proofs concurrently.
pub async fn aggregate_proof_async(transaction: Transaction) -> ProvingResult<Transaction> {
    let proof_future = aggregate_proofs(transaction);

    proof_future.await.expect("Task panicked")
}
