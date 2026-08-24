//! ERC20 forwarder deployment. The contract is UUPS-upgradeable, so deploying
//! it takes two steps: an implementation, whose constructor disables the
//! initializers, and an ERC-1967 proxy that delegates to it and holds the state.

use alloy::primitives::Address;
use alloy::primitives::B256;
use alloy::providers::Provider;
use alloy::sol_types::SolCall;
use anoma_pa_testkit::environment::StateBuilder;
use anomapay_erc20_forwarder_bindings::generated::erc20_forwarder::ERC20Forwarder;
use anomapay_erc20_forwarder_bindings::generated::erc1967_proxy::ERC1967Proxy;
use anyhow::Context;

use crate::state::forwarder::insert_erc20_forwarder_v1_address;

#[inline]
pub fn erc20_forwarder<P>(
    address: Address,
    provider: P,
) -> ERC20Forwarder::ERC20ForwarderInstance<P>
where
    P: Provider,
{
    ERC20Forwarder::ERC20ForwarderInstance::new(address, provider)
}

/// Deploys the implementation, returning its address. It is uninitializable by
/// construction and only usable as a proxy's delegation target.
pub async fn deploy_implementation<P>(provider: P) -> anyhow::Result<Address>
where
    P: Provider,
{
    let implementation = ERC20Forwarder::deploy(provider)
        .await
        .context("failed to deploy the ERC20 forwarder implementation")?;

    Ok(*implementation.address())
}

/// Deploys an ERC-1967 proxy delegating to `implementation` and initializes it
/// in the same transaction, mirroring `DeployERC20ForwarderProxy.s.sol`.
pub async fn deploy_proxy<P>(
    provider: P,
    implementation: Address,
    protocol_adapter: Address,
    logic_ref: B256,
    initial_owner: Address,
) -> anyhow::Result<Address>
where
    P: Provider,
{
    let initializer_data = ERC20Forwarder::initializeCall {
        protocolAdapter: protocol_adapter,
        logicRef: logic_ref,
        initialOwner: initial_owner,
    }
    .abi_encode();

    let proxy = ERC1967Proxy::deploy(provider, implementation, initializer_data.into())
        .await
        .context("failed to deploy the ERC20 forwarder proxy")?;

    Ok(*proxy.address())
}

/// Deploys the implementation and a proxy pointing to it, returning the proxy.
pub async fn deploy_erc20_forwarder<P>(
    provider: P,
    protocol_adapter: Address,
    logic_ref: B256,
    initial_owner: Address,
) -> anyhow::Result<Address>
where
    P: Provider + Clone,
{
    let implementation = deploy_implementation(provider.clone()).await?;

    deploy_proxy(
        provider,
        implementation,
        protocol_adapter,
        logic_ref,
        initial_owner,
    )
    .await
}

pub async fn deploy_and_insert_erc20_forwarder<P>(
    builder: &mut StateBuilder,
    provider: P,
    protocol_adapter: Address,
    logic_ref: B256,
    initial_owner: Address,
) -> anyhow::Result<Address>
where
    P: Provider + Clone,
{
    let address =
        deploy_erc20_forwarder(provider, protocol_adapter, logic_ref, initial_owner).await?;

    insert_erc20_forwarder_v1_address(builder, address);

    Ok(address)
}
