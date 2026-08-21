// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin-contracts-5.7.0/interfaces/IERC1967.sol";

import {DeployERC20ForwarderImplementation} from "../../../script/DeployERC20ForwarderImplementation.s.sol";
import {DeployERC20ForwarderProxy} from "../../../script/DeployERC20ForwarderProxy.s.sol";
import {ProductionScript} from "../../../script/production/ProductionScript.s.sol";
import {ProposeERC20ForwarderUpgrade} from "../../../script/production/ProposeERC20ForwarderUpgrade.s.sol";
import {ERC20Forwarder} from "../../../src/ERC20Forwarder.sol";
import {SafeFixture} from "../../fixtures/SafeFixture.sol";

/// @notice Checks the production-only upgrade proposal script against a Safe-owned production proxy. Outside
/// broadcast mode, the script simulates the Safe executing the upgrade, so the proxy must end up on the new
/// implementation.
contract ProposeERC20ForwarderUpgradeTest is SafeFixture {
    bytes32 internal constant _LOGIC_REF = bytes32(uint256(1));

    address internal immutable _PROTOCOL_ADAPTER = makeAddr("protocol adapter");

    address internal _owner;
    address internal _safe;
    address internal _productionProxy;
    address internal _stagingProxy;
    address internal _implementation;

    function setUp() public {
        // Keep the script on the simulation branch regardless of the shell environment.
        vm.setEnv("SAFE_BROADCAST", "false");

        DeployERC20ForwarderProxy deployScript = new DeployERC20ForwarderProxy();

        _owner = makeAddr("safe owner");
        _safe = _deploySafeAt(_owner, deployScript.PROXY_OWNER_PRODUCTION());

        (_productionProxy, _implementation,,) =
            deployScript.run({isProduction: true, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});
        (_stagingProxy,,,) =
            deployScript.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});
    }

    function test_run_upgrades_the_proxy() public {
        ProposeERC20ForwarderUpgrade script = new ProposeERC20ForwarderUpgrade();

        vm.expectEmit({
            checkTopic1: true, checkTopic2: false, checkTopic3: false, checkData: true, emitter: _productionProxy
        });
        emit IERC1967.Upgraded(_implementation);

        script.run({proxy: _productionProxy, proposer: _owner, newImplementation: _implementation});

        assertEq(
            ERC20Forwarder(_productionProxy).getImplementation(),
            _implementation,
            "proxy runs a different implementation"
        );
    }

    function test_run_reverts_if_the_proxy_is_not_a_production_deployment() public {
        ProposeERC20ForwarderUpgrade script = new ProposeERC20ForwarderUpgrade();

        vm.expectRevert(abi.encodeWithSelector(ProductionScript.NotAProductionDeployment.selector, _stagingProxy));
        script.run({proxy: _stagingProxy, proposer: _owner, newImplementation: _implementation});
    }

    function test_run_reverts_if_the_implementation_is_not_deployed() public {
        ProposeERC20ForwarderUpgrade script = new ProposeERC20ForwarderUpgrade();

        vm.etch(_implementation, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployERC20ForwarderImplementation.ImplementationNotDeployed.selector, _implementation
            )
        );
        script.run({proxy: _productionProxy, proposer: _owner, newImplementation: _implementation});
    }

    function test_run_reverts_if_the_implementation_is_unexpected() public {
        ProposeERC20ForwarderUpgrade script = new ProposeERC20ForwarderUpgrade();
        address unexpected = makeAddr("unexpected implementation");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployERC20ForwarderImplementation.UnexpectedImplementation.selector, _implementation, unexpected
            )
        );
        script.run({proxy: _productionProxy, proposer: _owner, newImplementation: unexpected});
    }
}
