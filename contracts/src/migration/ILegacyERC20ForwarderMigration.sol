// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

/// @title ILegacyERC20ForwarderMigration
/// @author Anoma Foundation, 2026
/// @notice Moves the tokens the legacy ERC20 forwarder holds to a fixed ERC20 forwarder.
interface ILegacyERC20ForwarderMigration {
    /// @notice Emitted after the full balance of a token has been moved from the legacy ERC20 forwarder to the ERC20
    /// forwarder and verified. The amount is zero if the legacy ERC20 forwarder held none of the token.
    /// @param legacyForwarder The source forwarder.
    /// @param forwarder The destination forwarder.
    /// @param token The migrated ERC20 token.
    /// @param amount The amount moved from the legacy ERC20 forwarder to the ERC20 forwarder.
    event ERC20TokenMigrated(
        address indexed legacyForwarder, address indexed forwarder, address indexed token, uint128 amount
    );

    /// @notice Moves the full balances of the legacy ERC20 forwarder to the ERC20 forwarder; omitted tokens can be
    /// supplied later.
    /// @dev The legacy ERC20 forwarder accepts uint128 amounts; larger balances revert without truncation.
    /// @dev Every token of the list emits the event, a zero balance included, so the events record which tokens the
    /// migration covered. Repeated calls and duplicate tokens move a zero balance, which still reaches the legacy ERC20
    /// forwarder as a zero-value transfer, so a token that rejects those reverts the whole batch.
    /// @param tokens The ERC20 token contracts to migrate.
    function migrate(IERC20[] calldata tokens) external;
}
