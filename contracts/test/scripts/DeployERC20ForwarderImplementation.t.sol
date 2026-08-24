// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {DeployERC20ForwarderImplementation} from "../../script/DeployERC20ForwarderImplementation.s.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";

/// @notice Checks the implementation deploy script.
contract DeployERC20ForwarderImplementationTest is Test {
    function test_run_deploys_deterministically() public {
        DeployERC20ForwarderImplementation script = new DeployERC20ForwarderImplementation();
        address implementation = script.run();

        address predicted =
            vm.computeCreate2Address(script.IMPLEMENTATION_SALT(), keccak256(type(ERC20Forwarder).creationCode));

        assertEq(implementation, predicted, "implementation address differs from the prediction");
        assertGt(implementation.code.length, 0, "implementation is not deployed");
    }

    function test_run_reverts_if_the_implementation_is_already_deployed() public {
        DeployERC20ForwarderImplementation script = new DeployERC20ForwarderImplementation();
        address implementation = script.run();

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployERC20ForwarderImplementation.ImplementationAlreadyDeployed.selector, implementation
            )
        );
        script.run();
    }
}
