// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts-5.7.0/utils/math/SafeCast.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.0.0/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.16.2/src/Test.sol";

import {ERC20ForwarderMigration} from "../src/migration/ERC20ForwarderMigration.sol";
import {IERC20ForwarderMigration} from "../src/migration/IERC20ForwarderMigration.sol";

contract ERC20ForwarderV1Mock {
    address public emergencyCaller;
    error WrongCaller();
    error WrongCallType();

    function setEmergencyCaller(address caller) external {
        emergencyCaller = caller;
    }

    function forwardEmergencyCall(bytes calldata input) external returns (bytes memory output) {
        require(msg.sender == emergencyCaller, WrongCaller());
        (uint8 callType, IERC20 token, uint128 amount, address receiver) =
            abi.decode(input, (uint8, IERC20, uint128, address));
        require(callType == 1, WrongCallType());
        SafeERC20.safeTransfer(token, receiver, amount);
        output = "";
    }
}

contract ERC20ForwarderMigrationTest is Test {
    ERC20ForwarderMigration internal _migration;
    ERC20ForwarderV1Mock internal _v1;
    address internal _v2;
    ERC20Example internal _token;
    IERC20[] internal _tokens;

    function setUp() public {
        _v1 = new ERC20ForwarderV1Mock();
        _v2 = address(new ERC20ForwarderV1Mock());
        _token = new ERC20Example();
        _tokens.push(_token);
        _migration = new ERC20ForwarderMigration(address(_v1), _v2, address(this));
        _v1.setEmergencyCaller(address(_migration));
    }

    function testFuzz_migratesFullBalanceToFixedDestination(uint128 amount, uint128 existing) public {
        _token.mint(address(_v1), amount);
        _token.mint(_v2, existing);
        _migration.migrate(_tokens);
        assertEq(_token.balanceOf(address(_v1)), 0);
        assertEq(_token.balanceOf(_v2), uint256(existing) + amount);
        assertEq(_token.balanceOf(address(_migration)), 0);
    }

    function test_emitsCanonicalV1ToV2MigrationEvent() public {
        uint128 amount = 42;
        _token.mint(address(_v1), amount);
        vm.expectEmit(address(_migration));
        emit IERC20ForwarderMigration.ERC20TokenMigrated(address(_v1), _v2, address(_token), amount);
        _migration.migrate(_tokens);
    }

    function test_nonOwnerCannotMigrate() public {
        address caller = makeAddr("non-owner");
        vm.prank(caller);
        bytes memory unauthorized = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller);
        vm.expectRevert(unauthorized);
        _migration.migrate(_tokens);
    }

    function test_omittedTokensDuplicatesAndRepeatedCalls() public {
        ERC20Example laterToken = new ERC20Example();
        _token.mint(address(_v1), 42);
        laterToken.mint(address(_v1), 99);
        _tokens.push(_token);
        _migration.migrate(_tokens);
        assertEq(laterToken.balanceOf(address(_v1)), 99);
        _tokens.push(laterToken);
        _migration.migrate(_tokens);
        _migration.migrate(_tokens);
        assertEq(_token.balanceOf(_v2), 42);
        assertEq(laterToken.balanceOf(_v2), 99);
    }

    function test_ownershipTransferRequiresAcceptanceAndCannotBeRenounced() public {
        address successor = makeAddr("successor");
        _migration.transferOwnership(successor);
        assertEq(_migration.owner(), address(this));
        vm.prank(successor);
        _migration.acceptOwnership();
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _migration.migrate(_tokens);
        vm.startPrank(successor);
        _migration.migrate(_tokens);
        vm.expectRevert(ERC20ForwarderMigration.RenunciationDisabled.selector);
        _migration.renounceOwnership();
        vm.stopPrank();
    }

    function test_rejectsInvalidDestinationsAndZeroOwner() public {
        vm.expectRevert(ERC20ForwarderMigration.InvalidForwarders.selector);
        new ERC20ForwarderMigration(address(_v1), address(_v1), address(this));
        vm.expectRevert(ERC20ForwarderMigration.InvalidForwarders.selector);
        new ERC20ForwarderMigration(address(0), _v2, address(this));
        vm.expectRevert(ERC20ForwarderMigration.InvalidForwarders.selector);
        new ERC20ForwarderMigration(address(_v1), makeAddr("EOA"), address(this));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ERC20ForwarderMigration(address(_v1), _v2, address(0));
    }

    function test_overflowRevertsWithoutTruncating() public {
        uint256 amount = uint256(type(uint128).max) + 1;
        _token.mint(address(_v1), amount);
        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, amount));
        _migration.migrate(_tokens);
        assertEq(_token.balanceOf(address(_v1)), amount);
    }

    function test_shortReceiptRevertsEntireBatch() public {
        ERC20Example firstToken = new ERC20Example();
        firstToken.mint(address(_v1), 99);
        _tokens[0] = firstToken;
        _tokens.push(_token);
        _token.mint(address(_v1), 42);
        vm.mockCall(address(_token), abi.encodeCall(IERC20.balanceOf, (_v2)), abi.encode(uint256(0)));
        vm.expectRevert(abi.encodeWithSelector(ERC20ForwarderMigration.IncompleteMigration.selector, address(_token)));
        _migration.migrate(_tokens);
        assertEq(_token.balanceOf(address(_v1)), 42);
        assertEq(firstToken.balanceOf(address(_v1)), 99);
        assertEq(firstToken.balanceOf(_v2), 0);
    }

    function test_v1FailurePropagatesWithoutMovingCustody() public {
        _token.mint(address(_v1), 42);
        _v1.setEmergencyCaller(makeAddr("different caller"));
        vm.expectRevert(ERC20ForwarderV1Mock.WrongCaller.selector);
        _migration.migrate(_tokens);
        assertEq(_token.balanceOf(address(_v1)), 42);
        assertEq(_token.balanceOf(_v2), 0);
    }
}
