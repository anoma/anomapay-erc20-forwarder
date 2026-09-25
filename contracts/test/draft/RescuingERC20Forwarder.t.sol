// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {IForwarder} from "anoma-forwarder-bases-3.0.0/src/interfaces/IForwarder.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-3.0.0/src/interfaces/ILogicRefSpecific.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.0.0/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.16.2/src/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {IRescuingERC20Forwarder} from "../../src/draft/IRescuingERC20Forwarder.sol";
import {RescuingERC20Forwarder} from "../../src/draft/RescuingERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

contract RescuingERC20ForwarderTest is Test {
    uint128 internal constant _AMOUNT = 1000;
    bytes32 internal constant _RETIRED_LOGIC_REF = bytes32(uint256(1));
    bytes32 internal constant _NEW_LOGIC_REF = bytes32(uint256(2));
    bytes32 internal constant _RESCUE_ROOT = bytes32(uint256(3));
    bytes32 internal constant _NULLIFIER = bytes32(uint256(4));

    address internal immutable _PA_OWNER = makeAddr("pa owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");
    address internal immutable _RECEIVER = makeAddr("receiver");

    ProtocolAdapterMock internal _pa;
    RescuingERC20Forwarder internal _fwd;
    ERC20Example internal _erc20;

    function setUp() public {
        _erc20 = new ERC20Example();
        _pa = _pausedAdapterHolding(_RESCUE_ROOT);
        _fwd = _deployForwarder(address(_pa));
    }

    function test_upgrades_safely() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
    }

    function test_reinitialize_rotates_the_logic_ref() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        assertEq(_fwd.getLogicRef(), _NEW_LOGIC_REF);
    }

    function test_reinitialize_records_the_retired_logic_ref_and_its_rescue_root() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        assertEq(_fwd.retiredLogicRefCount(), 1);
        assertEq(_fwd.getRescueRoot(_RETIRED_LOGIC_REF), _RESCUE_ROOT);

        (bytes32 retiredLogicRef, bytes32 rescueRoot) = _fwd.retiredLogicRefAtIndex(0);
        assertEq(retiredLogicRef, _RETIRED_LOGIC_REF);
        assertEq(rescueRoot, _RESCUE_ROOT);
    }

    function test_reinitialize_emits_the_LogicRefRetired_event() public {
        address implementation = address(new RescuingERC20Forwarder());
        bytes memory data = abi.encodeCall(RescuingERC20Forwarder.reinitialize, (_NEW_LOGIC_REF, _RESCUE_ROOT));

        vm.expectEmit(address(_fwd));
        emit IRescuingERC20Forwarder.LogicRefRetired({
            retiredLogicRef: _RETIRED_LOGIC_REF, rescueRoot: _RESCUE_ROOT, newLogicRef: _NEW_LOGIC_REF
        });

        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function test_reinitialize_reverts_if_the_caller_is_not_the_owner() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        _fwd.reinitialize({newLogicRef: bytes32(uint256(5)), rescueRoot: _RESCUE_ROOT});
    }

    function test_reinitialize_reverts_on_the_zero_logic_ref() public {
        _expectRetireRevert({
            newLogicRef: bytes32(0),
            rescueRoot: _RESCUE_ROOT,
            expectedError: abi.encodeWithSelector(ILogicRefSpecific.ZeroLogicRefNotAllowed.selector)
        });
    }

    function test_reinitialize_reverts_if_the_logic_ref_does_not_change() public {
        _expectRetireRevert({
            newLogicRef: _RETIRED_LOGIC_REF,
            rescueRoot: _RESCUE_ROOT,
            expectedError: abi.encodeWithSelector(RescuingERC20Forwarder.UnchangedLogicRef.selector, _RETIRED_LOGIC_REF)
        });
    }

    function test_reinitialize_reverts_if_the_protocol_adapter_is_not_paused() public {
        ProtocolAdapterMock runningAdapter = new ProtocolAdapterMock(_PA_OWNER);
        runningAdapter.mockAddCommitmentTreeRoot(_RESCUE_ROOT);
        _fwd = _deployForwarder(address(runningAdapter));

        _expectRetireRevert({
            newLogicRef: _NEW_LOGIC_REF,
            rescueRoot: _RESCUE_ROOT,
            expectedError: abi.encodeWithSelector(
                RescuingERC20Forwarder.ProtocolAdapterNotPaused.selector, address(runningAdapter)
            )
        });
    }

    function test_reinitialize_reverts_if_the_protocol_adapter_does_not_hold_the_rescue_root() public {
        bytes32 unknownRoot = bytes32(uint256(99));

        _expectRetireRevert({
            newLogicRef: _NEW_LOGIC_REF,
            rescueRoot: unknownRoot,
            expectedError: abi.encodeWithSelector(RescuingERC20Forwarder.UnknownRescueRoot.selector, unknownRoot)
        });
    }

    function test_reinitialize_reverts_if_the_logic_ref_is_retired_already() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        // Rotating back retires the new reference, so retiring the first one again must fail.
        vm.prank(_FORWARDER_OWNER);
        _fwd.reinitialize({newLogicRef: _RETIRED_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(RescuingERC20Forwarder.LogicRefAlreadyRetired.selector, _RETIRED_LOGIC_REF)
        );
        _fwd.reinitialize({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
    }

    function test_reinitialize_keeps_the_earlier_generation_rescuable() public {
        bytes32 thirdLogicRef = bytes32(uint256(5));
        bytes32 secondRescueRoot = bytes32(uint256(6));
        _pa.mockAddCommitmentTreeRoot(secondRescueRoot);

        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        vm.prank(_FORWARDER_OWNER);
        _fwd.reinitialize({newLogicRef: thirdLogicRef, rescueRoot: secondRescueRoot});

        assertEq(_fwd.retiredLogicRefCount(), 2);
        assertEq(_fwd.getRescueRoot(_RETIRED_LOGIC_REF), _RESCUE_ROOT);
        assertEq(_fwd.getRescueRoot(_NEW_LOGIC_REF), secondRescueRoot);

        // Both generations rescue against the root recorded for them.
        _rescue({retiredLogicRef: _RETIRED_LOGIC_REF, rescueRoot: _RESCUE_ROOT, nullifier: _NULLIFIER});
        _rescue({retiredLogicRef: _NEW_LOGIC_REF, rescueRoot: secondRescueRoot, nullifier: bytes32(uint256(7))});
    }

    function test_forwardCall_reverts_on_the_retired_logic_ref() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
        bytes memory input = _rescueInput({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            rescueRoot: _RESCUE_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd)
        });

        vm.prank(address(_pa));
        vm.expectRevert(
            abi.encodeWithSelector(ILogicRefSpecific.LogicRefMismatch.selector, _NEW_LOGIC_REF, _RETIRED_LOGIC_REF)
        );
        IForwarder(address(_fwd)).forwardCall({logicRef: _RETIRED_LOGIC_REF, input: input});
    }

    function test_rescue_records_the_nullifier() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        assertFalse(_fwd.isNullifierRescued(_NULLIFIER));
        _rescue({retiredLogicRef: _RETIRED_LOGIC_REF, rescueRoot: _RESCUE_ROOT, nullifier: _NULLIFIER});
        assertTrue(_fwd.isNullifierRescued(_NULLIFIER));
    }

    function test_rescue_moves_no_tokens() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
        _erc20.mint({to: address(_fwd), value: _AMOUNT});

        _rescue({retiredLogicRef: _RETIRED_LOGIC_REF, rescueRoot: _RESCUE_ROOT, nullifier: _NULLIFIER});

        assertEq(_erc20.balanceOf(address(_fwd)), _AMOUNT);
    }

    function test_rescue_emits_the_Rescued_event() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        vm.expectEmit(address(_fwd));
        emit IRescuingERC20Forwarder.Rescued({
            token: address(_erc20), retiredLogicRef: _RETIRED_LOGIC_REF, nullifier: _NULLIFIER, amount: _AMOUNT
        });

        _rescue({retiredLogicRef: _RETIRED_LOGIC_REF, rescueRoot: _RESCUE_ROOT, nullifier: _NULLIFIER});
    }

    function test_rescue_reverts_if_the_resource_was_rescued_already() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
        _rescue({retiredLogicRef: _RETIRED_LOGIC_REF, rescueRoot: _RESCUE_ROOT, nullifier: _NULLIFIER});

        _expectRescueRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            rescueRoot: _RESCUE_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(RescuingERC20Forwarder.ResourceAlreadyRescued.selector, _NULLIFIER)
        });
    }

    function test_rescue_reverts_if_the_protocol_adapter_consumed_the_resource() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
        _pa.mockAddNullifier(_NULLIFIER);

        _expectRescueRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            rescueRoot: _RESCUE_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(RescuingERC20Forwarder.ResourceAlreadyConsumed.selector, _NULLIFIER)
        });
    }

    function test_rescue_reverts_on_an_unretired_logic_ref() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        _expectRescueRevert({
            retiredLogicRef: _NEW_LOGIC_REF,
            rescueRoot: _RESCUE_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                RescuingERC20Forwarder.UnknownRetiredLogicRef.selector, _NEW_LOGIC_REF
            )
        });
    }

    function test_rescue_reverts_on_another_root_than_the_recorded_one() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
        bytes32 otherRoot = bytes32(uint256(8));

        _expectRescueRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            rescueRoot: otherRoot,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                RescuingERC20Forwarder.RescueRootMismatch.selector, _RESCUE_ROOT, otherRoot
            )
        });
    }

    function test_rescue_reverts_on_another_forwarder() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
        address otherForwarder = makeAddr("other forwarder");

        _expectRescueRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            rescueRoot: _RESCUE_ROOT,
            nullifier: _NULLIFIER,
            forwarder: otherForwarder,
            expectedError: abi.encodeWithSelector(
                RescuingERC20Forwarder.ForwarderMismatch.selector, address(_fwd), otherForwarder
            )
        });
    }

    function test_rescue_reverts_on_a_short_input() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});

        bytes memory input = abi.encode(
            RescuingERC20Forwarder.RescuingCallType.Rescue, address(_erc20), _AMOUNT, _NULLIFIER, _RESCUE_ROOT
        );

        vm.prank(address(_pa));
        vm.expectRevert(abi.encodeWithSelector(ERC20Forwarder.InvalidInputLength.selector, 4 * 32, 2 * 32));
        IForwarder(address(_fwd)).forwardCall({logicRef: _NEW_LOGIC_REF, input: input});
    }

    function test_unwrap_still_releases_tokens() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, rescueRoot: _RESCUE_ROOT});
        _erc20.mint({to: address(_fwd), value: _AMOUNT});

        bytes memory input = abi.encode(
            RescuingERC20Forwarder.RescuingCallType.Unwrap,
            address(_erc20),
            _AMOUNT,
            ERC20Forwarder.UnwrapData({receiver: _RECEIVER})
        );

        vm.prank(address(_pa));
        IForwarder(address(_fwd)).forwardCall({logicRef: _NEW_LOGIC_REF, input: input});

        assertEq(_erc20.balanceOf(_RECEIVER), _AMOUNT);
        assertEq(_erc20.balanceOf(address(_fwd)), 0);
    }

    /// @dev A stopped adapter that holds the root, which is the state the rotation expects.
    function _pausedAdapterHolding(bytes32 root) internal returns (ProtocolAdapterMock adapter) {
        adapter = new ProtocolAdapterMock(_PA_OWNER);
        adapter.mockAddCommitmentTreeRoot(root);

        vm.prank(_PA_OWNER);
        adapter.emergencyStop();
    }

    function _deployForwarder(address protocolAdapter) internal returns (RescuingERC20Forwarder forwarder) {
        forwarder = RescuingERC20Forwarder(
            Upgrades.deployUUPSProxy(
                "ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(ERC20Forwarder.initialize, (protocolAdapter, _RETIRED_LOGIC_REF, _FORWARDER_OWNER))
            )
        );
    }

    /// @dev Upgrades the proxy to the draft and retires the logic reference it holds, as the owner does.
    function _upgradeAndRetire(bytes32 newLogicRef, bytes32 rescueRoot) internal {
        // `startPrank` keeps the owner as the caller across the implementation deploy and the `upgradeToAndCall`
        // that `Upgrades.upgradeProxy` performs internally; a single `vm.prank` would only apply to the deploy.
        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            address(_fwd),
            "RescuingERC20Forwarder.sol:RescuingERC20Forwarder",
            abi.encodeCall(RescuingERC20Forwarder.reinitialize, (newLogicRef, rescueRoot))
        );
        vm.stopPrank();
    }

    function _expectRetireRevert(bytes32 newLogicRef, bytes32 rescueRoot, bytes memory expectedError) internal {
        address implementation = address(new RescuingERC20Forwarder());
        bytes memory data = abi.encodeCall(RescuingERC20Forwarder.reinitialize, (newLogicRef, rescueRoot));

        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(expectedError);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function _rescue(bytes32 retiredLogicRef, bytes32 rescueRoot, bytes32 nullifier) internal {
        bytes32 logicRef = _fwd.getLogicRef();
        bytes memory input = _rescueInput({
            retiredLogicRef: retiredLogicRef, rescueRoot: rescueRoot, nullifier: nullifier, forwarder: address(_fwd)
        });

        vm.prank(address(_pa));
        IForwarder(address(_fwd)).forwardCall({logicRef: logicRef, input: input});
    }

    function _expectRescueRevert(
        bytes32 retiredLogicRef,
        bytes32 rescueRoot,
        bytes32 nullifier,
        address forwarder,
        bytes memory expectedError
    ) internal {
        bytes32 logicRef = _fwd.getLogicRef();
        bytes memory input = _rescueInput({
            retiredLogicRef: retiredLogicRef, rescueRoot: rescueRoot, nullifier: nullifier, forwarder: forwarder
        });

        vm.prank(address(_pa));
        vm.expectRevert(expectedError);
        IForwarder(address(_fwd)).forwardCall({logicRef: logicRef, input: input});
    }

    function _rescueInput(bytes32 retiredLogicRef, bytes32 rescueRoot, bytes32 nullifier, address forwarder)
        internal
        view
        returns (bytes memory input)
    {
        input = abi.encode(
            RescuingERC20Forwarder.RescuingCallType.Rescue,
            address(_erc20),
            _AMOUNT,
            RescuingERC20Forwarder.RescueData({
                nullifier: nullifier, rescueRoot: rescueRoot, retiredLogicRef: retiredLogicRef, forwarder: forwarder
            })
        );
    }
}
