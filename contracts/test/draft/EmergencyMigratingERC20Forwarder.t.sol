// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.7.0/proxy/utils/Initializable.sol";
import {IForwarder} from "anoma-forwarder-bases-3.0.1/src/interfaces/IForwarder.sol";
import {ILogicRefSpecific} from "anoma-forwarder-bases-3.0.1/src/interfaces/ILogicRefSpecific.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.0.1/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.2/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";
import {IEmergencyMigratingERC20Forwarder} from "../../src/draft/IEmergencyMigratingERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {EmergencyMigratingERC20ForwarderNextMock} from "../mocks/EmergencyMigratingERC20ForwarderNext.m.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

contract EmergencyMigratingERC20ForwarderTest is Test {
    uint128 internal constant _AMOUNT = 1000;
    bytes32 internal constant _VULNERABLE_LOGIC_REF = bytes32(uint256(1));
    bytes32 internal constant _NEW_LOGIC_REF = bytes32(uint256(2));
    bytes32 internal constant _ROOT = bytes32(uint256(3));
    bytes32 internal constant _NULLIFIER = bytes32(uint256(4));
    bytes32 internal constant _DEPRECATED_LOGIC_REF = bytes32(uint256(7));

    address internal immutable _PA_OWNER = makeAddr("pa owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");
    address internal immutable _RECEIVER = makeAddr("receiver");
    address internal immutable _FORWARDER_V1 = makeAddr("v1 forwarder");

    ProtocolAdapterMock internal _pa;
    EmergencyMigratingERC20Forwarder internal _fwd;
    ERC20Example internal _erc20;

    function setUp() public {
        _erc20 = new ERC20Example();
        _pa = _adapterWithHistoricalRoot(_ROOT);
        _fwd = _deployForwarder(address(_pa));
    }

    function test_upgrades_safely() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
    }

    function test_FORWARDER_V1_returns_the_constructor_argument() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        assertEq(_fwd.FORWARDER_V1(), _FORWARDER_V1);
    }

    function test_reinitialize_replaces_the_logic_ref() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        assertEq(_fwd.getLogicRef(), _NEW_LOGIC_REF);
    }

    function test_reinitialize_lists_the_vulnerable_logic_refs() public {
        _setDenied({adapter: _pa, logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});

        _upgradeAndReinitialize({
            newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: _listOf(_VULNERABLE_LOGIC_REF, _DEPRECATED_LOGIC_REF)
        });

        assertTrue(_fwd.isLogicRefVulnerable(_VULNERABLE_LOGIC_REF));
        assertTrue(_fwd.isLogicRefVulnerable(_DEPRECATED_LOGIC_REF));
        assertFalse(_fwd.isLogicRefVulnerable(_NEW_LOGIC_REF));
        assertEq(_fwd.vulnerableLogicRefCount(), 2);
        assertEq(_fwd.vulnerableLogicRefAtIndex(0), _VULNERABLE_LOGIC_REF);
        assertEq(_fwd.vulnerableLogicRefAtIndex(1), _DEPRECATED_LOGIC_REF);
    }

    /// @dev The previous logic ref has no flaw: only a deprecated one has.
    function test_reinitialize_lists_only_the_passed_logic_refs() public {
        _setDenied({adapter: _pa, logicRef: _VULNERABLE_LOGIC_REF, isDenied: false});
        _setDenied({adapter: _pa, logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});

        _upgradeAndReinitialize({newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: _listOf(_DEPRECATED_LOGIC_REF)});

        assertEq(_fwd.getLogicRef(), _NEW_LOGIC_REF);
        assertFalse(_fwd.isLogicRefVulnerable(_VULNERABLE_LOGIC_REF));
        assertEq(_fwd.vulnerableLogicRefCount(), 1);
        assertEq(_fwd.vulnerableLogicRefAtIndex(0), _DEPRECATED_LOGIC_REF);
    }

    /// @dev The current logic ref has no flaw and can start a migration already.
    function test_reinitialize_keeps_the_logic_ref_and_lists_the_vulnerable_logic_refs() public {
        _setDenied({adapter: _pa, logicRef: _VULNERABLE_LOGIC_REF, isDenied: false});
        _setDenied({adapter: _pa, logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});

        _upgradeAndReinitialize({
            newLogicRef: _VULNERABLE_LOGIC_REF, vulnerableLogicRefs: _listOf(_DEPRECATED_LOGIC_REF)
        });

        assertEq(_fwd.getLogicRef(), _VULNERABLE_LOGIC_REF);
        assertTrue(_fwd.isLogicRefVulnerable(_DEPRECATED_LOGIC_REF));
        assertEq(_fwd.vulnerableLogicRefCount(), 1);
    }

    /// @dev A voluntary upgrade after an incident lists nothing.
    function test_reinitialize_replaces_the_logic_ref_with_an_empty_list() public {
        _upgradeAndReinitialize({newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: new bytes32[](0)});

        assertEq(_fwd.getLogicRef(), _NEW_LOGIC_REF);
        assertEq(_fwd.vulnerableLogicRefCount(), 0);
    }

    function test_reinitialize_emits_the_LogicRefReplaced_event() public {
        address implementation = address(new EmergencyMigratingERC20Forwarder(_FORWARDER_V1));
        bytes memory data = abi.encodeCall(
            EmergencyMigratingERC20Forwarder.reinitialize, (_NEW_LOGIC_REF, _listOf(_VULNERABLE_LOGIC_REF))
        );

        vm.expectEmit(address(_fwd));
        emit IEmergencyMigratingERC20Forwarder.LogicRefReplaced({
            previousLogicRef: _VULNERABLE_LOGIC_REF, newLogicRef: _NEW_LOGIC_REF
        });

        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function test_reinitialize_emits_the_VulnerableLogicRefListed_event() public {
        address implementation = address(new EmergencyMigratingERC20Forwarder(_FORWARDER_V1));
        bytes memory data = abi.encodeCall(
            EmergencyMigratingERC20Forwarder.reinitialize, (_NEW_LOGIC_REF, _listOf(_VULNERABLE_LOGIC_REF))
        );

        vm.expectEmit(address(_fwd));
        emit IEmergencyMigratingERC20Forwarder.VulnerableLogicRefListed({logicRef: _VULNERABLE_LOGIC_REF});

        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function test_reinitialize_reverts_if_the_caller_is_not_the_owner() public {
        address implementation = address(new EmergencyMigratingERC20Forwarder(_FORWARDER_V1));
        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: ""});

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
        _fwd.reinitialize({newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: _listOf(_VULNERABLE_LOGIC_REF)});
    }

    function test_reinitialize_reverts_if_it_runs_a_second_time() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        _setDenied({adapter: _pa, logicRef: _NEW_LOGIC_REF, isDenied: true});

        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        _fwd.reinitialize({newLogicRef: bytes32(uint256(5)), vulnerableLogicRefs: _listOf(_NEW_LOGIC_REF)});
    }

    function test_reinitialize_reverts_on_the_zero_logic_ref() public {
        _expectReinitializeRevert({
            newLogicRef: bytes32(0),
            vulnerableLogicRefs: _listOf(_VULNERABLE_LOGIC_REF),
            expectedError: abi.encodeWithSelector(ILogicRefSpecific.ZeroLogicRefNotAllowed.selector)
        });
    }

    function test_reinitialize_reverts_if_it_changes_nothing() public {
        _expectReinitializeRevert({
            newLogicRef: _VULNERABLE_LOGIC_REF,
            vulnerableLogicRefs: new bytes32[](0),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.UnchangedLogicRef.selector, _VULNERABLE_LOGIC_REF
            )
        });
    }

    function test_reinitialize_reverts_if_the_logic_ref_is_vulnerable_already() public {
        _expectReinitializeRevert({
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_VULNERABLE_LOGIC_REF, _VULNERABLE_LOGIC_REF),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefAlreadyVulnerable.selector, _VULNERABLE_LOGIC_REF
            )
        });
    }

    function testFuzz_reinitialize_reverts_if_the_protocol_adapter_does_not_deny_the_vulnerable_logic_ref(bool consumed)
        public
    {
        _pa.mockSetLogicRefDenied({logicRef: _VULNERABLE_LOGIC_REF, consumed: consumed, isDenied: false});

        _expectReinitializeRevert({
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_VULNERABLE_LOGIC_REF),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefNotDenied.selector, _VULNERABLE_LOGIC_REF, consumed
            )
        });
    }

    function testFuzz_reinitialize_reverts_if_the_protocol_adapter_denies_the_new_logic_ref(bool consumed) public {
        _pa.mockSetLogicRefDenied({logicRef: _NEW_LOGIC_REF, consumed: consumed, isDenied: true});

        _expectReinitializeRevert({
            newLogicRef: _NEW_LOGIC_REF,
            vulnerableLogicRefs: _listOf(_VULNERABLE_LOGIC_REF),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefAlreadyDenied.selector, _NEW_LOGIC_REF, consumed
            )
        });
    }

    function test_reinitialize_keeps_earlier_vulnerable_logic_refs_migratable() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        _setDenied({adapter: _pa, logicRef: _NEW_LOGIC_REF, isDenied: true});
        _upgradeToNextAndReinitialize({
            version: 3, newLogicRef: bytes32(uint256(5)), vulnerableLogicRefs: _listOf(_NEW_LOGIC_REF)
        });

        assertEq(_fwd.vulnerableLogicRefCount(), 2);
        assertEq(_fwd.vulnerableLogicRefAtIndex(1), _NEW_LOGIC_REF);

        // One batch migrates resources of both vulnerable logic refs.
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 2});
        entries[1].vulnerableLogicRef = _NEW_LOGIC_REF;
        _migrateBatch(entries);

        assertTrue(_fwd.isNullifierMigrated(entries[0].nullifier));
        assertTrue(_fwd.isNullifierMigrated(entries[1].nullifier));
    }

    function test_forwardCall_reverts_on_the_vulnerable_logic_ref() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        bytes memory input = _migrateInput(
            _batch({
                vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
                commitmentTreeRoot: _ROOT,
                nullifier: _NULLIFIER,
                forwarder: address(_fwd)
            })
        );

        vm.prank(address(_pa));
        vm.expectRevert(
            abi.encodeWithSelector(ILogicRefSpecific.LogicRefMismatch.selector, _NEW_LOGIC_REF, _VULNERABLE_LOGIC_REF)
        );
        IForwarder(address(_fwd)).forwardCall({logicRef: _VULNERABLE_LOGIC_REF, input: input});
    }

    function test_migrate_records_the_nullifier() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        assertFalse(_fwd.isNullifierMigrated(_NULLIFIER));
        _migrate({vulnerableLogicRef: _VULNERABLE_LOGIC_REF, commitmentTreeRoot: _ROOT, nullifier: _NULLIFIER});
        assertTrue(_fwd.isNullifierMigrated(_NULLIFIER));
    }

    function test_migrate_emits_the_Migrated_event() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        vm.expectEmit(address(_fwd));
        emit IEmergencyMigratingERC20Forwarder.Migrated({
            token: address(_erc20), vulnerableLogicRef: _VULNERABLE_LOGIC_REF, nullifier: _NULLIFIER
        });

        _migrate({vulnerableLogicRef: _VULNERABLE_LOGIC_REF, commitmentTreeRoot: _ROOT, nullifier: _NULLIFIER});
    }

    function test_migrate_reverts_if_the_resource_was_migrated_already() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        _migrate({vulnerableLogicRef: _VULNERABLE_LOGIC_REF, commitmentTreeRoot: _ROOT, nullifier: _NULLIFIER});

        _expectMigrateRevert({
            vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
            commitmentTreeRoot: _ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.ResourceAlreadyMigrated.selector, _NULLIFIER
            )
        });
    }

    function test_migrate_reverts_if_the_protocol_adapter_no_longer_denies_the_vulnerable_logic_ref() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        _setDenied({adapter: _pa, logicRef: _VULNERABLE_LOGIC_REF, isDenied: false});

        _expectMigrateRevert({
            vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
            commitmentTreeRoot: _ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefNotDenied.selector, _VULNERABLE_LOGIC_REF, true
            )
        });
    }

    function test_migrate_reverts_if_the_protocol_adapter_no_longer_denies_another_vulnerable_logic_ref() public {
        _setDenied({adapter: _pa, logicRef: _DEPRECATED_LOGIC_REF, isDenied: true});
        _upgradeAndReinitialize({
            newLogicRef: _NEW_LOGIC_REF, vulnerableLogicRefs: _listOf(_VULNERABLE_LOGIC_REF, _DEPRECATED_LOGIC_REF)
        });
        _setDenied({adapter: _pa, logicRef: _VULNERABLE_LOGIC_REF, isDenied: false});

        _expectMigrateRevert({
            vulnerableLogicRef: _DEPRECATED_LOGIC_REF,
            commitmentTreeRoot: _ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefNotDenied.selector, _VULNERABLE_LOGIC_REF, true
            )
        });
    }

    function test_migrate_reverts_if_the_protocol_adapter_consumed_the_resource() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        _pa.mockAddNullifier(_NULLIFIER);

        _expectMigrateRevert({
            vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
            commitmentTreeRoot: _ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.ResourceAlreadyConsumed.selector, _NULLIFIER
            )
        });
    }

    function test_migrate_reverts_on_a_logic_ref_that_is_not_vulnerable() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        _expectMigrateRevert({
            vulnerableLogicRef: _NEW_LOGIC_REF,
            commitmentTreeRoot: _ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.LogicRefNotVulnerable.selector, _NEW_LOGIC_REF
            )
        });
    }

    function test_migrate_accepts_any_historical_root() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        bytes32 laterRoot = bytes32(uint256(6));
        _pa.mockAddCommitmentTreeRoot(laterRoot);

        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 2});
        entries[1].commitmentTreeRoot = laterRoot;
        _migrateBatch(entries);

        assertTrue(_fwd.isNullifierMigrated(entries[0].nullifier));
        assertTrue(_fwd.isNullifierMigrated(entries[1].nullifier));
    }

    function test_migrate_reverts_on_a_root_that_is_not_historical() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        bytes32 unknownRoot = bytes32(uint256(8));

        _expectMigrateRevert({
            vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
            commitmentTreeRoot: unknownRoot,
            nullifier: _NULLIFIER,
            forwarder: address(_fwd),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.NonExistingRoot.selector, unknownRoot
            )
        });
    }

    function test_migrate_accepts_a_resource_with_the_V1_forwarder_in_its_label() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        _migrateBatch(
            _batch({
                vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
                commitmentTreeRoot: _ROOT,
                nullifier: _NULLIFIER,
                forwarder: _FORWARDER_V1
            })
        );

        assertTrue(_fwd.isNullifierMigrated(_NULLIFIER));
    }

    function test_migrate_reverts_on_another_forwarder() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        address otherForwarder = makeAddr("other forwarder");

        _expectMigrateRevert({
            vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
            commitmentTreeRoot: _ROOT,
            nullifier: _NULLIFIER,
            forwarder: otherForwarder,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.UnknownForwarder.selector, otherForwarder
            )
        });
    }

    function test_migrate_reverts_on_the_zero_forwarder_on_a_chain_without_a_V1_forwarder() public {
        address implementation = address(new EmergencyMigratingERC20Forwarder(address(0)));
        bytes memory data = abi.encodeCall(
            EmergencyMigratingERC20Forwarder.reinitialize, (_NEW_LOGIC_REF, _listOf(_VULNERABLE_LOGIC_REF))
        );
        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});

        _expectMigrateRevert({
            vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
            commitmentTreeRoot: _ROOT,
            nullifier: _NULLIFIER,
            forwarder: address(0),
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.UnknownForwarder.selector, address(0)
            )
        });
    }

    function test_migrate_records_every_nullifier_of_a_batch() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 3});

        _migrateBatch(entries);

        for (uint256 i = 0; i < entries.length; ++i) {
            assertTrue(_fwd.isNullifierMigrated(entries[i].nullifier));
        }
    }

    function test_migrate_reverts_if_a_batch_names_a_resource_twice() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 3});
        entries[2].nullifier = entries[0].nullifier;

        _expectMigrateBatchRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.ResourceAlreadyMigrated.selector, entries[0].nullifier
            )
        });
    }

    function test_migrate_records_nothing_if_a_later_entry_fails() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries = _batchOf({count: 2});
        _pa.mockAddNullifier(entries[1].nullifier);

        _expectMigrateBatchRevert({
            entries: entries,
            expectedError: abi.encodeWithSelector(
                EmergencyMigratingERC20Forwarder.ResourceAlreadyConsumed.selector, entries[1].nullifier
            )
        });

        assertFalse(_fwd.isNullifierMigrated(entries[0].nullifier));
    }

    function test_migrate_reverts_on_an_empty_batch() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        _expectMigrateBatchRevert({
            entries: new EmergencyMigratingERC20Forwarder.MigrateEntry[](0),
            expectedError: abi.encodeWithSelector(EmergencyMigratingERC20Forwarder.EmptyMigrationBatch.selector)
        });
    }

    function test_migrate_reverts_on_trailing_bytes() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        bytes memory input = bytes.concat(_migrateInput(_batchOf({count: 1})), bytes32(0));

        vm.prank(address(_pa));
        vm.expectRevert(abi.encodeWithSelector(ERC20Forwarder.InvalidInputLength.selector, 9 * 32, 10 * 32));
        IForwarder(address(_fwd)).forwardCall({logicRef: _NEW_LOGIC_REF, input: input});
    }

    function test_migrate_decodes_the_encoding_of_the_trigger_logic() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});

        // `(CallTypeV2::Migrate, token, quantity, Vec<MigrateV1Data>).abi_encode_params()`, written out by hand.
        bytes memory input = abi.encodePacked(
            abi.encode(uint256(2), address(_erc20), uint256(_AMOUNT), uint256(0x80), uint256(1)),
            abi.encode(_NULLIFIER, _ROOT, _VULNERABLE_LOGIC_REF, address(_fwd))
        );
        assertEq(input, _migrateInput(_batchOf({count: 1})));

        vm.prank(address(_pa));
        IForwarder(address(_fwd)).forwardCall({logicRef: _NEW_LOGIC_REF, input: input});

        assertTrue(_fwd.isNullifierMigrated(_NULLIFIER));
    }

    function test_unwrap_still_releases_tokens() public {
        _upgradeAndReplace({newLogicRef: _NEW_LOGIC_REF});
        _erc20.mint({to: address(_fwd), value: _AMOUNT});

        bytes memory input = abi.encode(
            EmergencyMigratingERC20Forwarder.EmergencyMigratingCallType.Unwrap,
            address(_erc20),
            _AMOUNT,
            ERC20Forwarder.UnwrapData({receiver: _RECEIVER})
        );

        vm.prank(address(_pa));
        IForwarder(address(_fwd)).forwardCall({logicRef: _NEW_LOGIC_REF, input: input});

        assertEq(_erc20.balanceOf(_RECEIVER), _AMOUNT);
        assertEq(_erc20.balanceOf(address(_fwd)), 0);
    }

    /// @dev An adapter with the root as a historical root and that denies the logic ref to replace.
    function _adapterWithHistoricalRoot(bytes32 root) internal returns (ProtocolAdapterMock adapter) {
        adapter = new ProtocolAdapterMock(_PA_OWNER);
        adapter.mockAddCommitmentTreeRoot(root);
        _setDenied({adapter: adapter, logicRef: _VULNERABLE_LOGIC_REF, isDenied: true});
    }

    /// @dev Adds the logic ref to both denylists of the adapter, or removes it from both.
    function _setDenied(ProtocolAdapterMock adapter, bytes32 logicRef, bool isDenied) internal {
        adapter.mockSetLogicRefDenied({logicRef: logicRef, consumed: true, isDenied: isDenied});
        adapter.mockSetLogicRefDenied({logicRef: logicRef, consumed: false, isDenied: isDenied});
    }

    function _deployForwarder(address protocolAdapter) internal returns (EmergencyMigratingERC20Forwarder forwarder) {
        forwarder = EmergencyMigratingERC20Forwarder(
            Upgrades.deployUUPSProxy(
                "ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(ERC20Forwarder.initialize, (protocolAdapter, _VULNERABLE_LOGIC_REF, _FORWARDER_OWNER))
            )
        );
    }

    /// @dev Upgrades the proxy to the draft, replaces its logic reference and lists the previous one, as the owner does
    /// after a flaw in the logic ref that the forwarder accepts.
    function _upgradeAndReplace(bytes32 newLogicRef) internal {
        _upgradeAndReinitialize({newLogicRef: newLogicRef, vulnerableLogicRefs: _listOf(_VULNERABLE_LOGIC_REF)});
    }

    function _upgradeAndReinitialize(bytes32 newLogicRef, bytes32[] memory vulnerableLogicRefs) internal {
        // `startPrank` keeps the owner as the caller across the implementation deploy and the `upgradeToAndCall`
        // that `Upgrades.upgradeProxy` performs internally; a single `vm.prank` would only apply to the deploy.
        Options memory options;
        options.constructorData = abi.encode(_FORWARDER_V1);

        vm.startPrank(_FORWARDER_OWNER);
        Upgrades.upgradeProxy(
            address(_fwd),
            "EmergencyMigratingERC20Forwarder.sol:EmergencyMigratingERC20Forwarder",
            abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (newLogicRef, vulnerableLogicRefs)),
            options
        );
        vm.stopPrank();
    }

    /// @dev Upgrades the proxy to the implementation of a later incident and reinitializes it.
    function _upgradeToNextAndReinitialize(uint64 version, bytes32 newLogicRef, bytes32[] memory vulnerableLogicRefs)
        internal
    {
        address implementation = address(new EmergencyMigratingERC20ForwarderNextMock(version, _FORWARDER_V1));
        bytes memory data =
            abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (newLogicRef, vulnerableLogicRefs));

        vm.prank(_FORWARDER_OWNER);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function _expectReinitializeRevert(
        bytes32 newLogicRef,
        bytes32[] memory vulnerableLogicRefs,
        bytes memory expectedError
    ) internal {
        address implementation = address(new EmergencyMigratingERC20Forwarder(_FORWARDER_V1));
        bytes memory data =
            abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (newLogicRef, vulnerableLogicRefs));

        vm.prank(_FORWARDER_OWNER);
        vm.expectRevert(expectedError);
        _fwd.upgradeToAndCall({newImplementation: implementation, data: data});
    }

    function _migrate(bytes32 vulnerableLogicRef, bytes32 commitmentTreeRoot, bytes32 nullifier) internal {
        _migrateBatch(
            _batch({
                vulnerableLogicRef: vulnerableLogicRef,
                commitmentTreeRoot: commitmentTreeRoot,
                nullifier: nullifier,
                forwarder: address(_fwd)
            })
        );
    }

    function _migrateBatch(EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries) internal {
        bytes32 logicRef = _fwd.getLogicRef();
        bytes memory input = _migrateInput(entries);

        vm.prank(address(_pa));
        IForwarder(address(_fwd)).forwardCall({logicRef: logicRef, input: input});
    }

    function _expectMigrateRevert(
        bytes32 vulnerableLogicRef,
        bytes32 commitmentTreeRoot,
        bytes32 nullifier,
        address forwarder,
        bytes memory expectedError
    ) internal {
        _expectMigrateBatchRevert({
            entries: _batch({
                vulnerableLogicRef: vulnerableLogicRef,
                commitmentTreeRoot: commitmentTreeRoot,
                nullifier: nullifier,
                forwarder: forwarder
            }),
            expectedError: expectedError
        });
    }

    function _expectMigrateBatchRevert(
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries,
        bytes memory expectedError
    ) internal {
        bytes32 logicRef = _fwd.getLogicRef();
        bytes memory input = _migrateInput(entries);

        vm.prank(address(_pa));
        vm.expectRevert(expectedError);
        IForwarder(address(_fwd)).forwardCall({logicRef: logicRef, input: input});
    }

    /// @dev A batch of distinct resources with the first vulnerable logic ref; the first one has `_NULLIFIER`.
    function _batchOf(uint256 count)
        internal
        view
        returns (EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries)
    {
        entries = new EmergencyMigratingERC20Forwarder.MigrateEntry[](count);
        for (uint256 i = 0; i < count; ++i) {
            entries[i] = _entry({
                vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
                commitmentTreeRoot: _ROOT,
                nullifier: bytes32(uint256(_NULLIFIER) + i),
                forwarder: address(_fwd)
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

    function _batch(bytes32 vulnerableLogicRef, bytes32 commitmentTreeRoot, bytes32 nullifier, address forwarder)
        internal
        pure
        returns (EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries)
    {
        entries = new EmergencyMigratingERC20Forwarder.MigrateEntry[](1);
        entries[0] = _entry({
            vulnerableLogicRef: vulnerableLogicRef,
            commitmentTreeRoot: commitmentTreeRoot,
            nullifier: nullifier,
            forwarder: forwarder
        });
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

    function _entry(bytes32 vulnerableLogicRef, bytes32 commitmentTreeRoot, bytes32 nullifier, address forwarder)
        internal
        pure
        returns (EmergencyMigratingERC20Forwarder.MigrateEntry memory entry)
    {
        entry = EmergencyMigratingERC20Forwarder.MigrateEntry({
            nullifier: nullifier,
            commitmentTreeRoot: commitmentTreeRoot,
            vulnerableLogicRef: vulnerableLogicRef,
            forwarder: forwarder
        });
    }
}
