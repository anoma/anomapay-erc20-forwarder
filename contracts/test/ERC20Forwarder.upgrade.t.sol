// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin-contracts-5.7.0/interfaces/IERC1967.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts-5.7.0/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin-contracts-5.7.0/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-5.7.0/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-3.1.0/src/interfaces/ILogicRefSpecific.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.2/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {DeployERC20ForwarderImplementation} from "../script/DeployERC20ForwarderImplementation.s.sol";
import {Parameters} from "../script/Parameters.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ERC20ForwarderUpgradeExample} from "./examples/ERC20ForwarderUpgradeExample.sol";
import {ProtocolAdapterMock} from "./mocks/ProtocolAdapter.m.sol";

contract ERC20ForwarderUpgradeTest is Test {
    bytes32 internal constant _INITIAL_LOGIC_REF = bytes32(type(uint256).max / 2);
    bytes32 internal constant _UPGRADED_LOGIC_REF = bytes32(type(uint256).max);

    address internal immutable _PA_OWNER = makeAddr("pa owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");

    ProtocolAdapterMock internal _pa;
    UUPSUpgradeable internal _fwdProxy;
    address internal _upgradedImplementation;

    bytes internal _reinitializeCalldata;

    function setUp() public {
        _pa = new ProtocolAdapterMock(_PA_OWNER);

        _fwdProxy = UUPSUpgradeable(
            Upgrades.deployUUPSProxy(
                "ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(ERC20Forwarder.initialize, (address(_pa), _INITIAL_LOGIC_REF, _FORWARDER_OWNER))
            )
        );

        _reinitializeCalldata = abi.encodeCall(ERC20ForwarderUpgradeExample.reinitializeLogicRef, (_UPGRADED_LOGIC_REF));

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
            address(_fwdProxy), "ERC20ForwarderUpgradeExample.sol:ERC20ForwarderUpgradeExample", _reinitializeCalldata
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
        emit Initializable.Initialized({
            version: ERC20ForwarderUpgradeExample(_upgradedImplementation).REINITIALIZER_VERSION()
        });

        vm.prank(_FORWARDER_OWNER);
        _fwdProxy.upgradeToAndCall({newImplementation: _upgradedImplementation, data: _reinitializeCalldata});
    }

    function test_upgradeToAndCall_with_the_initialization_data_sets_the_logic_ref_of_a_production_and_a_staging_proxy()
        public
    {
        // As in production, this proxy ran only `initialize`.
        address productionProxy = address(_fwdProxy);

        // As in staging, this proxy also ran the reinitializer of the implementation before.
        address stagingProxy = _deployProxy();
        vm.prank(_FORWARDER_OWNER);
        ERC20Forwarder(stagingProxy).reinitializeLogicRef(_UPGRADED_LOGIC_REF);

        assertNotEq(ILogicRefSpecific(productionProxy).getLogicRef(), Parameters.LOGIC_REF, "logic ref already set");
        assertNotEq(ILogicRefSpecific(stagingProxy).getLogicRef(), Parameters.LOGIC_REF, "logic ref already set");

        bytes memory initializationData = new DeployERC20ForwarderImplementation().INITIALIZATION_DATA();

        vm.startPrank(_FORWARDER_OWNER);
        UUPSUpgradeable(productionProxy).upgradeToAndCall({
            newImplementation: _upgradedImplementation, data: initializationData
        });
        UUPSUpgradeable(stagingProxy).upgradeToAndCall({
            newImplementation: _upgradedImplementation, data: initializationData
        });
        vm.stopPrank();

        assertEq(ILogicRefSpecific(productionProxy).getLogicRef(), Parameters.LOGIC_REF);
        assertEq(ILogicRefSpecific(stagingProxy).getLogicRef(), Parameters.LOGIC_REF);
    }

    function test_reinitializeLogicRef_replaces_the_logic_ref() public {
        assertNotEq(_INITIAL_LOGIC_REF, _UPGRADED_LOGIC_REF);

        vm.prank(_FORWARDER_OWNER);
        ERC20Forwarder(address(_fwdProxy)).reinitializeLogicRef(_UPGRADED_LOGIC_REF);

        assertEq(ILogicRefSpecific(address(_fwdProxy)).getLogicRef(), _UPGRADED_LOGIC_REF);
    }

    function test_reinitializeLogicRef_reverts_if_the_caller_is_not_the_owner() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        ERC20Forwarder(address(_fwdProxy)).reinitializeLogicRef(_UPGRADED_LOGIC_REF);
    }

    function test_reinitializeLogicRef_reverts_after_an_upgrade_without_the_call_if_the_caller_is_not_the_owner()
        public
    {
        vm.prank(_FORWARDER_OWNER);
        _fwdProxy.upgradeToAndCall({newImplementation: _upgradedImplementation, data: ""});

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        ERC20ForwarderUpgradeExample(address(_fwdProxy)).reinitializeLogicRef(_UPGRADED_LOGIC_REF);
    }

    function test_reinitializeLogicRef_reverts_if_it_runs_a_second_time() public {
        vm.startPrank(_FORWARDER_OWNER);
        ERC20Forwarder(address(_fwdProxy)).reinitializeLogicRef(_UPGRADED_LOGIC_REF);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ERC20Forwarder(address(_fwdProxy)).reinitializeLogicRef(_INITIAL_LOGIC_REF);
        vm.stopPrank();
    }

    function test_reinitializeLogicRef_reverts_on_the_zero_logic_ref() public {
        vm.expectRevert(ILogicRefSpecific.ZeroLogicRefNotAllowed.selector);
        vm.prank(_FORWARDER_OWNER);
        ERC20Forwarder(address(_fwdProxy)).reinitializeLogicRef(bytes32(0));
    }

    function testFuzz_reinitializeLogicRef_reverts_if_the_protocol_adapter_denies_the_logic_ref(bool consumed) public {
        _pa.mockSetLogicRefDenied({logicRef: _UPGRADED_LOGIC_REF, consumed: consumed, isDenied: true});

        vm.expectRevert(
            abi.encodeWithSelector(ERC20Forwarder.LogicRefAlreadyDenied.selector, _UPGRADED_LOGIC_REF, consumed)
        );
        vm.prank(_FORWARDER_OWNER);
        ERC20Forwarder(address(_fwdProxy)).reinitializeLogicRef(_UPGRADED_LOGIC_REF);
    }

    function _deployProxy() internal returns (address proxy) {
        proxy = address(
            new ERC1967Proxy({
                implementation: Upgrades.getImplementationAddress(address(_fwdProxy)),
                _data: abi.encodeCall(ERC20Forwarder.initialize, (address(_pa), _INITIAL_LOGIC_REF, _FORWARDER_OWNER))
            })
        );
    }
}
