// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

/// @title IERC20ForwarderMigration
/// @author Anoma Foundation, 2026
/// @notice Moves V1 pooled token custody to a fixed V2 destination.
interface IERC20ForwarderMigration {
    /// @notice Moves full V1 balances to V2; omitted tokens can be supplied later.
    /// @dev V1 accepts uint128 amounts; larger balances revert without truncation.
    /// @dev Zero balances, repeated calls and duplicate tokens are harmless.
    /// @param tokens The ERC20 token contracts to migrate.
    function migrate(IERC20[] calldata tokens) external;
}
