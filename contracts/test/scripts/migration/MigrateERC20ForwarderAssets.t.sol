// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";

import {MigrateERC20ForwarderAssets} from "../../../script/migration/MigrateERC20ForwarderAssets.s.sol";
import {MigrationScript} from "../../../script/migration/MigrationScript.s.sol";
import {ERC20ForwarderMigration} from "../../../src/migration/ERC20ForwarderMigration.sol";
import {MigrationFixture} from "../../fixtures/MigrationFixture.sol";
import {ERC20ForwarderV1Mock} from "../../mocks/ERC20ForwarderV1.m.sol";

/// @notice Checks the migration script against a chain that carries both recorded forwarders. The script reads the
/// migration contract from the emergency caller of V1, so every test states which contract V1 holds.
contract MigrateERC20ForwarderAssetsTest is MigrationFixture {
    MigrateERC20ForwarderAssets internal _script;

    function test_executeMigration_reverts_if_v1_holds_no_emergency_caller() public {
        _script = new MigrateERC20ForwarderAssets();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.EmergencyCallerNotSet.selector, _forwarderV1));
        _script.executeMigration({isProduction: false, tokens: _tokens});
    }

    function test_executeMigration_moves_the_tokens_to_the_recorded_forwarder() public {
        _deployMigration();

        new MigrateERC20ForwarderAssets().executeMigration({isProduction: false, tokens: _tokens});

        assertEq(_token.balanceOf(_forwarderV1), 0, "the source keeps a balance");
        assertEq(_token.balanceOf(_forwarderV2), _AMOUNT, "the destination did not receive the balance");
    }

    function test_executeMigration_reverts_if_the_emergency_caller_names_another_forwarder() public {
        address forwarderV1 =
            address(new ERC20ForwarderV1Mock({protocolAdapter: _protocolAdapterV1, emergencyCommittee: _committee}));
        _assignEmergencyCaller(address(new ERC20ForwarderMigration(forwarderV1, _forwarderV2, _wallet)));

        _script = new MigrateERC20ForwarderAssets();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.ForwarderV1Mismatch.selector, _forwarderV1, forwarderV1));
        _script.executeMigration({isProduction: false, tokens: _tokens});
    }

    function test_executeMigration_reverts_if_the_deployment_wallet_does_not_own_the_emergency_caller() public {
        address owner = makeAddr("another owner");
        _assignEmergencyCaller(address(new ERC20ForwarderMigration(_forwarderV1, _forwarderV2, owner)));

        _script = new MigrateERC20ForwarderAssets();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.OwnerMismatch.selector, _wallet, owner));
        _script.executeMigration({isProduction: false, tokens: _tokens});
    }

    function test_verify_passes_once_the_tokens_moved() public {
        ERC20ForwarderMigration migration = _deployMigration();

        vm.prank(_wallet);
        migration.migrate(_tokens);

        assertEq(_token.balanceOf(_forwarderV2), _AMOUNT, "the destination did not receive the balance");
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

    /// @notice Makes a contract the emergency caller of V1, the way the forwarder multisig does.
    /// @param caller The contract to assign.
    function _assignEmergencyCaller(address caller) private {
        vm.prank(_committee);
        IEmergencyMigratable(_forwarderV1).setEmergencyCaller(caller);
    }
}
