// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Pausable} from "@openzeppelin-contracts-5.7.0/utils/Pausable.sol";
import {
    RecordedDeployments as ProtocolAdapterDeployments
} from "anoma-pa-evm-2.0.0-rc.14/generated/RecordedDeployments.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {IProtocolAdapterSpecific} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IProtocolAdapterSpecific.sol";
import {Script} from "forge-std-1.17.0/src/Script.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {LegacyERC20ForwarderMigration} from "../../src/migration/LegacyERC20ForwarderMigration.sol";
import {DeployERC20ForwarderProxy} from "../DeployERC20ForwarderProxy.s.sol";
import {Parameters} from "../Parameters.sol";

/// @title MigrationScript
/// @author Anoma Foundation, 2026
/// @notice The base of the scripts that move one chain's ERC20 tokens from the legacy ERC20 forwarder to the ERC20
/// forwarder proxy. Both forwarders come from the recorded deployments, their protocol adapters from the records of the
/// protocol adapter package, and all of them are checked against the chain, so `--rpc-url` alone names the chain.
/// @custom:security-contact security@anoma.foundation
abstract contract MigrationScript is Script {
    /// @notice Thrown if the chain ran no legacy ERC20 forwarder, i.e. it has no tokens to move.
    error LegacyForwarderNotRecorded(uint256 chainId);

    /// @notice Thrown if the environment records no ERC20 forwarder for the chain, i.e. it has no destination.
    error DeploymentNotRecorded(string environment, uint256 chainId);

    /// @notice Thrown if a forwarder forwards for another protocol adapter than the recorded one.
    error ProtocolAdapterMismatch(address expected, address actual);

    /// @notice Thrown if a contract has another owner than the expected one.
    error OwnerMismatch(address expected, address actual);

    /// @notice Thrown if the migration contract names another forwarder than the recorded legacy ERC20 forwarder.
    error LegacyForwarderMismatch(address expected, address actual);

    /// @notice Thrown if the migration contract names another forwarder than the recorded ERC20 forwarder.
    error ForwarderMismatch(address expected, address actual);

    /// @notice Thrown if the legacy ERC20 forwarder has another emergency caller than the expected one.
    error EmergencyCallerMismatch(address expected, address actual);

    /// @notice Thrown if the legacy ERC20 forwarder has no emergency caller, i.e. the Safe has not assigned the
    /// migration contract yet.
    error EmergencyCallerNotSet(address legacyForwarder);

    /// @notice Thrown if the owner has not stopped the legacy protocol adapter. That stop is enough for the legacy
    /// ERC20 forwarder to accept both emergency calls.
    error ProtocolAdapterNotStopped(address protocolAdapter);

    /// @notice Returns the chain's recorded forwarders and checks them against the chain: the environment's proxy
    /// owner owns the ERC20 forwarder, and each forwarder forwards for the protocol adapter the records name for it.
    /// @param isProduction Whether the tokens move to the production or the staging ERC20 forwarder.
    /// @return legacyForwarder The chain's legacy ERC20 forwarder, which holds the tokens.
    /// @return forwarder The environment's ERC20 forwarder of the chain, which receives them.
    function _configuration(bool isProduction) internal returns (address legacyForwarder, address forwarder) {
        DeployERC20ForwarderProxy proxyDeployScript = new DeployERC20ForwarderProxy();

        legacyForwarder = RecordedDeployments.legacyForwarder(block.chainid);
        require(legacyForwarder != address(0), LegacyForwarderNotRecorded(block.chainid));

        forwarder = RecordedDeployments.forwarderProxy({isProduction: isProduction, chainId: block.chainid});
        require(
            forwarder != address(0),
            DeploymentNotRecorded(proxyDeployScript.environmentName(isProduction), block.chainid)
        );

        address expectedOwner = isProduction ? Parameters.FWD_MULTISIG : Parameters.DEPLOYMENT_WALLET;
        address actualOwner = ERC20Forwarder(forwarder).owner();
        require(actualOwner == expectedOwner, OwnerMismatch({expected: expectedOwner, actual: actualOwner}));

        _requireProtocolAdapter({
            forwarder: legacyForwarder, expected: ProtocolAdapterDeployments.legacyProtocolAdapter(block.chainid)
        });
        _requireProtocolAdapter({
            forwarder: forwarder,
            expected: ProtocolAdapterDeployments.protocolAdapterProxy({
                isProduction: isProduction, chainId: block.chainid
            })
        });
    }

    /// @notice Returns the chain's recorded forwarders and checks what moving the tokens depends on besides them:
    /// the migration contract moves the tokens between these two forwarders, the deployment wallet owns that
    /// contract, and the legacy protocol adapter is stopped.
    /// @param isProduction Whether the tokens move to the production or the staging ERC20 forwarder.
    /// @param migration The deployed migration contract.
    /// @return legacyForwarder The chain's legacy ERC20 forwarder, which holds the tokens.
    /// @return forwarder The environment's ERC20 forwarder of the chain, which receives them.
    function _checkedConfiguration(bool isProduction, LegacyERC20ForwarderMigration migration)
        internal
        returns (address legacyForwarder, address forwarder)
    {
        (legacyForwarder, forwarder) = _configuration(isProduction);

        address actualLegacyForwarder = address(migration.LEGACY_FORWARDER());
        require(
            actualLegacyForwarder == legacyForwarder,
            LegacyForwarderMismatch({expected: legacyForwarder, actual: actualLegacyForwarder})
        );

        address actualForwarder = migration.FORWARDER();
        require(actualForwarder == forwarder, ForwarderMismatch({expected: forwarder, actual: actualForwarder}));

        address actualOwner = migration.owner();
        require(
            actualOwner == Parameters.DEPLOYMENT_WALLET,
            OwnerMismatch({expected: Parameters.DEPLOYMENT_WALLET, actual: actualOwner})
        );

        address legacyProtocolAdapter = ProtocolAdapterDeployments.legacyProtocolAdapter(block.chainid);
        require(Pausable(legacyProtocolAdapter).paused(), ProtocolAdapterNotStopped(legacyProtocolAdapter));
    }

    /// @notice Returns the migration contract that the legacy ERC20 forwarder holds as its emergency caller, after
    /// checking it the way `_checkedConfiguration` does.
    /// @param isProduction Whether the tokens move to the production or the staging ERC20 forwarder.
    /// @return migration The migration contract the Safe assigned.
    function _assignedMigration(bool isProduction) internal returns (LegacyERC20ForwarderMigration migration) {
        (address legacyForwarder,) = _configuration(isProduction);

        address caller = IEmergencyMigratable(legacyForwarder).getEmergencyCaller();
        require(caller != address(0), EmergencyCallerNotSet(legacyForwarder));

        migration = LegacyERC20ForwarderMigration(caller);
        _checkedConfiguration({isProduction: isProduction, migration: migration});
    }

    /// @notice Reverts unless the legacy ERC20 forwarder holds the expected emergency caller, which is what orders the
    /// steps of the migration.
    /// @param legacyForwarder The chain's legacy ERC20 forwarder.
    /// @param expected The emergency caller the legacy ERC20 forwarder must hold.
    function _requireEmergencyCaller(address legacyForwarder, address expected) internal view {
        address actual = IEmergencyMigratable(legacyForwarder).getEmergencyCaller();
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
