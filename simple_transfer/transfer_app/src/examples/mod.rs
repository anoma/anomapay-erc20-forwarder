use alloy::primitives::{address, Address};

pub mod burn;
pub mod end_to_end;
pub mod mint;
pub mod shared;

// this is the token address for USDC on Sepolia. In this example we assume the user wants to
// transfer USDC.
const TOKEN_ADDRESS_SEPOLIA_USDC: Address = address!("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238");

const DEFAULT_AMOUNT: u64 = 10;

const DEFAULT_DEADLINE: u64 = 1893456000;
