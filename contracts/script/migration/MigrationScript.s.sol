// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Pausable} from "@openzeppelin-contracts-5.7.0/utils/Pausable.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {IProtocolAdapterSpecific} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IProtocolAdapterSpecific.sol";
import {Script} from "forge-std-1.16.2/src/Script.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {DeployERC20ForwarderProxy} from "../DeployERC20ForwarderProxy.s.sol";

/// @title MigrationScript
/// @author Anoma Foundation, 2026
/// @notice The base of the scripts that move one chain's ERC20 tokens from the V1 forwarder to the V2
/// forwarder proxy. Both forwarders come from the recorded deployments and are checked against the chain, so
/// `--rpc-url` alone names the chain.
/// @custom:security-contact security@anoma.foundation
abstract contract MigrationScript is Script {
    /// @notice Thrown if the chain ran no V1 forwarder, i.e. it has no tokens to move.
    error ForwarderV1NotRecorded(uint256 chainId);

    /// @notice Thrown if the environment records no V2 forwarder for the chain, i.e. it has no destination.
    error DeploymentNotRecorded(string environment, uint256 chainId);

    /// @notice Thrown if the V2 forwarder forwards for the same protocol adapter as V1, i.e. it does not replace V1.
    error SharedProtocolAdapter(address protocolAdapter);

    /// @notice Thrown if a contract has another owner than the expected one.
    error OwnerMismatch(address expected, address actual);

    /// @notice Thrown if the migration contract names another forwarder than the recorded V1 forwarder.
    error ForwarderV1Mismatch(address expected, address actual);

    /// @notice Thrown if the migration contract names another forwarder than the recorded V2 forwarder.
    error ForwarderV2Mismatch(address expected, address actual);

    /// @notice Thrown if V1 has another emergency caller than the expected one.
    error EmergencyCallerMismatch(address expected, address actual);

    /// @notice Thrown if the owner has not stopped the v1 protocol adapter. That stop is enough for V1 to accept both
    /// emergency calls.
    error ProtocolAdapterNotStopped(address protocolAdapter);

    /// @notice Returns the chain's recorded forwarders and checks the V2 forwarder against the chain: the
    /// environment's proxy owner owns it, and it forwards for another protocol adapter than V1.
    /// @param isProduction Whether the tokens move to the production or the staging V2 forwarder.
    /// @return forwarderV1 The chain's V1 forwarder, which holds the tokens.
    /// @return forwarderV2 The environment's V2 forwarder of the chain, which receives them.
    function _configuration(bool isProduction) internal returns (address forwarderV1, address forwarderV2) {
        DeployERC20ForwarderProxy proxyDeployScript = new DeployERC20ForwarderProxy();

        forwarderV1 = RecordedDeployments.forwarderV1(block.chainid);
        require(forwarderV1 != address(0), ForwarderV1NotRecorded(block.chainid));

        forwarderV2 = RecordedDeployments.forwarderProxy({isProduction: isProduction, chainId: block.chainid});
        require(
            forwarderV2 != address(0),
            DeploymentNotRecorded(proxyDeployScript.environmentName(isProduction), block.chainid)
        );

        address expectedOwner =
            isProduction ? proxyDeployScript.PROXY_OWNER_PRODUCTION() : proxyDeployScript.PROXY_OWNER_STAGING();
        address actualOwner = ERC20Forwarder(forwarderV2).owner();
        require(actualOwner == expectedOwner, OwnerMismatch({expected: expectedOwner, actual: actualOwner}));

        address protocolAdapterV1 = IProtocolAdapterSpecific(forwarderV1).getProtocolAdapter();
        require(
            ERC20Forwarder(forwarderV2).getProtocolAdapter() != protocolAdapterV1,
            SharedProtocolAdapter(protocolAdapterV1)
        );
    }

    /// @notice Returns the chain's recorded forwarders and checks what moving the tokens depends on besides them:
    /// the migration contract moves the tokens between these two forwarders, the deployment wallet owns that
    /// contract, and the v1 protocol adapter is stopped.
    /// @param isProduction Whether the tokens move to the production or the staging V2 forwarder.
    /// @param migration The deployed migration contract.
    /// @return forwarderV1 The chain's V1 forwarder, which holds the tokens.
    /// @return forwarderV2 The environment's V2 forwarder of the chain, which receives them.
    function _checkedConfiguration(bool isProduction, ERC20ForwarderMigration migration)
        internal
        returns (address forwarderV1, address forwarderV2)
    {
        (forwarderV1, forwarderV2) = _configuration(isProduction);

        address actualForwarderV1 = address(migration.FORWARDER_V1());
        require(
            actualForwarderV1 == forwarderV1, ForwarderV1Mismatch({expected: forwarderV1, actual: actualForwarderV1})
        );

        address actualForwarderV2 = migration.FORWARDER_V2();
        require(
            actualForwarderV2 == forwarderV2, ForwarderV2Mismatch({expected: forwarderV2, actual: actualForwarderV2})
        );

        address wallet = _deploymentWallet();
        address actualOwner = migration.owner();
        require(actualOwner == wallet, OwnerMismatch({expected: wallet, actual: actualOwner}));

        address protocolAdapterV1 = IProtocolAdapterSpecific(forwarderV1).getProtocolAdapter();
        require(Pausable(protocolAdapterV1).paused(), ProtocolAdapterNotStopped(protocolAdapterV1));
    }

    /// @notice Returns the deployment wallet, which owns the migration contract and moves the tokens with it. It is
    /// the wallet the protocol adapter repository names `Parameters.DEPLOYMENT_WALLET`, and the owner of the staging
    /// proxies here.
    /// @return wallet The deployment wallet.
    function _deploymentWallet() internal returns (address wallet) {
        wallet = new DeployERC20ForwarderProxy().PROXY_OWNER_STAGING();
    }

    /// @notice Reverts unless V1 holds the expected emergency caller, which is what orders the steps of the
    /// migration.
    /// @param forwarderV1 The chain's V1 forwarder.
    /// @param expected The emergency caller V1 must hold.
    function _requireEmergencyCaller(address forwarderV1, address expected) internal view {
        address actual = IEmergencyMigratable(forwarderV1).getEmergencyCaller();
        require(actual == expected, EmergencyCallerMismatch({expected: expected, actual: actual}));
    }
}
