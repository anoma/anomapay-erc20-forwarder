// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Parameters} from "../script/Parameters.sol";

/// @title DeploymentParameters
/// @author Anoma Foundation, 2026
/// @notice Exposes the deployment parameters through getters, so the bindings tests read the values the scripts hold
/// instead of restating them.
/// @custom:security-contact security@anoma.foundation
contract DeploymentParameters {
    /// @notice Returns the CREATE2 salt for the staging environment proxy deployment.
    /// @return salt The staging proxy salt.
    function PROXY_SALT_STAGING() external pure returns (bytes32 salt) {
        salt = Parameters.PROXY_SALT_STAGING;
    }

    /// @notice Returns the CREATE2 salt for the production environment proxy deployment.
    /// @return salt The production proxy salt.
    function PROXY_SALT_PRODUCTION() external pure returns (bytes32 salt) {
        salt = Parameters.PROXY_SALT_PRODUCTION;
    }

    /// @notice Returns the CREATE2 salt for the implementation deployment.
    /// @return salt The implementation salt, shared by both environments.
    function IMPLEMENTATION_SALT() external pure returns (bytes32 salt) {
        salt = Parameters.IMPLEMENTATION_SALT;
    }

    /// @notice Returns the CREATE2 salt for the migration contract deployment.
    /// @return salt The migration contract salt.
    function MIGRATION_SALT() external pure returns (bytes32 salt) {
        salt = Parameters.MIGRATION_SALT;
    }

    /// @notice Returns the logic ref the proxies are initialized with.
    /// @return logicRef The logic ref of the token transfer circuit.
    function LOGIC_REF() external pure returns (bytes32 logicRef) {
        logicRef = Parameters.LOGIC_REF;
    }

    /// @notice Returns the deployment wallet.
    /// @return wallet The deployment wallet, which owns the staging proxies.
    function DEPLOYMENT_WALLET() external pure returns (address wallet) {
        wallet = Parameters.DEPLOYMENT_WALLET;
    }

    /// @notice Returns the forwarder multisig.
    /// @return multisig The Safe that owns the production proxies and is the emergency committee of the V1 forwarders.
    function FWD_MULTISIG() external pure returns (address multisig) {
        multisig = Parameters.FWD_MULTISIG;
    }
}
