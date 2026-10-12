// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin-contracts-5.7.0/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.7.0/utils/ReentrancyGuard.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {ERC20Forwarder} from "../ERC20Forwarder.sol";
import {ILegacyERC20ForwarderMigration} from "./ILegacyERC20ForwarderMigration.sol";

/// @title LegacyERC20ForwarderMigration
/// @author Anoma Foundation, 2026
/// @notice The permanent emergency caller of the legacy ERC20 forwarder, which moves its tokens only to a fixed ERC20
/// forwarder.
/// @custom:security-contact security@anoma.foundation
contract LegacyERC20ForwarderMigration is ILegacyERC20ForwarderMigration, Ownable, ReentrancyGuard {
    /// @notice The legacy ERC20 forwarder, whose tokens this contract moves.
    IEmergencyMigratable public immutable LEGACY_FORWARDER;
    /// @notice The ERC20 forwarder that receives the tokens.
    address public immutable FORWARDER;

    /// @notice Thrown if the forwarders are the same contract, or if one of them is the zero address or holds no
    /// code.
    error InvalidForwarders();

    /// @notice Thrown if the source forwarder answers an unwrap with data, which it does not do.
    error UnexpectedEmergencyCallOutput(address token, bytes output);

    /// @notice Thrown if the source forwarder still holds the token after the call.
    error SourceBalanceRemaining(address token, uint256 remaining);

    /// @notice Thrown if the destination forwarder did not receive exactly the amount taken from the source.
    error DestinationBalanceMismatch(address token, uint256 expected, uint256 actual);

    /// @notice Fixes the source, destination and initial owner for this chain.
    /// @param legacyForwarder The deployed legacy ERC20 forwarder.
    /// @param forwarder The deployed ERC20 forwarder proxy receiving the tokens.
    /// @param initialOwner The account that moves the tokens, which the deploy script names.
    constructor(address legacyForwarder, address forwarder, address initialOwner) Ownable(initialOwner) {
        require(
            legacyForwarder != address(0) && forwarder != address(0) && legacyForwarder != forwarder
                && legacyForwarder.code.length != 0 && forwarder.code.length != 0,
            InvalidForwarders()
        );
        LEGACY_FORWARDER = IEmergencyMigratable(legacyForwarder);
        FORWARDER = forwarder;
    }

    // slither-disable-start reentrancy-balance
    /// @inheritdoc ILegacyERC20ForwarderMigration
    function migrate(IERC20[] calldata tokens) external override nonReentrant onlyOwner {
        uint256 count = tokens.length;

        // NOTE: Each token of the batch carries its own balance reads and its own emergency call, so the calls
        // belong inside the loop.
        // forge-lint: disable-next-item(calls-loop)
        for (uint256 i = 0; i < count; ++i) {
            IERC20 token = tokens[i];
            uint128 amount = SafeCast.toUint128(token.balanceOf(address(LEGACY_FORWARDER)));

            uint256 balanceBefore = token.balanceOf(FORWARDER);
            bytes memory output = LEGACY_FORWARDER.forwardEmergencyCall(
                abi.encode(ERC20Forwarder.CallType.Unwrap, token, amount, FORWARDER)
            );

            // NOTE: The legacy ERC20 forwarder returns empty bytes for a successful unwrap.
            // slither-disable-next-line incorrect-equality
            require(output.length == 0, UnexpectedEmergencyCallOutput({token: address(token), output: output}));

            uint256 remaining = token.balanceOf(address(LEGACY_FORWARDER));
            // NOTE: The amount is the balance of the legacy ERC20 forwarder read in this call, so that balance must end
            // at zero.
            // slither-disable-next-line incorrect-equality
            require(remaining == 0, SourceBalanceRemaining({token: address(token), remaining: remaining}));

            uint256 expected = balanceBefore + amount;
            uint256 received = token.balanceOf(FORWARDER);
            // NOTE: The forwarders support no fee-on-transfer token, so the ERC20 forwarder must receive the exact
            // amount.
            // slither-disable-next-line incorrect-equality
            require(
                received == expected,
                DestinationBalanceMismatch({token: address(token), expected: expected, actual: received})
            );

            emit ERC20TokenMigrated(address(LEGACY_FORWARDER), FORWARDER, address(token), amount);
        }
    }

    // slither-disable-end reentrancy-balance
}
