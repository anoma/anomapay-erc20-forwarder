// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin-contracts-5.6.1/interfaces/IERC1967.sol";
import {Initializable} from "@openzeppelin-contracts-5.6.1/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-5.6.1/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/OwnableUpgradeable.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-1.0.0-rc.3/src/interfaces/ILogicRefSpecific.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.1/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.1/src/Upgrades.sol";

import {ERC20ForwarderV2} from "../src/drafts/ERC20ForwarderV2.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ProtocolAdapterMock} from "./mocks/ProtocolAdapter.m.sol";

contract ERC20ForwarderUpgradeTest is Test {
    bytes32 internal constant _LOGIC_REF_V1 = bytes32(type(uint256).max / 2);
    bytes32 internal constant _LOGIC_REF_V2 = bytes32(type(uint256).max);

    address internal immutable _PA_OWNER = makeAddr("pa owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");

    address internal _pa;
    UUPSUpgradeable internal _fwdProxy;
    address internal _implV2;

    bytes internal _reinitializeCalldata;

    function setUp() public {
        _pa = address(new ProtocolAdapterMock(_PA_OWNER));

        _fwdProxy = UUPSUpgradeable(
            Upgrades.deployUUPSProxy(
                "ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(ERC20Forwarder.initialize, (_pa, _LOGIC_REF_V1, _FORWARDER_OWNER))
            )
        );

        _reinitializeCalldata = abi.encodeCall(ERC20ForwarderV2.reinitialize, (_LOGIC_REF_V2));

        Options memory opts;
        _implV2 = Upgrades.prepareUpgrade("ERC20ForwarderV2.sol:ERC20ForwarderV2", opts);
    }

    // This test runs the openzeppelin-foundry-upgrades checks.
    function test_upgrades_safely() public {
        // `startPrank`/`stopPrank` keeps `_FORWARDER_OWNER` as the caller across the implementation deploy and the
        // `upgradeToAndCall` that `Upgrades.upgradeProxy` performs internally; a single `vm.prank` would only apply
        // to the deploy.
        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            address(_fwdProxy),
            "ERC20ForwarderV2.sol:ERC20ForwarderV2",
            abi.encodeCall(ERC20ForwarderV2.reinitialize, (_LOGIC_REF_V2))
        );
        vm.stopPrank();
    }

    function test_upgradeToAndCall_reverts_if_the_caller_is_not_the_owner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        _fwdProxy.upgradeToAndCall({newImplementation: _implV2, data: _reinitializeCalldata});
    }

    function test_upgradeToAndCall_upgrades_to_the_erc20_forwarder_v2_implementation() public {
        vm.prank(_FORWARDER_OWNER);
        _fwdProxy.upgradeToAndCall({newImplementation: _implV2, data: _reinitializeCalldata});

        assertEq(Upgrades.getImplementationAddress(address(_fwdProxy)), _implV2);
    }

    function test_upgradeToAndCall_upgrades_the_logic_ref_v1_to_v2() public {
        assertNotEq(_LOGIC_REF_V1, _LOGIC_REF_V2);

        assertEq(ILogicRefSpecific(address(_fwdProxy)).getLogicRef(), _LOGIC_REF_V1);

        vm.prank(_FORWARDER_OWNER);
        _fwdProxy.upgradeToAndCall({newImplementation: _implV2, data: _reinitializeCalldata});

        assertEq(ILogicRefSpecific(address(_fwdProxy)).getLogicRef(), _LOGIC_REF_V2);
    }

    function test_upgradeToAndCall_emits_the_Upgraded_and_Initialized_events() public {
        vm.expectEmit(address(_fwdProxy));
        emit IERC1967.Upgraded({implementation: _implV2});

        vm.expectEmit(address(_fwdProxy));
        emit Initializable.Initialized({version: 2});

        vm.prank(_FORWARDER_OWNER);
        _fwdProxy.upgradeToAndCall({newImplementation: _implV2, data: _reinitializeCalldata});
    }
}
