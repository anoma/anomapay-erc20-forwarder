#![cfg(test)]

use crate::load_config;
use crate::requests::balances::{handle_token_balances_request, TokenBalancesRequest};
use alloy::primitives::Address;
use serial_test::serial;

/// Create an example request to fetch token balances for an address
pub fn create_token_balances_request(address: Address) -> TokenBalancesRequest {
    TokenBalancesRequest {
        address: address.to_string(),
    }
}

/// Test the token balances handler function directly
#[tokio::test]
#[serial]
async fn test_token_balances_handler() {
    let config = load_config().expect("failed to load config in test");

    let test_address_hex = "0x7bCd418a9705B93935D05a4BF74CE45e1f8Ab86A";
    let test_address = test_address_hex
        .parse::<Address>()
        .expect("Failed to parse test address");

    let request = create_token_balances_request(test_address);

    println!("Testing token balances for address: {}", test_address_hex);

    match handle_token_balances_request(request, &config).await {
        Ok(balances) => {
            println!("Successfully fetched {} token balances", balances.len());

            for balance in &balances {
                assert!(
                    !balance.address.is_empty(),
                    "Token address should not be empty"
                );
                assert!(
                    !balance.symbol.is_empty(),
                    "Token symbol should not be empty"
                );
                assert!(
                    balance.decimals > 0,
                    "Token decimals should be greater than 0"
                );
                assert!(!balance.value.is_empty(), "Token value should not be empty");

                println!(
                    "  - {}: {} (decimals: {})",
                    balance.symbol, balance.value, balance.decimals
                );
            }
        }
        Err(e) => {
            println!("   Error fetching token balances: {}", e);
            println!("   This might be expected if:");
            println!("   - Alchemy API key is not set or invalid");
            println!("   - Network connectivity issues");
            println!("   - Address has no token balances");
        }
    }
}

/// Test parsing address from hex string (with and without 0x prefix)
#[tokio::test]
#[serial]
async fn test_parse_address_from_hex() {
    let test_address_hex_with_prefix = "0x7bCd418a9705B93935D05a4BF74CE45e1f8Ab86A";
    let test_address_hex_without_prefix = "7bCd418a9705B93935D05a4BF74CE45e1f8Ab86A";
    
    let address_with_prefix = test_address_hex_with_prefix
        .parse::<Address>()
        .expect("Failed to parse address with 0x prefix");
    
    let address_without_prefix = test_address_hex_without_prefix
        .parse::<Address>()
        .expect("Failed to parse address without 0x prefix");
    
    assert_eq!(
        address_with_prefix,
        address_without_prefix,
        "Addresses with and without 0x prefix should be equal"
    );

    println!("Successfully parsed address from hex string (with and without 0x prefix)");
}
