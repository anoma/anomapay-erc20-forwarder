// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-3.0.1/src/interfaces/ILogicRefSpecific.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.0.1/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.2/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";
import {IEmergencyMigratingERC20Forwarder} from "../../src/draft/IEmergencyMigratingERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ERC20ForwarderTest} from "../ERC20Forwarder.t.sol";
import {EmergencyMigratingERC20ForwarderNextMock} from "../mocks/EmergencyMigratingERC20ForwarderNext.m.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

/// @dev The circuit versions of `docs/emergency-migration.md`: A deprecated, B active, C the new version, D the version
/// of a second incident. The forwarder starts as the regular `ERC20Forwarder` with B, and the adapter denies nothing.
abstract contract EmergencyMigratingERC20ForwarderFixture is Test {
    uint128 internal constant _AMOUNT = 1000;
    bytes32 internal constant _DEPRECATED_LOGIC_REF = bytes32(uint256(1));
    bytes32 internal constant _ACTIVE_LOGIC_REF = bytes32(uint256(2));
    bytes32 internal constant _NEW_LOGIC_REF = bytes32(uint256(3));
    bytes32 internal constant _SECOND_INCIDENT_LOGIC_REF = bytes32(uint256(4));
    bytes32 internal constant _ROOT = bytes32(uint256(5));
    bytes32 internal constant _NULLIFIER = bytes32(uint256(6));

    address internal immutable _PROTOCOL_ADAPTER_OWNER = makeAddr("protocol adapter owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");
    address internal immutable _FORWARDER_V1 = makeAddr("V1 forwarder");

    ProtocolAdapterMock internal _protocolAdapter;
    EmergencyMigratingERC20Forwarder internal _forwarder;
    ERC20Example internal _erc20;
    address internal _implementation;

    function setUp() public virtual {
        _erc20 = new ERC20Example();

        _protocolAdapter = new ProtocolAdapterMock(_PROTOCOL_ADAPTER_OWNER);
        _protocolAdapter.mockAddCommitmentTreeRoot(_ROOT);

        _forwarder = EmergencyMigratingERC20Forwarder(
            Upgrades.deployUUPSProxy(
                "ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(
                    ERC20Forwarder.initialize, (address(_protocolAdapter), _ACTIVE_LOGIC_REF, _FORWARDER_OWNER)
                )
            )
        );
        _implementation = address(new EmergencyMigratingERC20Forwarder(_FORWARDER_V1));
    }

    /// @dev Adds the logic ref to both denylists of the adapter, as `denyLogicRefs` does, or removes it from both, as an
    /// upgrade of the adapter could.
    function _setDenied(bytes32 logicRef, bool isDenied) internal {
        _protocolAdapter.mockSetLogicRefDenied({logicRef: logicRef, consumed: true, isDenied: isDenied});
        _protocolAdapter.mockSetLogicRefDenied({logicRef: logicRef, consumed: false, isDenied: isDenied});
    }

    /// @dev Makes no external call before `upgradeToAndCall`, so `vm.expectRevert` and `vm.expectEmit` apply to it.
    function _upgradeTo(address implementation, bytes32 newLogicRef, bytes32[] memory vulnerableLogicRefs) internal {
        bytes memory data =
            abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (newLogicRef, vulnerableLogicRefs));

        vm.prank(_FORWARDER_OWNER);
        _forwarder.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function _migrate(EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries) internal {
        bytes32 logicRef = _forwarder.getLogicRef();

        vm.prank(address(_protocolAdapter));
        _forwarder.forwardCall({logicRef: logicRef, input: _migrateInput(entries)});
    }

    function _expectMigrateRevert(
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries,
        bytes memory expectedError
    ) internal {
        bytes32 logicRef = _forwarder.getLogicRef();

        vm.prank(address(_protocolAdapter));
        vm.expectRevert(expectedError);
        _forwarder.forwardCall({logicRef: logicRef, input: _migrateInput(entries)});
    }

    /// @dev Distinct resources of the active version with this forwarder in their label; the first has `_NULLIFIER`.
    function _batchOf(uint256 count)
        internal
        view
        returns (EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries)
    {
        entries = new EmergencyMigratingERC20Forwarder.MigrateEntry[](count);
        for (uint256 i = 0; i < count; ++i) {
            entries[i] = EmergencyMigratingERC20Forwarder.MigrateEntry({
                nullifier: bytes32(uint256(_NULLIFIER) + i),
                commitmentTreeRoot: _ROOT,
                vulnerableLogicRef: _ACTIVE_LOGIC_REF,
                forwarder: address(_forwarder)
            });
        }
    }

    function _migrateInput(EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries)
        internal
        view
        returns (bytes memory input)
    {
        input = abi.encode(
            EmergencyMigratingERC20Forwarder.EmergencyMigratingCallType.Migrate, address(_erc20), _AMOUNT, entries
        );
    }

    function _listOf(bytes32 logicRef) internal pure returns (bytes32[] memory logicRefs) {
        logicRefs = new bytes32[](1);
        logicRefs[0] = logicRef;
    }

    function _listOf(bytes32 first, bytes32 second) internal pure returns (bytes32[] memory logicRefs) {
        logicRefs = new bytes32[](2);
        logicRefs[0] = first;
        logicRefs[1] = second;
    }
}

/// @dev Each test upgrades the regular forwarder itself.
contract EmergencyMigratingERC20ForwarderUpgradeTest is EmergencyMigratingERC20ForwarderFixture {
    /// @dev The only upgrade that runs the upgrade-safety validation, because each validation takes an `npx` call.
    function test_upgrades_safely() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        Options memory options;
        options.constructorData = abi.encode(_FORWARDER_V1);

        // `Upgrades.upgradeProxy` deploys the implementation before it upgrades, so one `vm.prank` covers only the deploy.
        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            address(_forwarder),
            "EmergencyMigratingERC20Forwarder.sol:EmergencyMigratingERC20Forwarder",
            abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (_NEW_LOGIC_REF, _listOf(_ACTIVE_LOGIC_REF))),
            options
        );
        vm.stopPrank();
    }

    /// @dev Only the deprecated version has the flaw, so the active one is not listed.
    function test_reinitialize_replaces_the_logic_ref_and_lists_only_the_passed_logic_refs() public {
        _setDenied({logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});

        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_DEPRECATED_LOGIC_REF)
        });

        assertEq(_forwarder.getLogicRef(), _NEW_LOGIC_REF);
        assertTrue(_forwarder.isLogicRefVulnerable(_DEPRECATED_LOGIC_REF));
        assertFalse(_forwarder.isLogicRefVulnerable(_ACTIVE_LOGIC_REF));
        assertFalse(_forwarder.isLogicRefVulnerable(_NEW_LOGIC_REF));
    }

    /// @dev The active version has no flaw and can start an emergency migration already.
    function test_reinitialize_keeps_the_logic_ref_and_lists_the_vulnerable_logic_refs() public {
        _setDenied({logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});

        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _ACTIVE_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_DEPRECATED_LOGIC_REF)
        });

        assertEq(_forwarder.getLogicRef(), _ACTIVE_LOGIC_REF);
        assertTrue(_forwarder.isLogicRefVulnerable(_DEPRECATED_LOGIC_REF));
        assertFalse(_forwarder.isLogicRefVulnerable(_ACTIVE_LOGIC_REF));
    }

    function test_reinitialize_emits_the_VulnerableLogicRefListed_and_LogicRefReplaced_events() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});

        vm.expectEmit(address(_forwarder));
        emit IEmergencyMigratingERC20Forwarder.VulnerableLogicRefListed({logicRef: _ACTIVE_LOGIC_REF});
        vm.expectEmit(address(_forwarder));
        emit IEmergencyMigratingERC20Forwarder.LogicRefReplaced({
            previousLogicRef: _ACTIVE_LOGIC_REF, newLogicRef: _NEW_LOGIC_REF
        });

        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
    }

    function test_reinitialize_reverts_if_the_caller_is_not_the_owner() public {
        vm.prank(_FORWARDER_OWNER);
        _forwarder.upgradeToAndCall({newImplementation: _implementation, data: ""});

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        _forwarder.reinitialize({newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)});
    }

    function test_reinitialize_reverts_if_it_runs_a_second_time() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
        _setDenied({logicRef: _NEW_LOGIC_REF, isDenied: true});

        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        _forwarder.reinitialize({newLogicRef: _SECOND_INCIDENT_LOGIC_REF, vulnerableLogicRefs: _listOf(_NEW_LOGIC_REF)});
    }

    function test_reinitialize_reverts_on_the_zero_logic_ref() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});

        vm.expectRevert(abi.encodeWithSelector(ILogicRefSpecific.ZeroLogicRefNotAllowed.selector));
        _upgradeTo({
            implementation: _implementation, newLogicRef: bytes32(0), vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
    }

    /// @dev The call replaces the logic ref, so the empty list alone makes it revert.
    function test_reinitialize_reverts_on_an_empty_list() public {
        vm.expectRevert(abi.encodeWithSelector(EmergencyMigratingERC20Forwarder.EmptyVulnerableLogicRefList.selector));
        _upgradeTo({
            implementation: _implementation, newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: new bytes32[](0)
        });
    }

    function test_reinitialize_reverts_if_the_logic_ref_is_vulnerable_already() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefAlreadyVulnerable.selector, _ACTIVE_LOGIC_REF
            )
        );
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF, _ACTIVE_LOGIC_REF)
        });
    }

    function testFuzz_reinitialize_reverts_if_the_protocol_adapter_does_not_deny_the_vulnerable_logic_ref(bool consumed)
        public
    {
        _protocolAdapter.mockSetLogicRefDenied({logicRef: _ACTIVE_LOGIC_REF, consumed: !consumed, isDenied: true});

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefNotDenied.selector, _ACTIVE_LOGIC_REF, consumed
            )
        );
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
    }

    function testFuzz_reinitialize_reverts_if_the_protocol_adapter_denies_the_new_logic_ref(bool consumed) public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        _protocolAdapter.mockSetLogicRefDenied({logicRef: _NEW_LOGIC_REF, consumed: consumed, isDenied: true});

        vm.expectRevert(
            abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefAlreadyDenied.selector, _NEW_LOGIC_REF, consumed
            )
        );
        _upgradeTo({
            implementation: _implementation,
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
    }

    function test_migrate_reverts_on_the_zero_forwarder_on_a_chain_without_a_V1_forwarder() public {
        _setDenied({logicRef: _ACTIVE_LOGIC_REF, isDenied: true});
        _upgradeTo({
            implementation: address(new EmergencyMigratingERC20Forwarder(address(0))),
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_ACTIVE_LOGIC_REF)
        });
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 1});
        entries[0].forwarder = address(0);

        _expectMigrateRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.UnknownForwarder.selector, address(0)
            )
        });
    }
}

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
        address implementation = address(new EmergencyMigratingERC20Forwarder(address(0)));

        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({
            newImplementation: implementation,
            data: abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (_logicRef, vulnerableLogicRefs))
        });
    }
}
