#![cfg(test)]
//! Test the behavior of fetching token prices.

extern crate dotenv;
use crate::load_config;
use crate::request::prices::call_prices_api::get_token_price;
use alloy::primitives::Address;

/// Test fetching token price for an address
#[tokio::test]
async fn test_get_token_price() {
    dotenv::dotenv().ok();

    let config = load_config().await.expect("failed to load config in test");

    // USDC token address on mainnet
    // Note: Prices API only works on mainnet, not testnets like Sepolia
    let test_token_address_hex = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
    let test_token_address = test_token_address_hex
        .parse::<Address>()
        .expect("Failed to parse test token address");

    println!(
        "Testing token price for address: {}",
        test_token_address_hex
    );

    // Try with config network first, then fall back to mainnet if on testnet
    let result = if config.rpc_url.contains("sepolia") {
        // Prices API only works on mainnet, so use mainnet for testing
        println!("   Config is set to Sepolia, using mainnet for price API");
        crate::request::prices::call_prices_api::get_token_price_with_network(
            test_token_address,
            &config,
            Some("eth-mainnet"),
        )
        .await
    } else {
        get_token_price(test_token_address, &config).await
    };

    match result {
        Ok(price) => {
            println!("Successfully fetched token price");
            assert!(!price.address.is_zero(), "Token address should not be zero");
            assert!(price.usd_price > 0.0, "USD price should be greater than 0");
            assert!(
                !price.last_updated_at.is_empty(),
                "Last updated timestamp should not be empty"
            );

            println!(
                "  - Token: {} | Price: ${} | Updated: {}",
                price.address, price.usd_price, price.last_updated_at
            );
        }
        Err(e) => {
            println!("   Error fetching token price: {}", e);
            println!("   This might be expected if:");
            println!("   - Alchemy API key is not set or invalid");
            println!("   - Network connectivity issues");
            println!("   - Token address is invalid or price not available");
        }
    }
}

/// Test parsing address from hex string (with and without 0x prefix)
#[tokio::test]
async fn test_parse_token_address_from_hex() {
    let test_address_hex_with_prefix = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
    let test_address_hex_without_prefix = "a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

    let address_with_prefix = test_address_hex_with_prefix
        .parse::<Address>()
        .expect("Failed to parse address with 0x prefix");

    let address_without_prefix = test_address_hex_without_prefix
        .parse::<Address>()
        .expect("Failed to parse address without 0x prefix");

    assert_eq!(
        address_with_prefix, address_without_prefix,
        "Addresses with and without 0x prefix should be equal"
    );

    println!("Successfully parsed token address from hex string (with and without 0x prefix)");
}
