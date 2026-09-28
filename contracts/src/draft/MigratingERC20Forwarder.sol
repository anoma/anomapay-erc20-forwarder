// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin-contracts-5.7.0/utils/structs/EnumerableMap.sol";
import {ICommitmentTree} from "anoma-pa-evm-2.0.0-rc.7/src/interfaces/ICommitmentTree.sol";
import {INullifierSet} from "anoma-pa-evm-2.0.0-rc.7/src/interfaces/INullifierSet.sol";
import {IProtocolAdapter} from "anoma-pa-evm-2.0.0-rc.7/src/interfaces/IProtocolAdapter.sol";

import {ERC20Forwarder} from "../ERC20Forwarder.sol";
import {ILogicRefDenylist} from "./ILogicRefDenylist.sol";
import {IMigratingERC20Forwarder} from "./IMigratingERC20Forwarder.sol";

/// @title MigratingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice A draft ERC20 forwarder that migrates ERC20 resources from a retired logic reference to a new one. It adds
/// the `Migrate` call type to wrap and unwrap.
/// @dev See `docs/emergency-migration.md` for the incident procedure, the design and its limits.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from ERC20Forwarder
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MigratingERC20Forwarder is IMigratingERC20Forwarder, ERC20Forwarder {
    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;

    /// @notice The call types. `Wrap` and `Unwrap` have the same values as in `ERC20Forwarder.CallType`.
    enum MigratingCallType {
        Wrap,
        Unwrap,
        Migrate
    }

    /// @notice One resource of a migration batch, in the order that the migration logic encodes it.
    /// @param nullifier The nullifier of the resource.
    /// @param migrationRoot The commitment tree root that the resource is proven against.
    /// @param retiredLogicRef The logic reference of the resource.
    /// @param forwarder The forwarder address in the resource label.
    struct MigrateEntry {
        bytes32 nullifier;
        bytes32 migrationRoot;
        bytes32 retiredLogicRef;
        address forwarder;
    }

    /// @notice The ERC-7201 storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.MigratingERC20Forwarder
    struct MigratingERC20ForwarderStorage {
        // The migration root of each retired logic reference, in the order of retirement.
        EnumerableMap.Bytes32ToBytes32Map _migrationRoots;
        // The nullifiers of the migrated resources.
        mapping(bytes32 nullifier => bool isMigrated) _isNullifierMigrated;
    }

    /// @notice The ERC-7201 storage slot associated with the `MigratingERC20ForwarderStorage` struct.
    /// @dev `cast index-erc7201 "anoma.storage.MigratingERC20Forwarder"`
    bytes32 internal constant _MIGRATING_ERC20_FORWARDER_STORAGE_SLOT =
        0x542a3d2fc110dcee1dc322fc93583e849eb18bb7c89b4453a5bd009e400fab00;

    /// @notice The length of the migration input before its first entry.
    uint256 internal constant _MIGRATE_HEADER_LENGTH = _GENERIC_INPUT_OFFSET + 2 * 32;

    /// @notice The length of one migration entry.
    uint256 internal constant _MIGRATE_ENTRY_LENGTH = 4 * 32;

    /// @notice Thrown if the protocol adapter is not paused during a rotation.
    error ProtocolAdapterNotPaused(address protocolAdapter);

    /// @notice Thrown if the protocol adapter does not deny a retired logic reference.
    error LogicRefNotDenied(bytes32 logicRef);

    /// @notice Thrown if the protocol adapter denies the new logic reference.
    error DeniedLogicRef(bytes32 logicRef);

    /// @notice Thrown if the root history of the protocol adapter does not contain the migration root.
    error UnknownMigrationRoot(bytes32 migrationRoot);

    /// @notice Thrown if a rotation keeps the current logic reference.
    error UnchangedLogicRef(bytes32 logicRef);

    /// @notice Thrown if a rotation retires a logic reference a second time.
    error LogicRefAlreadyRetired(bytes32 logicRef);

    /// @notice Thrown if a migration names a logic reference that is not retired.
    error UnknownRetiredLogicRef(bytes32 retiredLogicRef);

    /// @notice Thrown if a migration names another root than the root recorded for its logic reference.
    error MigrationRootMismatch(bytes32 expected, bytes32 actual);

    /// @notice Thrown if the label of a migrated resource contains another forwarder address.
    error ForwarderMismatch(address expected, address actual);

    /// @notice Thrown if a migration contains no resource.
    error EmptyMigrationBatch();

    /// @notice Thrown if the protocol adapter consumed the resource already.
    error ResourceAlreadyConsumed(bytes32 nullifier);

    /// @notice Thrown if this contract migrated the resource already.
    error ResourceAlreadyMigrated(bytes32 nullifier);

    /// @inheritdoc IMigratingERC20Forwarder
    function reinitialize(bytes32 newLogicRef, bytes32 migrationRoot)
        external
        override
        onlyOwner
        reinitializer(_getInitializedVersion() + 1)
    {
        require(newLogicRef != bytes32(0), ZeroLogicRefNotAllowed());

        ForwarderBaseStorage storage $ = _getForwarderBaseStorage();
        bytes32 retiredLogicRef = $._logicRef;
        require(newLogicRef != retiredLogicRef, UnchangedLogicRef(retiredLogicRef));

        address protocolAdapter = $._protocolAdapter;
        require(IProtocolAdapter(protocolAdapter).paused(), ProtocolAdapterNotPaused(protocolAdapter));
        require(
            ICommitmentTree(protocolAdapter).isCommitmentTreeRootContained(migrationRoot),
            UnknownMigrationRoot(migrationRoot)
        );

        // The adapter must not also consume the resources that this contract migrates.
        require(
            ILogicRefDenylist(protocolAdapter).isLogicRefDenied(retiredLogicRef), LogicRefNotDenied(retiredLogicRef)
        );
        require(!ILogicRefDenylist(protocolAdapter).isLogicRefDenied(newLogicRef), DeniedLogicRef(newLogicRef));

        require(
            _getMigratingERC20ForwarderStorage()._migrationRoots.set({key: retiredLogicRef, value: migrationRoot}),
            LogicRefAlreadyRetired(retiredLogicRef)
        );

        $._logicRef = newLogicRef;

        emit LogicRefRetired(retiredLogicRef, migrationRoot, newLogicRef);
    }

    /// @inheritdoc IMigratingERC20Forwarder
    function getMigrationRoot(bytes32 retiredLogicRef) external view override returns (bytes32 migrationRoot) {
        // slither-disable-next-line unused-return
        (, migrationRoot) = _getMigratingERC20ForwarderStorage()._migrationRoots.tryGet(retiredLogicRef);
    }

    /// @inheritdoc IMigratingERC20Forwarder
    function retiredLogicRefCount() external view override returns (uint256 count) {
        count = _getMigratingERC20ForwarderStorage()._migrationRoots.length();
    }

    /// @inheritdoc IMigratingERC20Forwarder
    function retiredLogicRefAtIndex(uint256 index)
        external
        view
        override
        returns (bytes32 retiredLogicRef, bytes32 migrationRoot)
    {
        (retiredLogicRef, migrationRoot) = _getMigratingERC20ForwarderStorage()._migrationRoots.at(index);
    }

    /// @inheritdoc IMigratingERC20Forwarder
    function isNullifierMigrated(bytes32 nullifier) external view override returns (bool isMigrated) {
        isMigrated = _getMigratingERC20ForwarderStorage()._isNullifierMigrated[nullifier];
    }

    /// @notice Forwards a call wrapping, unwrapping, or migrating ERC20 resources based on the provided input.
    /// @param input Contains data to
    /// - wrap ERC20 tokens into resources using Uniswap's Permit2,
    /// - unwrap ERC20 tokens from resources, and
    /// - migrate resources carrying a retired logic reference.
    /// @return output The empty string signaling that the function call has succeeded.
    function _forwardCall(bytes calldata input) internal virtual override returns (bytes memory output) {
        (MigratingCallType callType, IERC20 token,) =
            abi.decode(input[:_GENERIC_INPUT_OFFSET], (MigratingCallType, IERC20, uint128));

        if (callType != MigratingCallType.Migrate) {
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

    /// @notice Migrates a batch of resources carrying retired logic references by recording their nullifiers.
    /// @param token The address of the token the migrated resources are labelled with.
    /// @param input The forwarder input, which ends with the batch.
    function _migrate(address token, bytes calldata input) internal {
        (,,, MigrateEntry[] memory entries) = abi.decode(input, (MigratingCallType, IERC20, uint128, MigrateEntry[]));

        uint256 entryCount = entries.length;
        require(entryCount != 0, EmptyMigrationBatch());
        _checkLength({input: input, expectedLength: _MIGRATE_HEADER_LENGTH + entryCount * _MIGRATE_ENTRY_LENGTH});

        MigratingERC20ForwarderStorage storage $ = _getMigratingERC20ForwarderStorage();
        address protocolAdapter = _getForwarderBaseStorage()._protocolAdapter;

        for (uint256 i = 0; i < entryCount; ++i) {
            MigrateEntry memory entry = entries[i];

            require(
                entry.forwarder == address(this), ForwarderMismatch({expected: address(this), actual: entry.forwarder})
            );

            (bool isRetired, bytes32 migrationRoot) = $._migrationRoots.tryGet(entry.retiredLogicRef);
            require(isRetired, UnknownRetiredLogicRef(entry.retiredLogicRef));
            require(
                entry.migrationRoot == migrationRoot,
                MigrationRootMismatch({expected: migrationRoot, actual: entry.migrationRoot})
            );

            // The adapter must not also consume the resources that this contract migrates.
            // NOTE: The adapter is the caller and a trusted contract.
            // forge-lint: disable-next-item(calls-loop)
            require(
                ILogicRefDenylist(protocolAdapter).isLogicRefDenied(entry.retiredLogicRef),
                LogicRefNotDenied(entry.retiredLogicRef)
            );

            // forge-lint: disable-next-item(calls-loop)
            require(
                !INullifierSet(protocolAdapter).isNullifierContained(entry.nullifier),
                ResourceAlreadyConsumed(entry.nullifier)
            );

            // Recording each nullifier before the next entry also rejects a resource that a batch contains twice.
            require(!$._isNullifierMigrated[entry.nullifier], ResourceAlreadyMigrated(entry.nullifier));
            $._isNullifierMigrated[entry.nullifier] = true;

            emit Migrated({token: token, retiredLogicRef: entry.retiredLogicRef, nullifier: entry.nullifier});
        }
    }

    /// @notice Returns the storage from the migrating ERC20 forwarder storage slot.
    /// @return migratingErc20ForwarderStorage The data associated with the migrating ERC20 forwarder storage.
    function _getMigratingERC20ForwarderStorage()
        internal
        pure
        returns (MigratingERC20ForwarderStorage storage migratingErc20ForwarderStorage)
    {
        // forge-lint: disable-next-item(inline-assembly)
        assembly {
            migratingErc20ForwarderStorage.slot := _MIGRATING_ERC20_FORWARDER_STORAGE_SLOT
        }
    }
}
