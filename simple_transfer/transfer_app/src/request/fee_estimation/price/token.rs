use crate::AnomaPayConfig;
use crate::request::fee_estimation::token::Token;
use crate::request::fee_estimation::{FeeEstimationError, FeeEstimationResult};
use crate::request::helpers::price_helper::get_token_prices_with_network;
use crate::request::prices::PricesError;

/// Returns the price of a token in ether.
/// # Arguments
/// * `config` The AnomaPay config.
/// * `fee_token` The fee compatible token to get the price in ether for.
pub async fn get_ether_price_in_tokens(
    config: &AnomaPayConfig,
    fee_token: &Token,
) -> FeeEstimationResult<f64> {
    use crate::request::fee_estimation::token::NativeToken;

    let fee_token_address = fee_token.mainnet_address();
    let eth_address = Token::Native(NativeToken::ETH).mainnet_address();

    let prices = get_token_prices_with_network(
        vec![fee_token_address, eth_address],
        config,
        Some("eth-mainnet"), // Api does not support testnets
    )
    .await
    .map_err(FeeEstimationError::TokenPriceError)?;

    let token_price_in_usd = prices
        .iter()
        .find(|p| p.address == fee_token_address)
        .map(|p| p.usd_price)
        .ok_or_else(|| {
            FeeEstimationError::TokenPriceError(PricesError::AlchemyApiError(format!(
                "Price not found for token at address {:?}",
                fee_token_address
            )))
        })?;

    let ether_price_in_usd = prices
        .iter()
        .find(|p| p.address == eth_address)
        .map(|p| p.usd_price)
        .ok_or_else(|| {
            FeeEstimationError::TokenPriceError(PricesError::AlchemyApiError(format!(
                "Price not found for ETH (WETH) at address {:?}",
                eth_address
            )))
        })?;

    Ok(ether_price_in_usd / token_price_in_usd)
}
