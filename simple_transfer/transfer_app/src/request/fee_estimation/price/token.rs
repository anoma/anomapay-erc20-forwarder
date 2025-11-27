use crate::request::fee_estimation::token::{Data, NativeToken, Token};
use crate::request::fee_estimation::{FeeEstimationError, FeeEstimationResult};
use crate::AnomaPayConfig;
use reqwest::{Client, Response};
use rocket::serde::Deserialize;
use thiserror::Error;

pub type PriceResult<T> = Result<T, PriceError>;

#[derive(Error, Debug)]
pub enum PriceError {
    #[error("The API request returned an error: {0:?}.")]
    RequestError(reqwest::Error),
    #[error("The price could not be fetched.")]
    PriceError(Response),
    #[error("The token symbol was not found in the response.")]
    TokenSymbolNotFound,
    #[error("The token query returned an error: {0}.")]
    TokenSymbolError(String),
    #[error("The USD price could not be found in the response.")]
    UsdPriceNotFound,
    #[error("The price could not be parsed.")]
    PriceParsingError(std::num::ParseFloatError),
}

#[derive(Debug, Deserialize, Clone)]
pub struct PriceResponse {
    pub data: Vec<TokenData>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct TokenData {
    pub symbol: String,
    pub prices: Vec<PriceEntry>,
    pub error: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct PriceEntry {
    pub currency: String,
    pub value: String,
    #[allow(unused)]
    #[serde(rename = "lastUpdatedAt")]
    pub last_updated_at: String,
}

impl PriceResponse {
    #[allow(clippy::result_large_err)]
    pub fn find_usd_price(&self, token_symbol: String) -> PriceResult<f64> {
        self.data
            .iter()
            .find(|token_data| token_data.symbol == token_symbol)
            .ok_or(PriceError::TokenSymbolNotFound)?
            .prices
            .iter()
            .find(|price| price.currency == "usd")
            .ok_or(PriceError::UsdPriceNotFound)?
            .value
            .parse::<f64>()
            .map_err(PriceError::PriceParsingError)
    }
}

/// Returns the price of a token in ether.
/// # Arguments
/// * `config` The AnomaPay config.
/// * `fee_token` The fee compatible token to get the price in ether for.
pub async fn get_ether_price_in_tokens(
    config: &AnomaPayConfig,
    fee_token: &Token,
) -> FeeEstimationResult<f64> {
    let price_response = get_token_prices(config, vec![fee_token.clone(), NativeToken::ETH.into()])
        .await
        .map_err(FeeEstimationError::TokenPriceError)?;

    let token_price_in_usd = price_response
        .find_usd_price(fee_token.symbol())
        .map_err(FeeEstimationError::TokenPriceError)?;

    let ether_price_in_usd = price_response
        .find_usd_price(NativeToken::ETH.symbol())
        .map_err(FeeEstimationError::TokenPriceError)?;

    Ok(ether_price_in_usd / token_price_in_usd)
}

/// Returns the price of the given token in ether.
/// # Arguments
/// * `config` The AnomaPay config.
/// * `symbols` The token symbols to get the price for, e.g. `["ETH", "USDC"]`.
pub async fn get_token_prices(
    config: &AnomaPayConfig,
    tokens: Vec<Token>,
) -> PriceResult<PriceResponse> {
    let client = Client::new();

    let params: Vec<(String, String)> = tokens
        .into_iter()
        .map(|t| (String::from("symbols"), t.symbol()))
        .collect();

    let resp = client
        .get("https://api.g.alchemy.com/prices/v1/tokens/by-symbol")
        .header(
            "Authorization",
            format!("Bearer {}", config.alchemy_api_key),
        )
        .query(&params)
        .send()
        .await
        .map_err(PriceError::RequestError)?;

    if !resp.status().is_success() {
        return Err(PriceError::PriceError(resp));
    }

    let price_response: PriceResponse = resp.json().await.map_err(PriceError::RequestError)?;

    for data in &price_response.data {
        if let Some(error_message) = data.error.clone() {
            return Err(PriceError::TokenSymbolError(error_message));
        }
    }

    Ok(price_response)
}
