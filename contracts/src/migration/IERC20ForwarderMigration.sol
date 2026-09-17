// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

/// @title IERC20ForwarderMigration
/// @author Anoma Foundation, 2026
/// @notice Moves V1 pooled token custody to a fixed V2 destination.
interface IERC20ForwarderMigration {
    /// @notice Emitted after a token's full V1 balance has been moved to V2 and verified. The amount is zero if V1
    /// held none of the token.
    /// @param forwarderV1 The source forwarder.
    /// @param forwarderV2 The destination forwarder.
    /// @param token The migrated ERC20 token.
    /// @param amount The amount moved from V1 to V2.
    event ERC20TokenMigrated(
        address indexed forwarderV1, address indexed forwarderV2, address indexed token, uint128 amount
    );

    /// @notice Moves full V1 balances to V2; omitted tokens can be supplied later.
    /// @dev V1 accepts uint128 amounts; larger balances revert without truncation.
    /// @dev Every token of the list emits the event, a zero balance included, so the events record which tokens the
    /// migration covered. Repeated calls and duplicate tokens move a zero balance, which still reaches V1 as a
    /// zero-value transfer, so a token that rejects those reverts the whole batch.
    /// @param tokens The ERC20 token contracts to migrate.
    function migrate(IERC20[] calldata tokens) external;
}
