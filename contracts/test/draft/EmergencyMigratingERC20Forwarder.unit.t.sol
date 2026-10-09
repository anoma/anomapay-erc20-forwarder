// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ILogicRefSpecific} from "anoma-forwarder-bases-3.0.1/src/interfaces/ILogicRefSpecific.sol";

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";
import {IEmergencyMigratingERC20Forwarder} from "../../src/draft/IEmergencyMigratingERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ERC20ForwarderTest} from "../ERC20Forwarder.t.sol";
import {EmergencyMigratingERC20ForwarderFixture} from "../fixtures/EmergencyMigratingERC20ForwarderFixture.sol";
import {EmergencyMigratingERC20ForwarderNextMock} from "../mocks/EmergencyMigratingERC20ForwarderNext.m.sol";

/// @dev A flaw in the active and the deprecated version: the forwarder moves to the new version and lists both.
contract EmergencyMigratingERC20ForwarderMigrateTest is EmergencyMigratingERC20ForwarderFixture {
    function setUp() public override {
        super.setUp();

        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        _setDenied({logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF, _DEPRECATED_LOGIC_REF)
        });
    }

    function test_forwardCall_reverts_on_a_vulnerable_logic_ref() public {
        bytes memory input = _migrateInput(_batchOf({count: 1}));

        vm.prank(address(_protocolAdapter));
        vm.expectRevert(
            abi.encodeWithSelector(ILogicRefSpecific.LogicRefMismatch.selector, _NEW_LOGIC_REF, _ACTIVE_LOGIC_REF)
        );
        _forwarder.forwardCall({logicRef: _ACTIVE_LOGIC_REF, input: input});
    }

    function test_migrate_records_every_nullifier_of_a_batch() public {
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 3});

        _migrate(entries);

        for (uint256 i = 0; i < entries.length; ++i) {
            assertTrue(_forwarder.isNullifierMigrated(entries[i].nullifier));
        }
    }

    function test_migrate_emits_the_Migrated_event() public {
        vm.expectEmit(address(_forwarder));
        emit IEmergencyMigratingERC20Forwarder.Migrated({
            token: address(_erc20), vulnerableLogicRef: _ACTIVE_LOGIC_REF, nullifier: _NULLIFIER
        });

        _migrate(_batchOf({count: 1}));
    }

    /// @dev `(CallTypeV2::Migrate, token, quantity, Vec<MigrateV1Data>).abi_encode_params()` of the trigger's logic,
    /// written out by hand.
    function test_migrate_decodes_the_encoding_of_the_trigger_logic() public {
        bytes memory input = abi.encodePacked(
            abi.encode(uint256(2), address(_erc20), uint256(_AMOUNT), uint256(0x80), uint256(1)),
            abi.encode(_NULLIFIER, _ROOT, _ACTIVE_LOGIC_REF, address(_forwarder))
        );

        vm.prank(address(_protocolAdapter));
        _forwarder.forwardCall({logicRef: _NEW_LOGIC_REF, input: input});

        assertTrue(_forwarder.isNullifierMigrated(_NULLIFIER));
    }

    function test_migrate_reverts_if_the_resource_was_migrated_already() public {
        _migrate(_batchOf({count: 1}));

        _expectMigrateRevert({
            entries: _batchOf({count: 1}),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.ResourceAlreadyMigrated.selector, _NULLIFIER
            )
        });
    }

    function test_migrate_reverts_if_a_batch_names_a_resource_twice() public {
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 3});
        entries[2].nullifier = entries[0].nullifier;

        _expectMigrateRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.ResourceAlreadyMigrated.selector, entries[0].nullifier
            )
        });
    }

    /// @dev The batch names only the active version, so the check covers every listed logic ref.
    function test_migrate_reverts_if_the_protocol_adapter_no_longer_denies_a_vulnerable_logic_ref() public {
        _setDenied({logicRef: _DEPRECATED_LOGIC_REF, isDenied: false});

        _expectMigrateRevert({
            entries: _batchOf({count: 1}),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefNotDenied.selector, _DEPRECATED_LOGIC_REF, true
            )
        });
    }

    function test_migrate_reverts_if_the_protocol_adapter_consumed_the_resource() public {
        _protocolAdapter.mockAddNullifier(_NULLIFIER);

        _expectMigrateRevert({
            entries: _batchOf({count: 1}),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.ResourceAlreadyConsumed.selector, _NULLIFIER
            )
        });
    }

    function test_migrate_reverts_on_a_logic_ref_that_is_not_vulnerable() public {
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 1});
        entries[0].vulnerableLogicRef = _NEW_LOGIC_REF;

        _expectMigrateRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefNotVulnerable.selector, _NEW_LOGIC_REF
            )
        });
    }

    function test_migrate_accepts_any_historical_root() public {
        bytes32 laterRoot = bytes32(uint256(_ROOT) + 1);
        _protocolAdapter.mockAddCommitmentTreeRoot(laterRoot);
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 2});
        entries[1].commitmentTreeRoot = laterRoot;

        _migrate(entries);

        assertTrue(_forwarder.isNullifierMigrated(entries[0].nullifier));
        assertTrue(_forwarder.isNullifierMigrated(entries[1].nullifier));
    }

    function test_migrate_reverts_on_a_root_that_is_not_historical() public {
        bytes32 unknownRoot = bytes32(uint256(_ROOT) + 1);
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 1});
        entries[0].commitmentTreeRoot = unknownRoot;

        _expectMigrateRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.NonExistingRoot.selector, unknownRoot
            )
        });
    }

    function test_migrate_accepts_a_resource_with_the_V1_forwarder_in_its_label() public {
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 1});
        entries[0].forwarder = _FORWARDER_V1;

        _migrate(entries);

        assertTrue(_forwarder.isNullifierMigrated(_NULLIFIER));
    }

    function test_migrate_reverts_on_another_forwarder() public {
        address otherForwarder = makeAddr("other forwarder");
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 1});
        entries[0].forwarder = otherForwarder;

        _expectMigrateRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.UnknownForwarder.selector, otherForwarder
            )
        });
    }

    function test_migrate_reverts_on_an_empty_batch() public {
        _expectMigrateRevert({
            entries: _batchOf({count: 0}),
            expectedError: abi.encodeWithSelector(EmergencyMigratingERC20Forwarder.EmptyMigrationBatch.selector)
        });
    }

    function test_migrate_reverts_on_trailing_bytes() public {
        bytes memory input = bytes.concat(_migrateInput(_batchOf({count: 1})), bytes32(0));

        vm.prank(address(_protocolAdapter));
        vm.expectRevert(abi.encodeWithSelector(ERC20Forwarder.InvalidInputLength.selector, 9 * 32, 10 * 32));
        _forwarder.forwardCall({logicRef: _NEW_LOGIC_REF, input: input});
    }

    /// @dev A second incident with a flaw in the new version, which the version of the second incident fixes.
    function test_reinitialize_keeps_earlier_vulnerable_logic_refs_migratable() public {
        _setDenied({logicRef: _NEW_LOGIC_REF, isDenied: true});
        _upgradeTo({
            implementation: address(new EmergencyMigratingERC20ForwarderNextMock(_FORWARDER_V1)),
            newLogicRef: _SECOND_INCIDENT_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_NEW_LOGIC_REF)
        });
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 2});
        entries[1].vulnerableLogicRef = _NEW_LOGIC_REF;

        _migrate(entries);

        assertTrue(_forwarder.isNullifierMigrated(entries[0].nullifier));
        assertTrue(_forwarder.isNullifierMigrated(entries[1].nullifier));
    }

    function test_FORWARDER_V1_returns_the_constructor_argument() public view {
        assertEq(_forwarder.FORWARDER_V1(), _FORWARDER_V1);
    }
}

/// @dev Runs the wrap and unwrap tests of `ERC20Forwarder` through the forwarder after an emergency upgrade.
contract EmergencyMigratingERC20ForwarderWrapAndUnwrapTest is ERC20ForwarderTest {
    function _deployProtocolAdapterAndForwarders() internal override {
        super._deployProtocolAdapterAndForwarders();

        bytes32 vulnerableLogicRef = _logicRef;
        bytes32[] memory vulnerableLogicRefs = new bytes32[](1);
        vulnerableLogicRefs[0] = vulnerableLogicRef;
        _logicRef = bytes32(uint256(vulnerableLogicRef) + 1);

        _pa.mockSetLogicRefDenied({logicRef: vulnerableLogicRef, consumed: true, isDenied: true});
        _pa.mockSetLogicRefDenied({logicRef: vulnerableLogicRef, consumed: false, isDenied: true});
        address implementation = address(new EmergencyMigratingERC20Forwarder(makeAddr("V1 forwarder")));

        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({
            newImplementation: implementation,
            data: abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (_logicRef, vulnerableLogicRefs))
        });
    }
}
