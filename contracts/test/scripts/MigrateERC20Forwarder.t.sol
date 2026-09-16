// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {Test} from "forge-std-1.16.2/src/Test.sol";

import {DeployERC20ForwarderProxy} from "../../script/DeployERC20ForwarderProxy.s.sol";
import {IStoppedProtocolAdapter, MigrateERC20Forwarder} from "../../script/migration/MigrateERC20Forwarder.s.sol";
import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {IERC20ForwarderV1} from "../../src/migration/IERC20ForwarderV1.sol";

interface IProtocolAdapterStop {
    function emergencyStop() external;
}

contract MigrateERC20ForwarderTest is Test {
    MigrateERC20Forwarder internal _script;
    IERC20ForwarderV1 internal _v1;
    IStoppedProtocolAdapter internal _pa;
    IERC20 internal _usdc;
    address internal _v2;

    function setUp() public {
        string memory json = vm.readFile("script/migration/tokens.json");
        uint256 forkBlock = vm.parseJsonUint(json, ".chains.84532.audit.blockNumber");
        vm.createSelectFork(vm.envOr("MIGRATION_FORK_RPC", string("base-sepolia")), forkBlock);
        _v1 = IERC20ForwarderV1(vm.parseJsonAddress(json, ".chains.84532.forwarderV1"));
        _pa = IStoppedProtocolAdapter(_v1.getProtocolAdapter());
        _usdc = IERC20(0x036CbD53842c5426634e7929541eC2318f3dCF7e);
        _v2 = 0xE54182d915dE447deFc4A17Ec1D4E0dc627551F7;
        _script = new MigrateERC20Forwarder();
    }

    function test_deploysWithoutChangingPAOrCustody() public {
        uint256 beforeV1 = _usdc.balanceOf(address(_v1));
        uint256 beforeV2 = _usdc.balanceOf(_v2);
        ERC20ForwarderMigration migration = _script.run(false);
        assertEq(migration.owner(), new DeployERC20ForwarderProxy().PROXY_OWNER_PRODUCTION());
        assertEq(address(migration.FORWARDER_V1()), address(_v1));
        assertEq(migration.FORWARDER_V2(), _v2);
        assertFalse(_pa.isEmergencyStopped());
        assertEq(_v1.getEmergencyCaller(), address(0));
        assertEq(_usdc.balanceOf(address(_v1)), beforeV1);
        assertEq(_usdc.balanceOf(_v2), beforeV2);
    }

    function test_productionWithoutRecordedV2RemainsInactive() public {
        vm.expectRevert(abi.encodeWithSelector(MigrateERC20Forwarder.MissingV2Deployment.selector, 84532, true));
        _script.run(true);
        assertFalse(_pa.isEmergencyStopped());
        assertEq(_v1.getEmergencyCaller(), address(0));
    }

    function test_safeActionsEnforceStopAndAssignmentOrder() public {
        ERC20ForwarderMigration migration = _script.run(false);
        address proposer = makeAddr("proposer");
        vm.expectRevert(MigrateERC20Forwarder.ProtocolAdapterNotStopped.selector);
        _script.proposeCaller(false, migration, proposer);
        vm.prank(Ownable(address(_pa)).owner());
        IProtocolAdapterStop(address(_pa)).emergencyStop();
        vm.expectRevert(abi.encodeWithSelector(MigrateERC20Forwarder.WrongEmergencyCaller.selector, address(0)));
        _script.proposeMigration(false, migration, proposer);

        uint256 beforeV1 = _usdc.balanceOf(address(_v1));
        uint256 beforeV2 = _usdc.balanceOf(_v2);
        assertGt(beforeV1, 0);
        _script.proposeCaller(false, migration, proposer);
        assertEq(_v1.getEmergencyCaller(), address(migration));
        _script.proposeMigration(false, migration, proposer);
        assertEq(_usdc.balanceOf(address(_v1)), 0);
        assertEq(_usdc.balanceOf(_v2), beforeV2 + beforeV1);
    }

    function test_rejectsMigrationWithUnrecordedDestination() public {
        ERC20ForwarderMigration wrong = new ERC20ForwarderMigration(address(_v1), address(_usdc), address(this));
        vm.expectRevert(MigrateERC20Forwarder.InvalidConfiguration.selector);
        _script.proposeCaller(false, wrong, address(this));
    }

    function test_rejectsUnexpectedMigrationControl() public {
        ERC20ForwarderMigration wrongOwner = new ERC20ForwarderMigration(address(_v1), _v2, address(this));
        vm.expectRevert(MigrateERC20Forwarder.InvalidConfiguration.selector);
        _script.proposeCaller(false, wrongOwner, address(this));

        ERC20ForwarderMigration pendingTransfer = _script.run(false);
        vm.prank(pendingTransfer.owner());
        pendingTransfer.transferOwnership(makeAddr("successor"));
        vm.expectRevert(MigrateERC20Forwarder.InvalidConfiguration.selector);
        _script.proposeCaller(false, pendingTransfer, address(this));
    }
}
