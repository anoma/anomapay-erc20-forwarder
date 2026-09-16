// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin-contracts-5.7.0/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.7.0/utils/ReentrancyGuard.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.0.0/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.16.2/src/Test.sol";

import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {IERC20ForwarderMigration} from "../../src/migration/IERC20ForwarderMigration.sol";
import {ERC20ReentrantExample} from "../examples/ERC20ReentrantExample.sol";
import {ERC20ForwarderMock} from "../mocks/ERC20Forwarder.m.sol";
import {ERC20ForwarderV1Mock} from "../mocks/ERC20ForwarderV1.m.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

/// @notice Checks the migration contract, which moves the V1 custody to the one destination it is built with. The
/// owner picks the tokens, so every test states what a batch leaves behind.
contract ERC20ForwarderMigrationUnitTest is Test {
    uint128 internal constant _AMOUNT = 42;

    ProtocolAdapterMock internal _protocolAdapterV1;
    ERC20ForwarderV1Mock internal _forwarderV1;
    address internal _forwarderV2;
    ERC20Example internal _token;
    ERC20ForwarderMigration internal _migration;
    IERC20[] internal _tokens;

    function setUp() public {
        _protocolAdapterV1 = new ProtocolAdapterMock(address(this));
        _protocolAdapterV1.emergencyStop();

        _forwarderV1 =
            new ERC20ForwarderV1Mock({protocolAdapter: address(_protocolAdapterV1), emergencyCommittee: address(this)});
        _forwarderV2 = address(
            new ERC20ForwarderMock({owner_: makeAddr("proxy owner"), protocolAdapter: makeAddr("protocol adapter v2")})
        );

        _token = new ERC20Example();
        _tokens.push(_token);

        _migration = new ERC20ForwarderMigration(address(_forwarderV1), _forwarderV2, address(this));
        _forwarderV1.setEmergencyCaller(address(_migration));
    }

    function testFuzz_migrate_moves_the_full_balance_to_the_destination(uint128 amount, uint128 held) public {
        _token.mint(address(_forwarderV1), amount);
        _token.mint(_forwarderV2, held);

        _migration.migrate(_tokens);

        assertEq(_token.balanceOf(address(_forwarderV1)), 0, "the source keeps a balance");
        assertEq(_token.balanceOf(_forwarderV2), uint256(held) + amount, "the destination balance differs");
        assertEq(_token.balanceOf(address(_migration)), 0, "the migration keeps a balance");
    }

    function test_migrate_emits_the_ERC20TokenMigrated_event() public {
        _token.mint(address(_forwarderV1), _AMOUNT);

        vm.expectEmit(address(_migration));
        emit IERC20ForwarderMigration.ERC20TokenMigrated(address(_forwarderV1), _forwarderV2, address(_token), _AMOUNT);

        _migration.migrate(_tokens);
    }

    function test_migrate_emits_no_event_for_a_zero_balance() public {
        vm.recordLogs();
        _migration.migrate(_tokens);

        assertEq(vm.getRecordedLogs().length, 0, "a token without a balance emitted an event");
    }

    function test_migrate_moves_a_token_left_out_of_an_earlier_batch() public {
        ERC20Example laterToken = new ERC20Example();
        _token.mint(address(_forwarderV1), _AMOUNT);
        laterToken.mint(address(_forwarderV1), _AMOUNT);

        _migration.migrate(_tokens);
        assertEq(laterToken.balanceOf(address(_forwarderV1)), _AMOUNT, "the omitted token moved");

        _tokens.push(laterToken);
        _migration.migrate(_tokens);

        assertEq(_token.balanceOf(_forwarderV2), _AMOUNT, "the first token moved twice");
        assertEq(laterToken.balanceOf(_forwarderV2), _AMOUNT, "the omitted token did not move");
    }

    function test_migrate_ignores_a_duplicate_token() public {
        _token.mint(address(_forwarderV1), _AMOUNT);
        _tokens.push(_token);

        _migration.migrate(_tokens);

        assertEq(_token.balanceOf(_forwarderV2), _AMOUNT, "the destination balance differs");
    }

    function test_migrate_reverts_if_the_caller_is_not_the_owner() public {
        address caller = makeAddr("not the owner");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        _migration.migrate(_tokens);
    }

    function test_migrate_reverts_if_the_balance_exceeds_the_v1_amount_type() public {
        uint256 amount = uint256(type(uint128).max) + 1;
        _token.mint(address(_forwarderV1), amount);

        vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, amount));
        _migration.migrate(_tokens);

        assertEq(_token.balanceOf(address(_forwarderV1)), amount, "the source lost the balance");
    }

    function test_migrate_reverts_if_the_destination_does_not_receive_the_amount() public {
        ERC20Example firstToken = new ERC20Example();
        firstToken.mint(address(_forwarderV1), _AMOUNT);
        _token.mint(address(_forwarderV1), _AMOUNT);
        _tokens[0] = firstToken;
        _tokens.push(_token);

        // A token that reports an unchanged destination balance, as a token taking a transfer fee does.
        vm.mockCall(address(_token), abi.encodeCall(IERC20.balanceOf, (_forwarderV2)), abi.encode(uint256(0)));

        vm.expectRevert(abi.encodeWithSelector(ERC20ForwarderMigration.IncompleteMigration.selector, address(_token)));
        _migration.migrate(_tokens);

        assertEq(firstToken.balanceOf(_forwarderV2), 0, "the batch moved the token before the failing one");
        assertEq(_token.balanceOf(address(_forwarderV1)), _AMOUNT, "the source lost the balance");
    }

    function test_migrate_reverts_if_it_is_reentered() public {
        ERC20ReentrantExample reentrantToken = new ERC20ReentrantExample();
        reentrantToken.mint(address(_forwarderV1), _AMOUNT);
        reentrantToken.setMigration(_migration);
        _tokens[0] = reentrantToken;

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _migration.migrate(_tokens);

        assertEq(reentrantToken.balanceOf(address(_forwarderV1)), _AMOUNT, "the source lost the balance");
    }

    function test_migrate_reverts_if_v1_holds_no_emergency_caller() public {
        ERC20ForwarderV1Mock forwarderV1 =
            new ERC20ForwarderV1Mock({protocolAdapter: address(_protocolAdapterV1), emergencyCommittee: address(this)});
        ERC20ForwarderMigration migration =
            new ERC20ForwarderMigration(address(forwarderV1), _forwarderV2, address(this));
        _token.mint(address(forwarderV1), _AMOUNT);

        vm.expectRevert(ERC20ForwarderV1Mock.EmergencyCallerNotSet.selector);
        migration.migrate(_tokens);

        assertEq(_token.balanceOf(address(forwarderV1)), _AMOUNT, "the source lost the balance");
    }

    function test_migrate_reverts_if_v1_holds_another_emergency_caller() public {
        address emergencyCaller = makeAddr("another emergency caller");
        ERC20ForwarderV1Mock forwarderV1 =
            new ERC20ForwarderV1Mock({protocolAdapter: address(_protocolAdapterV1), emergencyCommittee: address(this)});
        forwarderV1.setEmergencyCaller(emergencyCaller);
        ERC20ForwarderMigration migration =
            new ERC20ForwarderMigration(address(forwarderV1), _forwarderV2, address(this));
        _token.mint(address(forwarderV1), _AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20ForwarderV1Mock.UnauthorizedCaller.selector, emergencyCaller, address(migration)
            )
        );
        migration.migrate(_tokens);

        assertEq(_token.balanceOf(address(forwarderV1)), _AMOUNT, "the source lost the balance");
    }

    function test_constructor_reverts_if_the_forwarders_are_the_same_contract() public {
        vm.expectRevert(ERC20ForwarderMigration.InvalidForwarders.selector);
        new ERC20ForwarderMigration(address(_forwarderV1), address(_forwarderV1), address(this));
    }

    function test_constructor_reverts_if_a_forwarder_is_the_zero_address() public {
        vm.expectRevert(ERC20ForwarderMigration.InvalidForwarders.selector);
        new ERC20ForwarderMigration(address(0), _forwarderV2, address(this));

        vm.expectRevert(ERC20ForwarderMigration.InvalidForwarders.selector);
        new ERC20ForwarderMigration(address(_forwarderV1), address(0), address(this));
    }

    function test_constructor_reverts_if_a_forwarder_carries_no_code() public {
        vm.expectRevert(ERC20ForwarderMigration.InvalidForwarders.selector);
        new ERC20ForwarderMigration(address(_forwarderV1), makeAddr("account"), address(this));
    }

    function test_constructor_reverts_if_the_initial_owner_is_the_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ERC20ForwarderMigration(address(_forwarderV1), _forwarderV2, address(0));
    }

    function test_transferOwnership_moves_the_migration_only_once_the_successor_accepts() public {
        address successor = makeAddr("successor");
        _token.mint(address(_forwarderV1), _AMOUNT);

        _migration.transferOwnership(successor);
        assertEq(_migration.owner(), address(this), "the transfer moved the ownership before acceptance");

        vm.prank(successor);
        _migration.acceptOwnership();
        assertEq(_migration.owner(), successor, "the acceptance did not move the ownership");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _migration.migrate(_tokens);

        vm.prank(successor);
        _migration.migrate(_tokens);
        assertEq(_token.balanceOf(_forwarderV2), _AMOUNT, "the successor could not migrate");
    }

    function test_renounceOwnership_reverts() public {
        vm.expectRevert(ERC20ForwarderMigration.RenunciationDisabled.selector);
        _migration.renounceOwnership();
    }
}
