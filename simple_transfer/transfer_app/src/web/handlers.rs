use crate::request::proving::parameters::Parameters;
use crate::rpc::pa_submit_transaction;
use crate::web::ReqResult;
use crate::web::RequestError::{Submit, TransactionGeneration};
use crate::AnomaPayConfig;
use arm::transaction::Transaction;

/// Given a `Parameters` struct, creates and submits a transaction.
/// Returns an error if it failed.
pub async fn handle_parameters(
    parameters: Parameters,
    config: &AnomaPayConfig,
) -> ReqResult<String> {
    // Try and generate a transaction.
    let transaction: Transaction = parameters
        .generate_transaction(config)
        .await
        .map_err(|_| TransactionGeneration("kapot".to_string()))?;

    // Submit the transaction.
    let tx_hash = pa_submit_transaction(config, transaction)
        .await
        .map_err(|_| Submit("kapot".to_string()))?;

    Ok(tx_hash)
}
