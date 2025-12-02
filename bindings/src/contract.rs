use crate::addresses::erc20_forwarder_address;
use crate::contract::ERC20Forwarder::ERC20ForwarderInstance;
use alloy::providers::{DynProvider, Provider};
use alloy::sol;
use alloy::transports::{RpcError, TransportErrorKind};
use alloy_chains::NamedChain;
use thiserror::Error;

pub type BindingsResult<T> = Result<T, BindingsError>;

#[derive(Error, Debug)]
pub enum BindingsError {
    #[error("The RPC transport returned an error.")]
    RpcTransportError(RpcError<TransportErrorKind>),
    #[error("The chain ID {0} is not in the list of named chains.")]
    ChainIdUnknown(u64),
    #[error(
        "The current protocol adapter version has not been deployed on the provided chain '{0}'."
    )]
    UnsupportedChain(NamedChain),
}

sol!(
    #[allow(missing_docs)]
    #[derive(Debug, PartialEq, serde::Serialize, serde::Deserialize, Default)]
    #[sol(rpc)]
    ERC20Forwarder,
    "../contracts/out/ERC20Forwarder.sol/ERC20Forwarder.json"
);

pub async fn erc20_forwarder(
    provider: &DynProvider,
) -> BindingsResult<ERC20ForwarderInstance<DynProvider>> {
    let chain_id = provider
        .get_chain_id()
        .await
        .map_err(BindingsError::RpcTransportError)?;

    let named_chain =
        NamedChain::try_from(chain_id).map_err(|_| BindingsError::ChainIdUnknown(chain_id))?;

    match erc20_forwarder_address(&named_chain) {
        Some(address) => Ok(ERC20ForwarderInstance::new(address, provider.clone())),
        None => Err(BindingsError::UnsupportedChain(named_chain)),
    }
}
