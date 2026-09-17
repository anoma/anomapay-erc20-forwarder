// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1967} from "@openzeppelin-contracts-5.7.0/interfaces/IERC1967.sol";
import {Test} from "forge-std-1.16.2/src/Test.sol";

import {DeployERC20ForwarderImplementation} from "../../../script/DeployERC20ForwarderImplementation.s.sol";
import {ExecuteERC20ForwarderUpgrade} from "../../../script/staging/ExecuteERC20ForwarderUpgrade.s.sol";
import {StagingScript} from "../../../script/staging/StagingScript.s.sol";
import {DeployERC20ForwarderProxyMock} from "../../mocks/DeployERC20ForwarderProxy.m.sol";

/// @notice Checks the staging-only upgrade execution script. `ERC20Forwarder.upgrade.t.sol` covers the upgrade
/// mechanism itself.
contract ExecuteERC20ForwarderUpgradeTest is Test {
    address internal immutable _PROTOCOL_ADAPTER = makeAddr("protocol adapter");

    address internal _stagingProxy;
    address internal _productionProxy;
    address internal _implementation;

    function setUp() public {
        DeployERC20ForwarderProxyMock deployScript = new DeployERC20ForwarderProxyMock(_PROTOCOL_ADAPTER);

        (_stagingProxy, _implementation,,) = deployScript.run({isProduction: false});
        (_productionProxy,,,) = deployScript.run({isProduction: true});
    }

    function test_run_upgrades_the_proxy() public {
        ExecuteERC20ForwarderUpgrade script = new ExecuteERC20ForwarderUpgrade();

        vm.expectEmit(_stagingProxy);
        emit IERC1967.Upgraded(_implementation);
        script.run({proxy: _stagingProxy, newImplementation: _implementation});
    }

    function test_run_reverts_if_the_proxy_is_not_a_staging_deployment() public {
        ExecuteERC20ForwarderUpgrade script = new ExecuteERC20ForwarderUpgrade();

        vm.expectRevert(abi.encodeWithSelector(StagingScript.NotAStagingDeployment.selector, _productionProxy));
        script.run({proxy: _productionProxy, newImplementation: _implementation});
    }

    function test_run_reverts_if_the_implementation_is_not_deployed() public {
        ExecuteERC20ForwarderUpgrade script = new ExecuteERC20ForwarderUpgrade();

        vm.etch(_implementation, "");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployERC20ForwarderImplementation.ImplementationNotDeployed.selector, _implementation
            )
        );
        script.run({proxy: _stagingProxy, newImplementation: _implementation});
    }

    function test_run_reverts_if_the_implementation_is_unexpected() public {
        ExecuteERC20ForwarderUpgrade script = new ExecuteERC20ForwarderUpgrade();
        address unexpected = makeAddr("unexpected implementation");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployERC20ForwarderImplementation.UnexpectedImplementation.selector, _implementation, unexpected
            )
        );
        script.run({proxy: _stagingProxy, newImplementation: unexpected});
    }
}
