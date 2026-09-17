// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Pausable} from "@openzeppelin-contracts-5.7.0/utils/Pausable.sol";
import {
    RecordedDeployments as ProtocolAdapterDeployments
} from "anoma-pa-evm-2.0.0-rc.3/generated/RecordedDeployments.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {IProtocolAdapterSpecific} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IProtocolAdapterSpecific.sol";
import {Script} from "forge-std-1.16.2/src/Script.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {DeployERC20ForwarderProxy} from "../DeployERC20ForwarderProxy.s.sol";
import {Parameters} from "../Parameters.sol";

/// @title MigrationScript
/// @author Anoma Foundation, 2026
/// @notice The base of the scripts that move one chain's ERC20 tokens from the V1 forwarder to the V2 forwarder proxy.
/// Both forwarders come from the recorded deployments, their protocol adapters from the records of the protocol
/// adapter package, and all of them are checked against the chain, so `--rpc-url` alone names the chain.
/// @custom:security-contact security@anoma.foundation
abstract contract MigrationScript is Script {
    /// @notice Thrown if the chain ran no V1 forwarder, i.e. it has no tokens to move.
    error ForwarderV1NotRecorded(uint256 chainId);

    /// @notice Thrown if the environment records no V2 forwarder for the chain, i.e. it has no destination.
    error DeploymentNotRecorded(string environment, uint256 chainId);

    /// @notice Thrown if a forwarder forwards for another protocol adapter than the recorded one.
    error ProtocolAdapterMismatch(address expected, address actual);

    /// @notice Thrown if a contract has another owner than the expected one.
    error OwnerMismatch(address expected, address actual);

    /// @notice Thrown if the migration contract names another forwarder than the recorded V1 forwarder.
    error ForwarderV1Mismatch(address expected, address actual);

    /// @notice Thrown if the migration contract names another forwarder than the recorded V2 forwarder.
    error ForwarderV2Mismatch(address expected, address actual);

    /// @notice Thrown if V1 has another emergency caller than the expected one.
    error EmergencyCallerMismatch(address expected, address actual);

    /// @notice Thrown if V1 has no emergency caller, i.e. the Safe has not assigned the migration contract yet.
    error EmergencyCallerNotSet(address forwarderV1);

    /// @notice Thrown if the owner has not stopped the v1 protocol adapter. That stop is enough for V1 to accept both
    /// emergency calls.
    error ProtocolAdapterNotStopped(address protocolAdapter);

    /// @notice Returns the chain's recorded forwarders and checks them against the chain: the environment's proxy
    /// owner owns the V2 forwarder, and each forwarder forwards for the protocol adapter the records name for it.
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

        address expectedOwner = isProduction ? Parameters.FWD_MULTISIG : Parameters.DEPLOYMENT_WALLET;
        address actualOwner = ERC20Forwarder(forwarderV2).owner();
        require(actualOwner == expectedOwner, OwnerMismatch({expected: expectedOwner, actual: actualOwner}));

        _requireProtocolAdapter({
            forwarder: forwarderV1, expected: ProtocolAdapterDeployments.protocolAdapterV1(block.chainid)
        });
        _requireProtocolAdapter({
            forwarder: forwarderV2,
            expected: ProtocolAdapterDeployments.protocolAdapterProxy({
                isProduction: isProduction, chainId: block.chainid
            })
        });
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

        address actualOwner = migration.owner();
        require(
            actualOwner == Parameters.DEPLOYMENT_WALLET,
            OwnerMismatch({expected: Parameters.DEPLOYMENT_WALLET, actual: actualOwner})
        );

        address protocolAdapterV1 = ProtocolAdapterDeployments.protocolAdapterV1(block.chainid);
        require(Pausable(protocolAdapterV1).paused(), ProtocolAdapterNotStopped(protocolAdapterV1));
    }

    /// @notice Returns the migration contract that V1 holds as its emergency caller, after checking it the way
    /// `_checkedConfiguration` does.
    /// @param isProduction Whether the tokens move to the production or the staging V2 forwarder.
    /// @return migration The migration contract the Safe assigned.
    function _assignedMigration(bool isProduction) internal returns (ERC20ForwarderMigration migration) {
        (address forwarderV1,) = _configuration(isProduction);

        address caller = IEmergencyMigratable(forwarderV1).getEmergencyCaller();
        require(caller != address(0), EmergencyCallerNotSet(forwarderV1));

        migration = ERC20ForwarderMigration(caller);
        _checkedConfiguration({isProduction: isProduction, migration: migration});
    }

    /// @notice Reverts unless V1 holds the expected emergency caller, which is what orders the steps of the
    /// migration.
    /// @param forwarderV1 The chain's V1 forwarder.
    /// @param expected The emergency caller V1 must hold.
    function _requireEmergencyCaller(address forwarderV1, address expected) internal view {
        address actual = IEmergencyMigratable(forwarderV1).getEmergencyCaller();
        require(actual == expected, EmergencyCallerMismatch({expected: expected, actual: actual}));
    }

    /// @notice Reverts unless the forwarder forwards for the expected protocol adapter.
    /// @param forwarder The forwarder to check.
    /// @param expected The protocol adapter the records name for the forwarder.
    function _requireProtocolAdapter(address forwarder, address expected) internal view {
        address actual = IProtocolAdapterSpecific(forwarder).getProtocolAdapter();
        require(actual == expected, ProtocolAdapterMismatch({expected: expected, actual: actual}));
    }
}
