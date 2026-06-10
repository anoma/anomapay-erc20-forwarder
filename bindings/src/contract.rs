use crate::addresses::erc20_forwarder_proxy_address;
use crate::generated::erc20_forwarder::ERC20Forwarder::ERC20ForwarderInstance;
use alloy::primitives::{Address, B256, U256, b256};
use alloy::providers::{DynProvider, Provider};
use alloy_chains::NamedChain;
use serde::Serialize;
use thiserror::Error;

/// The ERC-1967 implementation slot, `bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)`.
///
/// Identical to `ERC1967Utils.IMPLEMENTATION_SLOT`. The implementation address an ERC-1967 proxy delegates to is
/// stored here; it is read via `eth_getStorageAt` since `ERC1967Utils.getImplementation` is an internal library
/// function with no on-chain interface.
pub const ERC1967_IMPLEMENTATION_SLOT: B256 =
    b256!("360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc");

pub type BindingsResult<T> = Result<T, BindingsError>;

#[derive(Error, Debug, Serialize)]
pub enum BindingsError {
    #[error("The RPC transport returned an error.")]
    RpcTransportError(String),
    #[error("The chain ID {0} is not in the list of named chains.")]
    ChainIdUnknown(u64),
    #[error(
        "The current protocol adapter version has not been deployed on the provided chain '{0}'."
    )]
    UnsupportedChain(String),
}

pub async fn erc20_forwarder(
    provider: &DynProvider,
) -> BindingsResult<ERC20ForwarderInstance<DynProvider>> {
    let chain_id = provider
        .get_chain_id()
        .await
        .map_err(|err| BindingsError::RpcTransportError(err.to_string()))?;

    let named_chain =
        NamedChain::try_from(chain_id).map_err(|_| BindingsError::ChainIdUnknown(chain_id))?;

    match erc20_forwarder_proxy_address(&named_chain) {
        Some(address) => Ok(ERC20ForwarderInstance::new(address, provider.clone())),
        None => Err(BindingsError::UnsupportedChain(named_chain.to_string())),
    }
}

/// Reads the current implementation address an ERC-1967 proxy delegates to from its implementation slot.
pub async fn erc1967_implementation<P: Provider>(
    provider: &P,
    proxy: Address,
) -> BindingsResult<Address> {
    let value = provider
        .get_storage_at(proxy, U256::from_be_bytes(ERC1967_IMPLEMENTATION_SLOT.0))
        .await
        .map_err(|err| BindingsError::RpcTransportError(err.to_string()))?;

    Ok(Address::from_word(B256::from(value)))
}
