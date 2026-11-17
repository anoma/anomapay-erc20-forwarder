// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.1.0/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.4/src/Upgrades.sol";

import {ExecuteERC20ForwarderWithdrawal} from "../../../script/staging/ExecuteERC20ForwarderWithdrawal.s.sol";
import {StagingScript} from "../../../script/staging/StagingScript.s.sol";
import {DeployERC20ForwarderProxyMock} from "../../mocks/DeployERC20ForwarderProxy.m.sol";
import {ExecuteERC20ForwarderWithdrawalMock} from "../../mocks/ExecuteERC20ForwarderWithdrawal.m.sol";

/// @notice Checks the staging-only withdrawal script. `WithdrawingERC20Forwarder.t.sol` covers the withdrawal itself.
contract ExecuteERC20ForwarderWithdrawalTest is Test {
    uint256 internal constant _AMOUNT = 42;

    address internal immutable _PROTOCOL_ADAPTER = makeAddr("protocol adapter");

    address internal _stagingProxy;
    address internal _productionProxy;
    IERC20[] internal _tokens;

    function setUp() public {
        DeployERC20ForwarderProxyMock deployScript = new DeployERC20ForwarderProxyMock(_PROTOCOL_ADAPTER);

        (_stagingProxy,,,) = deployScript.run({isProduction: false});
        (_productionProxy,,,) = deployScript.run({isProduction: true});

        for (uint256 i = 1; i <= 2; ++i) {
            ERC20Example token = new ERC20Example();
            token.mint({to: _stagingProxy, value: i * _AMOUNT});
            _tokens.push(token);
        }
    }

    function test_run_upgrades_the_proxy_and_sends_its_tokens_to_the_recipient() public {
        ExecuteERC20ForwarderWithdrawal script = new ExecuteERC20ForwarderWithdrawalMock(_stagingProxy, _tokens);
        address recipient = script.RECIPIENT();

        (address implementation,, uint256[] memory amounts) = script.run();

        assertEq(Upgrades.getImplementationAddress(_stagingProxy), implementation);
        for (uint256 i = 0; i < _tokens.length; ++i) {
            assertEq(amounts[i], (i + 1) * _AMOUNT, "the returned amount differs");
            assertEq(_tokens[i].balanceOf(_stagingProxy), 0, "the proxy keeps a balance");
            assertEq(_tokens[i].balanceOf(recipient), amounts[i], "the recipient balance differs");
        }
    }

    function test_run_reuses_the_deployed_implementation() public {
        ExecuteERC20ForwarderWithdrawal script = new ExecuteERC20ForwarderWithdrawalMock(_stagingProxy, _tokens);
        (address implementation,,) = script.run();

        (address reusedImplementation,, uint256[] memory amounts) = script.run();

        assertEq(reusedImplementation, implementation);
        for (uint256 i = 0; i < _tokens.length; ++i) {
            assertEq(amounts[i], 0, "the second run withdraws an amount");
        }
    }

    function test_run_reverts_if_the_proxy_is_not_a_staging_deployment() public {
        ExecuteERC20ForwarderWithdrawal script = new ExecuteERC20ForwarderWithdrawalMock(_productionProxy, _tokens);

        vm.expectRevert(abi.encodeWithSelector(StagingScript.NotAStagingDeployment.selector, _productionProxy));
        script.run();
    }

    function test_run_reverts_on_a_chain_without_listed_tokens() public {
        ExecuteERC20ForwarderWithdrawal script = new ExecuteERC20ForwarderWithdrawal();

        vm.expectRevert(abi.encodeWithSelector(ExecuteERC20ForwarderWithdrawal.NoTokensListed.selector, block.chainid));
        script.run();
    }
}
