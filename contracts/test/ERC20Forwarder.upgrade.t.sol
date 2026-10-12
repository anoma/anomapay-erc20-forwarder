// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin-contracts-5.7.0/interfaces/IERC1967.sol";
import {Initializable} from "@openzeppelin-contracts-5.7.0/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-5.7.0/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-3.0.1/src/interfaces/ILogicRefSpecific.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.2/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ERC20ForwarderUpgradeExample} from "./examples/ERC20ForwarderUpgradeExample.sol";
import {ProtocolAdapterMock} from "./mocks/ProtocolAdapter.m.sol";

contract ERC20ForwarderUpgradeTest is Test {
    bytes32 internal constant _INITIAL_LOGIC_REF = bytes32(type(uint256).max / 2);
    bytes32 internal constant _UPGRADED_LOGIC_REF = bytes32(type(uint256).max);

    address internal immutable _PA_OWNER = makeAddr("pa owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");

    address internal _pa;
    UUPSUpgradeable internal _fwdProxy;
    address internal _upgradedImplementation;

    bytes internal _reinitializeCalldata;

    function setUp() public {
        _pa = address(new ProtocolAdapterMock(_PA_OWNER));

        _fwdProxy = UUPSUpgradeable(
            Upgrades.deployUUPSProxy(
                "ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(ERC20Forwarder.initialize, (_pa, _INITIAL_LOGIC_REF, _FORWARDER_OWNER))
            )
        );

        _reinitializeCalldata = abi.encodeCall(ERC20ForwarderUpgradeExample.reinitialize, (_UPGRADED_LOGIC_REF));

        Options memory opts;
        _upgradedImplementation =
            Upgrades.prepareUpgrade("ERC20ForwarderUpgradeExample.sol:ERC20ForwarderUpgradeExample", opts);
    }

    // This test runs the openzeppelin-foundry-upgrades checks.
    function test_upgrades_safely() public {
        // `startPrank`/`stopPrank` keeps `_FORWARDER_OWNER` as the caller across the implementation deploy and the
        // `upgradeToAndCall` that `Upgrades.upgradeProxy` performs internally; a single `vm.prank` would only apply
        // to the deploy.
        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            address(_fwdProxy),
            "ERC20ForwarderUpgradeExample.sol:ERC20ForwarderUpgradeExample",
            abi.encodeCall(ERC20ForwarderUpgradeExample.reinitialize, (_UPGRADED_LOGIC_REF))
        );
        vm.stopPrank();
    }

    function test_upgradeToAndCall_reverts_if_the_caller_is_not_the_owner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        _fwdProxy.upgradeToAndCall({newImplementation: _upgradedImplementation, data: _reinitializeCalldata});
    }

    function test_upgradeToAndCall_upgrades_to_the_upgrade_example_implementation() public {
        vm.prank(_FORWARDER_OWNER);
        _fwdProxy.upgradeToAndCall({newImplementation: _upgradedImplementation, data: _reinitializeCalldata});

        assertEq(Upgrades.getImplementationAddress(address(_fwdProxy)), _upgradedImplementation);
    }

    function test_upgradeToAndCall_replaces_the_initial_logic_ref_with_the_upgraded_one() public {
        assertNotEq(_INITIAL_LOGIC_REF, _UPGRADED_LOGIC_REF);

        assertEq(ILogicRefSpecific(address(_fwdProxy)).getLogicRef(), _INITIAL_LOGIC_REF);

        vm.prank(_FORWARDER_OWNER);
        _fwdProxy.upgradeToAndCall({newImplementation: _upgradedImplementation, data: _reinitializeCalldata});

        assertEq(ILogicRefSpecific(address(_fwdProxy)).getLogicRef(), _UPGRADED_LOGIC_REF);
    }

    function test_upgradeToAndCall_emits_the_Upgraded_and_Initialized_events() public {
        vm.expectEmit(address(_fwdProxy));
        emit IERC1967.Upgraded({implementation: _upgradedImplementation});

        vm.expectEmit(address(_fwdProxy));
        emit Initializable.Initialized({version: 2});

        vm.prank(_FORWARDER_OWNER);
        _fwdProxy.upgradeToAndCall({newImplementation: _upgradedImplementation, data: _reinitializeCalldata});
    }
}
