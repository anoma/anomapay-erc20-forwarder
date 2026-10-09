// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-3.0.1/src/interfaces/ILogicRefSpecific.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.2/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";
import {IEmergencyMigratingERC20Forwarder} from "../../src/draft/IEmergencyMigratingERC20Forwarder.sol";
import {EmergencyMigratingERC20ForwarderFixture} from "../fixtures/EmergencyMigratingERC20ForwarderFixture.sol";

/// @dev Each test upgrades the regular forwarder itself.
contract EmergencyMigratingERC20ForwarderUpgradeTest is EmergencyMigratingERC20ForwarderFixture {
    /// @dev The only upgrade that runs the upgrade-safety validation, because each validation takes an `npx` call.
    function test_upgrades_safely() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        Options memory options;
        options.constructorData = abi.encode(_FORWARDER_V1);

        // `Upgrades.upgradeProxy` deploys the implementation before it upgrades, so one `vm.prank` covers only the deploy.
        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            address(_forwarder),
            "EmergencyMigratingERC20Forwarder.sol:EmergencyMigratingERC20Forwarder",
            abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (_NEW_LOGIC_REF, _listOf(_ACTIVE_LOGIC_REF))),
            options
        );
        vm.stopPrank();
    }

    /// @dev Only the deprecated version has the flaw, so the active one is not listed.
    function test_reinitialize_replaces_the_logic_ref_and_lists_only_the_passed_logic_refs() public {
        _setDenied({logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});

        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_DEPRECATED_LOGIC_REF)
        });

        assertEq(_forwarder.getLogicRef(), _NEW_LOGIC_REF);
        assertTrue(_forwarder.isLogicRefVulnerable(_DEPRECATED_LOGIC_REF));
        assertFalse(_forwarder.isLogicRefVulnerable(_ACTIVE_LOGIC_REF));
        assertFalse(_forwarder.isLogicRefVulnerable(_NEW_LOGIC_REF));
    }

    /// @dev The active version has no flaw and can start an emergency migration already.
    function test_reinitialize_keeps_the_logic_ref_and_lists_the_vulnerable_logic_refs() public {
        _setDenied({logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});

        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _ACTIVE_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_DEPRECATED_LOGIC_REF)
        });

        assertEq(_forwarder.getLogicRef(), _ACTIVE_LOGIC_REF);
        assertTrue(_forwarder.isLogicRefVulnerable(_DEPRECATED_LOGIC_REF));
        assertFalse(_forwarder.isLogicRefVulnerable(_ACTIVE_LOGIC_REF));
    }

    function test_reinitialize_emits_the_VulnerableLogicRefListed_and_LogicRefReplaced_events() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});

        vm.expectEmit(address(_forwarder));
        emit IEmergencyMigratingERC20Forwarder.VulnerableLogicRefListed({logicRef: _ACTIVE_LOGIC_REF});
        vm.expectEmit(address(_forwarder));
        emit IEmergencyMigratingERC20Forwarder.LogicRefReplaced({
            previousLogicRef: _ACTIVE_LOGIC_REF, newLogicRef: _NEW_LOGIC_REF
        });

        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
    }

    function test_reinitialize_reverts_if_the_caller_is_not_the_owner() public {
        vm.prank(_FORWARDER_OWNER);
        _forwarder.upgradeToAndCall({newImplementation: _implementation, data: ""});

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        _forwarder.reinitialize({newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)});
    }

    function test_reinitialize_reverts_if_it_runs_a_second_time() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
        _setDenied({logicRef: _NEW_LOGIC_REF, isDenied: true});

        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        _forwarder.reinitialize({newLogicRef: _SECOND_INCIDENT_LOGIC_REF, vulnerableLogicRefs: _listOf(_NEW_LOGIC_REF)});
    }

    function test_reinitialize_reverts_on_the_zero_logic_ref() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});

        vm.expectRevert(abi.encodeWithSelector(ILogicRefSpecific.ZeroLogicRefNotAllowed.selector));
        _upgradeTo({
            implementation: _implementation, newLogicRef: bytes32(0), vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
    }

    /// @dev The call replaces the logic ref, so the empty list alone makes it revert.
    function test_reinitialize_reverts_on_an_empty_list() public {
        vm.expectRevert(abi.encodeWithSelector(EmergencyMigratingERC20Forwarder.EmptyVulnerableLogicRefList.selector));
        _upgradeTo({
            implementation: _implementation, newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: new bytes32[](0)
        });
    }

    function test_reinitialize_reverts_if_the_logic_ref_is_vulnerable_already() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefAlreadyVulnerable.selector, _ACTIVE_LOGIC_REF
            )
        );
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF, _ACTIVE_LOGIC_REF)
        });
    }

    function testFuzz_reinitialize_reverts_if_the_protocol_adapter_does_not_deny_the_vulnerable_logic_ref(bool consumed)
        public
    {
        _protocolAdapter.mockSetLogicRefDenied({logicRef: _ACTIVE_LOGIC_REF, consumed: !consumed, isDenied: true});

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefNotDenied.selector, _ACTIVE_LOGIC_REF, consumed
            )
        );
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
    }

    function testFuzz_reinitialize_reverts_if_the_protocol_adapter_denies_the_new_logic_ref(bool consumed) public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        _protocolAdapter.mockSetLogicRefDenied({logicRef: _NEW_LOGIC_REF, consumed: consumed, isDenied: true});

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefAlreadyDenied.selector, _NEW_LOGIC_REF, consumed
            )
        );
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
    }

    function test_migrate_reverts_on_the_zero_forwarder_on_a_chain_without_a_V1_forwarder() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        _upgradeTo({
            implementation: address(new EmergencyMigratingERC20Forwarder(address(0))),
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 1});
        entries[0].forwarder = address(0);

        _expectMigrateRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.UnknownForwarder.selector, address(0)
            )
        });
    }
}
