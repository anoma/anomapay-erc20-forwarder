// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

import {ExecuteERC20ForwarderWithdrawal} from "../../script/staging/ExecuteERC20ForwarderWithdrawal.s.sol";

/// @notice The withdrawal, acting on the given proxy and tokens instead of the recorded proxy and the tokens of the
/// chain. The records and the token lists hold only the deployments on the chains, not a test deployment.
contract ExecuteERC20ForwarderWithdrawalMock is ExecuteERC20ForwarderWithdrawal {
    address internal immutable _PROXY;
    IERC20[] internal _tokenList;

    constructor(address proxy, IERC20[] memory tokens) {
        _PROXY = proxy;
        _tokenList = tokens;
    }

    function _recordedProxy(bool) internal view override returns (address proxy) {
        proxy = _PROXY;
    }

    function _tokens() internal view override returns (IERC20[] memory tokens) {
        tokens = _tokenList;
    }
}
