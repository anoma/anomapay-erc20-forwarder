// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployLegacyERC20ForwarderMigration} from "../../../script/migration/DeployLegacyERC20ForwarderMigration.s.sol";
import {MigrationScript} from "../../../script/migration/MigrationScript.s.sol";
import {Parameters} from "../../../script/Parameters.sol";
import {RecordedDeploymentsScript} from "../../../script/RecordedDeploymentsScript.s.sol";
import {LegacyERC20ForwarderMigration} from "../../../src/migration/LegacyERC20ForwarderMigration.sol";
import {MigrationFixture} from "../../fixtures/MigrationFixture.sol";
import {ERC20ForwarderMock} from "../../mocks/ERC20Forwarder.m.sol";
import {LegacyERC20ForwarderMock} from "../../mocks/LegacyERC20Forwarder.m.sol";

/// @notice Checks the script that deploys the migration contract and proposes its caller assignment, against a chain
/// that records both forwarders. It reads them and their protocol adapters from the records, so every test states what
/// the chain has to answer. Outside broadcast mode the script simulates the forwarder multisig executing the proposal,
/// so the assignment must leave the state it proposes.
contract DeployLegacyERC20ForwarderMigrationTest is MigrationFixture {
    function test_run_deploys_a_migration_between_the_recorded_forwarders() public {
        LegacyERC20ForwarderMigration migration = _deployMigration();

        assertEq(address(migration.LEGACY_FORWARDER()), _legacyForwarder, "the migration names another source");
        assertEq(migration.FORWARDER(), _forwarder, "the migration names another destination");
    }

    function test_run_deploys_the_migration_at_the_predicted_address() public {
        address predicted = new DeployLegacyERC20ForwarderMigration().predict({isProduction: false});

        LegacyERC20ForwarderMigration migration = _deployMigration();

        assertEq(address(migration), predicted, "the migration lands at another address");
    }

    function test_run_gives_the_migration_to_the_deployment_wallet() public {
        LegacyERC20ForwarderMigration migration = _deployMigration();

        assertEq(migration.owner(), _wallet, "the deployment wallet does not own the migration");
    }

    function test_run_makes_the_migration_the_emergency_caller() public {
        LegacyERC20ForwarderMigration migration = _deployMigration();

        assertEq(
            LegacyERC20ForwarderMock(_legacyForwarder).getEmergencyCaller(),
            address(migration),
            "the legacy ERC20 forwarder holds another emergency caller"
        );
    }

    function test_run_moves_no_tokens() public {
        _deployMigration();

        assertEq(_token.balanceOf(_legacyForwarder), _AMOUNT, "the source lost the balance");
        assertEq(_token.balanceOf(_forwarder), 0, "the destination received a balance");
    }

    function test_run_reverts_if_the_emergency_caller_is_assigned() public {
        LegacyERC20ForwarderMigration migration = _deployMigration();

        DeployLegacyERC20ForwarderMigration script = new DeployLegacyERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.EmergencyCallerMismatch.selector, address(0), address(migration))
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_protocol_adapter_is_not_stopped() public {
        _installLegacyProtocolAdapter({isStopped: false});

        DeployLegacyERC20ForwarderMigration script = new DeployLegacyERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.ProtocolAdapterNotStopped.selector, _legacyProtocolAdapter)
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_chain_records_no_legacy_forwarder() public {
        uint256 chainId = 31337;
        vm.chainId(chainId);

        DeployLegacyERC20ForwarderMigration script = new DeployLegacyERC20ForwarderMigration();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.LegacyForwarderNotRecorded.selector, chainId));
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_environment_records_no_deployment() public {
        DeployLegacyERC20ForwarderMigration script = new DeployLegacyERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(RecordedDeploymentsScript.DeploymentNotRecorded.selector, "production", _CHAIN_ID)
        );
        script.run({isProduction: true});
    }

    function test_run_reverts_if_the_forwarder_has_another_owner() public {
        address owner = makeAddr("another owner");
        _install({
            source: address(new ERC20ForwarderMock({owner_: owner, protocolAdapter: _protocolAdapter})),
            target: _forwarder
        });

        DeployLegacyERC20ForwarderMigration script = new DeployLegacyERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.OwnerMismatch.selector, Parameters.DEPLOYMENT_WALLET, owner)
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_legacy_forwarder_forwards_for_another_protocol_adapter() public {
        address protocolAdapter = makeAddr("another protocol adapter");
        _install({
            source: address(
                new LegacyERC20ForwarderMock({protocolAdapter: protocolAdapter, emergencyCommittee: _committee})
            ),
            target: _legacyForwarder
        });

        DeployLegacyERC20ForwarderMigration script = new DeployLegacyERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationScript.ProtocolAdapterMismatch.selector, _legacyProtocolAdapter, protocolAdapter
            )
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_forwarder_forwards_for_another_protocol_adapter() public {
        address protocolAdapter = makeAddr("another protocol adapter");
        _install({
            source: address(
                new ERC20ForwarderMock({owner_: Parameters.DEPLOYMENT_WALLET, protocolAdapter: protocolAdapter})
            ),
            target: _forwarder
        });

        DeployLegacyERC20ForwarderMigration script = new DeployLegacyERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.ProtocolAdapterMismatch.selector, _protocolAdapter, protocolAdapter)
        );
        script.run({isProduction: false});
    }
}
