// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin-contracts-5.7.0/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.7.0/utils/ReentrancyGuard.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {ERC20Forwarder} from "../ERC20Forwarder.sol";
import {IERC20ForwarderMigration} from "./IERC20ForwarderMigration.sol";

/// @title ERC20ForwarderMigration
/// @author Anoma Foundation, 2026
/// @notice Permanent V1 emergency caller that moves custody only to its fixed V2 destination.
/// @custom:security-contact security@anoma.foundation
contract ERC20ForwarderMigration is IERC20ForwarderMigration, Ownable, ReentrancyGuard {
    /// @notice The immutable source forwarder.
    IEmergencyMigratable public immutable FORWARDER_V1;
    /// @notice The immutable destination forwarder.
    address public immutable FORWARDER_V2;

    /// @notice Thrown if the forwarders are the same contract, or if one of them is the zero address or holds no
    /// code.
    error InvalidForwarders();

    /// @notice Thrown if the source forwarder answers an unwrap with data, which it does not do.
    error UnexpectedEmergencyCallOutput(address token, bytes output);

    /// @notice Thrown if the source forwarder still holds the token after the call.
    error SourceBalanceRemaining(address token, uint256 balance);

    /// @notice Thrown if the destination forwarder did not receive exactly the amount taken from the source.
    error DestinationBalanceMismatch(address token, uint256 expected, uint256 actual);

    /// @notice Fixes the source, destination and initial owner for this chain.
    /// @param forwarderV1 The deployed immutable V1 forwarder.
    /// @param forwarderV2 The deployed V2 forwarder proxy receiving custody.
    /// @param initialOwner The account that moves the custody, which the deploy script names.
    constructor(address forwarderV1, address forwarderV2, address initialOwner) Ownable(initialOwner) {
        require(
            forwarderV1 != address(0) && forwarderV2 != address(0) && forwarderV1 != forwarderV2
                && forwarderV1.code.length != 0 && forwarderV2.code.length != 0,
            InvalidForwarders()
        );
        FORWARDER_V1 = IEmergencyMigratable(forwarderV1);
        FORWARDER_V2 = forwarderV2;
    }

    // slither-disable-start reentrancy-balance
    /// @inheritdoc IERC20ForwarderMigration
    function migrate(IERC20[] calldata tokens) external override nonReentrant onlyOwner {
        uint256 count = tokens.length;

        // NOTE: Each token of the batch carries its own balance reads and its own emergency call, so the calls
        // belong inside the loop.
        // forge-lint: disable-next-item(calls-loop)
        for (uint256 i = 0; i < count; ++i) {
            IERC20 token = tokens[i];
            uint128 amount = SafeCast.toUint128(token.balanceOf(address(FORWARDER_V1)));

            uint256 beforeV2 = token.balanceOf(FORWARDER_V2);
            bytes memory output = FORWARDER_V1.forwardEmergencyCall(
                abi.encode(ERC20Forwarder.CallType.Unwrap, token, amount, FORWARDER_V2)
            );

            require(output.length == 0, UnexpectedEmergencyCallOutput({token: address(token), output: output}));

            uint256 remaining = token.balanceOf(address(FORWARDER_V1));
            require(remaining == 0, SourceBalanceRemaining({token: address(token), remaining: remaining}));

            uint256 expected = beforeV2 + amount;
            uint256 received = token.balanceOf(FORWARDER_V2);
            require(
                received == expected,
                DestinationBalanceMismatch({token: address(token), expected: expected, actual: received})
            );

            emit ERC20TokenMigrated(address(FORWARDER_V1), FORWARDER_V2, address(token), amount);
        }
    }

    // slither-disable-end reentrancy-balance
}
