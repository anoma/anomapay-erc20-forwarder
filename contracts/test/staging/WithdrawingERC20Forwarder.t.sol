// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.7.0/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin-contracts-5.7.0/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.1.0/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.4/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.4/src/Upgrades.sol";

import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {IWithdrawingERC20Forwarder} from "../../src/staging/IWithdrawingERC20Forwarder.sol";
import {WithdrawingERC20Forwarder} from "../../src/staging/WithdrawingERC20Forwarder.sol";

/// @dev Each test upgrades a regular forwarder that holds two tokens.
contract WithdrawingERC20ForwarderTest is Test {
    bytes32 internal constant _LOGIC_REF = bytes32(type(uint256).max);
    uint256 internal constant _AMOUNT = 42;

    address internal immutable _PROTOCOL_ADAPTER = makeAddr("protocol adapter");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");
    address internal immutable _RECIPIENT = makeAddr("recipient");

    address internal _forwarder;
    address internal _implementation;
    IERC20[] internal _tokens;

    function setUp() public {
        _forwarder = address(
            new ERC1967Proxy(
                address(new ERC20Forwarder()),
                abi.encodeCall(ERC20Forwarder.initialize, (_PROTOCOL_ADAPTER, _LOGIC_REF, _FORWARDER_OWNER))
            )
        );
        _implementation = address(new WithdrawingERC20Forwarder(_RECIPIENT));

        for (uint256 i = 1; i <= 2; ++i) {
            ERC20Example token = new ERC20Example();
            token.mint({to: _forwarder, value: i * _AMOUNT});
            _tokens.push(token);
        }
    }

    /// @dev The only upgrade that runs the upgrade-safety validation, because each validation takes an `npx` call.
    function test_upgrades_safely() public {
        Options memory options;
        options.constructorData = abi.encode(_RECIPIENT);

        // `Upgrades.upgradeProxy` deploys the implementation before it upgrades, so one `vm.prank` covers only the
        // deploy.
        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            _forwarder,
            "WithdrawingERC20Forwarder.sol:WithdrawingERC20Forwarder",
            abi.encodeCall(IWithdrawingERC20Forwarder.withdraw, (_tokens)),
            options
        );
        vm.stopPrank();
    }

    function test_constructor_reverts_on_the_zero_recipient() public {
        vm.expectRevert(WithdrawingERC20Forwarder.ZeroRecipientNotAllowed.selector);
        new WithdrawingERC20Forwarder(address(0));
    }

    function test_withdraw_sends_the_full_balance_of_each_token_to_the_recipient() public {
        uint256[] memory amounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; ++i) {
            amounts[i] = _tokens[i].balanceOf(_forwarder);
            assertGt(amounts[i], 0, "the forwarder holds none of the token before the withdrawal");
        }

        _upgradeAndWithdraw();

        for (uint256 i = 0; i < _tokens.length; ++i) {
            assertEq(_tokens[i].balanceOf(_forwarder), 0, "the forwarder keeps a balance");
            assertEq(_tokens[i].balanceOf(_RECIPIENT), amounts[i], "the recipient balance differs");
        }
    }

    function test_withdraw_emits_the_Withdrawn_event_for_each_token() public {
        for (uint256 i = 0; i < _tokens.length; ++i) {
            vm.expectEmit(_forwarder);
            emit IWithdrawingERC20Forwarder.Withdrawn({
                token: address(_tokens[i]), to: _RECIPIENT, amount: _tokens[i].balanceOf(_forwarder)
            });
        }

        _upgradeAndWithdraw();
    }

    function test_withdraw_reverts_if_the_caller_is_not_the_owner() public {
        vm.prank(_FORWARDER_OWNER);
        UUPSUpgradeable(_forwarder).upgradeToAndCall({newImplementation: _implementation, data: ""});

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        IWithdrawingERC20Forwarder(_forwarder).withdraw(_tokens);
    }

    function test_upgradeToAndCall_keeps_the_owner_the_protocol_adapter_and_the_logic_ref() public {
        _upgradeAndWithdraw();

        WithdrawingERC20Forwarder forwarder = WithdrawingERC20Forwarder(_forwarder);
        assertEq(forwarder.owner(), _FORWARDER_OWNER);
        assertEq(forwarder.getProtocolAdapter(), _PROTOCOL_ADAPTER);
        assertEq(forwarder.getLogicRef(), _LOGIC_REF);
        assertEq(forwarder.RECIPIENT(), _RECIPIENT);
    }

    function _upgradeAndWithdraw() internal {
        vm.prank(_FORWARDER_OWNER);
        UUPSUpgradeable(_forwarder).upgradeToAndCall({
            newImplementation: _implementation, data: abi.encodeCall(IWithdrawingERC20Forwarder.withdraw, (_tokens))
        });
    }
}
