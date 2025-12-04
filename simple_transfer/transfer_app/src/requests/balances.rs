use crate::request::balances::get_all_token_balances;
use crate::requests::RequestErr::FailedTokenBalancesRequest;
use crate::requests::RequestResult;
use crate::AnomaPayConfig;
use alloy::primitives::Address;
use serde::{Deserialize, Serialize};

/// Defines the payload sent to the API to fetch token balances for an address
#[derive(Deserialize, Serialize, Debug, PartialEq)]
pub struct TokenBalancesRequest {
    /// Ethereum address in hex format (with or without 0x prefix)
    pub address: String,
}

/// Response structure for token balance
#[derive(Serialize, Debug)]
pub struct TokenBalanceResponse {
    pub address: String,
    pub value: String,
    pub decimals: u8,
    pub symbol: String,
}

/// Handles a request to fetch token balances for an address
pub async fn handle_token_balances_request(
    request: TokenBalancesRequest,
    config: &AnomaPayConfig,
) -> RequestResult<Vec<TokenBalanceResponse>> {
    // Parse address from hex string (with or without 0x prefix)
    let user_address = request.address.parse::<Address>().map_err(|_| {
        FailedTokenBalancesRequest(Box::new(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            format!("Invalid address format: {}", request.address),
        )))
    })?;

    let balances = get_all_token_balances(user_address, config)
        .await
        .map_err(|err| FailedTokenBalancesRequest(Box::new(err)))?;

    let response: Vec<TokenBalanceResponse> = balances
        .into_iter()
        .map(|balance| TokenBalanceResponse {
            address: balance.address.to_string(),
            value: balance.value.to_string(),
            decimals: balance.decimals,
            symbol: balance.symbol,
        })
        .collect();

    Ok(response)
}
