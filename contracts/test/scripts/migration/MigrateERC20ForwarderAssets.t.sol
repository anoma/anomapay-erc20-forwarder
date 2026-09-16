// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.0.0/test/examples/ERC20Example.sol";

import {RecordedDeployments} from "../../../generated/RecordedDeployments.sol";
import {DeployERC20ForwarderProxy} from "../../../script/DeployERC20ForwarderProxy.s.sol";
import {MigrateERC20ForwarderAssets} from "../../../script/migration/MigrateERC20ForwarderAssets.s.sol";
import {ERC20ForwarderMigration} from "../../../src/migration/ERC20ForwarderMigration.sol";
import {SafeFixture} from "../../fixtures/SafeFixture.sol";
import {ERC20ForwarderMock} from "../../mocks/ERC20Forwarder.m.sol";
import {ERC20ForwarderV1Mock} from "../../mocks/ERC20ForwarderV1.m.sol";
import {ProtocolAdapterMock} from "../../mocks/ProtocolAdapter.m.sol";

/// @notice Checks the migration script against a chain that carries both recorded forwarders, with the V1 forwarder
/// and the Safe installed at the recorded addresses. Outside broadcast mode the script simulates the Safe executing
/// the proposal, so each proposal must leave the state it proposes.
contract MigrateERC20ForwarderAssetsTest is SafeFixture {
    uint256 internal constant _CHAIN_ID = 11155111;
    uint128 internal constant _AMOUNT = 42;
    bytes32 internal constant _LOGIC_REF = bytes32(uint256(1));

    address internal immutable _PROTOCOL_ADAPTER_V2 = makeAddr("protocol adapter v2");

    MigrateERC20ForwarderAssets internal _script;
    ProtocolAdapterMock internal _protocolAdapterV1;
    address internal _safe;
    address internal _safeOwner;
    address internal _forwarderV1;
    address internal _forwarderV2;
    ERC20Example internal _token;
    IERC20[] internal _tokens;

    function setUp() public {
        // Keep the script on the simulation branch regardless of the shell environment.
        vm.setEnv("SAFE_BROADCAST", "false");

        DeployERC20ForwarderProxy deployScript = new DeployERC20ForwarderProxy();
        _safeOwner = makeAddr("safe owner");
        _safe = _deploySafeAt(_safeOwner, deployScript.PROXY_OWNER_PRODUCTION());

        _protocolAdapterV1 = new ProtocolAdapterMock(address(this));
        _protocolAdapterV1.emergencyStop();

        // Deployed before the chain ID changes, because the deploy script refuses a chain with a recorded deployment.
        (address proxy,,,) =
            deployScript.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER_V2, logicRef: _LOGIC_REF});

        _forwarderV1 = RecordedDeployments.forwarderV1(_CHAIN_ID);
        _forwarderV2 = RecordedDeployments.forwarderProxy({isProduction: false, chainId: _CHAIN_ID});

        _install({
            source: address(
                new ERC20ForwarderV1Mock({protocolAdapter: address(_protocolAdapterV1), emergencyCommittee: _safe})
            ),
            target: _forwarderV1
        });
        _install({source: proxy, target: _forwarderV2});

        _token = new ERC20Example();
        _token.mint(_forwarderV1, _AMOUNT);
        _tokens.push(_token);

        vm.chainId(_CHAIN_ID);
        _script = new MigrateERC20ForwarderAssets();
    }

    function test_run_deploys_a_migration_between_the_recorded_forwarders() public {
        ERC20ForwarderMigration migration = _script.run(false);

        assertEq(address(migration.FORWARDER_V1()), _forwarderV1, "the migration names another source");
        assertEq(migration.FORWARDER_V2(), _forwarderV2, "the migration names another destination");
        assertEq(migration.owner(), _safe, "the Safe does not own the migration");
    }

    function test_run_moves_no_custody() public {
        _script.run(false);

        assertEq(_token.balanceOf(_forwarderV1), _AMOUNT, "the source lost the balance");
        assertEq(_token.balanceOf(_forwarderV2), 0, "the destination received a balance");
    }

    function test_run_reverts_if_the_chain_records_no_v1_forwarder() public {
        uint256 chainId = 31337;
        vm.chainId(chainId);

        vm.expectRevert(abi.encodeWithSelector(MigrateERC20ForwarderAssets.ForwarderV1NotRecorded.selector, chainId));
        _script.run(false);
    }

    function test_run_reverts_if_the_environment_records_no_deployment() public {
        vm.expectRevert(
            abi.encodeWithSelector(MigrateERC20ForwarderAssets.DeploymentNotRecorded.selector, "production", _CHAIN_ID)
        );
        _script.run(true);
    }

    function test_run_reverts_if_the_v2_forwarder_has_another_owner() public {
        address owner = makeAddr("another owner");
        _install({
            source: address(new ERC20ForwarderMock({owner_: owner, protocolAdapter: _PROTOCOL_ADAPTER_V2})),
            target: _forwarderV2
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateERC20ForwarderAssets.OwnerMismatch.selector,
                new DeployERC20ForwarderProxy().PROXY_OWNER_STAGING(),
                owner
            )
        );
        _script.run(false);
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

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateERC20ForwarderAssets.SharedProtocolAdapter.selector, address(_protocolAdapterV1)
            )
        );
        _script.run(false);
    }

    function test_proposeCaller_makes_the_migration_the_emergency_caller() public {
        ERC20ForwarderMigration migration = _script.run(false);

        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});

        assertEq(
            ERC20ForwarderV1Mock(_forwarderV1).getEmergencyCaller(),
            address(migration),
            "v1 holds another emergency caller"
        );
    }

    function test_proposeCaller_reverts_if_the_emergency_caller_is_assigned() public {
        ERC20ForwarderMigration migration = _script.run(false);
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateERC20ForwarderAssets.EmergencyCallerMismatch.selector, address(0), address(migration)
            )
        );
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});
    }

    function test_proposeCaller_reverts_if_the_protocol_adapter_is_not_stopped() public {
        ERC20ForwarderMigration migration = _script.run(false);
        ProtocolAdapterMock protocolAdapter = new ProtocolAdapterMock(address(this));
        _install({
            source: address(
                new ERC20ForwarderV1Mock({protocolAdapter: address(protocolAdapter), emergencyCommittee: _safe})
            ),
            target: _forwarderV1
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateERC20ForwarderAssets.ProtocolAdapterNotStopped.selector, address(protocolAdapter)
            )
        );
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});
    }

    function test_proposeCaller_reverts_if_the_migration_names_another_forwarder() public {
        address forwarderV1 = address(
            new ERC20ForwarderV1Mock({protocolAdapter: address(_protocolAdapterV1), emergencyCommittee: _safe})
        );
        ERC20ForwarderMigration migration = new ERC20ForwarderMigration(forwarderV1, _forwarderV2, _safe);

        vm.expectRevert(
            abi.encodeWithSelector(MigrateERC20ForwarderAssets.ForwarderV1Mismatch.selector, _forwarderV1, forwarderV1)
        );
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});
    }

    function test_proposeCaller_reverts_if_the_safe_does_not_own_the_migration() public {
        address owner = makeAddr("another owner");
        ERC20ForwarderMigration migration = new ERC20ForwarderMigration(_forwarderV1, _forwarderV2, owner);

        vm.expectRevert(abi.encodeWithSelector(MigrateERC20ForwarderAssets.OwnerMismatch.selector, _safe, owner));
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});
    }

    function test_proposeCaller_reverts_if_an_ownership_transfer_is_pending() public {
        ERC20ForwarderMigration migration = _script.run(false);
        address successor = makeAddr("successor");

        vm.prank(_safe);
        migration.transferOwnership(successor);

        vm.expectRevert(
            abi.encodeWithSelector(MigrateERC20ForwarderAssets.OwnershipTransferPending.selector, successor)
        );
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});
    }

    function test_proposeMigration_moves_the_custody_to_the_recorded_forwarder() public {
        ERC20ForwarderMigration migration = _script.run(false);
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});

        _script.proposeMigration({isProduction: false, migration: migration, tokens: _tokens, proposer: _safeOwner});

        assertEq(_token.balanceOf(_forwarderV1), 0, "the source keeps the balance");
        assertEq(_token.balanceOf(_forwarderV2), _AMOUNT, "the destination did not receive the balance");
    }

    function test_proposeMigration_reverts_if_the_migration_is_not_the_emergency_caller() public {
        ERC20ForwarderMigration migration = _script.run(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateERC20ForwarderAssets.EmergencyCallerMismatch.selector, address(migration), address(0)
            )
        );
        _script.proposeMigration({isProduction: false, migration: migration, tokens: _tokens, proposer: _safeOwner});
    }

    function test_verify_passes_once_the_custody_moved() public {
        ERC20ForwarderMigration migration = _script.run(false);
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});
        _script.proposeMigration({isProduction: false, migration: migration, tokens: _tokens, proposer: _safeOwner});

        _script.verify({isProduction: false, migration: migration, tokens: _tokens});
    }

    function test_verify_reverts_if_the_source_keeps_a_token() public {
        ERC20ForwarderMigration migration = _script.run(false);
        _script.proposeCaller({isProduction: false, migration: migration, proposer: _safeOwner});

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateERC20ForwarderAssets.TokenNotMigrated.selector, address(_token), uint256(_AMOUNT)
            )
        );
        _script.verify({isProduction: false, migration: migration, tokens: _tokens});
    }

    /// @notice Installs a deployed contract at the address the records name, which is where the script looks for it.
    /// @param source The deployed contract.
    /// @param target The recorded address.
    function _install(address source, address target) private {
        vm.etch(target, source.code);
        vm.copyStorage(source, target);
    }
}
