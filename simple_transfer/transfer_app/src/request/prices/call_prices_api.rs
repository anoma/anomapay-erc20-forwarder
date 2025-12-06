use crate::AnomaPayConfig;
use crate::request::helpers::price_helper::{TokenPrice, get_token_prices_with_network};
use crate::request::prices::{PricesError, PricesResult};
use alloy::primitives::Address;

/// Fetches a single token price using Alchemy Prices API
pub async fn get_token_price(
    token_address: Address,
    config: &AnomaPayConfig,
) -> PricesResult<TokenPrice> {
    get_token_price_with_network(token_address, config, None).await
}

/// Fetches a single token price using Alchemy Prices API with an optional network override
pub async fn get_token_price_with_network(
    token_address: Address,
    config: &AnomaPayConfig,
    network_override: Option<&str>,
) -> PricesResult<TokenPrice> {
    let prices =
        get_token_prices_with_network(vec![token_address], config, network_override).await?;
    prices
        .into_iter()
        .next()
        .ok_or_else(|| PricesError::AlchemyApiError("No price data returned for token".to_string()))
}
