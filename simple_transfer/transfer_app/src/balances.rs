use crate::evm::EvmError::AlchemyApiError;
use crate::evm::EvmResult;
use crate::AnomaPayConfig;
use alloy::hex;
use alloy::primitives::{Address, U256};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::str::FromStr;

/// Alchemy API request structure
#[derive(Serialize)]
struct AlchemyRequest {
    jsonrpc: String,
    id: u64,
    method: String,
    params: Vec<serde_json::Value>,
}

/// Alchemy API response structure
#[derive(Deserialize, Debug)]
struct AlchemyResponse {
    #[allow(dead_code)]
    jsonrpc: String,
    #[allow(dead_code)]
    id: u64,
    result: Option<AlchemyTokenBalancesResult>,
    error: Option<AlchemyError>,
}

#[derive(Deserialize, Debug)]
struct AlchemyTokenBalancesResult {
    #[allow(dead_code)]
    address: String,
    #[serde(rename = "tokenBalances")]
    token_balances: Vec<AlchemyTokenBalance>,
}

#[derive(Deserialize, Debug)]
struct AlchemyTokenBalance {
    #[serde(rename = "contractAddress")]
    contract_address: String,
    #[serde(rename = "tokenBalance")]
    token_balance: String,
    error: Option<String>,
}

#[derive(Deserialize, Debug)]
struct AlchemyError {
    #[allow(dead_code)]
    code: i32,
    message: String,
}

#[derive(Deserialize, Debug)]
struct AlchemyTokenMetadataResponse {
    #[allow(dead_code)]
    jsonrpc: String,
    #[allow(dead_code)]
    id: u64,
    result: Option<AlchemyTokenMetadata>,
    error: Option<AlchemyError>,
}

#[derive(Deserialize, Debug)]
struct AlchemyTokenMetadata {
    #[allow(dead_code)]
    name: Option<String>,
    symbol: Option<String>,
    decimals: Option<u64>,
    #[allow(dead_code)]
    logo: Option<String>,
}

/// Token balance information
pub struct TokenBalance {
    pub address: Address,
    pub value: U256,
    pub decimals: u8,
    pub symbol: String,
}

/// Gets the Alchemy API base URL based on the config
fn get_alchemy_base_url(config: &AnomaPayConfig) -> String {
    if config.ethereum_rpc.contains("alchemy.com") {
        let url_parts: Vec<&str> = config.ethereum_rpc.split("/v2/").collect();
        if !url_parts.is_empty() {
            format!("{}/v2/{}", url_parts[0], config.alchemy_api_key)
        } else {
            let chain = if config.ethereum_rpc.contains("sepolia") {
                "eth-sepolia"
            } else {
                "eth-mainnet"
            };
            format!(
                "https://{}.g.alchemy.com/v2/{}",
                chain, config.alchemy_api_key
            )
        }
    } else {
        // Default to mainnet if not an Alchemy URL
        format!(
            "https://eth-mainnet.g.alchemy.com/v2/{}",
            config.alchemy_api_key
        )
    }
}

/// Fetches token balances using Alchemy API
async fn get_alchemy_token_balances(
    user_address: Address,
    config: &AnomaPayConfig,
) -> EvmResult<Vec<(Address, U256)>> {
    let client = Client::new();
    let base_url = get_alchemy_base_url(config);
    let address_hex = format!("0x{}", hex::encode(user_address.as_slice()));

    let request = AlchemyRequest {
        jsonrpc: "2.0".to_string(),
        id: 1,
        method: "alchemy_getTokenBalances".to_string(),
        params: vec![
            serde_json::Value::String(address_hex),
            serde_json::Value::String("erc20".to_string()),
        ],
    };

    let response = client
        .post(&base_url)
        .json(&request)
        .send()
        .await
        .map_err(|e| AlchemyApiError(format!("HTTP request failed: {}", e)))?;

    let alchemy_response: AlchemyResponse = response
        .json()
        .await
        .map_err(|e| AlchemyApiError(format!("Failed to parse response: {}", e)))?;

    if let Some(error) = alchemy_response.error {
        return Err(AlchemyApiError(format!(
            "Alchemy API error: {}",
            error.message
        )));
    }

    let result = alchemy_response
        .result
        .ok_or_else(|| AlchemyApiError("No result from Alchemy API".to_string()))?;

    let mut balances = Vec::new();
    for token_balance in result.token_balances {
        if token_balance.error.is_some() {
            continue;
        }

        let contract_address = Address::from_str(&token_balance.contract_address)
            .map_err(|e| AlchemyApiError(format!("Invalid contract address: {}", e)))?;

        let balance_hex = token_balance.token_balance.trim_start_matches("0x");
        let balance = U256::from_str_radix(balance_hex, 16)
            .map_err(|e| AlchemyApiError(format!("Invalid balance format: {}", e)))?;

        if balance != U256::ZERO {
            balances.push((contract_address, balance));
        }
    }

    Ok(balances)
}

/// Fetches token metadata using Alchemy API
async fn get_alchemy_token_metadata(
    token_address: Address,
    config: &AnomaPayConfig,
) -> EvmResult<(u8, String)> {
    let client = Client::new();
    let base_url = get_alchemy_base_url(config);
    let address_hex = format!("0x{}", hex::encode(token_address.as_slice()));

    let request = AlchemyRequest {
        jsonrpc: "2.0".to_string(),
        id: 1,
        method: "alchemy_getTokenMetadata".to_string(),
        params: vec![serde_json::Value::String(address_hex)],
    };

    let response = client
        .post(&base_url)
        .json(&request)
        .send()
        .await
        .map_err(|e| AlchemyApiError(format!("HTTP request failed: {}", e)))?;

    let metadata_response: AlchemyTokenMetadataResponse = response
        .json()
        .await
        .map_err(|e| AlchemyApiError(format!("Failed to parse response: {}", e)))?;

    if let Some(error) = metadata_response.error {
        return Err(AlchemyApiError(format!(
            "Alchemy API error: {}",
            error.message
        )));
    }

    let metadata = metadata_response
        .result
        .ok_or_else(|| AlchemyApiError("No result from Alchemy API".to_string()))?;

    let decimals = metadata
        .decimals
        .ok_or_else(|| AlchemyApiError("Token decimals not available".to_string()))?
        as u8;

    let symbol = metadata
        .symbol
        .ok_or_else(|| AlchemyApiError("Token symbol not available".to_string()))?;

    Ok((decimals, symbol))
}

/// Fetches all token balances for a user address using Alchemy API
pub async fn get_all_token_balances(
    user_address: Address,
    config: &AnomaPayConfig,
) -> EvmResult<Vec<TokenBalance>> {
    let balances = get_alchemy_token_balances(user_address, config).await?;

    let metadata_futures: Vec<_> = balances
        .iter()
        .map(|(token_addr, _)| get_alchemy_token_metadata(*token_addr, config))
        .collect();

    let metadata_results = futures::future::join_all(metadata_futures).await;

    let mut token_balances = Vec::new();
    for ((token_addr, balance), metadata_result) in balances.iter().zip(metadata_results) {
        match metadata_result {
            Ok((decimals, symbol)) => {
                token_balances.push(TokenBalance {
                    address: *token_addr,
                    value: *balance,
                    decimals,
                    symbol,
                });
            }
            Err(e) => {
                log::warn!("Failed to fetch metadata for token {:?}: {}", token_addr, e);
            }
        }
    }

    Ok(token_balances)
}
