// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {IPermit2, ISignatureTransfer} from "@permit2/src/interfaces/IPermit2.sol";

import {EmergencyMigratableForwarderBase} from "./bases/EmergencyMigratableForwarderBase.sol";
import {ERC20ForwarderPermit2} from "./ERC20ForwarderPermit2.sol";

/// @title ERC20Forwarder
/// @author Anoma Foundation, 2025
/// @notice The ERC20 token forwarder contract allowing to
/// - wrap ERC20 tokens into ERC20 resources using Uniswap's Permit2 and
/// - unwrap ERC20 tokens from ERC20 resources.
/// @custom:security-contact security@anoma.foundation
contract ERC20Forwarder is EmergencyMigratableForwarderBase {
    using ERC20ForwarderPermit2 for ERC20ForwarderPermit2.Witness;
    using SafeERC20 for IERC20;

    enum CallType {
        Wrap,
        Unwrap
    }

    /// @notice A struct containing wrap specific inputs.
    /// @param nonce A unique value to prevent signature replays.
    /// @param deadline The deadline of the permit signature.
    /// @param owner The owner from which the funds a transferred from and signer of the Permit2 message.
    /// @param witness The action tree root that was signed over in addition to the permit data.
    /// @param r The ECDSA signature component `r` of the Permit2 signature.
    /// @param s The ECDSA signature component `s` of the Permit2 signature.
    /// @param v The ECDSA recovery identifier (27 or 28) of the Permit2 signature.
    // solhint-disable-next-line gas-struct-packing
    struct WrapData {
        uint256 nonce;
        uint256 deadline;
        address owner;
        bytes32 actionTreeRoot;
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /// @notice A struct containing unwrap specific inputs.
    /// @param receiver The receiving account address.
    struct UnwrapData {
        address receiver;
    }

    /// @notice The offset for the calltype specific input data (3 slots).
    // slither-disable-next-line unused-state
    uint256 internal constant _GENERIC_INPUT_OFFSET = 3 * 32;

    /// @notice The canonical Uniswap Permit2 contract being deployed at the same address on all supported chains.
    /// (see [Uniswap's announcement](https://blog.uniswap.org/permit2-and-universal-router)).
    IPermit2 internal constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /// @notice Emitted when ERC20 tokens get wrapped.
    /// @param token The ERC20 token address.
    /// @param from The address from which tokens were withdrawn.
    /// @param amount The token amount being deposited into the ERC20 forwarder contract.
    event Wrapped(address indexed token, address indexed from, uint128 amount);

    /// @notice Emitted when ERC20 tokens get unwrapped.
    /// @param token The ERC20 token address.
    /// @param to The address to which tokens were deposited.
    /// @param amount The token amount being withdrawn from the ERC20 forwarder contract.
    event Unwrapped(address indexed token, address indexed to, uint128 amount);

    error BalanceMismatch(uint256 expected, uint256 actual);

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the logic function of the resource kind triggering the forward call.
    /// @param emergencyCommittee The emergency committee address that is allowed to set the emergency caller if the
    /// RISC Zero verifier has been stopped.
    constructor(address protocolAdapter, bytes32 logicRef, address emergencyCommittee)
        EmergencyMigratableForwarderBase(protocolAdapter, logicRef, emergencyCommittee)
    {}

    // slither-disable-start dead-code /* NOTE: This code is not dead and falsely flagged as such by slither. */

    /// @notice Forwards a call wrapping or unwrapping ERC20 tokens based on the provided input.
    /// @param input Contains data to
    /// - wrap ERC20 tokens into resources using Uniswap Permit2 and
    /// - unwrap ERC20 tokens from resources
    /// @return output The empty string signaling that the function call has succeeded.
    function _forwardCall(bytes calldata input) internal virtual override returns (bytes memory output) {
        (CallType callType, IERC20 token, uint128 amount) =
            abi.decode(input[:_GENERIC_INPUT_OFFSET], (CallType, IERC20, uint128));

        bytes calldata specificInput = input[_GENERIC_INPUT_OFFSET:];

        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 balanceDelta = 0;

        if (callType == CallType.Wrap) {
            _wrap({token: address(token), amount: amount, wrapInput: specificInput});
            balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        } else {
            _unwrap({token: address(token), amount: amount, unwrapInput: specificInput});
            balanceDelta = balanceBefore - token.balanceOf(address(this));
        }

        if (balanceDelta != amount) {
            revert BalanceMismatch({expected: amount, actual: balanceDelta});
        }

        output = "";
    }

    // slither-disable-end dead-code

    /// @notice Wraps an ERC20 token and transfers funds from the user that must have authorized the call using
    /// `Permit2.permitWitnessTransferFrom`.
    /// @param token The address of the token to be transferred.
    /// @param amount The amount to be transferred.
    /// @param wrapInput The input bytes containing the encoded arguments specific for the wrap call.
    function _wrap(address token, uint128 amount, bytes calldata wrapInput) internal {
        (WrapData memory data) = abi.decode(wrapInput, (WrapData));

        emit Wrapped({token: token, from: data.owner, amount: amount});

        _PERMIT2.permitWitnessTransferFrom({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
                nonce: data.nonce,
                deadline: data.deadline
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({to: address(this), requestedAmount: amount}),
            owner: data.owner,
            witness: ERC20ForwarderPermit2.Witness({actionTreeRoot: data.actionTreeRoot}).hash(),
            witnessTypeString: ERC20ForwarderPermit2._WITNESS_TYPE_STRING,
            signature: abi.encodePacked(data.r, data.s, data.v)
        });
    }

    /// @notice Unwraps an ERC20 token and transfers funds to the recipient using the `SafeERC20.safeTransfer`.
    /// @param token The address of the token to be transferred.
    /// @param amount The amount to be transferred.
    /// @param unwrapInput The input bytes containing the encoded arguments for the unwrap call.
    function _unwrap(address token, uint128 amount, bytes calldata unwrapInput) internal {
        (UnwrapData memory data) = abi.decode(unwrapInput, (UnwrapData));

        emit Unwrapped({token: address(token), to: data.receiver, amount: amount});

        IERC20(token).safeTransfer({to: data.receiver, value: amount});
    }

    /// @notice Forwards an emergency call wrapping or unwrapping ERC20 tokens based on the provided input.
    /// @param input Contains data to withdraw or send ERC20 tokens from or to a user, respectively.
    /// @return output The output of the emergency call.
    /// @dev This function internally uses the `SafeERC20` library.
    function _forwardEmergencyCall(bytes calldata input) internal override returns (bytes memory output) {
        output = _forwardCall(input);
    }
}
