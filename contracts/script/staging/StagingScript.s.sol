// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.16.2/src/Script.sol";

import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {DeployERC20ForwarderProxy} from "../DeployERC20ForwarderProxy.s.sol";

/// @title StagingScript
/// @author Anoma Foundation, 2026
/// @notice The base of the scripts acting on the staging environment ERC20 forwarder proxy, which the staging proxy
/// owner drives directly.
/// @custom:security-contact security@anoma.foundation
abstract contract StagingScript is Script {
    /// @notice Thrown if the proxy is not a staging deployment, i.e. not owned by the staging proxy owner.
    error NotAStagingDeployment(address proxy);

    /// @notice Thrown if the sender is not the proxy owner.
    error UnauthorizedSender(address sender);

    /// @notice Checks that the proxy belongs to the staging environment and that the sender owns it.
    /// @param proxy The staging environment ERC20 forwarder proxy to act on.
    function _checkSenderAuthorization(address proxy) internal {
        address owner = ERC20Forwarder(proxy).owner();
        require(owner == new DeployERC20ForwarderProxy().PROXY_OWNER_STAGING(), NotAStagingDeployment(proxy));
        require(msg.sender == owner, UnauthorizedSender(msg.sender));
    }
}
