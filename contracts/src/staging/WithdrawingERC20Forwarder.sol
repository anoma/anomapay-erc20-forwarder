// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/utils/SafeERC20.sol";

import {ERC20Forwarder} from "../ERC20Forwarder.sol";
import {IWithdrawingERC20Forwarder} from "./IWithdrawingERC20Forwarder.sol";

/// @title WithdrawingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice An ERC20 forwarder whose owner can send its full token balances to a recipient fixed at deployment. A
/// staging forwarder upgrades to it to give back its tokens before its protocol adapter is replaced.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from ERC20Forwarder
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract WithdrawingERC20Forwarder is IWithdrawingERC20Forwarder, ERC20Forwarder {
    using SafeERC20 for IERC20;

    /// @inheritdoc IWithdrawingERC20Forwarder
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable override RECIPIENT;

    /// @notice Thrown if the recipient is the zero address.
    error ZeroRecipientNotAllowed();

    /// @notice Sets the recipient of the withdrawn tokens.
    /// @param recipient The account that receives the withdrawn tokens.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address recipient) {
        require(recipient != address(0), ZeroRecipientNotAllowed());
        RECIPIENT = recipient;
    }

    /// @inheritdoc IWithdrawingERC20Forwarder
    function withdraw(IERC20[] calldata tokens) external override nonReentrant onlyOwner {
        uint256 count = tokens.length;

        // NOTE: Each token of the batch carries its own balance read and its own transfer, so the calls belong inside
        // the loop.
        // forge-lint: disable-next-item(calls-loop)
        for (uint256 i = 0; i < count; ++i) {
            IERC20 token = tokens[i];
            uint256 amount = token.balanceOf(address(this));

            token.safeTransfer({to: RECIPIENT, value: amount});

            // NOTE: The event ordering is protected by the `nonReentrant` modifier.
            // slither-disable-next-line reentrancy-events
            emit Withdrawn({token: address(token), to: RECIPIENT, amount: amount});
        }
    }
}
