use crate::evm::EvmError::{FetchReceiptError, SubmitTransactionError};
use crate::evm::EvmResult;
use alloy::hex::ToHexExt;
use alloy::network::ReceiptResponse;
use arm::transaction::Transaction;
use evm_protocol_adapter_bindings::call::protocol_adapter;
use evm_protocol_adapter_bindings::conversion::ProtocolAdapter;

/// Submit a transaction to the protocol adapter and wait for the receipt.
pub async fn pa_submit_transaction(transaction: Transaction) -> EvmResult<String> {
    // convert the transaction to an EVM transaction struct.
    let tx = ProtocolAdapter::Transaction::from(transaction);

    let transaction_builder = protocol_adapter()
        .execute(tx)
        .send()
        .await
        .map_err(SubmitTransactionError)?;

    let receipt = transaction_builder
        .get_receipt()
        .await
        .map_err(FetchReceiptError)?;

    let tx_hash = receipt.transaction_hash();

    Ok(tx_hash.0.encode_hex())
}
