// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin-contracts-5.7.0/utils/structs/EnumerableSet.sol";
import {ICommitmentTree} from "anoma-pa-evm-2.0.0-rc.8/src/interfaces/ICommitmentTree.sol";
import {ILogicRefDenylist} from "anoma-pa-evm-2.0.0-rc.8/src/interfaces/ILogicRefDenylist.sol";
import {INullifierSet} from "anoma-pa-evm-2.0.0-rc.8/src/interfaces/INullifierSet.sol";

import {ERC20Forwarder} from "../ERC20Forwarder.sol";
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
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice The call types. `Wrap` and `Unwrap` have the same values as in `ERC20Forwarder.CallType`.
    enum MigratingCallType {
        Wrap,
        Unwrap,
        Migrate
    }

    /// @notice One resource of a migration batch, in the order that the migration logic encodes it.
    /// @param nullifier The nullifier of the resource.
    /// @param commitmentTreeRoot The commitment tree root that the resource is proven against.
    /// @param retiredLogicRef The logic reference of the resource.
    /// @param forwarder The forwarder address in the resource label.
    struct MigrateEntry {
        bytes32 nullifier;
        bytes32 commitmentTreeRoot;
        bytes32 retiredLogicRef;
        address forwarder;
    }

    /// @notice The ERC-7201 storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.MigratingERC20Forwarder
    struct MigratingERC20ForwarderStorage {
        // The retired logic references, in the order of retirement.
        EnumerableSet.Bytes32Set _retiredLogicRefs;
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

    /// @notice Thrown if a denylist of the protocol adapter does not contain a retired logic reference.
    /// @param logicRef The retired logic reference.
    /// @param consumed `true` for the denylist for consumed resources, `false` for the one for created resources.
    error LogicRefNotDenied(bytes32 logicRef, bool consumed);

    /// @notice Thrown if a denylist of the protocol adapter contains the new logic reference.
    /// @param logicRef The new logic reference.
    /// @param consumed `true` for the denylist for consumed resources, `false` for the one for created resources.
    error DeniedLogicRef(bytes32 logicRef, bool consumed);

    /// @notice Thrown if a rotation keeps the current logic reference.
    error UnchangedLogicRef(bytes32 logicRef);

    /// @notice Thrown if a rotation retires a logic reference a second time.
    error LogicRefAlreadyRetired(bytes32 logicRef);

    /// @notice Thrown if a migration names a logic reference that is not retired.
    error UnknownRetiredLogicRef(bytes32 retiredLogicRef);

    /// @notice Thrown if the root history of the protocol adapter does not contain the root of a migrated resource.
    error NonExistingRoot(bytes32 root);

    /// @notice Thrown if the label of a migrated resource contains another forwarder address.
    error ForwarderMismatch(address expected, address actual);

    /// @notice Thrown if a migration contains no resource.
    error EmptyMigrationBatch();

    /// @notice Thrown if the protocol adapter consumed the resource already.
    error ResourceAlreadyConsumed(bytes32 nullifier);

    /// @notice Thrown if this contract migrated the resource already.
    error ResourceAlreadyMigrated(bytes32 nullifier);

    /// @inheritdoc IMigratingERC20Forwarder
    function reinitialize(bytes32 newLogicRef) external override onlyOwner reinitializer(_getInitializedVersion() + 1) {
        require(newLogicRef != bytes32(0), ZeroLogicRefNotAllowed());

        ForwarderBaseStorage storage $ = _getForwarderBaseStorage();
        bytes32 retiredLogicRef = $._logicRef;
        require(newLogicRef != retiredLogicRef, UnchangedLogicRef(retiredLogicRef));

        address protocolAdapter = $._protocolAdapter;
        _checkLogicRefDenied({protocolAdapter: protocolAdapter, logicRef: retiredLogicRef});
        _checkLogicRefNotDenied({protocolAdapter: protocolAdapter, logicRef: newLogicRef});

        require(
            _getMigratingERC20ForwarderStorage()._retiredLogicRefs.add(retiredLogicRef),
            LogicRefAlreadyRetired(retiredLogicRef)
        );

        $._logicRef = newLogicRef;

        emit LogicRefRetired({retiredLogicRef: retiredLogicRef, newLogicRef: newLogicRef});
    }

    /// @inheritdoc IMigratingERC20Forwarder
    function isLogicRefRetired(bytes32 logicRef) external view override returns (bool isRetired) {
        isRetired = _getMigratingERC20ForwarderStorage()._retiredLogicRefs.contains(logicRef);
    }

    /// @inheritdoc IMigratingERC20Forwarder
    function retiredLogicRefCount() external view override returns (uint256 count) {
        count = _getMigratingERC20ForwarderStorage()._retiredLogicRefs.length();
    }

    /// @inheritdoc IMigratingERC20Forwarder
    function retiredLogicRefAtIndex(uint256 index) external view override returns (bytes32 retiredLogicRef) {
        retiredLogicRef = _getMigratingERC20ForwarderStorage()._retiredLogicRefs.at(index);
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

        // Each entry must name a retired logic reference, so these checks cover the whole batch.
        uint256 retiredCount = $._retiredLogicRefs.length();
        for (uint256 i = 0; i < retiredCount; ++i) {
            _checkLogicRefDenied({protocolAdapter: protocolAdapter, logicRef: $._retiredLogicRefs.at(i)});
        }

        for (uint256 i = 0; i < entryCount; ++i) {
            MigrateEntry memory entry = entries[i];

            require(
                entry.forwarder == address(this), ForwarderMismatch({expected: address(this), actual: entry.forwarder})
            );

            require($._retiredLogicRefs.contains(entry.retiredLogicRef), UnknownRetiredLogicRef(entry.retiredLogicRef));

            // Every root of the adapter works: the adapter creates no resource with a retired logic reference.
            // NOTE: The adapter is the caller and a trusted contract.
            // forge-lint: disable-next-item(calls-loop)
            require(
                ICommitmentTree(protocolAdapter).isCommitmentTreeRootContained(entry.commitmentTreeRoot),
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

            emit Migrated({token: token, retiredLogicRef: entry.retiredLogicRef, nullifier: entry.nullifier});
        }
    }

    /// @notice Checks that both denylists of the protocol adapter contain a retired logic reference: the adapter then
    /// neither consumes the resources that this contract migrates nor creates new ones.
    /// @param protocolAdapter The protocol adapter.
    /// @param logicRef The retired logic reference.
    function _checkLogicRefDenied(address protocolAdapter, bytes32 logicRef) internal view {
        // NOTE: `_migrate` calls this function in a loop, and the adapter is a trusted contract.
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
