//! Defines functions to communicate with the protocol adapter on Ethereum.
use crate::{
    rpc::RpcError::{FetchReceiptError, InvalidRPCUrl, SubmitTransactionError},
    AnomaPayConfig,
};
use alloy::hex::ToHexExt;
use alloy::network::ReceiptResponse;
use arm::transaction::Transaction;
// use evm_protocol_adapter_bindings::call::protocol_adapter;
use evm_protocol_adapter_bindings::contract::protocol_adapter;
use evm_protocol_adapter_bindings::conversion::ProtocolAdapter;
pub type RpcResult<T> = Result<T, RpcError>;
use alloy::providers::{DynProvider, Provider, ProviderBuilder};

/// EthError represents all error states for calls to the Protocol Adapter.
#[derive(thiserror::Error, Debug)]
pub enum RpcError {
    #[error("Failed to submit a transaction to the protocol adapter: {0}")]
    SubmitTransactionError(alloy::contract::Error),
    #[error("Failed to fetch the receipt from the submitted transaction: {0}")]
    FetchReceiptError(alloy::providers::PendingTransactionError),
    #[error("The Ethereum RPC url was not valid.")]
    InvalidRPCUrl,
}

/// Create a provider based on the private key from the configuration.
async fn create_provider(config: &AnomaPayConfig) -> RpcResult<DynProvider> {
    let provider = ProviderBuilder::new()
        .wallet(config.hot_wallet_private_key.clone())
        .connect_http(config.ethereum_rpc.parse().map_err(|_e| InvalidRPCUrl)?)
        .erased();

    Ok(provider)
}

#[allow(dead_code)]
/// Submit a transaction to the protocol adapter and wait for the receipt.
pub async fn pa_submit_transaction(
    config: &AnomaPayConfig,
    transaction: Transaction,
) -> RpcResult<String> {
    let provider = create_provider(config).await?;
    // Convert the transaction to an EVM transaction struct.
    let tx = ProtocolAdapter::Transaction::from(transaction);

    let pa = protocol_adapter(&provider).await.expect("foo");

    // Submit the transaction to the ethereum chain.
    let transaction_builder = pa
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
