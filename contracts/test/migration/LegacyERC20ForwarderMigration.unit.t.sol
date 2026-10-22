// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts-5.7.0/utils/ReentrancyGuard.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.1.0/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";

import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ILegacyERC20ForwarderMigration} from "../../src/migration/ILegacyERC20ForwarderMigration.sol";
import {LegacyERC20ForwarderMigration} from "../../src/migration/LegacyERC20ForwarderMigration.sol";
import {ERC20ReentrantExample} from "../examples/ERC20ReentrantExample.sol";
import {ERC20ForwarderMock} from "../mocks/ERC20Forwarder.m.sol";
import {LegacyERC20ForwarderMock} from "../mocks/LegacyERC20Forwarder.m.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

/// @notice Checks the migration contract, which moves the tokens of the legacy ERC20 forwarder to the one destination
/// it is built with. The owner picks the tokens, so every test states what a batch leaves behind.
contract LegacyERC20ForwarderMigrationUnitTest is Test {
    uint128 internal constant _AMOUNT = 42;

    ProtocolAdapterMock internal _legacyProtocolAdapter;
    LegacyERC20ForwarderMock internal _legacyForwarder;
    address internal _forwarder;
    ERC20Example internal _token;
    LegacyERC20ForwarderMigration internal _migration;
    IERC20[] internal _tokens;

    function setUp() public {
        _legacyProtocolAdapter = new ProtocolAdapterMock(address(this));
        _legacyProtocolAdapter.emergencyStop();

        _legacyForwarder = new LegacyERC20ForwarderMock({
            protocolAdapter: address(_legacyProtocolAdapter), emergencyCommittee: address(this)
        });
        _forwarder = address(
            new ERC20ForwarderMock({owner_: makeAddr("proxy owner"), protocolAdapter: makeAddr("protocol adapter")})
        );

        _token = new ERC20Example();
        _tokens.push(_token);

        _migration = new LegacyERC20ForwarderMigration(address(_legacyForwarder), _forwarder, address(this));
        _legacyForwarder.setEmergencyCaller(address(_migration));
    }

    function testFuzz_migrate_moves_the_full_balance_to_the_destination(uint256 amount, uint128 held) public {
        // Up to three calls of the legacy ERC20 forwarder.
        amount = bound(amount, 0, 3 * uint256(type(uint128).max));
        _token.mint(address(_legacyForwarder), amount);
        _token.mint(_forwarder, held);

        _migration.migrate(_tokens);

        assertEq(_token.balanceOf(address(_legacyForwarder)), 0, "the source keeps a balance");
        assertEq(_token.balanceOf(_forwarder), uint256(held) + amount, "the destination balance differs");
        assertEq(_token.balanceOf(address(_migration)), 0, "the migration keeps a balance");
    }

    function test_migrate_emits_the_ERC20TokenMigrated_event() public {
        _token.mint(address(_legacyForwarder), _AMOUNT);

        vm.expectEmit(address(_migration));
        emit ILegacyERC20ForwarderMigration.ERC20TokenMigrated(
            address(_legacyForwarder), _forwarder, address(_token), _AMOUNT
        );

        _migration.migrate(_tokens);
    }

    function test_migrate_emits_the_event_for_a_zero_balance() public {
        vm.expectEmit(address(_migration));
        emit ILegacyERC20ForwarderMigration.ERC20TokenMigrated(
            address(_legacyForwarder), _forwarder, address(_token), 0
        );

        _migration.migrate(_tokens);
    }

    function test_migrate_moves_a_token_left_out_of_an_earlier_batch() public {
        ERC20Example laterToken = new ERC20Example();
        _token.mint(address(_legacyForwarder), _AMOUNT);
        laterToken.mint(address(_legacyForwarder), _AMOUNT);

        _migration.migrate(_tokens);
        assertEq(laterToken.balanceOf(address(_legacyForwarder)), _AMOUNT, "the omitted token moved");

        _tokens.push(laterToken);
        _migration.migrate(_tokens);

        assertEq(_token.balanceOf(_forwarder), _AMOUNT, "the first token moved twice");
        assertEq(laterToken.balanceOf(_forwarder), _AMOUNT, "the omitted token did not move");
    }

    function test_migrate_ignores_a_duplicate_token() public {
        _token.mint(address(_legacyForwarder), _AMOUNT);
        _tokens.push(_token);

        _migration.migrate(_tokens);

        assertEq(_token.balanceOf(_forwarder), _AMOUNT, "the destination balance differs");
    }

    function test_migrate_reverts_if_the_caller_is_not_the_owner() public {
        address caller = makeAddr("not the owner");

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
        _migration.migrate(_tokens);
    }

    function test_migrate_moves_a_balance_above_the_amount_type_of_the_legacy_forwarder_in_several_calls() public {
        uint128 maxPart = type(uint128).max;
        uint256 amount = 2 * uint256(maxPart) + 1;
        _token.mint(address(_legacyForwarder), amount);

        vm.expectCall(
            address(_legacyForwarder),
            abi.encodeCall(
                LegacyERC20ForwarderMock.forwardEmergencyCall,
                (abi.encode(ERC20Forwarder.CallType.Unwrap, _token, maxPart, _forwarder))
            ),
            2
        );
        vm.expectCall(
            address(_legacyForwarder),
            abi.encodeCall(
                LegacyERC20ForwarderMock.forwardEmergencyCall,
                (abi.encode(ERC20Forwarder.CallType.Unwrap, _token, uint128(1), _forwarder))
            ),
            1
        );
        vm.expectEmit(address(_migration));
        emit ILegacyERC20ForwarderMigration.ERC20TokenMigrated(
            address(_legacyForwarder), _forwarder, address(_token), amount
        );

        _migration.migrate(_tokens);

        assertEq(_token.balanceOf(address(_legacyForwarder)), 0, "the source keeps a balance");
        assertEq(_token.balanceOf(_forwarder), amount, "the destination balance differs");
    }

    function test_migrate_reverts_if_the_destination_does_not_receive_the_amount() public {
        ERC20Example firstToken = new ERC20Example();
        firstToken.mint(address(_legacyForwarder), _AMOUNT);
        _token.mint(address(_legacyForwarder), _AMOUNT);
        _tokens[0] = firstToken;
        _tokens.push(_token);

        // A token that reports an unchanged destination balance, as a token taking a transfer fee does.
        vm.mockCall(address(_token), abi.encodeCall(IERC20.balanceOf, (_forwarder)), abi.encode(uint256(0)));

        vm.expectRevert(
            abi.encodeWithSelector(
                LegacyERC20ForwarderMigration.DestinationBalanceMismatch.selector,
                address(_token),
                uint256(_AMOUNT),
                uint256(0)
            )
        );
        _migration.migrate(_tokens);

        assertEq(firstToken.balanceOf(_forwarder), 0, "the batch moved the token before the failing one");
        assertEq(_token.balanceOf(address(_legacyForwarder)), _AMOUNT, "the source lost the balance");
    }

    function test_migrate_reverts_if_the_source_answers_with_data() public {
        _token.mint(address(_legacyForwarder), _AMOUNT);
        bytes memory output = hex"01";

        // A source forwarder that answers an unwrap with data, which the deployed one never does.
        vm.mockCall(
            address(_legacyForwarder),
            abi.encodeWithSelector(LegacyERC20ForwarderMock.forwardEmergencyCall.selector),
            abi.encode(output)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LegacyERC20ForwarderMigration.UnexpectedEmergencyCallOutput.selector, address(_token), output
            )
        );
        _migration.migrate(_tokens);
    }

    function test_migrate_reverts_if_the_source_keeps_a_balance() public {
        _token.mint(address(_legacyForwarder), _AMOUNT);

        // A token that reports an unchanged source balance, as a token taking a transfer fee does.
        vm.mockCall(
            address(_token), abi.encodeCall(IERC20.balanceOf, (address(_legacyForwarder))), abi.encode(uint256(_AMOUNT))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LegacyERC20ForwarderMigration.SourceBalanceRemaining.selector, address(_token), uint256(_AMOUNT)
            )
        );
        _migration.migrate(_tokens);
    }

    function test_migrate_reverts_if_it_is_reentered() public {
        ERC20ReentrantExample reentrantToken = new ERC20ReentrantExample();
        reentrantToken.mint(address(_legacyForwarder), _AMOUNT);
        reentrantToken.setMigration(_migration);
        _tokens[0] = reentrantToken;

        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _migration.migrate(_tokens);

        assertEq(reentrantToken.balanceOf(address(_legacyForwarder)), _AMOUNT, "the source lost the balance");
    }

    function test_migrate_reverts_if_the_legacy_forwarder_holds_no_emergency_caller() public {
        LegacyERC20ForwarderMock legacyForwarder = new LegacyERC20ForwarderMock({
            protocolAdapter: address(_legacyProtocolAdapter), emergencyCommittee: address(this)
        });
        LegacyERC20ForwarderMigration migration =
            new LegacyERC20ForwarderMigration(address(legacyForwarder), _forwarder, address(this));
        _token.mint(address(legacyForwarder), _AMOUNT);

        vm.expectRevert(LegacyERC20ForwarderMock.EmergencyCallerNotSet.selector);
        migration.migrate(_tokens);

        assertEq(_token.balanceOf(address(legacyForwarder)), _AMOUNT, "the source lost the balance");
    }

    function test_migrate_reverts_if_the_legacy_forwarder_holds_another_emergency_caller() public {
        address emergencyCaller = makeAddr("another emergency caller");
        LegacyERC20ForwarderMock legacyForwarder = new LegacyERC20ForwarderMock({
            protocolAdapter: address(_legacyProtocolAdapter), emergencyCommittee: address(this)
        });
        legacyForwarder.setEmergencyCaller(emergencyCaller);
        LegacyERC20ForwarderMigration migration =
            new LegacyERC20ForwarderMigration(address(legacyForwarder), _forwarder, address(this));
        _token.mint(address(legacyForwarder), _AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                LegacyERC20ForwarderMock.UnauthorizedCaller.selector, emergencyCaller, address(migration)
            )
        );
        migration.migrate(_tokens);

        assertEq(_token.balanceOf(address(legacyForwarder)), _AMOUNT, "the source lost the balance");
    }

    function test_constructor_reverts_if_the_forwarders_are_the_same_contract() public {
        vm.expectRevert(LegacyERC20ForwarderMigration.InvalidForwarders.selector);
        new LegacyERC20ForwarderMigration(address(_legacyForwarder), address(_legacyForwarder), address(this));
    }

    function test_constructor_reverts_if_a_forwarder_is_the_zero_address() public {
        vm.expectRevert(LegacyERC20ForwarderMigration.InvalidForwarders.selector);
        new LegacyERC20ForwarderMigration(address(0), _forwarder, address(this));

        vm.expectRevert(LegacyERC20ForwarderMigration.InvalidForwarders.selector);
        new LegacyERC20ForwarderMigration(address(_legacyForwarder), address(0), address(this));
    }

    function test_constructor_reverts_if_a_forwarder_carries_no_code() public {
        vm.expectRevert(LegacyERC20ForwarderMigration.InvalidForwarders.selector);
        new LegacyERC20ForwarderMigration(address(_legacyForwarder), makeAddr("account"), address(this));
    }

    function test_constructor_reverts_if_the_initial_owner_is_the_zero_address() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new LegacyERC20ForwarderMigration(address(_legacyForwarder), _forwarder, address(0));
    }

    function test_transferOwnership_moves_the_migration_to_the_successor() public {
        address successor = makeAddr("successor");
        _token.mint(address(_legacyForwarder), _AMOUNT);

        _migration.transferOwnership(successor);
        assertEq(_migration.owner(), successor, "the transfer did not move the ownership");

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        _migration.migrate(_tokens);

        vm.prank(successor);
        _migration.migrate(_tokens);
        assertEq(_token.balanceOf(_forwarder), _AMOUNT, "the successor could not migrate");
    }
}
