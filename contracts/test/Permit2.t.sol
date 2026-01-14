// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std-1.14.0/src/Test.sol";
import {IPermit2} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IPermit2.sol";
import {Permit2Lib} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/libraries/Permit2Lib.sol";

import {DeployPermit2} from "./script/DeployPermit2.s.sol";

contract DeployPermit2Test is Test {
    IPermit2 internal _permit2;

    function setUp() public {
        _permit2 = new DeployPermit2().run();
    }

    function test_deploys_Permit2_to_the_canonical_address() public view {
        assertEq(address(_permit2), address(Permit2Lib.PERMIT2));
    }
}
