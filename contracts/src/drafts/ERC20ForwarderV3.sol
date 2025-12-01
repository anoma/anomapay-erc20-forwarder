// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICommitmentTree} from "@anoma-evm-pa/interfaces/ICommitmentTree.sol";
import {INullifierSet} from "@anoma-evm-pa/interfaces/INullifierSet.sol";

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

    ERC20ForwarderV2 internal immutable _ERC20_FORWARDER_V2;
    address internal immutable _PROTOCOL_ADAPTER_V2;
    bytes32 internal immutable _COMMITMENT_TREE_ROOT_V2;
    bytes32 internal immutable _LOGIC_REFERENCE_V2;

    error InvalidMigrationCommitmentTreeRootV2(bytes32 expected, bytes32 actual);
    error InvalidMigrationLogicRefV2(bytes32 expected, bytes32 actual);
    error InvalidMigrationLabelRefV2(bytes32 expected, bytes32 actual);

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
        CallTypeV3 callType = CallTypeV3(uint8(input[31]));

        if (callType == CallTypeV3.Wrap) {
            _wrap(input);
        } else if (callType == CallTypeV3.Unwrap) {
            _unwrap(input);
        } else if (callType == CallTypeV3.MigrateV1) {
            _migrateV1(input);
        } else {
            _migrateV2(input);
        }

        output = "";
    }

    /// @notice Migrates ERC20 resources by transferring ERC20 tokens from the ERC20 forwarder v2 and storing the
    /// associated nullifier.
    /// @param input The input bytes containing the encoded arguments for the migration call:
    /// * The `CallTypeV2.MigrateV1` enum value that has been checked already and is therefore unused.
    /// * `nullifier`: The nullifier of the resource to be migrated.
    /// * `token`: The address of the token to migrated.
    /// * `amount`: The amount to be migrated.
    function _migrateV1(bytes calldata input) internal virtual override {
        (,
            // CallTypeV3.MigrateV1
            address token,
            uint128 amount,
            bytes32 nullifier,
            bytes32 root,
            bytes32 logicRef,
            bytes32 labelRef
        ) = abi.decode(input, (CallTypeV3, address, uint128, bytes32, bytes32, bytes32, bytes32));

        // Emit the `Wrapped` event indicating that ERC20 tokens have been deposited from the ERC20 forwarder v2.
        emit ERC20Forwarder.Wrapped({token: token, from: address(_ERC20_FORWARDER_V2), amount: amount});

        // Forwards a call to migrate ERC20 v1 tokens via the ERC20 forwarder v1.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V2.forwardEmergencyCall({
            input: abi.encode(CallTypeV2.MigrateV1, token, amount, nullifier, root, logicRef, labelRef)
        });

        // Forwards a call to transfer the ERC20 tokens from the ERC20 forwarder v2 to this contract.
        // This emits the `Unwrapped` event on the ERC20 forwarder v2 contract indicating that funds have been withdrawn
        // and the `Transfer` event on the ERC20 token.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V2.forwardEmergencyCall({input: abi.encode(CallType.Unwrap, token, address(this), amount)});
    }

    /// @notice Migrates ERC20 v2 resources by transferring ERC20 tokens from the ERC20 forwarder v1 and storing the
    /// associated nullifier.
    /// @param input The input bytes containing the encoded arguments for the migration call:
    /// * The `CallTypeV3.MigrateV2` enum value that has been checked already and is therefore unused.
    /// * `nullifier`: The nullifier of the resource to be migrated.
    /// * `token`: The address of the token to migrated.
    /// * `amount`: The amount to be migrated.
    function _migrateV2(bytes calldata input) internal virtual {
        (,
            // CallTypeV3.MigrateV2
            address token,
            uint128 amount,
            bytes32 nullifier,
            bytes32 root,
            bytes32 logicRef,
            bytes32 labelRef
        ) = abi.decode(input, (CallTypeV3, address, uint128, bytes32, bytes32, bytes32, bytes32));

        // Check that the resource being upgraded is not in the protocol adapter v2 nullifier set.
        if (INullifierSet(_PROTOCOL_ADAPTER_V2).isNullifierContained(nullifier)) {
            revert ResourceAlreadyConsumed(nullifier);
        }

        // Add the nullifier to the this contract's nullifier set. The call will revert if the nullifier already exists.
        _addNullifier(nullifier);

        // Check that the root matches the final PA V2 commitment tree root.
        if (root != _COMMITMENT_TREE_ROOT_V2) {
            revert InvalidMigrationCommitmentTreeRootV2({expected: _COMMITMENT_TREE_ROOT_V2, actual: root});
        }

        // Check that logicRef matches with ERC20ForwarderV2.
        if (logicRef != _LOGIC_REFERENCE_V2) {
            revert InvalidMigrationLogicRefV2({expected: _LOGIC_REFERENCE_V2, actual: logicRef});
        }

        bytes32 expectedLabelRef = sha256(abi.encode(address(_ERC20_FORWARDER_V2), token));

        // Check that the labelRef is as expected so that the forwarder matches.
        if (expectedLabelRef != labelRef) {
            revert InvalidMigrationLabelRefV2({expected: expectedLabelRef, actual: labelRef});
        }

        // Emit the `Wrapped` event indicating that ERC20 tokens have been deposited from the ERC20 forwarder v2.
        emit ERC20Forwarder.Wrapped({token: token, from: address(_ERC20_FORWARDER_V2), amount: amount});

        // Forwards the call to transfer the ERC20 tokens from the ERC20 forwarder v2 to this contract.
        // This emits the `Unwrapped` event on the ERC20 forwarder v2 contract indicating that funds have been withdrawn
        // and the `Transfer` event on the ERC20 token.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V2.forwardEmergencyCall({input: abi.encode(CallType.Unwrap, token, address(this), amount)});
    }
}
