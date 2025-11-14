pub mod balances;

use thiserror::Error;

pub type BalancesResult<T> = Result<T, BalancesError>;

#[derive(Error, Debug)]
pub enum BalancesError {
    #[error("Alchemy API error: {0}")]
    AlchemyApiError(String),
    #[error("Failed to call Ethereum contract: {0}")]
    ContractCallError(String),
    #[error("Invalid Ethereum RPC URL")]
    InvalidEthereumRPC,
}

