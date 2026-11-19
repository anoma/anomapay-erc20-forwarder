// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.4/src/Upgrades.sol";
import {LibString} from "solady-0.1.26/src/utils/LibString.sol";
import {SemVerLib} from "solady-0.1.26/src/utils/SemVerLib.sol";
import {
    ISignatureTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IPermit2.sol";

import {ERC20Forwarder as ERC20ForwarderV2_1_0} from "../../src/draft/ERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ERC20ForwarderPermit2} from "../../src/ERC20ForwarderPermit2.sol";
import {ERC20ForwarderTest} from "../ERC20Forwarder.t.sol";
import {SafeFixture} from "../fixtures/SafeFixture.sol";
import {Permit2Signature} from "../libs/Permit2Signature.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

/// @dev Runs the tests of the 2.0.0 forwarder against the draft, and adds the tests of signatures other than one
/// 65-byte ECDSA signature.
contract ERC20ForwarderDraftTest is ERC20ForwarderTest, SafeFixture {
    using ERC20ForwarderPermit2 for ERC20ForwarderPermit2.Witness;

    function test_wrap_pulls_funds_with_a_compact_signature() public {
        _erc20.mint({to: _alice, value: _TRANSFER_AMOUNT});
        uint256 startBalanceForwarder = _erc20.balanceOf(address(_fwd));

        vm.prank(_alice);
        _erc20.approve(address(_permit2), type(uint256).max);

        (bytes32 r, bytes32 vs) = vm.signCompact(_alicePrivateKey, _permitDigest(_defaultPermit));

        vm.prank(address(_pa));
        _fwd.forwardCall({
            logicRef: _logicRef,
            input: _wrapInputWithSignature({permit: _defaultPermit, owner: _alice, signature: abi.encodePacked(r, vs)})
        });

        assertEq(_erc20.balanceOf(_alice), 0);
        assertEq(_erc20.balanceOf(address(_fwd)), startBalanceForwarder + _TRANSFER_AMOUNT);
    }

    function test_wrap_pulls_funds_from_a_safe_with_the_signatures_of_two_of_three_owners() public {
        uint256[] memory ownerKeys = _safeOwnerKeys();
        address safe = _deploySafe({ownerKeys: ownerKeys, threshold: 2});
        uint256[] memory signerKeys = new uint256[](2);
        signerKeys[0] = ownerKeys[0];
        signerKeys[1] = ownerKeys[2];

        bytes memory signature = _safeSignatures({
            ownerKeys: signerKeys, hash: _safeMessageHash(safe, abi.encode(_permitDigest(_defaultPermit)))
        });
        assertGt(signature.length, 65, "the Safe signature is longer than one ECDSA signature");

        _wrapFromSafeAndCheckTheBalances({safe: safe, signature: signature});
    }

    function test_wrap_pulls_funds_from_a_safe_with_an_empty_signature_for_a_message_that_the_safe_approved() public {
        uint256[] memory ownerKeys = _safeOwnerKeys();
        address safe = _deploySafe({ownerKeys: ownerKeys, threshold: 2});
        uint256[] memory signerKeys = new uint256[](2);
        signerKeys[0] = ownerKeys[0];
        signerKeys[1] = ownerKeys[1];

        _approveSafeMessage({safe: safe, ownerKeys: signerKeys, message: abi.encode(_permitDigest(_defaultPermit))});

        _wrapFromSafeAndCheckTheBalances({safe: safe, signature: ""});
    }

    function test_check_that_the_current_version_is_not_a_major_release() public view override {
        assertEq(
            SemVerLib.cmp(LibString.toSmallString(_fwd.VERSION()), "2.0.0"), 1, "version should be greater than 2.0.0"
        );
        assertEq(
            SemVerLib.cmp(LibString.toSmallString(_fwd.VERSION()), "3.0.0"), -1, "version should be less than 3.0.0"
        );
    }

    function _deployProtocolAdapterAndForwarders() internal override {
        _logicRef = bytes32(uint256(1));

        _pa = new ProtocolAdapterMock(_PA_OWNER);

        _fwd = ERC20Forwarder(
            Upgrades.deployUUPSProxy(
                "draft/ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(ERC20ForwarderV2_1_0.initialize, (address(_pa), _logicRef, _FORWARDER_OWNER))
            )
        );
    }

    function _wrapFromSafeAndCheckTheBalances(address safe, bytes memory signature) internal {
        _erc20.mint({to: safe, value: _TRANSFER_AMOUNT});
        uint256 startBalanceForwarder = _erc20.balanceOf(address(_fwd));

        vm.prank(safe);
        _erc20.approve(address(_permit2), type(uint256).max);

        vm.prank(address(_pa));
        _fwd.forwardCall({
            logicRef: _logicRef,
            input: _wrapInputWithSignature({permit: _defaultPermit, owner: safe, signature: signature})
        });

        assertEq(_erc20.balanceOf(safe), 0);
        assertEq(_erc20.balanceOf(address(_fwd)), startBalanceForwarder + _TRANSFER_AMOUNT);
    }

    /// @notice The private keys of three Safe owners.
    function _safeOwnerKeys() internal returns (uint256[] memory ownerKeys) {
        ownerKeys = new uint256[](3);
        (, ownerKeys[0]) = makeAddrAndKey("safe owner 0");
        (, ownerKeys[1]) = makeAddrAndKey("safe owner 1");
        (, ownerKeys[2]) = makeAddrAndKey("safe owner 2");
    }

    /// @notice The Permit2 digest of `permit` with the forwarder as the spender and `_ACTION_TREE_ROOT` as the witness.
    function _permitDigest(ISignatureTransfer.PermitTransferFrom memory permit) internal view returns (bytes32 digest) {
        digest = Permit2Signature.permitWitnessTransferFromDigest({
            domainSeparator: _permit2.DOMAIN_SEPARATOR(),
            permit: permit,
            spender: address(_fwd),
            witness: ERC20ForwarderPermit2.Witness(_ACTION_TREE_ROOT).hash()
        });
    }

    /// @inheritdoc ERC20ForwarderTest
    function _wrapInput(
        ISignatureTransfer.PermitTransferFrom memory permit,
        address owner,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal pure override returns (bytes memory input) {
        input = _wrapInputWithSignature({permit: permit, owner: owner, signature: abi.encodePacked(r, s, v)});
    }

    /// @notice The forwarder input of a wrap of `permit` from `owner` with `signature`.
    function _wrapInputWithSignature(
        ISignatureTransfer.PermitTransferFrom memory permit,
        address owner,
        bytes memory signature
    ) internal pure returns (bytes memory input) {
        input = abi.encode(
            ERC20ForwarderV2_1_0.CallType.Wrap,
            permit.permitted.token,
            permit.permitted.amount,
            ERC20ForwarderV2_1_0.WrapData({
                nonce: permit.nonce,
                deadline: permit.deadline,
                owner: owner,
                actionTreeRoot: _ACTION_TREE_ROOT,
                signature: signature
            })
        );
    }
}
