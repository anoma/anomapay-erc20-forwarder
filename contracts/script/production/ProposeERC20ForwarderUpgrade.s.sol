// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin-contracts-5.7.0/proxy/utils/UUPSUpgradeable.sol";

import {DeployERC20ForwarderImplementation} from "../DeployERC20ForwarderImplementation.s.sol";
import {ProductionScript} from "./ProductionScript.s.sol";

/// @title ProposeERC20ForwarderUpgrade
/// @author Anoma Foundation, 2026
/// @notice A script to propose upgrading the production environment ERC20 forwarder proxy to the deployed
/// implementation of the current source version (see `DeployERC20ForwarderImplementation`) to the Safe owning the
/// proxy. The Safe owners confirm and execute the proposed upgrade in the Safe app.
/// @custom:security-contact security@anoma.foundation
contract ProposeERC20ForwarderUpgrade is ProductionScript {
    /// @notice Proposes the upgrade of the recorded production proxy to the implementation this source version
    /// predicts to the Safe owning the proxy.
    /// @param proposer The Safe owner or delegate proposing the transaction.
    function run(address proposer) public {
        DeployERC20ForwarderImplementation implementationDeployScript = new DeployERC20ForwarderImplementation();
        address implementation = _requireDeployedImplementation(implementationDeployScript);

        _propose({
            callData: abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall, (implementation, implementationDeployScript.INITIALIZATION_DATA())
            ),
            proposer: proposer
        });
    }
}
