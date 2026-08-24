// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.16.2/src/Script.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";

/// @title PrintERC20ForwarderVersion
/// @author Anoma Foundation, 2025
/// @notice A script returning the version the ERC20 forwarder source compiles to. The release flow reads it to label
/// the published package, so that the label always describes the source it ships.
/// @custom:security-contact security@anoma.foundation
contract PrintERC20ForwarderVersion is Script {
    /// @notice Returns the version of the ERC20 forwarder this source compiles to.
    /// @return version The ERC20 forwarder version.
    function run() public returns (string memory version) {
        version = new ERC20Forwarder().VERSION();
    }
}
