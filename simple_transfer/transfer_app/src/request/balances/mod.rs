pub mod call_balances_api;

use thiserror::Error;

pub type BalancesResult<T> = Result<T, BalancesError>;

#[derive(Error, Debug)]
pub enum BalancesError {
    #[error("Alchemy API error: {0}")]
    AlchemyApiError(String),
}
