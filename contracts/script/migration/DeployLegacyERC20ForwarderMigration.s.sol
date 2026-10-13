// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {IOwnerManager} from "safe-smart-account-1.5.0/contracts/interfaces/IOwnerManager.sol";
import {Safe} from "safe-utils-0.0.22/src/Safe.sol";

import {LegacyERC20ForwarderMigration} from "../../src/migration/LegacyERC20ForwarderMigration.sol";
import {Parameters} from "../Parameters.sol";
import {MigrationScript} from "./MigrationScript.s.sol";

/// @title DeployLegacyERC20ForwarderMigration
/// @author Anoma Foundation, 2026
/// @notice A script to deploy the migration contract of one chain and to propose it to the forwarder multisig as the
/// permanent emergency caller of the legacy ERC20 forwarder. The migration contract is the only contract that can move
/// its tokens, and it can move them only to the recorded ERC20 forwarder. The deployment wallet deploys, proposes and
/// owns it, and moves the tokens with it through `MigrateERC20ForwarderAssets`.
/// @dev The deployment is deterministic: the address commits to both forwarders and the owner. So the proposal names
/// the right contract even before the deployment lands, and a repeated run finds the contract instead of deploying a
/// second one. The legacy ERC20 forwarder accepts the caller assignment only once its protocol adapter is stopped, so
/// the script refuses to run before the stop. The assignment cannot be undone, because the legacy ERC20 forwarder
/// accepts one emergency caller and keeps it.
/// @custom:security-contact security@anoma.foundation
contract DeployLegacyERC20ForwarderMigration is MigrationScript {
    using Safe for *;

    Safe.Client internal _safe;

    /// @notice Thrown if the simulated Safe execution of the transaction fails during a dry run.
    error TransactionSimulationFailed();

    /// @notice Deploys the migration contract between the chain's recorded forwarders, unless it is deployed already,
    /// and proposes it to the forwarder multisig as the emergency caller of the legacy ERC20 forwarder. Without
    /// `--broadcast`, the deployment is simulated locally and the Safe execution of the assignment is simulated instead
    /// of proposed.
    /// @dev The script broadcasts as the deployment wallet, because with `--account` alone forge runs it as its default
    /// sender.
    /// @param isProduction Whether the tokens move to the production or the staging ERC20 forwarder.
    /// @return migration The migration contract, owned by the deployment wallet.
    function run(bool isProduction) public returns (LegacyERC20ForwarderMigration migration) {
        (address legacyForwarder, address forwarder) = _configuration(isProduction);

        migration = LegacyERC20ForwarderMigration(_predict({legacyForwarder: legacyForwarder, forwarder: forwarder}));
        if (address(migration).code.length == 0) {
            vm.broadcast(Parameters.DEPLOYMENT_WALLET);
            migration = new LegacyERC20ForwarderMigration{salt: Parameters.MIGRATION_SALT}({
                legacyForwarder: legacyForwarder, forwarder: forwarder, initialOwner: Parameters.DEPLOYMENT_WALLET
            });
        }

        _checkedConfiguration({isProduction: isProduction, migration: migration});
        _requireEmergencyCaller({legacyForwarder: legacyForwarder, expected: address(0)});

        _propose({
            target: legacyForwarder,
            callData: abi.encodeCall(IEmergencyMigratable.setEmergencyCaller, (address(migration)))
        });
    }

    /// @notice Predicts the deterministic address the migration contract of the chain deploys to.
    /// @param isProduction Whether the tokens move to the production or the staging ERC20 forwarder.
    /// @return migration The predicted migration contract address.
    function predict(bool isProduction) public returns (address migration) {
        (address legacyForwarder, address forwarder) = _configuration(isProduction);
        migration = _predict({legacyForwarder: legacyForwarder, forwarder: forwarder});
    }

    /// @notice Proposes a transaction to the forwarder multisig via the Safe Transaction Service, signed by the
    /// deployment wallet.
    /// @dev Without `--broadcast`, the Safe execution of the transaction is simulated instead of proposed.
    /// @param target The contract the Safe calls.
    /// @param callData The call to propose.
    function _propose(address target, bytes memory callData) internal {
        address safe = Parameters.FWD_MULTISIG;
        _safe.initialize(safe);

        if (Safe.isBroadcastMode()) {
            _safe.proposeTransaction(target, callData, Parameters.DEPLOYMENT_WALLET);
        } else {
            require(
                _safe.simulateTransactionMultiSigNoSign(target, callData, IOwnerManager(safe).getOwners()),
                TransactionSimulationFailed()
            );
        }
    }

    /// @notice Derives the deterministic migration contract address from the forwarders it commits to.
    /// @param legacyForwarder The chain's legacy ERC20 forwarder.
    /// @param forwarder The environment's ERC20 forwarder of the chain.
    /// @return migration The deterministic migration contract address.
    function _predict(address legacyForwarder, address forwarder) internal pure returns (address migration) {
        bytes memory constructorArgs = abi.encode(legacyForwarder, forwarder, Parameters.DEPLOYMENT_WALLET);

        bytes memory initCode = abi.encodePacked(type(LegacyERC20ForwarderMigration).creationCode, constructorArgs);

        migration = vm.computeCreate2Address({salt: Parameters.MIGRATION_SALT, initCodeHash: keccak256(initCode)});
    }
}
