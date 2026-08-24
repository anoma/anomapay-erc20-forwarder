use crate::addresses::{Environment, erc20_forwarder_address};
use crate::error::{BindingsError, BindingsResult};
use crate::generated::erc20_forwarder::ERC20Forwarder::ERC20ForwarderInstance;
use alloy::providers::{DynProvider, Provider};
use alloy_chains::NamedChain;

/// Returns an ERC20 forwarder instance of the environment for the given provider.
pub async fn erc20_forwarder(
    provider: &DynProvider,
    environment: Environment,
) -> BindingsResult<ERC20ForwarderInstance<DynProvider>> {
    let named_chain = NamedChain::try_from(
        provider
            .get_chain_id()
            .await
            .map_err(BindingsError::RpcTransportError)?,
    )
    .map_err(|_| BindingsError::ChainIdUnknown)?;

    match erc20_forwarder_address(environment, &named_chain) {
        Some(address) => Ok(ERC20ForwarderInstance::new(address, provider.clone())),
        None => Err(BindingsError::UnsupportedChain(named_chain)),
    }
}
