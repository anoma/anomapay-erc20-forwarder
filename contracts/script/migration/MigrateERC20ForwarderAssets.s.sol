// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

import {LegacyERC20ForwarderMigration} from "../../src/migration/LegacyERC20ForwarderMigration.sol";
import {Parameters} from "../Parameters.sol";
import {MigrationScript} from "./MigrationScript.s.sol";

/// @title MigrateERC20ForwarderAssets
/// @author Anoma Foundation, 2026
/// @notice A script to move one chain's ERC20 tokens from the legacy ERC20 forwarder to the ERC20 forwarder proxy, once
/// the forwarder multisig has executed the caller assignment that `DeployLegacyERC20ForwarderMigration` proposed.
/// `executeMigration` moves the tokens as the deployment wallet that owns the migration contract. `verify` checks the
/// moved tokens against the chain. Both read the migration contract from the emergency caller of the legacy ERC20
/// forwarder.
/// @dev The legacy ERC20 forwarder rejects an emergency call from a contract it does not hold as its caller, so the
/// move runs only after the Safe owners have executed the assignment.
/// @custom:security-contact security@anoma.foundation
contract MigrateERC20ForwarderAssets is MigrationScript {
    /// @notice Thrown if the legacy ERC20 forwarder still holds a token, i.e. the move left it behind.
    error TokenNotMigrated(address token, uint256 balance);

    /// @notice Moves the tokens as the deployment wallet. Without `--broadcast` the move is simulated locally.
    /// @dev The migration contract moves each token's full balance from the legacy ERC20 forwarder and reverts unless
    /// the ERC20 forwarder receives all of it. A token left out of `tokens` can be moved by a later run. The script
    /// broadcasts as the deployment wallet, because with `--account` alone forge runs it as its default sender.
    /// @param isProduction Whether the tokens move to the production or the staging ERC20 forwarder.
    /// @param tokens The ERC20 tokens to move.
    function executeMigration(bool isProduction, IERC20[] calldata tokens) public {
        LegacyERC20ForwarderMigration migration = _assignedMigration(isProduction);

        vm.broadcast(Parameters.DEPLOYMENT_WALLET);
        migration.migrate(tokens);
    }

    /// @notice Checks the moved tokens against the chain: the emergency caller of the legacy ERC20 forwarder is the
    /// migration contract between the recorded forwarders, and the legacy ERC20 forwarder holds none of the named
    /// tokens. Run it after `executeMigration` has broadcast, because `executeMigration` itself only ever sees the
    /// simulated state. Reverts on the first difference.
    /// @param isProduction Whether the tokens moved to the production or the staging ERC20 forwarder.
    /// @param tokens The ERC20 tokens the move covered.
    function verify(bool isProduction, IERC20[] calldata tokens) public {
        address legacyForwarder = address(_assignedMigration(isProduction).LEGACY_FORWARDER());

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 balance = tokens[i].balanceOf(legacyForwarder);
            require(balance == 0, TokenNotMigrated({token: address(tokens[i]), balance: balance}));
        }
    }
}
