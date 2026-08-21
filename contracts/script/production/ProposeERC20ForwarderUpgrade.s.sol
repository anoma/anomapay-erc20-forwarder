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
    /// @notice Proposes the upgrade to the Safe owning the proxy.
    /// @param proxy The production environment ERC20 forwarder proxy to upgrade.
    /// @param proposer The Safe owner or delegate proposing the transaction.
    /// @param newImplementation The implementation contract to upgrade to, which must be the one this source version
    /// deploys to. Take it from the deployment that produced it, not from this source, so that the check below
    /// compares two independent derivations.
    function run(address proxy, address proposer, address newImplementation) public {
        DeployERC20ForwarderImplementation implementationScript = new DeployERC20ForwarderImplementation();
        address predictedImplementation = implementationScript.predict();

        require(
            newImplementation == predictedImplementation,
            DeployERC20ForwarderImplementation.UnexpectedImplementation(predictedImplementation, newImplementation)
        );
        require(
            newImplementation.code.length != 0,
            DeployERC20ForwarderImplementation.ImplementationNotDeployed(newImplementation)
        );

        _propose({
            proxy: proxy,
            callData: abi.encodeCall(
                UUPSUpgradeable.upgradeToAndCall, (newImplementation, implementationScript.INITIALIZATION_DATA())
            ),
            proposer: proposer
        });
    }
}
