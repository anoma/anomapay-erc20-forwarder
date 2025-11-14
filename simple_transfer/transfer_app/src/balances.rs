use crate::evm::EvmError::{AlchemyApiError, ContractCallError, InvalidEthereumRPC};
use crate::evm::EvmResult;
use crate::AnomaPayConfig;
use alloy::hex;
use alloy::primitives::{Address, U256};
use alloy::providers::ProviderBuilder;
use alloy::sol;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::str::FromStr;

// Extended ERC20 interface with metadata functions
sol! {
    #[sol(rpc)]
    interface IERC20Metadata {
        function decimals() external view returns (uint8);
        function symbol() external view returns (string);
    }
}

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

/// Token balance information
pub struct TokenBalance {
    pub address: Address,
    pub value: U256,
    pub decimals: u8,
    pub symbol: String,
}

/// Fetches token balances using Alchemy API
async fn get_alchemy_token_balances(
    user_address: Address,
    config: &AnomaPayConfig,
) -> EvmResult<Vec<(Address, U256)>> {
    let client = Client::new();

    // Determine the base URL from the ethereum_rpc URL
    // If it's an Alchemy URL, extract the API key; otherwise construct it
    let base_url = if config.ethereum_rpc.contains("alchemy.com") {
        let url_parts: Vec<&str> = config.ethereum_rpc.split("/v2/").collect();
        if url_parts.len() >= 1 {
            format!("{}/v2/{}", url_parts[0], config.api_key_alchemy)
        } else {
            let chain = if config.ethereum_rpc.contains("sepolia") {
                "eth-sepolia"
            } else if config.ethereum_rpc.contains("goerli") {
                "eth-goerli"
            } else {
                "eth-mainnet"
            };
            format!(
                "https://{}.g.alchemy.com/v2/{}",
                chain, config.api_key_alchemy
            )
        }
    } else {
        // Default to mainnet if not an Alchemy URL
        format!(
            "https://eth-mainnet.g.alchemy.com/v2/{}",
            config.api_key_alchemy
        )
    };

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

/// Fetches decimals and symbol for a token
async fn get_token_metadata(
    token_address: Address,
    config: &AnomaPayConfig,
) -> EvmResult<(u8, String)> {
    let url = config
        .ethereum_rpc
        .parse()
        .map_err(|_| InvalidEthereumRPC)?;
    let provider = ProviderBuilder::new().connect_http(url);

    let contract = IERC20Metadata::new(token_address, provider.clone());

    let decimals_call = contract.decimals();
    let symbol_call = contract.symbol();

    let (decimals_result, symbol_result) =
        tokio::try_join!(decimals_call.call(), symbol_call.call(),).map_err(ContractCallError)?;

    Ok((decimals_result, symbol_result))
}

/// Fetches all token balances for a user address using Alchemy API
pub async fn get_all_token_balances(
    user_address: Address,
    config: &AnomaPayConfig,
) -> EvmResult<Vec<TokenBalance>> {
    let balances = get_alchemy_token_balances(user_address, config).await?;

    let metadata_futures: Vec<_> = balances
        .iter()
        .map(|(token_addr, _)| get_token_metadata(*token_addr, config))
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
