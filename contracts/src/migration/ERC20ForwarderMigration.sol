// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin-contracts-5.7.0/access/Ownable2Step.sol";
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
contract ERC20ForwarderMigration is IERC20ForwarderMigration, Ownable2Step, ReentrancyGuard {
    /// @notice The immutable source forwarder.
    IEmergencyMigratable public immutable FORWARDER_V1;
    /// @notice The immutable destination forwarder.
    address public immutable FORWARDER_V2;

    error InvalidForwarders();
    error IncompleteMigration(address token);
    error RenunciationDisabled();

    /// @notice Fixes the source, destination and initial owner for this chain.
    /// @param forwarderV1 The deployed immutable V1 forwarder.
    /// @param forwarderV2 The deployed V2 forwarder proxy receiving custody.
    /// @param initialOwner The chain's ERC20 Forwarder Safe.
    constructor(address forwarderV1, address forwarderV2, address initialOwner) Ownable(initialOwner) {
        require(
            forwarderV1 != address(0) && forwarderV2 != address(0) && forwarderV1 != forwarderV2
                && forwarderV1.code.length != 0 && forwarderV2.code.length != 0,
            InvalidForwarders()
        );
        FORWARDER_V1 = IEmergencyMigratable(forwarderV1);
        FORWARDER_V2 = forwarderV2;
    }

    // Owner-chosen batches are guarded; exact pre/post balances enforce custody.
    // slither-disable-start calls-loop,reentrancy-balance,incorrect-equality
    // forge-lint: disable-start(calls-loop, require-revert-in-loop, incorrect-strict-equality)
    /// @inheritdoc IERC20ForwarderMigration
    function migrate(IERC20[] calldata tokens) external override nonReentrant onlyOwner {
        uint256 count = tokens.length;
        for (uint256 i = 0; i < count; ++i) {
            IERC20 token = tokens[i];
            uint128 amount = SafeCast.toUint128(token.balanceOf(address(FORWARDER_V1)));
            if (amount == 0) continue;

            uint256 beforeV2 = token.balanceOf(FORWARDER_V2);
            bytes memory output = FORWARDER_V1.forwardEmergencyCall(
                abi.encode(ERC20Forwarder.CallType.Unwrap, token, amount, FORWARDER_V2)
            );
            require(
                output.length == 0 && token.balanceOf(address(FORWARDER_V1)) == 0
                    && token.balanceOf(FORWARDER_V2) == beforeV2 + amount,
                IncompleteMigration(address(token))
            );
            emit ERC20TokenMigrated(address(FORWARDER_V1), FORWARDER_V2, address(token), amount);
        }
    }

    // forge-lint: disable-end(calls-loop, require-revert-in-loop, incorrect-strict-equality)

    // slither-disable-end calls-loop,reentrancy-balance,incorrect-equality

    /// @notice Ownership can be transferred but cannot be removed.
    function renounceOwnership() public view override onlyOwner {
        revert RenunciationDisabled();
    }
}
