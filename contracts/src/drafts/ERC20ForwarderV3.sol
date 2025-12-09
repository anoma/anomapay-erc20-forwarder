// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICommitmentTree} from "@anoma-evm-pa/interfaces/ICommitmentTree.sol";
import {INullifierSet} from "@anoma-evm-pa/interfaces/INullifierSet.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import {ERC20Forwarder} from "../ERC20Forwarder.sol";
import {ERC20ForwarderV2} from "./ERC20ForwarderV2.sol";

/// @title ERC20ForwarderV2
/// @author Anoma Foundation, 2025
/// @notice The ERC20 token forwarder contract v3 allowing to
/// - wrap ERC20 tokens into resources using Uniswap's Permit2,
/// - unwrap ERC20 tokens from resources, and
/// - migrate ERC20 resources from the ERC20 forwarder v1 and v2.
/// @custom:security-contact security@anoma.foundation
contract ERC20ForwarderV3 is ERC20ForwarderV2 {
    enum CallTypeV3 {
        Wrap,
        Unwrap,
        MigrateV1,
        MigrateV2
    }

    /// @notice A struct containing wrap specific inputs.
    /// @param nullifier The nullifier of the resource to be migrated.
    /// @param rootV2 The root of the commitment tree that must be the latest root of the stopped protocol adapter v2.
    /// @param logicRefV2 The logic reference that must match the ERC20 forwarder v2 contract.
    /// @param forwarderV2  The ERC20 forwarder v2 contract address that must match the one set in this contract.
    struct MigrateV2Data {
        bytes32 nullifier;
        bytes32 rootV2;
        bytes32 logicRefV2;
        address forwarderV2;
    }

    ERC20ForwarderV2 internal immutable _ERC20_FORWARDER_V2;
    address internal immutable _PROTOCOL_ADAPTER_V2;
    bytes32 internal immutable _COMMITMENT_TREE_ROOT_V2;
    bytes32 internal immutable _LOGIC_REFERENCE_V2;

    error InvalidMigrationCommitmentTreeRootV2(bytes32 expected, bytes32 actual);
    error InvalidMigrationLogicRefV2(bytes32 expected, bytes32 actual);
    error InvalidForwarderV2(address expected, address actual);

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapterV3 The protocol adapter v3 that can forward calls.
    /// @param logicRefV3 The reference to the logic function of the resource v3 triggering the forward calls.
    /// @param emergencyCommittee The emergency committee address that is allowed to set the emergency caller if the
    /// RISC Zero verifier has been stopped.
    /// @param erc20ForwarderV1 The ERC20 forwarder v1 connected to the protocol adapter v1 that has been stopped.
    /// @param erc20ForwarderV2 The ERC20 forwarder v2 connected to the protocol adapter v2 that has been stopped.
    constructor(
        address protocolAdapterV3,
        bytes32 logicRefV3,
        address emergencyCommittee,
        ERC20Forwarder erc20ForwarderV1,
        ERC20ForwarderV2 erc20ForwarderV2
    ) ERC20ForwarderV2(protocolAdapterV3, logicRefV3, emergencyCommittee, erc20ForwarderV1) {
        if (address(erc20ForwarderV2) == address(0)) {
            revert ZeroNotAllowed();
        }
        _ERC20_FORWARDER_V2 = erc20ForwarderV2;
        _PROTOCOL_ADAPTER_V2 = erc20ForwarderV2.getProtocolAdapter();
        _COMMITMENT_TREE_ROOT_V2 = ICommitmentTree(_PROTOCOL_ADAPTER_V1).latestCommitmentTreeRoot();
        _LOGIC_REFERENCE_V2 = erc20ForwarderV2.getLogicRef();
    }

    /// @notice Forwards a call wrapping, unwrapping, or migrating ERC20 tokens based on the provided input.
    /// @param input Contains data to
    /// - wrap ERC20 tokens into resources using Uniswap's Permit2,
    /// - unwrap ERC20 tokens from resources, and
    /// - migrate ERC20 resources from the ERC20 forwarder v1.
    /// - migrate ERC20 resources from the ERC20 forwarder v2.
    /// @return output The empty string signaling that the function call has succeeded.
    function _forwardCall(bytes calldata input) internal virtual override returns (bytes memory output) {
        (CallTypeV3 callType, IERC20 token, uint128 amount) =
            abi.decode(input[:_GENERIC_INPUT_OFFSET], (CallTypeV3, IERC20, uint128));

        bytes calldata specificInput = input[_GENERIC_INPUT_OFFSET:];

        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 balanceDelta = 0;

        if (callType == CallTypeV3.Wrap) {
            _wrap({token: address(token), amount: amount, wrapInput: specificInput});
            balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        } else if (callType == CallTypeV3.Unwrap) {
            _unwrap({token: address(token), amount: amount, unwrapInput: specificInput});
            balanceDelta = balanceBefore - token.balanceOf(address(this));
        } else if (callType == CallTypeV3.MigrateV1) {
            _migrateV1({token: address(token), amount: amount, migrateV1Input: specificInput});
            balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        } else {
            _migrateV2({token: address(token), amount: amount, migrateV2Input: specificInput});
            balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        }

        if (balanceDelta != amount) {
            revert BalanceMismatch({expected: amount, actual: balanceDelta});
        }

        output = "";
    }

    /// @notice Migrates ERC20 resources by transferring ERC20 tokens from the ERC20 forwarder v2 and storing the
    /// associated nullifier.
    /// @param token The address of the token to be transferred.
    /// @param amount The amount to be transferred.
    /// @param migrateV1Input The input bytes containing the encoded arguments for to migrate v1 resources.
    function _migrateV1(address token, uint128 amount, bytes calldata migrateV1Input) internal virtual override {
        (MigrateV1Data memory data) = abi.decode(migrateV1Input, (MigrateV1Data));

        // Emit the `Wrapped` event indicating that ERC20 tokens have been deposited from the ERC20 forwarder v2.
        emit ERC20Forwarder.Wrapped({token: token, from: address(_ERC20_FORWARDER_V2), amount: amount});

        // Forwards a call to migrate ERC20 v1 tokens via the ERC20 forwarder v1.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V2.forwardEmergencyCall({
            input: abi.encode(
                CallTypeV2.MigrateV1, token, amount, data.nullifier, data.rootV1, data.logicRefV1, data.forwarderV1
            )
        });

        // Forwards a call to transfer the ERC20 tokens from the ERC20 forwarder v2 to this contract.
        // This emits the `Unwrapped` event on the ERC20 forwarder v2 contract indicating that funds have been withdrawn
        // and the `Transfer` event on the ERC20 token.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V2.forwardEmergencyCall({input: abi.encode(CallType.Unwrap, token, amount, address(this))});
    }

    /// @notice Migrates ERC20 v2 resources by transferring ERC20 tokens from the ERC20 forwarder v1 and storing the
    /// associated nullifier.
    /// @param token The address of the token to be transferred.
    /// @param amount The amount to be transferred.
    /// @param migrateV2Input The input bytes containing the encoded arguments for to migrate v2 resources.
    function _migrateV2(address token, uint128 amount, bytes calldata migrateV2Input) internal virtual {
        (MigrateV2Data memory data) = abi.decode(migrateV2Input, (MigrateV2Data));

        // Check that the resource being upgraded is not in the protocol adapter v2 nullifier set.
        if (INullifierSet(_PROTOCOL_ADAPTER_V2).isNullifierContained(data.nullifier)) {
            revert ResourceAlreadyConsumed(data.nullifier);
        }

        // Add the nullifier to the this contract's nullifier set. The call will revert if the nullifier already exists.
        _addNullifier(data.nullifier);

        // Check that the root matches the final protocol adapter v2 commitment tree root.
        if (data.rootV2 != _COMMITMENT_TREE_ROOT_V2) {
            revert InvalidMigrationCommitmentTreeRootV2({expected: _COMMITMENT_TREE_ROOT_V2, actual: data.rootV2});
        }

        // Check that logicRef matches the logic reference associated with the ERC20 forwarder v2.
        if (data.logicRefV2 != _LOGIC_REFERENCE_V2) {
            revert InvalidMigrationLogicRefV2({expected: _LOGIC_REFERENCE_V2, actual: data.logicRefV2});
        }

        // Check that forwarder matches the ERC20 forwarder v2.
        if (data.forwarderV2 != address(_ERC20_FORWARDER_V2)) {
            revert InvalidForwarderV2({expected: address(_ERC20_FORWARDER_V2), actual: data.forwarderV2});
        }

        // Emit the `Wrapped` event indicating that ERC20 tokens have been deposited from the ERC20 forwarder v2.
        emit ERC20Forwarder.Wrapped({token: address(token), from: address(_ERC20_FORWARDER_V2), amount: amount});

        // Forwards the call to transfer the ERC20 tokens from the ERC20 forwarder v2 to this contract.
        // This emits the `Unwrapped` event on the ERC20 forwarder v2 contract indicating that funds have been withdrawn
        // and the `Transfer` event on the ERC20 token.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V2.forwardEmergencyCall(abi.encode(CallType.Unwrap, token, amount, address(this)));
    }
}
