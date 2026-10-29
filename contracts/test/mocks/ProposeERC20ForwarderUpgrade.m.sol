// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ProposeERC20ForwarderUpgrade} from "../../script/production/ProposeERC20ForwarderUpgrade.s.sol";

/// @notice The upgrade proposal, acting on the given proxy instead of the recorded one. The records are compiled in, so they
/// name no test deployment.
contract ProposeERC20ForwarderUpgradeMock is ProposeERC20ForwarderUpgrade {
    address internal immutable _PROXY;

    constructor(address proxy) {
        _PROXY = proxy;
    }

    function _recordedProxy(bool) internal view override returns (address proxy) {
        proxy = _PROXY;
    }
}
