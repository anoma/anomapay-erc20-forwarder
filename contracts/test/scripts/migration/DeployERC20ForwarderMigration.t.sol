// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployERC20ForwarderProxy} from "../../../script/DeployERC20ForwarderProxy.s.sol";
import {DeployERC20ForwarderMigration} from "../../../script/migration/DeployERC20ForwarderMigration.s.sol";
import {MigrationScript} from "../../../script/migration/MigrationScript.s.sol";
import {ERC20ForwarderMigration} from "../../../src/migration/ERC20ForwarderMigration.sol";
import {MigrationFixture} from "../../fixtures/MigrationFixture.sol";
import {ERC20ForwarderMock} from "../../mocks/ERC20Forwarder.m.sol";

/// @notice Checks the deploy script of the migration contract against a chain that records both forwarders. It reads
/// them from the records, so every test states what the chain has to answer.
contract DeployERC20ForwarderMigrationTest is MigrationFixture {
    function test_run_deploys_a_migration_between_the_recorded_forwarders() public {
        ERC20ForwarderMigration migration = _deployMigration();

        assertEq(address(migration.FORWARDER_V1()), _forwarderV1, "the migration names another source");
        assertEq(migration.FORWARDER_V2(), _forwarderV2, "the migration names another destination");
    }

    function test_run_gives_the_migration_to_the_deployment_wallet() public {
        ERC20ForwarderMigration migration = _deployMigration();

        assertEq(migration.owner(), _wallet, "the deployment wallet does not own the migration");
    }

    function test_run_moves_no_tokens() public {
        _deployMigration();

        assertEq(_token.balanceOf(_forwarderV1), _AMOUNT, "the source lost the balance");
        assertEq(_token.balanceOf(_forwarderV2), 0, "the destination received a balance");
    }

    function test_run_reverts_if_the_chain_records_no_v1_forwarder() public {
        uint256 chainId = 31337;
        vm.chainId(chainId);

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.ForwarderV1NotRecorded.selector, chainId));
        script.run(false);
    }

    function test_run_reverts_if_the_environment_records_no_deployment() public {
        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.DeploymentNotRecorded.selector, "production", _CHAIN_ID));
        script.run(true);
    }

    function test_run_reverts_if_the_v2_forwarder_has_another_owner() public {
        address owner = makeAddr("another owner");
        _install({
            source: address(new ERC20ForwarderMock({owner_: owner, protocolAdapter: _PROTOCOL_ADAPTER_V2})),
            target: _forwarderV2
        });

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();
        address expectedOwner = new DeployERC20ForwarderProxy().PROXY_OWNER_STAGING();

        vm.expectRevert(abi.encodeWithSelector(MigrationScript.OwnerMismatch.selector, expectedOwner, owner));
        script.run(false);
    }

    function test_run_reverts_if_the_v2_forwarder_shares_the_protocol_adapter() public {
        _install({
            source: address(
                new ERC20ForwarderMock({
                    owner_: new DeployERC20ForwarderProxy().PROXY_OWNER_STAGING(),
                    protocolAdapter: address(_protocolAdapterV1)
                })
            ),
            target: _forwarderV2
        });

        DeployERC20ForwarderMigration script = new DeployERC20ForwarderMigration();

        vm.expectRevert(
            abi.encodeWithSelector(MigrationScript.SharedProtocolAdapter.selector, address(_protocolAdapterV1))
        );
        script.run(false);
    }
}
