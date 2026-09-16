// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MigrateERC20ForwarderAssets} from "../../../script/migration/MigrateERC20ForwarderAssets.s.sol";
import {MigrationScript} from "../../../script/migration/MigrationScript.s.sol";
import {ERC20ForwarderMigration} from "../../../src/migration/ERC20ForwarderMigration.sol";
import {MigrationFixture} from "../../fixtures/MigrationFixture.sol";
import {ERC20ForwarderV1Mock} from "../../mocks/ERC20ForwarderV1.m.sol";
import {ProtocolAdapterMock} from "../../mocks/ProtocolAdapter.m.sol";

/// @notice Checks the migration script against a chain that carries both recorded forwarders. Outside broadcast mode
/// the script simulates the committee Safe executing the proposal, so the caller assignment must leave the state it
/// proposes. The move itself is only checked through its guards: the script broadcasts it as the deployment wallet,
/// and forge rejects a broadcast under the prank that makes the sender the wallet in the first place.
/// `ERC20ForwarderMigration.unit.t.sol` and the fork test cover the move itself.
contract MigrateERC20ForwarderAssetsTest is MigrationFixture {
    MigrateERC20ForwarderAssets internal _script;

    function test_proposeCaller_makes_the_migration_the_emergency_caller() public {
        ERC20ForwarderMigration migration = _deployMigration();

        _script = new MigrateERC20ForwarderAssets();
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});

        assertEq(
            ERC20ForwarderV1Mock(_forwarderV1).getEmergencyCaller(),
            address(migration),
            "v1 holds another emergency caller"
        );
    }

    function test_proposeCaller_reverts_if_the_emergency_caller_is_assigned() public {
        ERC20ForwarderMigration migration = _deployMigration();

        _script = new MigrateERC20ForwarderAssets();
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.EmergencyCallerMismatch.selector, address(0), address(migration))
        );
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});
    }

    function test_proposeCaller_reverts_if_the_protocol_adapter_is_not_stopped() public {
        ERC20ForwarderMigration migration = _deployMigration();
        ProtocolAdapterMock protocolAdapter = new ProtocolAdapterMock(address(this));
        _install({
            source: address(
                new ERC20ForwarderV1Mock({protocolAdapter: address(protocolAdapter), emergencyCommittee: _committee})
            ),
            target: _forwarderV1
        });

        _script = new MigrateERC20ForwarderAssets();
        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.ProtocolAdapterNotStopped.selector, address(protocolAdapter))
        );
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});
    }

    function test_proposeCaller_reverts_if_the_migration_names_another_forwarder() public {
        address forwarderV1 = address(
            new ERC20ForwarderV1Mock({protocolAdapter: address(_protocolAdapterV1), emergencyCommittee: _committee})
        );
        ERC20ForwarderMigration migration = new ERC20ForwarderMigration(forwarderV1, _forwarderV2, _wallet);

        _script = new MigrateERC20ForwarderAssets();
        vm.expectRevert(abi.encodeWithSelector(MigrationScript.ForwarderV1Mismatch.selector, _forwarderV1, forwarderV1));
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});
    }

    function test_proposeCaller_reverts_if_the_deployment_wallet_does_not_own_the_migration() public {
        address owner = makeAddr("another owner");
        ERC20ForwarderMigration migration = new ERC20ForwarderMigration(_forwarderV1, _forwarderV2, owner);

        _script = new MigrateERC20ForwarderAssets();
        vm.expectRevert(abi.encodeWithSelector(MigrationScript.OwnerMismatch.selector, _wallet, owner));
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});
    }

    function test_executeMigration_reverts_if_the_migration_is_not_the_emergency_caller() public {
        ERC20ForwarderMigration migration = _deployMigration();

        _script = new MigrateERC20ForwarderAssets();
        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.EmergencyCallerMismatch.selector, address(migration), address(0))
        );
        _script.executeMigration({isProduction: false, migration: migration, tokens: _tokens});
    }

    function test_executeMigration_reverts_if_the_sender_is_not_the_deployment_wallet() public {
        ERC20ForwarderMigration migration = _deployMigration();
        address outsider = makeAddr("outsider");

        _script = new MigrateERC20ForwarderAssets();
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(MigrateERC20ForwarderAssets.UnauthorizedSender.selector, outsider));
        _script.executeMigration({isProduction: false, migration: migration, tokens: _tokens});
    }

    function test_verify_passes_once_the_custody_moved() public {
        ERC20ForwarderMigration migration = _deployMigration();

        _script = new MigrateERC20ForwarderAssets();
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});

        vm.prank(_wallet);
        migration.migrate(_tokens);

        assertEq(_token.balanceOf(_forwarderV2), _AMOUNT, "the destination did not receive the balance");
        _script.verify({isProduction: false, migration: migration, tokens: _tokens});
    }

    function test_verify_reverts_if_the_source_keeps_a_token() public {
        ERC20ForwarderMigration migration = _deployMigration();

        _script = new MigrateERC20ForwarderAssets();
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _committeeOwner});

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateERC20ForwarderAssets.TokenNotMigrated.selector, address(_token), uint256(_AMOUNT)
            )
        );
        _script.verify({isProduction: false, migration: migration, tokens: _tokens});
    }
}
