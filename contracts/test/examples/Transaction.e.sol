// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Transaction} from "anoma-pa-evm-1.0.0/src/Types.sol";
import {Parsing} from "anoma-pa-evm-1.0.0/test/libs/parsing.sol";
import {Vm} from "forge-std-1.14.0/src/Test.sol";

library TransactionExample {
    using Parsing for Vm;

    function exampleTransaction(Vm vm) public view returns (Transaction memory txn) {
        txn = vm.parseTransaction("dependencies/anoma-pa-evm-1.0.0/test/examples/transactions/test_tx_reg_01_01.bin");
    }
}
