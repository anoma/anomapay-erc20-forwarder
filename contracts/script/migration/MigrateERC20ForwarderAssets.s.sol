// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {IOwnerManager} from "safe-smart-account-1.5.0/contracts/interfaces/IOwnerManager.sol";
import {Safe} from "safe-utils-0.0.22/src/Safe.sol";

import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {DeployERC20ForwarderProxy} from "../DeployERC20ForwarderProxy.s.sol";
import {MigrationScript} from "./MigrationScript.s.sol";

/// @title MigrateERC20ForwarderAssets
/// @author Anoma Foundation, 2026
/// @notice A script to move one chain's ERC20 tokens from the V1 forwarder to the V2 forwarder proxy, once the
/// chain's v1 protocol adapter is stopped and `DeployERC20ForwarderMigration` has deployed the migration contract.
/// `proposeCaller` proposes making the migration contract the permanent emergency caller of V1 to the emergency
/// committee Safe. `executeMigration` then moves the tokens as the deployment wallet that owns the migration
/// contract. `verify` checks the moved tokens against the chain.
/// @dev Only the caller assignment needs a Safe, because V1 accepts it from its emergency committee alone. The Safe
/// owners must execute that proposal before the move runs: V1 rejects an emergency call from a contract it does not
/// hold as its caller. The assignment cannot be undone, because V1 accepts one emergency caller and keeps it.
/// @custom:security-contact security@anoma.foundation
contract MigrateERC20ForwarderAssets is MigrationScript {
    using Safe for *;

    Safe.Client internal _safe;

    /// @notice Thrown if the V1 forwarder still holds a token, i.e. the move left it behind.
    error TokenNotMigrated(address token, uint256 balance);

    /// @notice Thrown if the sender is not the deployment wallet that owns the migration contract.
    error UnauthorizedSender(address sender);

    /// @notice Thrown if the simulated Safe execution of the transaction fails during a dry run.
    error TransactionSimulationFailed();

    /// @notice Proposes making the migration contract the permanent emergency caller of V1 to the emergency committee
    /// Safe.
    /// @dev Without `--broadcast`, the Safe execution of the assignment is simulated instead of proposed. The Safe
    /// owners confirm and execute it in the Safe app. It cannot be undone.
    /// @param isProduction Whether the tokens move to the production or the staging V2 forwarder.
    /// @param migration The deployed migration contract to assign.
    /// @param proposer The Safe owner or delegate proposing the transaction.
    function proposeCaller(bool isProduction, ERC20ForwarderMigration migration, address proposer) public {
        (address forwarderV1,) = _checkedConfiguration({isProduction: isProduction, migration: migration});
        _requireEmergencyCaller({forwarderV1: forwarderV1, expected: address(0)});

        _propose({
            safe: _emergencyCommittee(),
            target: forwarderV1,
            callData: abi.encodeCall(IEmergencyMigratable.setEmergencyCaller, (address(migration))),
            proposer: proposer
        });
    }

    /// @notice Moves the tokens as the deployment wallet, which the sender must be, once the Safe has executed the
    /// caller assignment. Without `--broadcast` the move is simulated locally.
    /// @dev The migration contract moves each token's full V1 balance and reverts unless V2 receives all of it. A
    /// token left out of `tokens` can be moved by a later run.
    /// @param isProduction Whether the tokens move to the production or the staging V2 forwarder.
    /// @param migration The deployed migration contract, already the emergency caller of V1.
    /// @param tokens The ERC20 tokens to move.
    function executeMigration(bool isProduction, ERC20ForwarderMigration migration, IERC20[] calldata tokens) public {
        (address forwarderV1,) = _checkedConfiguration({isProduction: isProduction, migration: migration});
        _requireEmergencyCaller({forwarderV1: forwarderV1, expected: address(migration)});
        require(msg.sender == _deploymentWallet(), UnauthorizedSender(msg.sender));

        vm.broadcast();
        migration.migrate(tokens);
    }

    /// @notice Checks the moved tokens against the chain: the migration contract is the emergency caller of V1, and
    /// V1 holds none of the named tokens. Run it after `executeMigration` has broadcast, because `executeMigration`
    /// itself only ever sees the simulated state. Reverts on the first difference.
    /// @param isProduction Whether the tokens moved to the production or the staging V2 forwarder.
    /// @param migration The deployed migration contract that moved the tokens.
    /// @param tokens The ERC20 tokens the move covered.
    function verify(bool isProduction, ERC20ForwarderMigration migration, IERC20[] calldata tokens) public {
        (address forwarderV1,) = _checkedConfiguration({isProduction: isProduction, migration: migration});
        _requireEmergencyCaller({forwarderV1: forwarderV1, expected: address(migration)});

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 balance = tokens[i].balanceOf(forwarderV1);
            require(balance == 0, TokenNotMigrated({token: address(tokens[i]), balance: balance}));
        }
    }

    /// @notice Returns the V1 emergency committee, the Safe that alone can name the emergency caller of V1. It owns
    /// the production proxies here.
    /// @dev The audited chains all name this Safe. A chain that names another one fails the dry run, because V1
    /// rejects an assignment from any other caller.
    /// @return committee The emergency committee Safe.
    function _emergencyCommittee() internal returns (address committee) {
        committee = new DeployERC20ForwarderProxy().PROXY_OWNER_PRODUCTION();
    }

    /// @notice Proposes a transaction to a Safe via the Safe Transaction Service.
    /// @dev Without `--broadcast`, the Safe execution of the transaction is simulated instead of proposed.
    /// @param safe The Safe to propose the transaction to.
    /// @param target The contract the Safe calls.
    /// @param callData The call to propose.
    /// @param proposer The Safe owner or delegate proposing the transaction.
    function _propose(address safe, address target, bytes memory callData, address proposer) internal {
        _safe.initialize(safe);

        if (Safe.isBroadcastMode()) {
            _safe.proposeTransaction(target, callData, proposer);
        } else {
            require(
                _safe.simulateTransactionMultiSigNoSign(target, callData, IOwnerManager(safe).getOwners()),
                TransactionSimulationFailed()
            );
        }
    }
}
