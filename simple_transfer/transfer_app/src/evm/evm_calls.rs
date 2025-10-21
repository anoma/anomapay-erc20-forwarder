use crate::evm::errors::EvmError;
use crate::evm::errors::EvmError::EvmSubmitError;
use alloy::network::ReceiptResponse;
use alloy::rpc::types::TransactionReceipt;
use arm::transaction::Transaction;
use evm_protocol_adapter_bindings::call::protocol_adapter;
use evm_protocol_adapter_bindings::conversion::ProtocolAdapter;

/// Submit a transaction to the protocol adapter and wait for the receipt.
pub async fn pa_submit_transaction(
    transaction: Transaction,
) -> Result<TransactionReceipt, EvmError> {
    // convert the transaction to an EVM transaction struct.
    let tx = ProtocolAdapter::Transaction::from(transaction);

    // submit the transaction
    let receipt = protocol_adapter()
        .execute(tx)
        .send()
        .await
        .map_err(|err| {
            println!("Failed to submit transaction {:?}", err);
            EvmSubmitError
        })
        .expect("Failed to submit transaction")
        .get_receipt()
        .await
        .expect("Failed to get receipt");

    println!("submitted transaction {}", receipt.transaction_hash());
    Ok(receipt)
}
