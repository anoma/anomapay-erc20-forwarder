// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.7.0/access/OwnableUpgradeable.sol";
import {IVersion} from "anoma-forwarder-bases-3.1.0/src/interfaces/IVersion.sol";

import {RecordedDeployments} from "../../../generated/RecordedDeployments.sol";
import {Parameters} from "../../../script/Parameters.sol";
import {DeploymentsFixture} from "../../fixtures/DeploymentsFixture.sol";

/// @notice Checks the production deployments recorded in `deployments.json`. The genesis check needs no chain access
/// and holds everywhere. That the environment runs this source, as a release owned by the forwarder multisig, holds
/// only while the deployments are verified, because the source leads them between deployments.
contract DeploymentsProductionTest is DeploymentsFixture {
    /// @notice Skips the test unless the production deployments are verified against this source.
    modifier onlyProduction() {
        vm.skip(!vm.envOr("VERIFY_PRODUCTION_DEPLOYMENTS", false), "VERIFY_PRODUCTION_DEPLOYMENTS is not set");
        _;
    }

    function test_recorded_deployments_run_the_source_implementation() public onlyProduction {
        _expectSourceImplementations({isProduction: true});
    }

    function test_recorded_deployments_run_a_release_version_and_are_owned_by_the_forwarder_multisig()
        public
        onlyProduction
    {
        RecordedDeployments.Deployment[] memory deployments = _recordedDeployments({isProduction: true});

        for (uint256 i = 0; i < deployments.length; ++i) {
            uint256 chainId = deployments[i].chainId;
            address proxy = deployments[i].proxy.addr;
            string memory context = _deploymentContext({isProduction: true, chainId: chainId});

            string memory version = abi.decode(
                _call({chainId: chainId, target: proxy, data: abi.encodeCall(IVersion.VERSION, ())}), (string)
            );
            address owner = abi.decode(
                _call({chainId: chainId, target: proxy, data: abi.encodeCall(OwnableUpgradeable.owner, ())}), (address)
            );

            assertTrue(_isRelease(version), string.concat(context, ": version is a prerelease"));
            assertEq(owner, Parameters.FWD_MULTISIG, string.concat(context, ": not owned by the forwarder multisig"));
        }
    }

    function test_recorded_deployments_use_the_environment_salt() public pure {
        _expectGenesisDeployments({isProduction: true});
    }
}
