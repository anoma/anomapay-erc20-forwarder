// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Transaction} from "anoma-pa-evm-nightly/src/Types.sol";
import {Parsing} from "anoma-pa-evm-nightly/test/libs/parsing.sol";
import {Vm} from "forge-std-1.15.0/src/Test.sol";

library TransactionExample {
    using Parsing for Vm;

    function exampleTransaction(Vm vm) public view returns (Transaction memory txn) {
        txn = vm.parseTransaction(
            "dependencies/anoma-pa-evm-nightly/contracts/test/examples/transactions/test_tx_reg_01_01.bin"
        );
    }
}
