use alloy::primitives::{address, Address};

pub mod approve;
pub mod errors;
pub mod evm_calls;
pub mod indexer;

// Address of the permit2 contract. This is the same for all chains.
// See https://docs.uniswap.org/contracts/v4/deployments
pub const PERMIT2_CONTRACT: Address = address!("0x000000000022D473030F116dDEE9F6B43aC78BA3");
