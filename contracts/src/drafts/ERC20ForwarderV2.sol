// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.5.0/token/ERC20/IERC20.sol";
import {ICommitmentTree} from "anoma-pa-evm-1.0.0-rc.8/src/interfaces/ICommitmentTree.sol";
import {INullifierSet} from "anoma-pa-evm-1.0.0-rc.8/src/interfaces/INullifierSet.sol";
import {IProtocolAdapter} from "anoma-pa-evm-1.0.0-rc.8/src/interfaces/IProtocolAdapter.sol";
import {NullifierSet} from "anoma-pa-evm-1.0.0-rc.8/src/state/NullifierSet.sol";

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

    /// @notice A struct containing specific inputs to migrate from v1.
    /// @param nullifier The nullifier of the resource to be migrated.
    /// @param rootV1 The root of the commitment tree that must be the latest root of the stopped protocol adapter v1.
    /// @param logicRefV1 The logic reference that must match the ERC20 forwarder v1 contract.
    /// @param forwarderV1  The ERC20 forwarder v1 contract address that must match the one set in this contract.
    struct MigrateV1Data {
        bytes32 nullifier;
        bytes32 rootV1;
        bytes32 logicRefV1;
        address forwarderV1;
    }

    /// @notice The length of the migrate v1 data.
    uint256 internal constant _MIGRATE_V1_DATA_LENGTH = 4 * 32;

    ERC20Forwarder internal immutable _ERC20_FORWARDER_V1;
    address internal immutable _PROTOCOL_ADAPTER_V1;
    bytes32 internal immutable _COMMITMENT_TREE_ROOT_V1;
    bytes32 internal immutable _LOGIC_REFERENCE_V1;

    error ResourceAlreadyConsumed(bytes32 nullifier);

    error InvalidMigrationCommitmentTreeRootV1(bytes32 expected, bytes32 actual);
    error InvalidMigrationLogicRefV1(bytes32 expected, bytes32 actual);
    error InvalidForwarderV1(address expected, address actual);
    error UnstoppedProtocolAdapterV1(address protocolAdapterV1);

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapterV2 The protocol adapter v2 that can forward calls.
    /// @param logicRefV2 The reference to the logic function of the resource v2 triggering the forward calls.
    /// @param emergencyCommittee The emergency committee that can set the emergency caller if the protocol adapter v2
    /// has been stopped.
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

        // Check that the protocol adapter v1 is stopped before capturing the final commitment tree root.
        if (!IProtocolAdapter(_PROTOCOL_ADAPTER_V1).isEmergencyStopped()) {
            revert UnstoppedProtocolAdapterV1({protocolAdapterV1: _PROTOCOL_ADAPTER_V1});
        }

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
    /// @param token The address of the token to be migrated.
    /// @param amount The amount to be migrated.
    /// @param migrateV1Input The input bytes containing the encoded arguments for to migrate v1 resources.
    function _migrateV1(address token, uint128 amount, bytes calldata migrateV1Input) internal virtual {
        _checkLength({input: migrateV1Input, expectedLength: _MIGRATE_V1_DATA_LENGTH});

        (MigrateV1Data memory data) = abi.decode(migrateV1Input, (MigrateV1Data));

        // Check that the resource being upgraded is not in the protocol adapter v1 nullifier set.
        if (INullifierSet(_PROTOCOL_ADAPTER_V1).isNullifierContained(data.nullifier)) {
            revert ResourceAlreadyConsumed(data.nullifier);
        }

        // Add the nullifier to the this contract's nullifier set. The call will revert if the nullifier already exists.
        _addNullifier(data.nullifier);

        // Check that the root matches the final protocol adapter V1 commitment tree root.
        if (data.rootV1 != _COMMITMENT_TREE_ROOT_V1) {
            revert InvalidMigrationCommitmentTreeRootV1({expected: _COMMITMENT_TREE_ROOT_V1, actual: data.rootV1});
        }

        // Check that logicRef matches the logic reference associated with the ERC20 forwarder v1.
        if (data.logicRefV1 != _LOGIC_REFERENCE_V1) {
            revert InvalidMigrationLogicRefV1({expected: _LOGIC_REFERENCE_V1, actual: data.logicRefV1});
        }

        // Check that forwarder matches the ERC20 forwarder v1.
        if (data.forwarderV1 != address(_ERC20_FORWARDER_V1)) {
            revert InvalidForwarderV1({expected: address(_ERC20_FORWARDER_V1), actual: data.forwarderV1});
        }

        // Emit the `Wrapped` event indicating that ERC20 tokens have been deposited from the ERC20 forwarder v1.
        emit ERC20Forwarder.Wrapped({token: token, from: address(_ERC20_FORWARDER_V1), amount: amount});

        // Forwards a call to transfer the ERC20 tokens from the ERC20 forwarder v1 to this contract.
        // This emits the `Unwrapped` event on the ERC20 forwarder v1 contract indicating that funds have been withdrawn
        // and the `Transfer` event on the ERC20 token.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V1.forwardEmergencyCall(
            abi.encode(CallType.Unwrap, token, amount, UnwrapData({receiver: address(this)}))
        );
    }

    // slither-disable-end dead-code
}
