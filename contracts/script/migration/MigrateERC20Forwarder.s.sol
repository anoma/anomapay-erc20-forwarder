// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {Script} from "forge-std-1.16.2/src/Script.sol";
import {IOwnerManager} from "safe-smart-account-1.5.0/contracts/interfaces/IOwnerManager.sol";
import {Safe} from "safe-utils-0.0.22/src/Safe.sol";

import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {IERC20ForwarderMigration} from "../../src/migration/IERC20ForwarderMigration.sol";
import {IERC20ForwarderV1} from "../../src/migration/IERC20ForwarderV1.sol";
import {DeployERC20ForwarderProxy} from "../DeployERC20ForwarderProxy.s.sol";

interface IStoppedProtocolAdapter {
    function isEmergencyStopped() external view returns (bool isStopped);
}

/// @notice Deploys a migration and proposes caller assignment and custody transfer.
contract MigrateERC20Forwarder is Script {
    using Safe for *;

    struct Configuration {
        IERC20ForwarderV1 v1;
        address v2;
        address committee;
        address initialOwner;
        IERC20[] tokens;
    }

    Safe.Client internal _safe;

    error MissingV2Deployment(uint256 chainId, bool isProduction);
    error InvalidConfiguration();
    error WrongEmergencyCaller(address caller);
    error ProtocolAdapterNotStopped();
    error SimulationFailed();

    /// @notice Deploys the migration for a recorded V2 environment.
    /// @param isProduction Selects production or staging from the deployment registry.
    /// @return migration The migration contract, initially owned by the Forwarder Safe.
    function run(bool isProduction) public returns (ERC20ForwarderMigration migration) {
        Configuration memory config = _configuration(isProduction);
        vm.startBroadcast();
        migration = new ERC20ForwarderMigration(address(config.v1), config.v2, config.initialOwner);
        vm.stopBroadcast();
    }

    /// @notice Proposes the irreversible caller assignment after PA V1 is stopped.
    /// @dev Execute this proposal before proposing migration to avoid nonce conflicts.
    /// @param isProduction Selects the V2 environment.
    /// @param migration The deployed migration contract to validate and assign.
    /// @param proposer The committee Safe owner or delegate proposing the call.
    function proposeCaller(bool isProduction, ERC20ForwarderMigration migration, address proposer) public {
        Configuration memory config = _validatedConfiguration(isProduction, migration);
        require(config.v1.getEmergencyCaller() == address(0), WrongEmergencyCaller(config.v1.getEmergencyCaller()));
        _propose(
            config.committee,
            address(config.v1),
            abi.encodeCall(IERC20ForwarderV1.setEmergencyCaller, (address(migration))),
            proposer
        );
    }

    /// @notice Proposes custody migration after the committee's assignment has executed.
    /// @param isProduction Selects the V2 environment.
    /// @param migration The deployed migration contract.
    /// @param proposer The migration owner's Safe owner or delegate proposing the call.
    function proposeMigration(bool isProduction, ERC20ForwarderMigration migration, address proposer) public {
        Configuration memory config = _validatedConfiguration(isProduction, migration);
        require(
            config.v1.getEmergencyCaller() == address(migration), WrongEmergencyCaller(config.v1.getEmergencyCaller())
        );
        _propose(
            migration.owner(),
            address(migration),
            abi.encodeCall(IERC20ForwarderMigration.migrate, (config.tokens)),
            proposer
        );
    }

    function _configuration(bool isProduction) internal returns (Configuration memory config) {
        string memory deployments = vm.readFile("../crates/bindings/deployments.json");
        string memory environment = isProduction ? ".production" : ".staging";
        for (uint256 i = 0;; ++i) {
            // solhint-disable-next-line func-named-parameters
            string memory entry = string.concat(environment, "[", vm.toString(i), "]");
            if (!vm.keyExistsJson(deployments, entry)) break;
            if (vm.parseJsonUint(deployments, string.concat(entry, ".chainId")) == block.chainid) {
                string memory addressKey = string.concat(entry, ".proxy.address");
                config.v2 = vm.parseJsonAddress(deployments, addressKey);
                break;
            }
        }
        require(config.v2 != address(0), MissingV2Deployment(block.chainid, isProduction));
        string memory json = vm.readFile("script/migration/tokens.json");
        string memory key = string.concat(".chains.", vm.toString(block.chainid));
        address v1 = vm.parseJsonAddress(json, string.concat(key, ".forwarderV1"));
        config.v1 = IERC20ForwarderV1(v1);
        config.committee = vm.parseJsonAddress(json, string.concat(key, ".audit.emergencyCommittee"));
        config.tokens = abi.decode(vm.parseJson(json, string.concat(key, ".tokens")), (IERC20[]));
        DeployERC20ForwarderProxy settings = new DeployERC20ForwarderProxy();
        config.initialOwner = settings.PROXY_OWNER_PRODUCTION();
        address expectedV2Owner = isProduction ? config.initialOwner : settings.PROXY_OWNER_STAGING();
        require(
            config.v2 != address(config.v1) && ERC20Forwarder(config.v2).owner() == expectedV2Owner
                && ERC20Forwarder(config.v2).getProtocolAdapter() != config.v1.getProtocolAdapter(),
            InvalidConfiguration()
        );
    }

    function _validatedConfiguration(bool isProduction, ERC20ForwarderMigration migration)
        internal
        returns (Configuration memory config)
    {
        config = _configuration(isProduction);
        require(
            address(migration.FORWARDER_V1()) == address(config.v1) && migration.FORWARDER_V2() == config.v2
                && migration.owner() == config.initialOwner && migration.pendingOwner() == address(0),
            InvalidConfiguration()
        );
        require(
            IStoppedProtocolAdapter(config.v1.getProtocolAdapter()).isEmergencyStopped(), ProtocolAdapterNotStopped()
        );
    }

    function _propose(address safe, address target, bytes memory data, address proposer) internal {
        Safe.Client storage client = _safe.initialize(safe);
        if (Safe.isBroadcastMode()) {
            bytes32 txHash = client.proposeTransaction(target, data, proposer);
            require(txHash != bytes32(0), SimulationFailed());
        } else {
            require(
                client.simulateTransactionMultiSigNoSign(target, data, IOwnerManager(safe).getOwners()),
                SimulationFailed()
            );
        }
    }
}
