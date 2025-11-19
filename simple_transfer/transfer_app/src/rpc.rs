//! Defines functions to communicate with the protocol adapter on Ethereum.
use crate::rpc::RpcError::{FetchReceiptError, SubmitTransactionError};
use alloy::hex::ToHexExt;
use alloy::network::ReceiptResponse;
use arm::transaction::Transaction;
use evm_protocol_adapter_bindings::call::protocol_adapter;
use evm_protocol_adapter_bindings::conversion::ProtocolAdapter;

pub type RpcResult<T> = Result<T, RpcError>;

/// EthError represents all error states for calls to the Protocol Adapter.
#[derive(thiserror::Error, Debug)]
pub enum RpcError {
    #[error("Failed to submit a transaction to the protocol adapter: {0}")]
    SubmitTransactionError(alloy::contract::Error),
    #[error("Failed to fetch the receipt from the submitted transaction: {0}")]
    FetchReceiptError(alloy::providers::PendingTransactionError),
}

#[allow(dead_code)]
/// Submit a transaction to the protocol adapter and wait for the receipt.
pub async fn pa_submit_transaction(transaction: Transaction) -> RpcResult<String> {
    // Convert the transaction to an EVM transaction struct.
    let tx = ProtocolAdapter::Transaction::from(transaction);

    // Submit the transaction to the ethereum chain.
    let transaction_builder = protocol_adapter()
        .execute(tx)
        .send()
        .await
        .map_err(SubmitTransactionError)?;

    // Wait for the transaction to be confirmed by waiting for the receipt.
    let receipt = transaction_builder
        .get_receipt()
        .await
        .map_err(FetchReceiptError)?;

    // From the receipt, get the transaction hash.
    let tx_hash = receipt.transaction_hash();

    Ok(tx_hash.0.encode_hex())
}
