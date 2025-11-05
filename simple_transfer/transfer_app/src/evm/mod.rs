use alloy::primitives::{address, Address};

pub mod approve;
pub mod errors;
pub mod evm_calls;
pub mod indexer;

// Address of the permit2 contract. This is the same for all chains.
// See https://docs.uniswap.org/contracts/v4/deployments
pub const PERMIT2_CONTRACT: Address = address!("0x000000000022D473030F116dDEE9F6B43aC78BA3");

pub type EvmResult<T> = Result<T, EvmError>;

#[derive(thiserror::Error, Debug)]
pub enum EvmError {
    #[error("Failed to submit a transaction to the protocol adapter: {0}")]
    SubmitTransactionError(alloy::contract::Error),
    #[error("Failed to fetch the receipt from the submitted transaction: {0}")]
    FetchReceiptError(alloy::providers::PendingTransactionError),
    #[error("Invalid Ethereum RPC URL")]
    InvalidEthereumRPC,
    #[error("Failed to call Ethereum contract {0}")]
    ContractCallError(alloy::contract::Error),
}

pub type IndexerResult<T> = Result<T, IndexerError>;

#[derive(thiserror::Error, Debug)]
pub enum IndexerError {
    #[error("The indexer returned an invalid neighbour value: {0:?}")]
    NeighbourValueError(Vec<u8>),
    #[error("The indexer has rate-limited us")]
    IndexerOverloaded,
    #[error("The request failed, but can be attempted again.")]
    Recoverable(reqwest::Error),
    #[error("The request failed, and cannot be attempted again.")]
    Unrecoverable(reqwest::Error),
    #[error("The requested merkle path was not found in the indexer.")]
    MerklePathNotFound,
    #[error("Invalid indexer url created")]
    InvalidIndexerUrl,
    #[error("The indexer returned a result, but it could ont be parsed. Is the JSON valid?")]
    InvalidResponse,
}
