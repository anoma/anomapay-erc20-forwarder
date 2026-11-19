// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {ForwarderBaseUpgradeable} from "anoma-forwarder-bases-3.1.0/src/ForwarderBaseUpgradeable.sol";
import {IVersion} from "anoma-forwarder-bases-3.1.0/src/interfaces/IVersion.sol";
import {ILogicRefDenylist} from "anoma-pa-evm-2.0.0-rc.16/src/interfaces/ILogicRefDenylist.sol";
import {
    IPermit2,
    ISignatureTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IPermit2.sol";

import {ERC20ForwarderPermit2} from "../ERC20ForwarderPermit2.sol";

/// @title ERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice A draft of version 2.1.0 of the ERC20 token forwarder contract, to which the 2.0.0 proxies upgrade. It
/// - wraps ERC20 tokens into ERC20 resources using Uniswap's Permit2, with a Permit2 signature of any length, and
/// - unwraps ERC20 tokens from ERC20 resources.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from src/ERC20Forwarder.sol:ERC20Forwarder
contract ERC20Forwarder is IVersion, ForwarderBaseUpgradeable {
    using ERC20ForwarderPermit2 for ERC20ForwarderPermit2.Witness;
    using SafeERC20 for IERC20;

    /// @notice The call types that the forwarder accepts.
    enum CallType {
        Wrap,
        Unwrap
    }

    /// @notice A struct containing wrap specific inputs.
    /// @param nonce A unique value to prevent signature replays.
    /// @param deadline The deadline of the permit signature.
    /// @param owner The account that signs the Permit2 message and from which Permit2 transfers the tokens.
    /// @param actionTreeRoot The action tree root that the owner signs together with the permit data.
    /// @param signature The Permit2 signature, of any length.
    // solhint-disable-next-line gas-struct-packing
    struct WrapData {
        uint256 nonce;
        uint256 deadline;
        address owner;
        bytes32 actionTreeRoot;
        bytes signature;
    }

    /// @notice A struct containing unwrap specific inputs.
    /// @param receiver The receiving account address.
    struct UnwrapData {
        address receiver;
    }

    /// @notice The length of a word of the ABI encoding, to which `bytes` are padded.
    uint256 internal constant _WORD_LENGTH = 32;

    /// @notice The offset for the calltype specific input data (3 slots).
    // NOTE: Slither does not see the uses of this constant as slice bounds.
    // slither-disable-next-line unused-state
    uint256 internal constant _GENERIC_INPUT_OFFSET = 3 * 32;

    /// @notice The length of the wrap data before the signature bytes.
    uint256 internal constant _WRAP_DATA_LENGTH = 7 * 32;

    /// @notice The length of the unwrap data.
    uint256 internal constant _UNWRAP_DATA_LENGTH = 1 * 32;

    /// @notice The canonical Uniswap Permit2 contract being deployed at the same address on all supported chains.
    /// (see [Uniswap's announcement](https://blog.uniswap.org/permit2-and-universal-router)).
    IPermit2 internal constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /// @inheritdoc IVersion
    string public constant override VERSION = "2.1.0";

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

    /// @notice Emitted when the forwarder replaces its logic reference with a new one.
    /// @param previousLogicRef The logic reference that the forwarder accepted until this call.
    /// @param newLogicRef The logic reference that the forwarder accepts from this call on.
    event LogicRefReplaced(bytes32 indexed previousLogicRef, bytes32 indexed newLogicRef);

    /// @notice Thrown if the increase of the forwarder's balance of the token in a wrap, or the decrease in an unwrap,
    /// differs from the amount in the input.
    error BalanceMismatch(uint256 expected, uint256 actual);

    /// @notice Thrown if the wrap data or the unwrap data do not have the length of their ABI encoding.
    error InvalidInputLength(uint256 expected, uint256 actual);

    /// @notice Thrown if a denylist of the protocol adapter contains the new logic reference.
    /// @param logicRef The new logic reference.
    /// @param consumed `true` for the denylist for consumed resources, `false` for the one for created resources.
    error LogicRefAlreadyDenied(bytes32 logicRef, bool consumed);

    /// @notice Disables the initializers on the implementation contract to prevent it from being left uninitialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the ERC20 resource logic function triggering the forward calls.
    /// @param initialOwner The initial owner of the contract having the upgrade authority.
    function initialize( /* solhint-disable-line comprehensive-interface*/
        address protocolAdapter,
        bytes32 logicRef,
        address initialOwner
    )
        external
        virtual
        initializer
    {
        __ForwarderBaseUpgradeable_init({
            protocolAdapter: protocolAdapter, logicRef: logicRef, initialOwner: initialOwner
        });
    }

    /// @notice Replaces the logic reference in the upgrade to this implementation, if the new one differs.
    /// @param newLogicRef The logic reference that the forwarder accepts after the call. The protocol adapter must deny
    /// it on neither denylist.
    function reinitializeLogicRef( /* solhint-disable-line comprehensive-interface*/
        bytes32 newLogicRef
    )
        external
        virtual
        onlyOwner
        reinitializer(2)
    {
        require(newLogicRef != bytes32(0), ZeroLogicRefNotAllowed());

        ForwarderBaseStorage storage $ = _getForwarderBaseStorage();
        _checkLogicRefNotDenied({protocolAdapter: $._protocolAdapter, logicRef: newLogicRef});

        bytes32 previousLogicRef = $._logicRef;
        if (newLogicRef != previousLogicRef) {
            $._logicRef = newLogicRef;

            emit LogicRefReplaced({previousLogicRef: previousLogicRef, newLogicRef: newLogicRef});
        }
    }

    /// @notice Forwards a call wrapping or unwrapping ERC20 tokens based on the provided input.
    /// @param input Contains data to
    /// - wrap ERC20 tokens into resources using Uniswap Permit2 and
    /// - unwrap ERC20 tokens from resources
    /// @return output The empty string signaling that the function call has succeeded.
    function _forwardCall(bytes calldata input) internal virtual override returns (bytes memory output) {
        (CallType callType, IERC20 token, uint128 amount) =
            abi.decode(input[:_GENERIC_INPUT_OFFSET], (CallType, IERC20, uint128));

        // NOTE: The balance read before the external call is reentrancy-protected by the `nonReentrant` modifier in
        // `ForwarderBaseUpgradeable.forwardCall`.
        // slither-disable-next-line reentrancy-balance
        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 balanceDelta = 0;

        if (callType == CallType.Wrap) {
            _wrap({token: address(token), amount: amount, input: input});
            balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        } else {
            _unwrap({token: address(token), amount: amount, unwrapInput: input[_GENERIC_INPUT_OFFSET:]});
            balanceDelta = balanceBefore - token.balanceOf(address(this));
        }

        // Check that the exact `amount` passed with the inputs is transferred.
        // slither-disable-next-line incorrect-equality
        require(balanceDelta == amount, BalanceMismatch({expected: amount, actual: balanceDelta}));

        output = "";
    }

    /// @notice Wraps an ERC20 token and transfers funds from the user that must have authorized the call using
    /// `Permit2.permitWitnessTransferFrom`.
    /// @param token The address of the token to be transferred.
    /// @param amount The amount to be transferred.
    /// @param input The forwarder input, which ends with the wrap data.
    function _wrap(address token, uint128 amount, bytes calldata input) internal {
        (,,, WrapData memory data) = abi.decode(input, (CallType, IERC20, uint128, WrapData));
        _checkLength({
            input: input[_GENERIC_INPUT_OFFSET:],
            expectedLength: _WRAP_DATA_LENGTH + Math.ceilDiv(data.signature.length, _WORD_LENGTH) * _WORD_LENGTH
        });

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
            signature: data.signature
        });

        // NOTE: The event ordering is protected by the `nonReentrant` modifier in
        // `ForwarderBaseUpgradeable.forwardCall`.
        // slither-disable-next-line reentrancy-events
        emit Wrapped({token: token, from: data.owner, amount: amount});
    }

    /// @notice Unwraps an ERC20 token and transfers funds to the recipient using the `SafeERC20.safeTransfer`.
    /// @param token The address of the token to be transferred.
    /// @param amount The amount to be transferred.
    /// @param unwrapInput The input bytes containing the encoded arguments for the unwrap call.
    function _unwrap(address token, uint128 amount, bytes calldata unwrapInput) internal {
        _checkLength({input: unwrapInput, expectedLength: _UNWRAP_DATA_LENGTH});

        UnwrapData memory data = abi.decode(unwrapInput, (UnwrapData));

        IERC20(token).safeTransfer({to: data.receiver, value: amount});

        // NOTE: The event ordering is protected by the `nonReentrant` modifier in
        // `ForwarderBaseUpgradeable.forwardCall`.
        // slither-disable-next-line reentrancy-events
        emit Unwrapped({token: token, to: data.receiver, amount: amount});
    }

    /// @notice Checks that no denylist of the protocol adapter contains the new logic reference.
    /// @param protocolAdapter The protocol adapter that holds the denylists.
    /// @param logicRef The new logic reference.
    function _checkLogicRefNotDenied(address protocolAdapter, bytes32 logicRef) internal view {
        require(
            !ILogicRefDenylist(protocolAdapter).isLogicRefDenied({logicRef: logicRef, consumed: true}),
            LogicRefAlreadyDenied({logicRef: logicRef, consumed: true})
        );
        require(
            !ILogicRefDenylist(protocolAdapter).isLogicRefDenied({logicRef: logicRef, consumed: false}),
            LogicRefAlreadyDenied({logicRef: logicRef, consumed: false})
        );
    }

    /// @notice Checks that the length of an input is the expected length.
    /// @param input The input data to check.
    /// @param expectedLength The expected length.
    function _checkLength(bytes calldata input, uint256 expectedLength) internal pure {
        require(input.length == expectedLength, InvalidInputLength({expected: expectedLength, actual: input.length}));
    }
}
