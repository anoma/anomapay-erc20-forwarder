use crate::evm::balances::get_all_token_balances;
use crate::helpers::parse_address;
use crate::requests::RequestErr::FailedTokenBalancesRequest;
use crate::requests::RequestResult;
use crate::AnomaPayConfig;
use serde::{Deserialize, Serialize};
use serde_with::base64::Base64;
use serde_with::serde_as;
use std::io;

/// Defines the payload sent to the API to fetch token balances for an address
#[serde_as]
#[derive(Deserialize, Serialize, Debug, PartialEq)]
pub struct TokenBalancesRequest {
    #[serde_as(as = "Base64")]
    pub address: Vec<u8>,
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
    let user_address = parse_address(request.address)
        .ok_or_else(|| {
            FailedTokenBalancesRequest(Box::new(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid user address",
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

