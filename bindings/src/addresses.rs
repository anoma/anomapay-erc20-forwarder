use alloy::primitives::{Address, address};
use alloy_chains::NamedChain;
use std::collections::HashMap;

/// Returns a map of ERC20 forwarder contract deployments for all supported chains.
pub fn erc20_forwarder_deployments_map() -> HashMap<NamedChain, Address> {
    HashMap::from([
        (
            NamedChain::Sepolia,
            address!("0x0A62bE41E66841f693f922991C4e40C89cb0CFDF"),
        ),
        (
            NamedChain::Mainnet,
            address!("0x775C81A47F2618a8594a7a7f4A3Df2a300337559"),
        ),
        (
            NamedChain::BaseSepolia,
            address!("0xfAa9DE773Be11fc759A16F294d32BB2261bF818B"),
        ),
        (
            NamedChain::Base,
            address!("0xfAa9DE773Be11fc759A16F294d32BB2261bF818B"),
        ),
        (
            NamedChain::Optimism,
            address!("0xfAa9DE773Be11fc759A16F294d32BB2261bF818B"),
        ),
        (
            NamedChain::Arbitrum,
            address!("0xfAa9DE773Be11fc759A16F294d32BB2261bF818B"),
        ),
        (
            NamedChain::Aurora,
            address!("0xA2C683FdAf51A4849D64DDeb26aBC16524Df4d00"),
        ),
        (
            NamedChain::AuroraTestnet,
            address!("0x10152C8E61506c87Eb57117FD82E754e068B2c66"),
        ),
        (
            NamedChain::BinanceSmartChain,
            address!("0xA2C683FdAf51A4849D64DDeb26aBC16524Df4d00"),
        ),
        (
            NamedChain::BinanceSmartChainTestnet,
            address!("0x24CEc6A74A0E39eE33C8356DB8655308112f587F"),
        ),
    ])
}

/// Returns the address of the ERC20 forwarder contract  deployed on the provided chain, if any.
pub fn erc20_forwarder_address(chain: &NamedChain) -> Option<Address> {
    erc20_forwarder_deployments_map().get(chain).cloned()
}
