// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

/// @title IWithdrawingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice Sends the full token balances of the forwarder to a recipient that the implementation fixes.
/// @custom:security-contact security@anoma.foundation
interface IWithdrawingERC20Forwarder {
    /// @notice Emitted when the forwarder sends its full balance of a token to the recipient. The amount is zero if
    /// the forwarder held none of the token.
    /// @param token The ERC20 token.
    /// @param to The recipient.
    /// @param amount The amount sent.
    event Withdrawn(address indexed token, address indexed to, uint256 amount);

    /// @notice Sends the full balance of each token to the recipient. Only the owner can call it.
    /// @param tokens The ERC20 tokens.
    function withdraw(IERC20[] calldata tokens) external;

    /// @notice The account that receives the withdrawn tokens.
    /// @return recipient The recipient.
    function RECIPIENT() external view returns (address recipient);
}
