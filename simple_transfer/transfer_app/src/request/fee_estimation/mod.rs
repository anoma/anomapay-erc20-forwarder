pub mod estimation;
pub mod price;
pub mod token;

use crate::request::prices::PricesError;
use thiserror::Error;

pub type FeeEstimationResult<T> = Result<T, FeeEstimationError>;

#[derive(Error, Debug)]
pub enum FeeEstimationError {
    #[error("The price of the token could not be fetched.")]
    TokenPriceError(PricesError),
    #[error("The gas price could not be fetched.")]
    GasPriceError,
}
