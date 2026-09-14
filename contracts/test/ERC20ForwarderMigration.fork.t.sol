// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

import {DeployERC20ForwarderProxy} from "../script/DeployERC20ForwarderProxy.s.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ERC20ForwarderMigration} from "../src/migration/ERC20ForwarderMigration.sol";
import {IERC20ForwarderV1} from "../src/migration/IERC20ForwarderV1.sol";
import {DeploymentsFixture} from "./fixtures/DeploymentsFixture.sol";

interface IProtocolAdapterV1 {
    function emergencyStop() external;
    function isEmergencyStopped() external view returns (bool isStopped);
}

contract ERC20ForwarderMigrationForkTest is DeploymentsFixture {
    function test_baseSepoliaDeployedV1ToRecordedStagingV2() public {
        string memory json = vm.readFile("script/migration/tokens.json");
        string memory key = ".chains.84532";
        vm.createSelectFork(vm.envOr("MIGRATION_FORK_RPC", string("base-sepolia")));
        assertEq(block.chainid, 84532);
        assertGt(vm.parseJsonUint(json, string.concat(key, ".audit.wrappedEventCount")), 0);

        IERC20ForwarderV1 v1 = IERC20ForwarderV1(vm.parseJsonAddress(json, string.concat(key, ".forwarderV1")));
        address committee = vm.parseJsonAddress(json, string.concat(key, ".audit.emergencyCommittee"));
        address v2;
        Deployment[] memory deployments = _recordedDeployments(false);
        for (uint256 i = 0; i < deployments.length; ++i) {
            if (deployments[i].chainId == block.chainid) {
                v2 = deployments[i].proxy.addr;
            }
        }
        assertGt(v2.code.length, 0, "recorded staging V2 must exist");
        assertEq(v2, 0xE54182d915dE447deFc4A17Ec1D4E0dc627551F7);
        assertEq(ERC20Forwarder(v2).VERSION(), "2.0.0-rc.0");

        address owner = new DeployERC20ForwarderProxy().PROXY_OWNER_PRODUCTION();
        ERC20ForwarderMigration migration = new ERC20ForwarderMigration(address(v1), v2, owner);
        IERC20[] memory tokens = abi.decode(vm.parseJson(json, string.concat(key, ".tokens")), (IERC20[]));
        uint256[] memory beforeV1 = new uint256[](tokens.length);
        uint256[] memory beforeV2 = new uint256[](tokens.length);
        bool hasCustody;
        for (uint256 i = 0; i < tokens.length; ++i) {
            beforeV1[i] = tokens[i].balanceOf(address(v1));
            beforeV2[i] = tokens[i].balanceOf(v2);
            if (beforeV1[i] > 0) hasCustody = true;
        }
        assertTrue(hasCustody, "fork must migrate real existing custody");

        address outsider = makeAddr("outsider");
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        migration.migrate(tokens);

        IProtocolAdapterV1 pa = IProtocolAdapterV1(v1.getProtocolAdapter());
        assertFalse(pa.isEmergencyStopped());
        vm.prank(committee);
        vm.expectRevert(bytes4(keccak256("ProtocolAdapterNotStopped()")));
        v1.setEmergencyCaller(address(migration));
        vm.prank(Ownable(address(pa)).owner());
        pa.emergencyStop();
        assertTrue(pa.isEmergencyStopped());

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedCaller(address,address)", committee, outsider));
        v1.setEmergencyCaller(address(migration));
        vm.prank(committee);
        v1.setEmergencyCaller(address(migration));
        vm.prank(committee);
        vm.expectRevert(abi.encodeWithSignature("EmergencyCallerAlreadySet(address)", address(migration)));
        v1.setEmergencyCaller(outsider);

        vm.prank(owner);
        migration.migrate(tokens);
        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(tokens[i].balanceOf(address(v1)), 0);
            assertEq(tokens[i].balanceOf(v2), beforeV2[i] + beforeV1[i]);
            assertEq(tokens[i].balanceOf(address(migration)), 0);
        }
    }
}
