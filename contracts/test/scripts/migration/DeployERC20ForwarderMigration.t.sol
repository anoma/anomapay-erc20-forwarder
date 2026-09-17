// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployERC20ForwarderMigration} from "../../../script/migration/DeployERC20ForwarderMigration.s.sol";
import {MigrationScript} from "../../../script/migration/MigrationScript.s.sol";
import {Parameters} from "../../../script/Parameters.sol";
import {ERC20ForwarderMigration} from "../../../src/migration/ERC20ForwarderMigration.sol";
import {MigrationFixture} from "../../fixtures/MigrationFixture.sol";
import {ERC20ForwarderMock} from "../../mocks/ERC20Forwarder.m.sol";
import {ERC20ForwarderV1Mock} from "../../mocks/ERC20ForwarderV1.m.sol";

/// @notice Checks the script that deploys the migration contract and proposes its caller assignment, against a chain
/// that records both forwarders. It reads them and their protocol adapters from the records, so every test states what
/// the chain has to answer. Outside broadcast mode the script simulates the forwarder multisig executing the proposal,
/// so the assignment must leave the state it proposes.
contract DeployERC20ForwarderMigrationTest is MigrationFixture {
    function test_run_deploys_a_migration_between_the_recorded_forwarders() public {
        ERC20ForwarderMigration migration = _deployMigration();

        assertEq(address(migration.FORWARDER_V1()), _forwarderV1, "the migration names another source");
        assertEq(migration.FORWARDER_V2(), _forwarderV2, "the migration names another destination");
    }

    function test_run_deploys_the_migration_at_the_predicted_address() public {
        address predicted = new DeployERC20ForwarderMigration().predict({isProduction: false});

        ERC20ForwarderMigration migration = _deployMigration();

        assertEq(address(migration), predicted, "the migration lands at another address");
    }

    function test_run_gives_the_migration_to_the_deployment_wallet() public {
        ERC20ForwarderMigration migration = _deployMigration();

        assertEq(migration.owner(), _wallet, "the deployment wallet does not own the migration");
    }

    function test_run_makes_the_migration_the_emergency_caller() public {
        ERC20ForwarderMigration migration = _deployMigration();

        assertEq(
            ERC20ForwarderV1Mock(_forwarderV1).getEmergencyCaller(),
            address(migration),
            "v1 holds another emergency caller"
        );
    }

    function test_run_moves_no_tokens() public {
        _deployMigration();

        assertEq(_token.balanceOf(_forwarderV1), _AMOUNT, "the source lost the balance");
        assertEq(_token.balanceOf(_forwarderV2), 0, "the destination received a balance");
    }

    function test_run_reverts_if_the_emergency_caller_is_assigned() public {
        ERC20ForwarderMigration migration = _deployMigration();

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.EmergencyCallerMismatch.selector, address(0), address(migration))
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_protocol_adapter_is_not_stopped() public {
        _installProtocolAdapterV1({isStopped: false});

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.ProtocolAdapterNotStopped.selector, _protocolAdapterV1));
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_chain_records_no_v1_forwarder() public {
        uint256 chainId = 31337;
        vm.chainId(chainId);

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.ForwarderV1NotRecorded.selector, chainId));
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_environment_records_no_deployment() public {
        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.DeploymentNotRecorded.selector, "production", _CHAIN_ID));
        script.run({isProduction: true});
    }

    function test_run_reverts_if_the_v2_forwarder_has_another_owner() public {
        address owner = makeAddr("another owner");
        _install({
            source: address(new ERC20ForwarderMock({owner_: owner, protocolAdapter: _protocolAdapterV2})),
            target: _forwarderV2
        });

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.OwnerMismatch.selector, Parameters.DEPLOYMENT_WALLET, owner)
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_v1_forwarder_forwards_for_another_protocol_adapter() public {
        address protocolAdapter = makeAddr("another protocol adapter");
        _install({
            source: address(
                new ERC20ForwarderV1Mock({protocolAdapter: protocolAdapter, emergencyCommittee: _committee})
            ),
            target: _forwarderV1
        });

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationScript.ProtocolAdapterMismatch.selector, _protocolAdapterV1, protocolAdapter
            )
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_v2_forwarder_forwards_for_another_protocol_adapter() public {
        address protocolAdapter = makeAddr("another protocol adapter");
        _install({
            source: address(
                new ERC20ForwarderMock({owner_: Parameters.DEPLOYMENT_WALLET, protocolAdapter: protocolAdapter})
            ),
            target: _forwarderV2
        });

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrationScript.ProtocolAdapterMismatch.selector, _protocolAdapterV2, protocolAdapter
            )
        );
        script.run({isProduction: false});
    }
}
