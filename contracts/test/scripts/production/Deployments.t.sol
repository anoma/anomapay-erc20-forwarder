// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {IVersion} from "anoma-forwarder-bases-3.1.0/src/interfaces/IVersion.sol";
import {IOwnerManager} from "safe-smart-account-1.5.0/contracts/interfaces/IOwnerManager.sol";

import {RecordedDeployments} from "../../../generated/RecordedDeployments.sol";
import {DeploymentsFixture} from "../../fixtures/DeploymentsFixture.sol";

/// @notice Checks the production deployments recorded in `deployments.json`. The genesis check needs no chain access
/// and holds everywhere. That the environment runs this source, as a release owned by a Safe, holds only while the
/// deployments are verified, because the source leads them between deployments.
contract DeploymentsProductionTest is DeploymentsFixture {
    /// @notice Skips the test unless the production deployments are verified against this source.
    modifier onlyProduction() {
        vm.skip(!vm.envOr("VERIFY_PRODUCTION_DEPLOYMENTS", false), "VERIFY_PRODUCTION_DEPLOYMENTS is not set");
        _;
    }

    function test_recorded_deployments_run_the_source_implementation() public onlyProduction {
        _expectSourceImplementations({isProduction: true});
    }

    function test_recorded_deployments_run_a_release_version_and_are_safe_owned() public onlyProduction {
        RecordedDeployments.Deployment[] memory deployments = _recordedDeployments({isProduction: true});

        for (uint256 i = 0; i < deployments.length; ++i) {
            string memory network = _network(deployments[i].chainId);
            address recordedProxy = deployments[i].proxy.addr;
            string memory context = _deploymentContext({isProduction: true, chainId: deployments[i].chainId});

            string memory version = abi.decode(
                _call({network: network, target: recordedProxy, data: abi.encodeCall(IVersion.VERSION, ())}), (string)
            );
            address owner = abi.decode(
                _call({network: network, target: recordedProxy, data: abi.encodeCall(OwnableUpgradeable.owner, ())}),
                (address)
            );

            assertTrue(_isRelease(version), string.concat(context, ": version is a prerelease"));
            assertTrue(
                _isSafeOn({network: network, account: owner}), string.concat(context, ": proxy is not owned by a Safe")
            );
        }
    }

    function test_recorded_deployments_use_the_environment_salt() public pure {
        _expectGenesisDeployments({isProduction: true});
    }

    /// @notice Returns whether an account on a network is a Safe: it has code, and its threshold is between one and
    /// its owner count.
    /// @param network The RPC endpoint alias of the network.
    /// @param account The account to check.
    /// @return isSafe Whether the account is a Safe.
    /// @dev A contract without the Safe getters fails the call, and so the test.
    function _isSafeOn(string memory network, address account) internal returns (bool isSafe) {
        if (_code({network: network, account: account}).length == 0) return false;

        address[] memory owners = abi.decode(
            _call({network: network, target: account, data: abi.encodeCall(IOwnerManager.getOwners, ())}), (address[])
        );
        uint256 threshold = abi.decode(
            _call({network: network, target: account, data: abi.encodeCall(IOwnerManager.getThreshold, ())}), (uint256)
        );

        isSafe = threshold >= 1 && threshold <= owners.length;
    }
}
