// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ExecuteERC20ForwarderUpgrade} from "../../script/staging/ExecuteERC20ForwarderUpgrade.s.sol";

/// @notice The upgrade, acting on the given proxy instead of the recorded one. The records hold only the deployments on
/// the chains, not a test deployment.
contract ExecuteERC20ForwarderUpgradeMock is ExecuteERC20ForwarderUpgrade {
    address internal immutable _PROXY;

    constructor(address proxy) {
        _PROXY = proxy;
    }

    function _recordedProxy(bool) internal view override returns (address proxy) {
        proxy = _PROXY;
    }
}
