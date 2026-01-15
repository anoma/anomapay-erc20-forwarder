// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin-contracts-5.5.0/token/ERC20/ERC20.sol";

contract ERC20Example is ERC20 {
    constructor() ERC20("MyToken", "MTK") {}

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }
}

contract ERC20WithFeeExample is ERC20 {
    uint256 public constant FEE = 1;

    address internal immutable _FEE_RECIPIENT;
    bool internal immutable _IS_FEE_ADDED;

    constructor(bool isFeeAdded) ERC20("MyToken", "MTK") {
        _FEE_RECIPIENT = address(this);
        _IS_FEE_ADDED = isFeeAdded;
    }

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function _update(address from, address to, uint256 value) internal override {
        // No fee on mint or burn
        // - mint: from == address(0)
        // - burn: to == address(0)
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }

        if (_IS_FEE_ADDED) {
            super._update(from, to, value);
        } else {
            super._update(from, to, value - FEE);
        }
        super._update(from, _FEE_RECIPIENT, FEE);
    }
}
