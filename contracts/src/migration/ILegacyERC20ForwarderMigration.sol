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
        address indexed legacyForwarder, address indexed forwarder, address indexed token, uint256 amount
    );

    /// @notice Moves the full balances of the legacy ERC20 forwarder to the ERC20 forwarder; omitted tokens can be
    /// supplied later.
    /// @param tokens The ERC20 token contracts to migrate.
    function migrate(IERC20[] calldata tokens) external;
}
