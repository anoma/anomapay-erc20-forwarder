//! The emergency upgrade of the ERC20 forwarder after a flaw in the ERC20 circuit, with the draft
//! `EmergencyMigratingERC20Forwarder`: the protocol adapter denies the ERC20 logic ref, and the forwarder proxy then
//! accepts the emergency migrating logic ref and migrates the resources of the ERC20 logic ref.

use alloy::network::TransactionBuilder;
use alloy::primitives::{Address, B256, U256};
use alloy::providers::Provider;
use alloy::providers::ext::{AnvilApi, ImpersonateConfig};
use alloy::sol_types::SolCall;
use anoma_pa_evm_bindings::generated::protocol_adapter::ILogicRefDenylist::DeniedLogicRef;
use anoma_pa_evm_bindings::generated::protocol_adapter::ProtocolAdapter;
use anomapay_erc20_forwarder_bindings::generated::emergency_migrating_erc20_forwarder::EmergencyMigratingERC20Forwarder;
use anyhow::Context;

use crate::deploy::forwarder::erc20_forwarder;
use crate::fixtures::emergency_migrating;
use crate::logic;

/// The ether of the owner of the protocol adapter, which pays the gas of the denial.
const OWNER_BALANCE: u128 = 1_000_000_000_000_000_000;

/// Denies the ERC20 logic ref on both denylists of `protocol_adapter` as its owner, then upgrades the ERC20 forwarder
/// proxy at `forwarder`, which `signer`, the signer of `provider`, owns, to an `EmergencyMigratingERC20Forwarder` that
/// accepts the emergency migrating logic ref and migrates the resources of the ERC20 logic ref.
pub async fn upgrade_to_emergency_migrating_erc20_forwarder<P>(
    provider: P,
    signer: Address,
    protocol_adapter: Address,
    forwarder: Address,
) -> anyhow::Result<()>
where
    P: Provider + Clone,
{
    let vulnerable = B256::from(<[u8; 32]>::from(logic::verifying_key()));

    let protocol_adapter = ProtocolAdapter::new(protocol_adapter, provider.clone());
    let owner = protocol_adapter
        .owner()
        .call()
        .await
        .context("failed to read the owner of the protocol adapter")?;
    let denial = protocol_adapter.denyLogicRefs(vec![
        DeniedLogicRef {
            logicRef: vulnerable,
            consumed: true,
        },
        DeniedLogicRef {
            logicRef: vulnerable,
            consumed: false,
        },
    ]);
    let pending = if owner == signer {
        denial.send().await
    } else {
        // On a fork, the owner is an account whose key the test lacks.
        provider
            .anvil_send_impersonated_transaction_with_config(
                denial.into_transaction_request().with_from(owner),
                ImpersonateConfig {
                    fund_amount: Some(U256::from(OWNER_BALANCE)),
                    stop_impersonate: true,
                },
            )
            .await
            .map_err(Into::into)
    };
    let receipt = pending
        .context("failed to send the denial of the ERC20 logic ref")?
        .get_receipt()
        .await
        .context("failed to fetch the receipt of the denial of the ERC20 logic ref")?;
    anyhow::ensure!(
        receipt.status(),
        "the denial of the ERC20 logic ref reverted"
    );

    // A new forwarder has no legacy forwarder.
    let implementation = EmergencyMigratingERC20Forwarder::deploy(provider.clone(), Address::ZERO)
        .await
        .context("failed to deploy the EmergencyMigratingERC20Forwarder implementation")?;
    let reinitialize = EmergencyMigratingERC20Forwarder::reinitializeCall {
        newLogicRef: B256::from(<[u8; 32]>::from(emergency_migrating::verifying_key())),
        vulnerableLogicRefs: vec![vulnerable],
    };
    let receipt = erc20_forwarder(forwarder, provider)
        .upgradeToAndCall(*implementation.address(), reinitialize.abi_encode().into())
        .send()
        .await
        .context("failed to send the upgrade of the ERC20 forwarder")?
        .get_receipt()
        .await
        .context("failed to fetch the receipt of the upgrade of the ERC20 forwarder")?;
    anyhow::ensure!(
        receipt.status(),
        "the upgrade of the ERC20 forwarder reverted"
    );
    Ok(())
}
