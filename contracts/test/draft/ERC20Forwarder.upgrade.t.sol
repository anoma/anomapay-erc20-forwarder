// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-3.1.0/src/interfaces/ILogicRefSpecific.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.4/src/Upgrades.sol";

import {ERC20Forwarder as ERC20ForwarderV2_1_0} from "../../src/draft/ERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

/// @dev Each test upgrades a proxy that ran only the `initialize` of the 2.0.0 forwarder, as in production.
contract ERC20ForwarderDraftUpgradeTest is Test {
    bytes32 internal constant _PREVIOUS_LOGIC_REF = bytes32(uint256(1));
    bytes32 internal constant _NEW_LOGIC_REF = bytes32(uint256(2));

    address internal immutable _PROTOCOL_ADAPTER_OWNER = makeAddr("protocol adapter owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");

    ProtocolAdapterMock internal _protocolAdapter;
    ERC20Forwarder internal _forwarder;
    address internal _implementation;

    function setUp() public {
        _protocolAdapter = new ProtocolAdapterMock(_PROTOCOL_ADAPTER_OWNER);

        _forwarder = ERC20Forwarder(
            Upgrades.deployUUPSProxy(
                "out/ERC20Forwarder.sol/ERC20Forwarder.json",
                abi.encodeCall(
                    ERC20Forwarder.initialize, (address(_protocolAdapter), _PREVIOUS_LOGIC_REF, _FORWARDER_OWNER)
                )
            )
        );
        _implementation = address(new ERC20ForwarderV2_1_0());
    }

    /// @dev The only upgrade that runs the upgrade-safety validation, because each validation takes an `npx` call.
    function test_upgrades_safely() public {
        // `Upgrades.upgradeProxy` deploys the implementation before it upgrades, so one `vm.prank` covers only the
        // deploy.
        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            address(_forwarder),
            "draft/ERC20Forwarder.sol:ERC20Forwarder",
            abi.encodeCall(ERC20ForwarderV2_1_0.reinitializeLogicRef, (_NEW_LOGIC_REF))
        );
        vm.stopPrank();

        assertEq(_forwarder.VERSION(), "2.1.0");
    }

    function test_reinitializeLogicRef_replaces_the_logic_ref() public {
        _upgradeTo(_NEW_LOGIC_REF);

        assertEq(_forwarder.getLogicRef(), _NEW_LOGIC_REF);
    }

    function test_reinitializeLogicRef_makes_the_forwarder_reject_the_previous_logic_ref() public {
        _upgradeTo(_NEW_LOGIC_REF);

        vm.prank(address(_protocolAdapter));
        vm.expectRevert(
            abi.encodeWithSelector(ILogicRefSpecific.LogicRefMismatch.selector, _NEW_LOGIC_REF, _PREVIOUS_LOGIC_REF)
        );
        _forwarder.forwardCall({logicRef: _PREVIOUS_LOGIC_REF, input: ""});
    }

    function test_reinitializeLogicRef_emits_the_LogicRefReplaced_event() public {
        vm.expectEmit(address(_forwarder));
        emit ERC20ForwarderV2_1_0.LogicRefReplaced({previousLogicRef: _PREVIOUS_LOGIC_REF, newLogicRef: _NEW_LOGIC_REF});

        _upgradeTo(_NEW_LOGIC_REF);
    }

    function test_reinitializeLogicRef_keeps_the_logic_ref_and_emits_no_event_if_the_new_one_is_the_same() public {
        vm.recordLogs();
        _upgradeTo(_PREVIOUS_LOGIC_REF);

        assertEq(_forwarder.getLogicRef(), _PREVIOUS_LOGIC_REF);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; ++i) {
            assertNotEq(logs[i].topics[0], ERC20ForwarderV2_1_0.LogicRefReplaced.selector);
        }
    }

    function test_reinitializeLogicRef_reverts_if_the_caller_is_not_the_owner() public {
        vm.prank(_FORWARDER_OWNER);
        _forwarder.upgradeToAndCall({newImplementation: _implementation, data: ""});

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        ERC20ForwarderV2_1_0(address(_forwarder)).reinitializeLogicRef({newLogicRef: _NEW_LOGIC_REF});
    }

    function test_reinitializeLogicRef_reverts_if_it_runs_a_second_time() public {
        _upgradeTo(_NEW_LOGIC_REF);

        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        ERC20ForwarderV2_1_0(address(_forwarder)).reinitializeLogicRef({newLogicRef: _PREVIOUS_LOGIC_REF});
    }

    function test_reinitializeLogicRef_reverts_on_the_zero_logic_ref() public {
        vm.expectRevert(abi.encodeWithSelector(ILogicRefSpecific.ZeroLogicRefNotAllowed.selector));
        _upgradeTo(bytes32(0));
    }

    function testFuzz_reinitializeLogicRef_reverts_if_the_protocol_adapter_denies_the_new_logic_ref(bool consumed)
        public
    {
        _protocolAdapter.mockSetLogicRefDenied({logicRef: _NEW_LOGIC_REF, consumed: consumed, isDenied: true});

        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV2_1_0.LogicRefAlreadyDenied.selector, _NEW_LOGIC_REF, consumed)
        );
        _upgradeTo(_NEW_LOGIC_REF);
    }

    /// @dev Makes no external call before `upgradeToAndCall`, so `vm.expectRevert` and `vm.expectEmit` apply to it.
    function _upgradeTo(bytes32 newLogicRef) internal {
        bytes memory data = abi.encodeCall(ERC20ForwarderV2_1_0.reinitializeLogicRef, (newLogicRef));

        vm.prank(_FORWARDER_OWNER);
        _forwarder.upgradeToAndCall({newImplementation: _implementation, data: data});
    }
}
