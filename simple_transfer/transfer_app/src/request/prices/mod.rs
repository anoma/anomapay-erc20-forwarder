pub mod call_prices_api;

use thiserror::Error;

pub type PricesResult<T> = Result<T, PricesError>;

#[derive(Error, Debug)]
pub enum PricesError {
    #[error("Alchemy API error: {0}")]
    AlchemyApiError(String),
}
