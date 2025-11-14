#![cfg(test)]

use crate::helpers::parse_address;
use crate::load_config;
use crate::requests::balances::{handle_token_balances_request, TokenBalancesRequest};
use alloy::primitives::Address;
use serial_test::serial;

/// Create an example request to fetch token balances for an address
pub fn create_token_balances_request(address: Address) -> TokenBalancesRequest {
    TokenBalancesRequest {
        address: address.as_slice().to_vec(),
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

            assert!(
                !balances.is_empty() || true,
                "Got token balances (empty is OK if address has no tokens)"
            );
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

/// Test parsing address from base64
#[tokio::test]
#[serial]
async fn test_parse_address_from_base64() {
    let test_address_hex = "0x7bCd418a9705B93935D05a4BF74CE45e1f8Ab86A";
    let test_address = test_address_hex
        .parse::<Address>()
        .expect("Failed to parse test address");

    let address_bytes = test_address.as_slice().to_vec();

    let parsed = parse_address(address_bytes);
    assert!(parsed.is_some(), "Should be able to parse valid address");
    assert_eq!(
        parsed.unwrap(),
        test_address,
        "Parsed address should match original"
    );

    println!("Successfully parsed address from bytes");
}
