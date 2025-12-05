use crate::AnomaPayConfig;
use crate::request::prices::{PricesError, PricesResult};
use alloy::hex;
use alloy::primitives::Address;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::str::FromStr;

/// Request structure for Alchemy Prices API
#[derive(Serialize, Debug)]
struct AlchemyPricesRequest {
    addresses: Vec<AlchemyPriceAddress>,
}

#[derive(Serialize, Debug)]
struct AlchemyPriceAddress {
    network: String,
    address: String,
}

/// Response structure for Alchemy Prices API
#[derive(Deserialize, Debug)]
struct AlchemyPricesResponse {
    data: Vec<AlchemyPriceData>,
}

#[derive(Deserialize, Debug)]
#[serde(untagged)]
enum AlchemyPriceError {
    String(String),
    Object { message: String },
}

#[derive(Deserialize, Debug)]
struct AlchemyPriceData {
    #[serde(rename = "network")]
    _network: String,
    #[serde(rename = "address")]
    _address: String,
    prices: Vec<AlchemyPrice>,
    error: Option<AlchemyPriceError>,
}

#[derive(Deserialize, Debug)]
struct AlchemyPrice {
    currency: String,
    value: String,
    #[serde(rename = "lastUpdatedAt")]
    last_updated_at: String,
}

/// Token price information
pub struct TokenPrice {
    pub address: Address,
    pub usd_price: f64,
    pub last_updated_at: String,
}

/// Gets the network name from config
// TODO: Adapt to multiple networks
fn get_network_from_config(config: &AnomaPayConfig) -> String {
    if config.ethereum_rpc.contains("sepolia") {
        "eth-sepolia".to_string()
    } else {
        "eth-mainnet".to_string()
    }
}

/// Fetches token price(s) using Alchemy Prices API with an optional network override
pub async fn get_token_prices_with_network(
    token_addresses: Vec<Address>,
    config: &AnomaPayConfig,
    network_override: Option<&str>,
) -> PricesResult<Vec<TokenPrice>> {
    if token_addresses.is_empty() {
        return Ok(Vec::new());
    }

    let client = Client::new();
    let network = network_override
        .map(|n| n.to_string())
        .unwrap_or_else(|| get_network_from_config(config));
    let url = format!(
        "https://api.g.alchemy.com/prices/v1/{}/tokens/by-address",
        config.alchemy_api_key
    );

    let addresses: Vec<AlchemyPriceAddress> = token_addresses
        .iter()
        .map(|addr| AlchemyPriceAddress {
            network: network.clone(),
            address: format!("0x{}", hex::encode(addr.as_slice())),
        })
        .collect();

    let request = AlchemyPricesRequest { addresses };

    let response = client
        .post(&url)
        .json(&request)
        .header("Content-Type", "application/json")
        .send()
        .await
        .map_err(|e| PricesError::AlchemyApiError(format!("HTTP request failed: {}", e)))?;

    if !response.status().is_success() {
        let status = response.status();
        let error_text = response
            .text()
            .await
            .unwrap_or_else(|_| "Unknown error".to_string());
        return Err(PricesError::AlchemyApiError(format!(
            "Alchemy API error: HTTP {} - {}",
            status, error_text
        )));
    }

    let response_text = response
        .text()
        .await
        .map_err(|e| PricesError::AlchemyApiError(format!("Failed to read response: {}", e)))?;

    // Log the response for debugging
    log::debug!("Alchemy Prices API response: {}", response_text);

    let prices_response: AlchemyPricesResponse =
        serde_json::from_str(&response_text).map_err(|e| {
            PricesError::AlchemyApiError(format!(
                "Failed to parse response: {}. Response body: {}",
                e, response_text
            ))
        })?;

    let mut token_prices = Vec::new();
    for price_data in prices_response.data {
        if let Some(error) = price_data.error {
            let error_msg = match error {
                AlchemyPriceError::String(s) => s,
                AlchemyPriceError::Object { message } => message,
            };
            log::warn!(
                "Error fetching price for token {}: {}",
                price_data._address,
                error_msg
            );
            continue;
        }

        let token_address = Address::from_str(&price_data._address)
            .map_err(|e| PricesError::AlchemyApiError(format!("Invalid token address: {}", e)))?;

        // Find USD price (case-insensitive)
        if price_data.prices.is_empty() {
            log::warn!(
                "No prices returned for token {} on network {}",
                price_data._address,
                price_data._network
            );
            continue;
        }

        let usd_price = price_data
            .prices
            .iter()
            .find(|p| p.currency.eq_ignore_ascii_case("USD"))
            .and_then(|p| p.value.parse::<f64>().ok())
            .ok_or_else(|| {
                let available_currencies: Vec<&str> = price_data
                    .prices
                    .iter()
                    .map(|p| p.currency.as_str())
                    .collect();
                PricesError::AlchemyApiError(format!(
                    "USD price not available for token {} on network {}. Available currencies: {:?}",
                    price_data._address, price_data._network, available_currencies
                ))
            })?;

        let last_updated = price_data
            .prices
            .iter()
            .find(|p| p.currency.eq_ignore_ascii_case("USD"))
            .map(|p| p.last_updated_at.clone())
            .unwrap_or_else(String::new);

        token_prices.push(TokenPrice {
            address: token_address,
            usd_price,
            last_updated_at: last_updated,
        });
    }

    Ok(token_prices)
}

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
