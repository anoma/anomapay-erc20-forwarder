#[cfg(test)]
extern crate dotenv;

use crate::load_config;
use crate::request::fee_estimation::token::{FeeCompatibleERC20Token, NativeToken, Token};
use crate::request::helpers::price_helper::get_token_prices_with_network;

#[tokio::test]
async fn test_token_price_fetches_prices_for_all_supported_tokens() {
    dotenv::dotenv().ok();
    let config = load_config().await.expect("failed to load config in test");

    let tokens: Vec<Token> = vec![
        Token::FeeCompatibleERC20(FeeCompatibleERC20Token::USDC),
        Token::Native(NativeToken::ETH),
    ];

    let addresses: Vec<_> = tokens.iter().map(|t| t.mainnet_address()).collect();

    let mut unique_addresses = addresses.clone();
    unique_addresses.sort();
    unique_addresses.dedup();
    let unique_count = unique_addresses.len();

    let res = get_token_prices_with_network(unique_addresses, &config, Some("eth-mainnet")).await;

    assert!(res.is_ok());
    // Should get prices for all unique addresses requested
    let prices = res.unwrap();
    assert_eq!(
        prices.len(),
        unique_count,
        "Should get price for each unique address"
    );
    assert!(!prices.is_empty());
}
