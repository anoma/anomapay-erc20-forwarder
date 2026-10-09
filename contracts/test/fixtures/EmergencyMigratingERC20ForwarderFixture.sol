// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Example} from "anoma-forwarder-bases-3.0.1/test/examples/ERC20Example.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";

/// @notice A test fixture providing the regular `ERC20Forwarder` proxy with the active version B, a protocol adapter
/// mock that denies nothing, and the draft implementation. The logic refs name the circuit versions of
/// `docs/emergency-migration.md`: A deprecated, B active, C the new version, D the version of a second incident.
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
