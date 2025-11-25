// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {NullifierSet} from "@anoma-evm-pa/state/NullifierSet.sol";

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
        Unwrap,
        Wrap,
        Migrate
    }

    address internal immutable _PROTOCOL_ADAPTER_V1;
    ERC20Forwarder internal immutable _ERC20_FORWARDER_V1;

    error NullifierAlreadyMigrated(bytes32 nullifier);

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapter The protocol adapter contract that is allowed to forward calls.
    /// @param calldataCarrierLogicRef The resource logic function of the calldata carrier resource.
    /// @param emergencyCommittee The emergency committee address that is allowed to set the emergency caller if the
    /// RISC Zero verifier has been stopped.
    /// @param protocolAdapterV1 The stopped protocol adapter address.
    /// @param erc20ForwarderV1 The forwarder address connected to the stopped PA.
    constructor(
        address protocolAdapter,
        bytes32 calldataCarrierLogicRef,
        address emergencyCommittee,
        address protocolAdapterV1,
        address erc20ForwarderV1
    )
        ERC20Forwarder(
            protocolAdapter,
            calldataCarrierLogicRef,
            emergencyCommittee
        )
    {
        if (protocolAdapterV1 == address(0) || erc20ForwarderV1 == address(0)) {
            revert ZeroNotAllowed();
        }

        _PROTOCOL_ADAPTER_V1 = protocolAdapterV1;
        _ERC20_FORWARDER_V1 = ERC20Forwarder(erc20ForwarderV1);
    }

    /// @notice Forwards a call wrapping, unwrapping, or migrating ERC20 tokens based on the provided input.
    /// @param input Contains data to
    /// - wrap ERC20 tokens into resources using Uniswap's Permit2,
    /// - unwrap ERC20 tokens from resources, and
    /// - migrate ERC20 resources from the ERC20 forwarder v1.
    /// @return output The empty string signaling that the function call has succeeded.
    function _forwardCall(
        bytes calldata input
    ) internal override returns (bytes memory output) {
        CallTypeV2 callType = CallTypeV2(uint8(input[31]));

        if (callType == CallTypeV2.Wrap) {
            _wrap(input);
        } else if (callType == CallTypeV2.Unwrap) {
            _unwrap(input);
        } else {
            _migrate(input);
        }

        output = "";
    }

    /// @notice Migrates ERC20 resources by transferring ERC20 tokens from the ERC20 forwarder v1 and storing the
    /// associated nullifier.
    /// @param input The input bytes containing the encoded arguments for the migration call:
    /// * The `CallTypeV2.Migrate` enum value that has been checked already and is therefore unused.
    /// * `nullifier`: The nullifier of the resource to be migrated.
    /// * `token`: The address of the token to migrated.
    /// * `amount`: The amount to be migrated.
    function _migrate(bytes calldata input) internal {
        (
            ,
            // CallTypeV2.Migrate
            address token,
            uint128 amount,
            bytes32 nullifier
        ) = abi.decode(input, (CallTypeV2, address, uint128, bytes32));

        // Check that the resource being upgraded is not in the previous protocol adapter's nullifier set.
        if (
            NullifierSet(_PROTOCOL_ADAPTER_V1).isNullifierContained(nullifier)
        ) {
            revert NullifierAlreadyMigrated(nullifier);
        }

        // Add the nullifier to the this contract's nullifier set. The call will revert if the nullifier already exists.
        _addNullifier(nullifier);

        // Emit the `Wrapped` event indicating that ERC20 tokens have been deposited from the ERC20 forwarder v1.
        emit ERC20Forwarder.Wrapped({
            token: token,
            from: address(_ERC20_FORWARDER_V1),
            amount: amount
        });

        // Forwards the call to transfer the ERC20 tokens from the ERC20 forwarder v1 to this contract.
        // This emits the `Unwrapped` event on the ERC20 forwarder v1 contract indicating that funds have been withdrawn
        // and the `Transfer` event on the ERC20 token.
        // slither-disable-next-line unused-return
        _ERC20_FORWARDER_V1.forwardEmergencyCall({
            input: abi.encode(CallType.Unwrap, token, address(this), amount)
        });
    }
}
