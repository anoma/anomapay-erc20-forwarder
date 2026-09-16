// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";

import {IERC20ForwarderMigration} from "../../src/migration/IERC20ForwarderMigration.sol";

/// @notice A token that calls the migration back while it moves this token, which is how a token with a transfer
/// callback would re-enter.
contract ERC20ReentrantExample is ERC20 {
    IERC20ForwarderMigration internal _migration;

    constructor() ERC20("MyToken", "MTK") {}

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function setMigration(IERC20ForwarderMigration migration) external {
        _migration = migration;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (address(_migration) == address(0) || from == address(0)) {
            return;
        }

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(this));
        _migration.migrate(tokens);
    }
}
