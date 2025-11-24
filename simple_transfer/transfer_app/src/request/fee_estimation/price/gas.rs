use crate::request::fee_estimation::{FeeEstimationError, FeeEstimationResult};
use alloy::providers::{DynProvider, Provider};

/// Returns the gas price in wei from the provider.
pub async fn gas_price(provider: &DynProvider) -> FeeEstimationResult<u128> {
    provider
        .get_gas_price()
        .await
        .map_err(|_| FeeEstimationError::GasPriceError)
}
