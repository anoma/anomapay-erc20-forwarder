// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";

import {MigrateERC20ForwarderAssets} from "../../../script/migration/MigrateERC20ForwarderAssets.s.sol";
import {MigrationScript} from "../../../script/migration/MigrationScript.s.sol";
import {LegacyERC20ForwarderMigration} from "../../../src/migration/LegacyERC20ForwarderMigration.sol";
import {MigrationFixture} from "../../fixtures/MigrationFixture.sol";
import {LegacyERC20ForwarderMock} from "../../mocks/LegacyERC20Forwarder.m.sol";

/// @notice Checks the migration script against a chain that carries both recorded forwarders. The script reads the
/// migration contract from the emergency caller of the legacy ERC20 forwarder, so every test states which contract the
/// legacy ERC20 forwarder holds.
contract MigrateERC20ForwarderAssetsTest is MigrationFixture {
    MigrateERC20ForwarderAssets internal _script;

    function test_executeMigration_reverts_if_the_legacy_forwarder_holds_no_emergency_caller() public {
        _script = new MigrateERC20ForwarderAssets();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.EmergencyCallerNotSet.selector, _legacyForwarder));
        _script.executeMigration({isProduction: false, tokens: _tokens});
    }

    function test_executeMigration_moves_the_tokens_to_the_recorded_forwarder() public {
        _deployMigration();

        new MigrateERC20ForwarderAssets().executeMigration({isProduction: false, tokens: _tokens});

        assertEq(_token.balanceOf(_legacyForwarder), 0, "the source keeps a balance");
        assertEq(_token.balanceOf(_forwarder), _AMOUNT, "the destination did not receive the balance");
    }

    function test_executeMigration_reverts_if_the_emergency_caller_names_another_forwarder() public {
        address legacyForwarder = address(
            new LegacyERC20ForwarderMock({protocolAdapter: _legacyProtocolAdapter, emergencyCommittee: _committee})
        );
        _assignEmergencyCaller(address(new LegacyERC20ForwarderMigration(legacyForwarder, _forwarder, _wallet)));

        _script = new MigrateERC20ForwarderAssets();

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.LegacyForwarderMismatch.selector, _legacyForwarder, legacyForwarder)
        );
        _script.executeMigration({isProduction: false, tokens: _tokens});
    }

    function test_executeMigration_reverts_if_the_deployment_wallet_does_not_own_the_emergency_caller() public {
        address owner = makeAddr("another owner");
        _assignEmergencyCaller(address(new LegacyERC20ForwarderMigration(_legacyForwarder, _forwarder, owner)));

        _script = new MigrateERC20ForwarderAssets();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.OwnerMismatch.selector, _wallet, owner));
        _script.executeMigration({isProduction: false, tokens: _tokens});
    }

    function test_verify_passes_once_the_tokens_moved() public {
        LegacyERC20ForwarderMigration migration = _deployMigration();

        vm.prank(_wallet);
        migration.migrate(_tokens);

        assertEq(_token.balanceOf(_forwarder), _AMOUNT, "the destination did not receive the balance");
        new MigrateERC20ForwarderAssets().verify({isProduction: false, tokens: _tokens});
    }

    function test_verify_reverts_if_the_source_keeps_a_token() public {
        _deployMigration();

        _script = new MigrateERC20ForwarderAssets();

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateERC20ForwarderAssets.TokenNotMigrated.selector, address(_token), uint256(_AMOUNT)
            )
        );
        _script.verify({isProduction: false, tokens: _tokens});
    }

    /// @notice Makes a contract the emergency caller of the legacy ERC20 forwarder, the way the forwarder multisig
    /// does.
    /// @param caller The contract to assign.
    function _assignEmergencyCaller(address caller) private {
        vm.prank(_committee);
        IEmergencyMigratable(_legacyForwarder).setEmergencyCaller(caller);
    }
}
