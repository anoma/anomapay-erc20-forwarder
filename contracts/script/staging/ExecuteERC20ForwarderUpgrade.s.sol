// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin-contracts-5.7.0/proxy/utils/UUPSUpgradeable.sol";

import {DeployERC20ForwarderImplementation} from "../DeployERC20ForwarderImplementation.s.sol";
import {StagingScript} from "./StagingScript.s.sol";

/// @title ExecuteERC20ForwarderUpgrade
/// @author Anoma Foundation, 2026
/// @notice A script to execute upgrading the staging environment ERC20 forwarder proxy to the deployed
/// implementation of the current source version (see `DeployERC20ForwarderImplementation`). Staging only: the
/// production proxy is owned by a Safe multisig, whose owners execute the upgrade proposed by
/// `production/ProposeERC20ForwarderUpgrade` in the Safe app instead.
/// @custom:security-contact security@anoma.foundation
contract ExecuteERC20ForwarderUpgrade is StagingScript {
    /// @notice Executes the upgrade of the recorded staging proxy to the implementation this source version predicts,
    /// as the proxy owner. Without `--broadcast`, the upgrade is simulated locally.
    function run() public {
        DeployERC20ForwarderImplementation implementationDeployScript = new DeployERC20ForwarderImplementation();
        address implementation = _requireDeployedImplementation(implementationDeployScript);
        address proxy = _requireRecordedProxy({isProduction: false});
        address owner = _stagingOwner({proxy: proxy});

        vm.startBroadcast(owner);
        UUPSUpgradeable(proxy).upgradeToAndCall(implementation, implementationDeployScript.INITIALIZATION_DATA());
        vm.stopBroadcast();
    }
}
