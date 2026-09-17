// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {Parameters} from "../Parameters.sol";
import {MigrationScript} from "./MigrationScript.s.sol";

/// @title MigrateERC20ForwarderAssets
/// @author Anoma Foundation, 2026
/// @notice A script to move one chain's ERC20 tokens from the V1 forwarder to the V2 forwarder proxy, once the
/// forwarder multisig has executed the caller assignment that `DeployERC20ForwarderMigration` proposed.
/// `executeMigration` moves the tokens as the deployment wallet that owns the migration contract. `verify` checks the
/// moved tokens against the chain. Both read the migration contract from the emergency caller of V1.
/// @dev V1 rejects an emergency call from a contract it does not hold as its caller, so the move runs only after the
/// Safe owners have executed the assignment.
/// @custom:security-contact security@anoma.foundation
contract MigrateERC20ForwarderAssets is MigrationScript {
    /// @notice Thrown if the V1 forwarder still holds a token, i.e. the move left it behind.
    error TokenNotMigrated(address token, uint256 balance);

    /// @notice Moves the tokens as the deployment wallet. Without `--broadcast` the move is simulated locally.
    /// @dev The migration contract moves each token's full V1 balance and reverts unless V2 receives all of it. A
    /// token left out of `tokens` can be moved by a later run. The script broadcasts as the deployment wallet, because
    /// with `--account` alone forge runs it as its default sender.
    /// @param isProduction Whether the tokens move to the production or the staging V2 forwarder.
    /// @param tokens The ERC20 tokens to move.
    function executeMigration(bool isProduction, IERC20[] calldata tokens) public {
        ERC20ForwarderMigration migration = _assignedMigration(isProduction);

        vm.broadcast(Parameters.DEPLOYMENT_WALLET);
        migration.migrate(tokens);
    }

    /// @notice Checks the moved tokens against the chain: the emergency caller of V1 is the migration contract between
    /// the recorded forwarders, and V1 holds none of the named tokens. Run it after `executeMigration` has broadcast,
    /// because `executeMigration` itself only ever sees the simulated state. Reverts on the first difference.
    /// @param isProduction Whether the tokens moved to the production or the staging V2 forwarder.
    /// @param tokens The ERC20 tokens the move covered.
    function verify(bool isProduction, IERC20[] calldata tokens) public {
        address forwarderV1 = address(_assignedMigration(isProduction).FORWARDER_V1());

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 balance = tokens[i].balanceOf(forwarderV1);
            require(balance == 0, TokenNotMigrated({token: address(tokens[i]), balance: balance}));
        }
    }
}
