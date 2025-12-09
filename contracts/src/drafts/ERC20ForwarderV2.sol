// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICommitmentTree} from "@anoma-evm-pa/interfaces/ICommitmentTree.sol";
import {INullifierSet} from "@anoma-evm-pa/interfaces/INullifierSet.sol";
import {NullifierSet} from "@anoma-evm-pa/state/NullifierSet.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import {ERC20Forwarder} from "../ERC20Forwarder.sol";

/// @title ERC20ForwarderV2
/// @author Anoma Foundation, 2025
/// @notice The ERC20 token forwarder contract v2 allowing to
/// - wrap ERC20 tokens into resources using Uniswap's Permit2,
/// - unwrap ERC20 tokens from resources, and
/// - migrate ERC20 resources from the ERC20 forwarder v1.
/// @custom:security-contact security@anoma.foundation
contract ERC20ForwarderV2 is ERC20Forwarder, NullifierSet {
    enum CallTypeV2 {
        Wrap,
        Unwrap,
        MigrateV1
    }

    ERC20Forwarder internal immutable _ERC20_FORWARDER_V1;
    address internal immutable _PROTOCOL_ADAPTER_V1;
    bytes32 internal immutable _COMMITMENT_TREE_ROOT_V1;
    bytes32 internal immutable _LOGIC_REFERENCE_V1;

    error ResourceAlreadyConsumed(bytes32 nullifier);

    error InvalidMigrationCommitmentTreeRootV1(bytes32 expected, bytes32 actual);
    error InvalidMigrationLogicRefV1(bytes32 expected, bytes32 actual);
    error InvalidForwarderV1(address expected, address actual);

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapterV2 The protocol adapter v2 that can forward calls.
    /// @param logicRefV2 The reference to the logic function of the resource v2 triggering the forward calls.
    /// @param emergencyCommittee The emergency committee address that is allowed to set the emergency caller if the
    /// RISC Zero verifier has been stopped.
    /// @param erc20ForwarderV1 The ERC20 forwarder v1 connected to the protocol adapter v1 that has been stopped.
    constructor(
        address protocolAdapterV2,
        bytes32 logicRefV2,
        address emergencyCommittee,
        ERC20Forwarder erc20ForwarderV1
    ) ERC20Forwarder(protocolAdapterV2, logicRefV2, emergencyCommittee) {
        if (address(erc20ForwarderV1) == address(0)) {
            revert ZeroNotAllowed();
        }

        _ERC20_FORWARDER_V1 = erc20ForwarderV1;
        _PROTOCOL_ADAPTER_V1 = erc20ForwarderV1.getProtocolAdapter();
        _COMMITMENT_TREE_ROOT_V1 = ICommitmentTree(_PROTOCOL_ADAPTER_V1).latestCommitmentTreeRoot();
        _LOGIC_REFERENCE_V1 = erc20ForwarderV1.getLogicRef();
    }

    // slither-disable-start dead-code /* NOTE: This code is not dead and falsely flagged as such by slither. */

    /// @notice Forwards a call wrapping, unwrapping, or migrating ERC20 tokens based on the provided input.
    /// @param input Contains data to
    /// - wrap ERC20 tokens into resources using Uniswap's Permit2,
    /// - unwrap ERC20 tokens from resources, and
    /// - migrate ERC20 resources from the ERC20 forwarder v1.
    /// @return output The empty string signaling that the function call has succeeded.
    function _forwardCall(bytes calldata input) internal virtual override returns (bytes memory output) {
        (CallTypeV2 callType, IERC20 token, uint128 amount) =
            abi.decode(input[:_GENERIC_INPUT_OFFSET], (CallTypeV2, IERC20, uint128));

        bytes calldata specificInput = input[_GENERIC_INPUT_OFFSET:];

        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 balanceDelta = 0;

        if (callType == CallTypeV2.Wrap) {
            _wrap({token: address(token), amount: amount, wrapInput: specificInput});
            balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        } else if (callType == CallTypeV2.Unwrap) {
            _unwrap({token: address(token), amount: amount, unwrapInput: specificInput});
            balanceDelta = balanceBefore - token.balanceOf(address(this));
        } else {
            _migrateV1({token: address(token), amount: amount, migrateV1Input: specificInput});
            balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        }

        if (balanceDelta != amount) {
            revert BalanceMismatch({expected: amount, actual: balanceDelta});
        }

        output = "";
    }

    /// @notice Migrates ERC20 resources by transferring ERC20 tokens from the ERC20 forwarder v1 and storing the
    /// associated nullifier.
    /// @param token The address of the token to be transferred.
    /// @param amount The amount to be transferred.
    /// @param migrateV1Input The input bytes containing the encoded arguments for the v1 migration call:
    /// * `nullifier`: The nullifier of the resource to be migrated.
    /// * `rootV1`: The root of the commitment tree that must be the latest root of the stopped protocol adapter v1.
    /// * `logicRefV1`: The logic reference that must match the ERC20 forwarder v1 contract.
    /// * `forwarderV1`: The ERC20 forwarder v1 contract address that must match the one set in this contract.
    function _migrateV1(address token, uint128 amount, bytes calldata migrateV1Input) internal virtual {
        (bytes32 nullifier, bytes32 rootV1, bytes32 logicRefV1, address forwarderV1) =
            abi.decode(migrateV1Input, (bytes32, bytes32, bytes32, address));

        // Check that the resource being upgraded is not in the protocol adapter v1 nullifier set.
        if (INullifierSet(_PROTOCOL_ADAPTER_V1).isNullifierContained(nullifier)) {
            revert ResourceAlreadyConsumed(nullifier);
        }

        // Add the nullifier to the this contract's nullifier set. The call will revert if the nullifier already exists.
        _addNullifier(nullifier);

        // Check that the root matches the final protocol adapter V1 commitment tree root.
        if (rootV1 != _COMMITMENT_TREE_ROOT_V1) {
            revert InvalidMigrationCommitmentTreeRootV1({expected: _COMMITMENT_TREE_ROOT_V1, actual: rootV1});
        }

        // Check that logicRef matches the logic reference associated with the ERC20 forwarder v1.
        if (logicRefV1 != _LOGIC_REFERENCE_V1) {
            revert InvalidMigrationLogicRefV1({expected: _LOGIC_REFERENCE_V1, actual: logicRefV1});
        }

        // Check that forwarder matches the ERC20 forwarder v1.
        if (forwarderV1 != address(_ERC20_FORWARDER_V1)) {
            revert InvalidForwarderV1({expected: address(_ERC20_FORWARDER_V1), actual: forwarderV1});
        }

        // Emit the `Wrapped` event indicating that ERC20 tokens have been deposited from the ERC20 forwarder v1.
        emit ERC20Forwarder.Wrapped({token: token, from: address(_ERC20_FORWARDER_V1), amount: amount});

        // Forwards a call to transfer the ERC20 tokens from the ERC20 forwarder v1 to this contract.
        // This emits the `Unwrapped` event on the ERC20 forwarder v1 contract indicating that funds have been
        // withdrawn and the `Transfer` event on the ERC20 token.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V1.forwardEmergencyCall(abi.encode(CallType.Unwrap, token, amount, address(this)));
    }

    // slither-disable-end dead-code
}
