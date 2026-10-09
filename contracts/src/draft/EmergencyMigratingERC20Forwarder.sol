// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin-contracts-5.7.0/utils/structs/EnumerableSet.sol";
import {ICommitmentTree} from "anoma-pa-evm-2.0.0-rc.9/src/interfaces/ICommitmentTree.sol";
import {ILogicRefDenylist} from "anoma-pa-evm-2.0.0-rc.9/src/interfaces/ILogicRefDenylist.sol";
import {INullifierSet} from "anoma-pa-evm-2.0.0-rc.9/src/interfaces/INullifierSet.sol";

import {ERC20Forwarder} from "../ERC20Forwarder.sol";
import {IEmergencyMigratingERC20Forwarder} from "./IEmergencyMigratingERC20Forwarder.sol";

/// @title EmergencyMigratingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice A draft ERC20 forwarder that migrates ERC20 resources from vulnerable logic references to its own. It
/// adds the `Migrate` call type to wrap and unwrap.
/// @dev See `docs/emergency-migration.md` for the incident procedure, the design and its limits.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from ERC20Forwarder
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract EmergencyMigratingERC20Forwarder is IEmergencyMigratingERC20Forwarder, ERC20Forwarder {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice The call types. `Wrap` and `Unwrap` have the same values as in `ERC20Forwarder.CallType`.
    enum EmergencyMigratingCallType {
        Wrap,
        Unwrap,
        Migrate
    }

    /// @notice One resource of a migration batch, in the order that the migration logic encodes it.
    /// @param nullifier The nullifier of the resource.
    /// @param commitmentTreeRoot The commitment tree root that the resource is proven against.
    /// @param vulnerableLogicRef The logic reference of the resource.
    /// @param forwarder The forwarder address in the resource label.
    struct MigrateEntry {
        bytes32 nullifier;
        bytes32 commitmentTreeRoot;
        bytes32 vulnerableLogicRef;
        address forwarder;
    }

    /// @notice The ERC-7201 storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.EmergencyMigratingERC20Forwarder
    struct EmergencyMigratingERC20ForwarderStorage {
        // The vulnerable logic references, in the order in which `reinitialize` listed them.
        EnumerableSet.Bytes32Set _vulnerableLogicRefs;
        // The nullifiers of the migrated resources.
        mapping(bytes32 nullifier => bool isMigrated) _isNullifierMigrated;
    }

    /// @notice The ERC-7201 storage slot associated with the `EmergencyMigratingERC20ForwarderStorage` struct.
    /// @dev `cast index-erc7201 "anoma.storage.EmergencyMigratingERC20Forwarder"`
    bytes32 internal constant _EMERGENCY_MIGRATING_ERC20_FORWARDER_STORAGE_SLOT =
        0xb269cedad1fa0780c097a713e151b5f44b6b1a0fbd620f339f9fe7fcf7836e00;

    /// @notice The length of the migration input before its first entry.
    uint256 internal constant _MIGRATE_HEADER_LENGTH = _GENERIC_INPUT_OFFSET + 2 * 32;

    /// @notice The length of one migration entry.
    uint256 internal constant _MIGRATE_ENTRY_LENGTH = 4 * 32;

    /// @notice The V1 forwarder of the chain, or the zero address on a chain without one.
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address internal immutable _V1_FORWARDER;

    /// @notice Thrown if a denylist of the protocol adapter does not contain a vulnerable logic reference.
    /// @param logicRef The vulnerable logic reference.
    /// @param consumed `true` for the denylist for consumed resources, `false` for the one for created resources.
    error LogicRefNotDenied(bytes32 logicRef, bool consumed);

    /// @notice Thrown if a denylist of the protocol adapter contains the new logic reference.
    /// @param logicRef The new logic reference.
    /// @param consumed `true` for the denylist for consumed resources, `false` for the one for created resources.
    error DeniedLogicRef(bytes32 logicRef, bool consumed);

    /// @notice Thrown if `reinitialize` keeps the current logic reference and lists no vulnerable logic reference.
    error UnchangedLogicRef(bytes32 logicRef);

    /// @notice Thrown if `reinitialize` lists a vulnerable logic reference a second time.
    error LogicRefAlreadyVulnerable(bytes32 logicRef);

    /// @notice Thrown if a migration names a logic reference that this forwarder does not list as vulnerable.
    error UnknownVulnerableLogicRef(bytes32 vulnerableLogicRef);

    /// @notice Thrown if the root history of the protocol adapter does not contain the root of a migrated resource.
    error NonExistingRoot(bytes32 root);

    /// @notice Thrown if the label of a migrated resource contains neither this forwarder nor the V1 forwarder.
    error UnknownForwarder(address forwarder);

    /// @notice Thrown if a migration contains no resource.
    error EmptyMigrationBatch();

    /// @notice Thrown if the protocol adapter consumed the resource already.
    error ResourceAlreadyConsumed(bytes32 nullifier);

    /// @notice Thrown if this contract migrated the resource already.
    error ResourceAlreadyMigrated(bytes32 nullifier);

    /// @notice Sets the V1 forwarder of the chain, whose resources can migrate too.
    /// @param v1Forwarder The V1 forwarder, or the zero address on a chain without one.
    /// @custom:oz-upgrades-unsafe-allow constructor
    // NOTE: The zero address stands for a chain without a V1 forwarder, and `_migrate` accepts no zero label.
    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address v1Forwarder) {
        // slither-disable-next-line missing-zero-check
        _V1_FORWARDER = v1Forwarder;
    }

    /// @inheritdoc IEmergencyMigratingERC20Forwarder
    /// @dev Runs once: version 2 is one more than the version that `ERC20Forwarder.initialize` sets.
    function reinitialize(bytes32 newLogicRef, bytes32[] calldata vulnerableLogicRefs)
        external
        virtual
        override
        onlyOwner
        reinitializer(2)
    {
        _reinitialize({newLogicRef: newLogicRef, vulnerableLogicRefs: vulnerableLogicRefs});
    }

    /// @inheritdoc IEmergencyMigratingERC20Forwarder
    function isLogicRefVulnerable(bytes32 logicRef) external view override returns (bool isVulnerable) {
        isVulnerable = _getEmergencyMigratingERC20ForwarderStorage()._vulnerableLogicRefs.contains(logicRef);
    }

    /// @inheritdoc IEmergencyMigratingERC20Forwarder
    function vulnerableLogicRefCount() external view override returns (uint256 count) {
        count = _getEmergencyMigratingERC20ForwarderStorage()._vulnerableLogicRefs.length();
    }

    /// @inheritdoc IEmergencyMigratingERC20Forwarder
    function vulnerableLogicRefAtIndex(uint256 index) external view override returns (bytes32 vulnerableLogicRef) {
        vulnerableLogicRef = _getEmergencyMigratingERC20ForwarderStorage()._vulnerableLogicRefs.at(index);
    }

    /// @inheritdoc IEmergencyMigratingERC20Forwarder
    function isNullifierMigrated(bytes32 nullifier) external view override returns (bool isMigrated) {
        isMigrated = _getEmergencyMigratingERC20ForwarderStorage()._isNullifierMigrated[nullifier];
    }

    /// @inheritdoc IEmergencyMigratingERC20Forwarder
    function getV1Forwarder() external view override returns (address v1Forwarder) {
        v1Forwarder = _V1_FORWARDER;
    }

    /// @notice Forwards a call wrapping, unwrapping, or migrating ERC20 resources based on the provided input.
    /// @param input Contains data to
    /// - wrap ERC20 tokens into resources using Uniswap's Permit2,
    /// - unwrap ERC20 tokens from resources, and
    /// - migrate resources carrying a vulnerable logic reference.
    /// @return output The empty string signaling that the function call has succeeded.
    function _forwardCall(bytes calldata input) internal virtual override returns (bytes memory output) {
        (EmergencyMigratingCallType callType, IERC20 token,) =
            abi.decode(input[:_GENERIC_INPUT_OFFSET], (EmergencyMigratingCallType, IERC20, uint128));

        if (callType != EmergencyMigratingCallType.Migrate) {
            return super._forwardCall(input);
        }

        uint256 balanceBefore = token.balanceOf(address(this));

        _migrate({token: address(token), input: input});

        // A migration moves no tokens.
        uint256 balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        // slither-disable-next-line incorrect-equality
        require(balanceDelta == 0, BalanceMismatch({expected: 0, actual: balanceDelta}));

        output = "";
    }

    /// @notice Migrates a batch of resources carrying vulnerable logic references by recording their nullifiers.
    /// @param token The address of the token the migrated resources are labelled with.
    /// @param input The forwarder input, which ends with the batch.
    function _migrate(address token, bytes calldata input) internal {
        (,,, MigrateEntry[] memory entries) =
            abi.decode(input, (EmergencyMigratingCallType, IERC20, uint128, MigrateEntry[]));

        uint256 entryCount = entries.length;
        require(entryCount != 0, EmptyMigrationBatch());
        _checkLength({input: input, expectedLength: _MIGRATE_HEADER_LENGTH + entryCount * _MIGRATE_ENTRY_LENGTH});

        EmergencyMigratingERC20ForwarderStorage storage $ = _getEmergencyMigratingERC20ForwarderStorage();
        address protocolAdapter = _getForwarderBaseStorage()._protocolAdapter;

        // Each entry must name a vulnerable logic reference, so these checks cover the whole batch.
        uint256 vulnerableCount = $._vulnerableLogicRefs.length();
        for (uint256 i = 0; i < vulnerableCount; ++i) {
            _checkLogicRefDenied({protocolAdapter: protocolAdapter, logicRef: $._vulnerableLogicRefs.at(i)});
        }

        for (uint256 i = 0; i < entryCount; ++i) {
            MigrateEntry memory entry = entries[i];

            // The forwarder holds the tokens of its own resources and of V1 resources.
            require(
                entry.forwarder == address(this) || (_V1_FORWARDER != address(0) && entry.forwarder == _V1_FORWARDER),
                UnknownForwarder(entry.forwarder)
            );

            require(
                $._vulnerableLogicRefs.contains(entry.vulnerableLogicRef),
                UnknownVulnerableLogicRef(entry.vulnerableLogicRef)
            );

            // Every root of the adapter works: the adapter creates no resource with a vulnerable logic reference.
            // NOTE: The adapter is the caller and a trusted contract.
            // forge-lint: disable-next-item(calls-loop)
            require(
                ICommitmentTree(protocolAdapter).isCommitmentTreeRootHistorical(entry.commitmentTreeRoot),
                NonExistingRoot(entry.commitmentTreeRoot)
            );

            // forge-lint: disable-next-item(calls-loop)
            require(
                !INullifierSet(protocolAdapter).isNullifierContained(entry.nullifier),
                ResourceAlreadyConsumed(entry.nullifier)
            );

            // Recording each nullifier before the next entry also rejects a resource that a batch contains twice.
            require(!$._isNullifierMigrated[entry.nullifier], ResourceAlreadyMigrated(entry.nullifier));
            $._isNullifierMigrated[entry.nullifier] = true;

            emit Migrated({token: token, vulnerableLogicRef: entry.vulnerableLogicRef, nullifier: entry.nullifier});
        }
    }

    /// @notice Lists vulnerable logic references and replaces the current logic reference if the new one differs.
    /// @param newLogicRef The logic reference that the forwarder accepts after the call.
    /// @param vulnerableLogicRefs The vulnerable logic references to list.
    function _reinitialize(bytes32 newLogicRef, bytes32[] calldata vulnerableLogicRefs) internal {
        require(newLogicRef != bytes32(0), ZeroLogicRefNotAllowed());

        ForwarderBaseStorage storage $ = _getForwarderBaseStorage();
        bytes32 previousLogicRef = $._logicRef;
        uint256 vulnerableCount = vulnerableLogicRefs.length;
        require(newLogicRef != previousLogicRef || vulnerableCount != 0, UnchangedLogicRef(previousLogicRef));

        address protocolAdapter = $._protocolAdapter;
        _checkLogicRefNotDenied({protocolAdapter: protocolAdapter, logicRef: newLogicRef});

        EnumerableSet.Bytes32Set storage listed = _getEmergencyMigratingERC20ForwarderStorage()._vulnerableLogicRefs;
        for (uint256 i = 0; i < vulnerableCount; ++i) {
            bytes32 vulnerableLogicRef = vulnerableLogicRefs[i];
            _checkLogicRefDenied({protocolAdapter: protocolAdapter, logicRef: vulnerableLogicRef});
            require(listed.add(vulnerableLogicRef), LogicRefAlreadyVulnerable(vulnerableLogicRef));

            emit VulnerableLogicRefListed(vulnerableLogicRef);
        }

        if (newLogicRef != previousLogicRef) {
            $._logicRef = newLogicRef;

            emit LogicRefReplaced({previousLogicRef: previousLogicRef, newLogicRef: newLogicRef});
        }
    }

    /// @notice Checks that both denylists of the protocol adapter contain a vulnerable logic reference: the adapter
    /// then neither consumes the resources that this contract migrates nor creates new ones.
    /// @param protocolAdapter The protocol adapter.
    /// @param logicRef The vulnerable logic reference.
    function _checkLogicRefDenied(address protocolAdapter, bytes32 logicRef) internal view {
        // NOTE: `_migrate` and `_reinitialize` call this function in a loop, and the adapter is a trusted contract.
        // forge-lint: disable-next-item(calls-loop)
        require(
            ILogicRefDenylist(protocolAdapter).isLogicRefDenied({logicRef: logicRef, consumed: true}),
            LogicRefNotDenied({logicRef: logicRef, consumed: true})
        );
        // forge-lint: disable-next-item(calls-loop)
        require(
            ILogicRefDenylist(protocolAdapter).isLogicRefDenied({logicRef: logicRef, consumed: false}),
            LogicRefNotDenied({logicRef: logicRef, consumed: false})
        );
    }

    /// @notice Checks that no denylist of the protocol adapter contains the new logic reference.
    /// @param protocolAdapter The protocol adapter.
    /// @param logicRef The new logic reference.
    function _checkLogicRefNotDenied(address protocolAdapter, bytes32 logicRef) internal view {
        require(
            !ILogicRefDenylist(protocolAdapter).isLogicRefDenied({logicRef: logicRef, consumed: true}),
            DeniedLogicRef({logicRef: logicRef, consumed: true})
        );
        require(
            !ILogicRefDenylist(protocolAdapter).isLogicRefDenied({logicRef: logicRef, consumed: false}),
            DeniedLogicRef({logicRef: logicRef, consumed: false})
        );
    }

    /// @notice Returns the storage from the migrating ERC20 forwarder storage slot.
    /// @return emergencyMigratingErc20ForwarderStorage The data associated with the migrating ERC20 forwarder storage.
    function _getEmergencyMigratingERC20ForwarderStorage()
        internal
        pure
        returns (EmergencyMigratingERC20ForwarderStorage storage emergencyMigratingErc20ForwarderStorage)
    {
        // forge-lint: disable-next-item(inline-assembly)
        assembly {
            emergencyMigratingErc20ForwarderStorage.slot := _EMERGENCY_MIGRATING_ERC20_FORWARDER_STORAGE_SLOT
        }
    }
}
