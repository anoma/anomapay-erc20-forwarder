// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {IForwarder} from "anoma-forwarder-bases-3.0.1/src/interfaces/IForwarder.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-3.0.1/src/interfaces/ILogicRefSpecific.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.0.1/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {IMigratingERC20Forwarder} from "../../src/draft/IMigratingERC20Forwarder.sol";
import {MigratingERC20Forwarder} from "../../src/draft/MigratingERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

contract MigratingERC20ForwarderTest is Test {
    uint128 internal constant _AMOUNT = 1000;
    bytes32 internal constant _RETIRED_LOGIC_REF = bytes32(uint256(1));
    bytes32 internal constant _NEW_LOGIC_REF = bytes32(uint256(2));
    bytes32 internal constant _MIGRATION_ROOT = bytes32(uint256(3));
    bytes32 internal constant _NULLIFIER = bytes32(uint256(4));

    address internal immutable _PA_OWNER = makeAddr("pa owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");
    address internal immutable _RECEIVER = makeAddr("receiver");

    ProtocolAdapterMock internal _pa;
    MigratingERC20Forwarder internal _fwd;
    ERC20Example internal _erc20;

    function setUp() public {
        _erc20 = new ERC20Example();
        _pa = _pausedAdapterHolding(_MIGRATION_ROOT);
        _fwd = _deployForwarder(address(_pa));
    }

    function test_upgrades_safely() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
    }

    function test_reinitialize_rotates_the_logic_ref() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        assertEq(_fwd.getLogicRef(), _NEW_LOGIC_REF);
    }

    function test_reinitialize_records_the_retired_logic_ref_and_its_migration_root() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        assertEq(_fwd.retiredLogicRefCount(), 1);
        assertEq(_fwd.getMigrationRoot(_RETIRED_LOGIC_REF), _MIGRATION_ROOT);

        (bytes32 retiredLogicRef, bytes32 migrationRoot) = _fwd.retiredLogicRefAtIndex(0);
        assertEq(retiredLogicRef, _RETIRED_LOGIC_REF);
        assertEq(migrationRoot, _MIGRATION_ROOT);
    }

    function test_reinitialize_emits_the_LogicRefRetired_event() public {
        address implementation = address(new MigratingERC20Forwarder());
        bytes memory data = abi.encodeCall(MigratingERC20Forwarder.reinitialize, (_NEW_LOGIC_REF, _MIGRATION_ROOT));

        vm.expectEmit(address(_fwd));
        emit IMigratingERC20Forwarder.LogicRefRetired({
            retiredLogicRef: _RETIRED_LOGIC_REF, migrationRoot: _MIGRATION_ROOT, newLogicRef: _NEW_LOGIC_REF
        });

        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function test_reinitialize_reverts_if_the_caller_is_not_the_owner() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        _fwd.reinitialize({newLogicRef: bytes32(uint256(5)), migrationRoot: _MIGRATION_ROOT});
    }

    function test_reinitialize_reverts_on_the_zero_logic_ref() public {
        _expectRetireRevert({
            newLogicRef: bytes32(0),
            migrationRoot: _MIGRATION_ROOT,
            expectedError: abi.encodeWithSelector(ILogicRefSpecific.ZeroLogicRefNotAllowed.selector)
        });
    }

    function test_reinitialize_reverts_if_the_logic_ref_does_not_change() public {
        _expectRetireRevert({
            newLogicRef: _RETIRED_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.UnchangedLogicRef.selector, _RETIRED_LOGIC_REF
            )
        });
    }

    function test_reinitialize_reverts_if_the_protocol_adapter_is_not_paused() public {
        ProtocolAdapterMock runningAdapter = new ProtocolAdapterMock(_PA_OWNER);
        runningAdapter.mockAddCommitmentTreeRoot(_MIGRATION_ROOT);
        _fwd = _deployForwarder(address(runningAdapter));

        _expectRetireRevert({
            newLogicRef: _NEW_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.ProtocolAdapterNotPaused.selector, address(runningAdapter)
            )
        });
    }

    function test_reinitialize_reverts_if_the_protocol_adapter_does_not_hold_the_migration_root() public {
        bytes32 unknownRoot = bytes32(uint256(99));

        _expectRetireRevert({
            newLogicRef: _NEW_LOGIC_REF,
            migrationRoot: unknownRoot,
            expectedError: abi.encodeWithSelector(MigratingERC20Forwarder.UnknownMigrationRoot.selector, unknownRoot)
        });
    }

    /// @dev Only an adapter that removes a denylist entry lets a retired logic ref become current again.
    function test_reinitialize_reverts_if_the_logic_ref_is_retired_already() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        _pa.mockSetLogicRefDenied({logicRef: _RETIRED_LOGIC_REF, isDenied: false});
        _pa.mockSetLogicRefDenied({logicRef: _NEW_LOGIC_REF, isDenied: true});
        vm.prank(_FORWARDER_OWNER);
        _fwd.reinitialize({newLogicRef: _RETIRED_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        _pa.mockSetLogicRefDenied({logicRef: _RETIRED_LOGIC_REF, isDenied: true});
        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(MigratingERC20Forwarder.LogicRefAlreadyRetired.selector, _RETIRED_LOGIC_REF)
        );
        _fwd.reinitialize({newLogicRef: bytes32(uint256(5)), migrationRoot: _MIGRATION_ROOT});
    }

    function test_reinitialize_reverts_if_the_protocol_adapter_does_not_deny_the_retired_logic_ref() public {
        _pa.mockSetLogicRefDenied({logicRef: _RETIRED_LOGIC_REF, isDenied: false});

        _expectRetireRevert({
            newLogicRef: _NEW_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.LogicRefNotDenied.selector, _RETIRED_LOGIC_REF
            )
        });
    }

    function test_reinitialize_reverts_if_the_protocol_adapter_denies_the_new_logic_ref() public {
        _pa.mockSetLogicRefDenied({logicRef: _NEW_LOGIC_REF, isDenied: true});

        _expectRetireRevert({
            newLogicRef: _NEW_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            expectedError: abi.encodeWithSelector(MigratingERC20Forwarder.DeniedLogicRef.selector, _NEW_LOGIC_REF)
        });
    }

    function test_reinitialize_keeps_the_earlier_generation_migratable() public {
        bytes32 thirdLogicRef = bytes32(uint256(5));
        bytes32 secondMigrationRoot = bytes32(uint256(6));
        _pa.mockAddCommitmentTreeRoot(secondMigrationRoot);

        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        _pa.mockSetLogicRefDenied({logicRef: _NEW_LOGIC_REF, isDenied: true});
        vm.prank(_FORWARDER_OWNER);
        _fwd.reinitialize({newLogicRef: thirdLogicRef, migrationRoot: secondMigrationRoot});

        assertEq(_fwd.retiredLogicRefCount(), 2);
        assertEq(_fwd.getMigrationRoot(_RETIRED_LOGIC_REF), _MIGRATION_ROOT);
        assertEq(_fwd.getMigrationRoot(_NEW_LOGIC_REF), secondMigrationRoot);

        // One batch migrates resources of both retired logic refs, each with the root recorded for it.
        MigratingERC20Forwarder.MigrateEntry[] memory entries = new MigratingERC20Forwarder.MigrateEntry[](2);
        entries[0] = _entry({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd)
        });
        entries[1] = _entry({
            retiredLogicRef: _NEW_LOGIC_REF,
            migrationRoot: secondMigrationRoot,
            nullifier: bytes32(uint256(7)),
            forwarder: address(_fwd)
        });
        _migrateBatch(entries);

        assertTrue(_fwd.isNullifierMigrated(_NULLIFIER));
        assertTrue(_fwd.isNullifierMigrated(bytes32(uint256(7))));
    }

    function test_forwardCall_reverts_on_the_retired_logic_ref() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        bytes memory input = _migrateInput(
            _batch({
                retiredLogicRef: _RETIRED_LOGIC_REF,
                migrationRoot: _MIGRATION_ROOT,
                nullifier: _NULLIFIER,
                forwarder: address(_fwd)
            })
        );

        vm.prank(address(_pa));
        vm.expectRevert(
            abi.encodeWithSelector(ILogicRefSpecific.LogicRefMismatch.selector, _NEW_LOGIC_REF, _RETIRED_LOGIC_REF)
        );
        IForwarder(address(_fwd)).forwardCall({logicRef: _RETIRED_LOGIC_REF, input: input});
    }

    function test_migrate_records_the_nullifier() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        assertFalse(_fwd.isNullifierMigrated(_NULLIFIER));
        _migrate({retiredLogicRef: _RETIRED_LOGIC_REF, migrationRoot: _MIGRATION_ROOT, nullifier: _NULLIFIER});
        assertTrue(_fwd.isNullifierMigrated(_NULLIFIER));
    }

    function test_migrate_moves_no_tokens() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        _erc20.mint({to: address(_fwd), value: _AMOUNT});

        _migrate({retiredLogicRef: _RETIRED_LOGIC_REF, migrationRoot: _MIGRATION_ROOT, nullifier: _NULLIFIER});

        assertEq(_erc20.balanceOf(address(_fwd)), _AMOUNT);
    }

    function test_migrate_emits_the_Migrated_event() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        vm.expectEmit(address(_fwd));
        emit IMigratingERC20Forwarder.Migrated({
            token: address(_erc20), retiredLogicRef: _RETIRED_LOGIC_REF, nullifier: _NULLIFIER
        });

        _migrate({retiredLogicRef: _RETIRED_LOGIC_REF, migrationRoot: _MIGRATION_ROOT, nullifier: _NULLIFIER});
    }

    function test_migrate_reverts_if_the_resource_was_migrated_already() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        _migrate({retiredLogicRef: _RETIRED_LOGIC_REF, migrationRoot: _MIGRATION_ROOT, nullifier: _NULLIFIER});

        _expectMigrateRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(MigratingERC20Forwarder.ResourceAlreadyMigrated.selector, _NULLIFIER)
        });
    }

    function test_migrate_reverts_if_the_protocol_adapter_no_longer_denies_the_retired_logic_ref() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        _pa.mockSetLogicRefDenied({logicRef: _RETIRED_LOGIC_REF, isDenied: false});

        _expectMigrateRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.LogicRefNotDenied.selector, _RETIRED_LOGIC_REF
            )
        });
    }

    function test_migrate_reverts_if_the_protocol_adapter_consumed_the_resource() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        _pa.mockAddNullifier(_NULLIFIER);

        _expectMigrateRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(MigratingERC20Forwarder.ResourceAlreadyConsumed.selector, _NULLIFIER)
        });
    }

    function test_migrate_reverts_on_an_unretired_logic_ref() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        _expectMigrateRevert({
            retiredLogicRef: _NEW_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.UnknownRetiredLogicRef.selector, _NEW_LOGIC_REF
            )
        });
    }

    function test_migrate_reverts_on_another_root_than_the_recorded_one() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        bytes32 otherRoot = bytes32(uint256(8));

        _expectMigrateRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            migrationRoot: otherRoot,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.MigrationRootMismatch.selector, _MIGRATION_ROOT, otherRoot
            )
        });
    }

    function test_migrate_reverts_on_another_forwarder() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        address otherForwarder = makeAddr("other forwarder");

        _expectMigrateRevert({
            retiredLogicRef: _RETIRED_LOGIC_REF,
            migrationRoot: _MIGRATION_ROOT,
            nullifier: _NULLIFIER,
            forwarder: otherForwarder,
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.ForwarderMismatch.selector, address(_fwd), otherForwarder
            )
        });
    }

    function test_migrate_records_every_nullifier_of_a_batch() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        MigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 3});

        _migrateBatch(entries);

        for (uint256 i = 0; i < entries.length; ++i) {
            assertTrue(_fwd.isNullifierMigrated(entries[i].nullifier));
        }
    }

    function test_migrate_reverts_if_a_batch_names_a_resource_twice() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        MigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 3});
        entries[2].nullifier = entries[0].nullifier;

        _expectMigrateBatchRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.ResourceAlreadyMigrated.selector, entries[0].nullifier
            )
        });
    }

    function test_migrate_records_nothing_if_a_later_entry_fails() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        MigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 2});
        _pa.mockAddNullifier(entries[1].nullifier);

        _expectMigrateBatchRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                MigratingERC20Forwarder.ResourceAlreadyConsumed.selector, entries[1].nullifier
            )
        });

        assertFalse(_fwd.isNullifierMigrated(entries[0].nullifier));
    }

    function test_migrate_reverts_on_an_empty_batch() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        _expectMigrateBatchRevert({
            entries: new MigratingERC20Forwarder.MigrateEntry[](0),
            expectedError: abi.encodeWithSelector(MigratingERC20Forwarder.EmptyMigrationBatch.selector)
        });
    }

    function test_migrate_reverts_on_trailing_bytes() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        bytes memory input = bytes.concat(_migrateInput(_batchOf({count: 1})), bytes32(0));

        vm.prank(address(_pa));
        vm.expectRevert(abi.encodeWithSelector(ERC20Forwarder.InvalidInputLength.selector, 9 * 32, 10 * 32));
        IForwarder(address(_fwd)).forwardCall({logicRef: _NEW_LOGIC_REF, input: input});
    }

    function test_migrate_decodes_the_encoding_of_the_migration_logic() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});

        // `(CallTypeV2::Migrate, token, quantity, Vec<MigrateV1Data>).abi_encode_params()`, written out by hand.
        bytes memory input = abi.encodePacked(
            abi.encode(uint256(2), address(_erc20), uint256(_AMOUNT), uint256(0x80), uint256(1)),
            abi.encode(_NULLIFIER, _MIGRATION_ROOT, _RETIRED_LOGIC_REF, address(_fwd))
        );
        assertEq(input, _migrateInput(_batchOf({count: 1})));

        vm.prank(address(_pa));
        IForwarder(address(_fwd)).forwardCall({logicRef: _NEW_LOGIC_REF, input: input});

        assertTrue(_fwd.isNullifierMigrated(_NULLIFIER));
    }

    function test_unwrap_still_releases_tokens() public {
        _upgradeAndRetire({newLogicRef: _NEW_LOGIC_REF, migrationRoot: _MIGRATION_ROOT});
        _erc20.mint({to: address(_fwd), value: _AMOUNT});

        bytes memory input = abi.encode(
            MigratingERC20Forwarder.MigratingCallType.Unwrap,
            address(_erc20),
            _AMOUNT,
            ERC20Forwarder.UnwrapData({receiver: _RECEIVER})
        );

        vm.prank(address(_pa));
        IForwarder(address(_fwd)).forwardCall({logicRef: _NEW_LOGIC_REF, input: input});

        assertEq(_erc20.balanceOf(_RECEIVER), _AMOUNT);
        assertEq(_erc20.balanceOf(address(_fwd)), 0);
    }

    /// @dev A paused adapter whose root history contains the root and that denies the logic ref to retire.
    function _pausedAdapterHolding(bytes32 root) internal returns (ProtocolAdapterMock adapter) {
        adapter = new ProtocolAdapterMock(_PA_OWNER);
        adapter.mockAddCommitmentTreeRoot(root);
        adapter.mockSetLogicRefDenied({logicRef: _RETIRED_LOGIC_REF, isDenied: true});

        vm.prank(_PA_OWNER);
        adapter.emergencyStop();
    }

    function _deployForwarder(address protocolAdapter) internal returns (MigratingERC20Forwarder forwarder) {
        forwarder = MigratingERC20Forwarder(
            Upgrades.deployUUPSProxy(
                "ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(ERC20Forwarder.initialize, (protocolAdapter, _RETIRED_LOGIC_REF, _FORWARDER_OWNER))
            )
        );
    }

    /// @dev Upgrades the proxy to the draft and retires its logic reference, as the owner does.
    function _upgradeAndRetire(bytes32 newLogicRef, bytes32 migrationRoot) internal {
        // `startPrank` keeps the owner as the caller across the implementation deploy and the `upgradeToAndCall`
        // that `Upgrades.upgradeProxy` performs internally; a single `vm.prank` would only apply to the deploy.
        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            address(_fwd),
            "MigratingERC20Forwarder.sol:MigratingERC20Forwarder",
            abi.encodeCall(MigratingERC20Forwarder.reinitialize, (newLogicRef, migrationRoot))
        );
        vm.stopPrank();
    }

    function _expectRetireRevert(bytes32 newLogicRef, bytes32 migrationRoot, bytes memory expectedError) internal {
        address implementation = address(new MigratingERC20Forwarder());
        bytes memory data = abi.encodeCall(MigratingERC20Forwarder.reinitialize, (newLogicRef, migrationRoot));

        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(expectedError);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function _migrate(bytes32 retiredLogicRef, bytes32 migrationRoot, bytes32 nullifier) internal {
        _migrateBatch(
            _batch({
                retiredLogicRef: retiredLogicRef,
                migrationRoot: migrationRoot,
                nullifier: nullifier,
                forwarder: address(_fwd)
            })
        );
    }

    function _migrateBatch(MigratingERC20Forwarder.MigrateEntry[] memory entries) internal {
        bytes32 logicRef = _fwd.getLogicRef();
        bytes memory input = _migrateInput(entries);

        vm.prank(address(_pa));
        IForwarder(address(_fwd)).forwardCall({logicRef: logicRef, input: input});
    }

    function _expectMigrateRevert(
        bytes32 retiredLogicRef,
        bytes32 migrationRoot,
        bytes32 nullifier,
        address forwarder,
        bytes memory expectedError
    ) internal {
        _expectMigrateBatchRevert({
            entries: _batch({
                retiredLogicRef: retiredLogicRef,
                migrationRoot: migrationRoot,
                nullifier: nullifier,
                forwarder: forwarder
            }),
            expectedError: expectedError
        });
    }

    function _expectMigrateBatchRevert(
        MigratingERC20Forwarder.MigrateEntry[] memory entries,
        bytes memory expectedError
    ) internal {
        bytes32 logicRef = _fwd.getLogicRef();
        bytes memory input = _migrateInput(entries);

        vm.prank(address(_pa));
        vm.expectRevert(expectedError);
        IForwarder(address(_fwd)).forwardCall({logicRef: logicRef, input: input});
    }

    /// @dev A batch of distinct resources with the first retired logic ref; the first one has `_NULLIFIER`.
    function _batchOf(uint256 count) internal view returns (MigratingERC20Forwarder.MigrateEntry[] memory entries) {
        entries = new MigratingERC20Forwarder.MigrateEntry[](count);
        for (uint256 i = 0; i < count; ++i) {
            entries[i] = _entry({
                retiredLogicRef: _RETIRED_LOGIC_REF,
                migrationRoot: _MIGRATION_ROOT,
                nullifier: bytes32(uint256(_NULLIFIER) + i),
                forwarder: address(_fwd)
            });
        }
    }

    function _migrateInput(MigratingERC20Forwarder.MigrateEntry[] memory entries)
        internal
        view
        returns (bytes memory input)
    {
        input = abi.encode(MigratingERC20Forwarder.MigratingCallType.Migrate, address(_erc20), _AMOUNT, entries);
    }

    function _batch(bytes32 retiredLogicRef, bytes32 migrationRoot, bytes32 nullifier, address forwarder)
        internal
        pure
        returns (MigratingERC20Forwarder.MigrateEntry[] memory entries)
    {
        entries = new MigratingERC20Forwarder.MigrateEntry[](1);
        entries[0] = _entry({
            retiredLogicRef: retiredLogicRef, migrationRoot: migrationRoot, nullifier: nullifier, forwarder: forwarder
        });
    }

    function _entry(bytes32 retiredLogicRef, bytes32 migrationRoot, bytes32 nullifier, address forwarder)
        internal
        pure
        returns (MigratingERC20Forwarder.MigrateEntry memory entry)
    {
        entry = MigratingERC20Forwarder.MigrateEntry({
            nullifier: nullifier, migrationRoot: migrationRoot, retiredLogicRef: retiredLogicRef, forwarder: forwarder
        });
    }
}
