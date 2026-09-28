// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {EnumerableMap} from "@openzeppelin-contracts-5.7.0/utils/structs/EnumerableMap.sol";
import {ICommitmentTree} from "anoma-pa-evm-2.0.0-rc.8/src/interfaces/ICommitmentTree.sol";
import {INullifierSet} from "anoma-pa-evm-2.0.0-rc.8/src/interfaces/INullifierSet.sol";
import {IProtocolAdapter} from "anoma-pa-evm-2.0.0-rc.8/src/interfaces/IProtocolAdapter.sol";

import {ERC20Forwarder} from "../ERC20Forwarder.sol";
import {IMigratingERC20Forwarder} from "./IMigratingERC20Forwarder.sol";

/// @title MigratingERC20Forwarder
/// @author Anoma Foundation, 2026
/// @notice A draft ERC20 forwarder that re-issues ERC20 resources after a proof system version turns out to be
/// forgeable. It adds one call type, `Migrate`, next to wrap and unwrap.
/// @dev A migration trusts no proof made under the forgeable version. It trusts one commitment tree root that the
/// protocol adapter recorded before that version went live.
///
/// The incident runs in this order.
/// 1. The owner pauses the protocol adapter, so nothing settles any more.
/// 2. The owner upgrades the protocol adapter to an implementation that holds sound circuit keys and names a sound
///    RISC Zero verifier.
/// 3. The owner upgrades this forwarder and calls `reinitialize` with the new logic reference and the migration root.
/// 4. The owner unpauses the protocol adapter.
/// 5. The owner of a retired resource sends one migration transaction per resource. It proves, under the new circuits,
///    that the resource sits in the commitment tree at the migration root. This contract records the resource's
///    nullifier, and the transaction creates the same resource under the new logic reference.
///
/// Anchoring. The forwarder keeps its address across an upgrade, so the label `hash(forwarder, token)` no longer
/// tells the resource versions apart. The logic reference does, because the resource kind is
/// `hash(logicRef, labelRef)` and the rotation moves the logic reference. Two values must survive the rotation, and
/// step 3 stores both.
/// * The retired logic reference. `reinitialize` reads it from storage before it overwrites it.
/// * The migration root. The protocol adapter keeps every root it ever had, so the root is still on chain, but no rule
///   on chain picks the right one. The owner names it, and `reinitialize` checks that the adapter holds it.
///
/// Which root to name is the incident's decision, not the contract's. The latest root migrates every resource and
/// keeps what the attacker created. An earlier root drops the resources created after it, the honest ones included.
///
/// Repeated migrations. Each rotation adds one entry to the map of retired logic references, and a migration names the
/// entry it comes from. A second rotation therefore leaves the first generation migratable, and one contract covers
/// V1 to V2, V1 to V3 and V2 to V3 without a contract per version.
///
/// What a migration does not check. The tokens stay where they are, so the balance check that guards wrap and unwrap
/// cannot guard a migration. This contract checks that a migration moves no tokens and records the nullifier once. It
/// checks nothing about the amount. The resource logic must bind the created resource to the migrated one: same
/// label, same quantity, same owner. A migration that the logic leaves unbound creates tokens out of nothing.
///
/// A migration also does not restore tokens. If the forgeable version was used to unwrap tokens, the forwarder holds
/// less than the migrated resources add up to, and the shortfall shows up at unwrap time, first come first served.
///
/// This contract declares no initializer of its own. `ERC20Forwarder.initialize` initializes every parent, and a
/// rotation must not run it again, which is why `reinitialize` calls no parent initializer.
///
/// It also reports the `VERSION` of `ERC20Forwarder`, because a constant cannot be overridden. Promoting this draft
/// means turning `VERSION` into a virtual getter first.
/// @custom:security-contact security@anoma.foundation
/// @custom:oz-upgrades-from ERC20Forwarder
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract MigratingERC20Forwarder is IMigratingERC20Forwarder, ERC20Forwarder {
    using EnumerableMap for EnumerableMap.Bytes32ToBytes32Map;

    enum MigratingCallType {
        Wrap,
        Unwrap,
        Migrate
    }

    /// @notice A struct containing migration specific inputs.
    /// @param nullifier The nullifier of the resource to migrate, computed under the retired logic.
    /// @param migrationRoot The commitment tree root the resource is proven against. It must be the root this contract
    /// recorded for the retired logic reference.
    /// @param retiredLogicRef The logic reference the resource carries. It must be one this contract retired.
    /// @param forwarder The forwarder the resource label commits to. It must be this contract.
    struct MigrateData {
        bytes32 nullifier;
        bytes32 migrationRoot;
        bytes32 retiredLogicRef;
        address forwarder;
    }

    /// @notice The ERC-7201 storage of the contract.
    /// @custom:storage-location erc7201:anoma.storage.MigratingERC20Forwarder
    struct MigratingERC20ForwarderStorage {
        // The migration root of each retired logic reference, in retirement order.
        EnumerableMap.Bytes32ToBytes32Map _migrationRoots;
        // The nullifiers of the resources this contract migrated.
        mapping(bytes32 nullifier => bool isMigrated) _isNullifierMigrated;
    }

    /// @notice The ERC-7201 storage slot associated with the `MigratingERC20ForwarderStorage` struct.
    /// @dev `cast index-erc7201 "anoma.storage.MigratingERC20Forwarder"`
    bytes32 internal constant _MIGRATING_ERC20_FORWARDER_STORAGE_SLOT =
        0x542a3d2fc110dcee1dc322fc93583e849eb18bb7c89b4453a5bd009e400fab00;

    /// @notice The length of the migration data.
    uint256 internal constant _MIGRATE_DATA_LENGTH = 4 * 32;

    /// @notice Thrown if the protocol adapter is not paused while the logic reference rotates.
    error ProtocolAdapterNotPaused(address protocolAdapter);

    /// @notice Thrown if the protocol adapter does not hold the named migration root.
    error UnknownMigrationRoot(bytes32 migrationRoot);

    /// @notice Thrown if the rotation would keep the logic reference it retires.
    error UnchangedLogicRef(bytes32 logicRef);

    /// @notice Thrown if the rotation retires a logic reference that is retired already.
    error LogicRefAlreadyRetired(bytes32 logicRef);

    /// @notice Thrown if a migration names a logic reference this contract never retired.
    error UnknownRetiredLogicRef(bytes32 retiredLogicRef);

    /// @notice Thrown if a migration names another root than the one recorded for the retired logic reference.
    error MigrationRootMismatch(bytes32 expected, bytes32 actual);

    /// @notice Thrown if a migration names another forwarder than this contract.
    error ForwarderMismatch(address expected, address actual);

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

        // A paused adapter settles nothing, so no resource moves between the root and the rotation.
        address protocolAdapter = $._protocolAdapter;
        require(IProtocolAdapter(protocolAdapter).paused(), ProtocolAdapterNotPaused(protocolAdapter));
        require(
            ICommitmentTree(protocolAdapter).isCommitmentTreeRootContained(migrationRoot),
            UnknownMigrationRoot(migrationRoot)
        );

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
        (MigratingCallType callType, IERC20 token, uint128 amount) =
            abi.decode(input[:_GENERIC_INPUT_OFFSET], (MigratingCallType, IERC20, uint128));

        // Wrap and unwrap keep the first two call type values, so the base decodes the same input.
        if (callType != MigratingCallType.Migrate) {
            return super._forwardCall(input);
        }

        uint256 balanceBefore = token.balanceOf(address(this));

        _migrate({token: address(token), amount: amount, migrateInput: input[_GENERIC_INPUT_OFFSET:]});

        // A migration re-issues a resource that the forwarder already holds the tokens for, so no tokens move.
        uint256 balanceDelta = token.balanceOf(address(this)) - balanceBefore;
        // slither-disable-next-line incorrect-equality
        require(balanceDelta == 0, BalanceMismatch({expected: 0, actual: balanceDelta}));

        output = "";
    }

    /// @notice Migrates a resource carrying a retired logic reference by recording its nullifier.
    /// @param token The address of the token the migrated resource is labelled with.
    /// @param amount The quantity the migrated resource carries.
    /// @param migrateInput The input bytes containing the encoded arguments for the migration call.
    /// @dev The adapter check rejects a resource that was consumed the ordinary way. A retired resource can still be
    /// transferred, because a transfer calls no forwarder, and the transfer puts the nullifier into the adapter's
    /// set. The same check also rejects a resource that an attacker nullified under the forgeable version; those
    /// tokens are gone either way.
    function _migrate(address token, uint128 amount, bytes calldata migrateInput) internal {
        _checkLength({input: migrateInput, expectedLength: _MIGRATE_DATA_LENGTH});

        (MigrateData memory data) = abi.decode(migrateInput, (MigrateData));

        // The migrated resource's label commits to the forwarder, and the upgrade did not move this contract.
        require(data.forwarder == address(this), ForwarderMismatch({expected: address(this), actual: data.forwarder}));

        MigratingERC20ForwarderStorage storage $ = _getMigratingERC20ForwarderStorage();

        (bool isRetired, bytes32 migrationRoot) = $._migrationRoots.tryGet(data.retiredLogicRef);
        require(isRetired, UnknownRetiredLogicRef(data.retiredLogicRef));
        require(
            data.migrationRoot == migrationRoot,
            MigrationRootMismatch({expected: migrationRoot, actual: data.migrationRoot})
        );

        require(
            !INullifierSet(_getForwarderBaseStorage()._protocolAdapter).isNullifierContained(data.nullifier),
            ResourceAlreadyConsumed(data.nullifier)
        );

        require(!$._isNullifierMigrated[data.nullifier], ResourceAlreadyMigrated(data.nullifier));
        $._isNullifierMigrated[data.nullifier] = true;

        // NOTE: A migration moves no tokens, so this is not the `Wrapped` event; an indexer summing wraps and unwraps
        // must not count it as a deposit.
        emit Migrated({token: token, retiredLogicRef: data.retiredLogicRef, nullifier: data.nullifier, amount: amount});
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
