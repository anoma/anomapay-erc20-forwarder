// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {MigrationScript} from "./MigrationScript.s.sol";

/// @title DeployERC20ForwarderMigration
/// @author Anoma Foundation, 2026
/// @notice A script to deploy the migration contract of one chain — the only contract that can move the V1 tokens,
/// and that can move them only to the recorded V2 forwarder. The deployment wallet owns it and moves the tokens with
/// it through `MigrateERC20ForwarderAssets`.
/// @dev The deployed contract fixes both forwarders and the owner, so a chain that records another V2 forwarder, or
/// another wallet, needs its own deployment.
/// @custom:security-contact security@anoma.foundation
contract DeployERC20ForwarderMigration is MigrationScript {
    /// @notice Deploys the migration contract between the chain's recorded forwarders. Without `--broadcast` the
    /// deployment is simulated locally.
    /// @dev The deployment is not deterministic, so a repeated run deploys a second contract. Pass the one this run
    /// reports to the steps that follow.
    /// @param isProduction Whether the tokens move to the production or the staging V2 forwarder.
    /// @return migration The migration contract, owned by the deployment wallet.
    function run(bool isProduction) public returns (ERC20ForwarderMigration migration) {
        (address forwarderV1, address forwarderV2) = _configuration(isProduction);
        address wallet = _deploymentWallet();

        vm.broadcast();
        migration = new ERC20ForwarderMigration(forwarderV1, forwarderV2, wallet);
    }
}
