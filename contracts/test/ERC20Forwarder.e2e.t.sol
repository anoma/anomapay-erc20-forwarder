// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Parsing} from "@anoma-evm-pa-testing/libs/Parsing.sol";

import {DeployRiscZeroContracts} from "@anoma-evm-pa-testing/script/DeployRiscZeroContracts.s.sol";
import {ProtocolAdapter} from "@anoma-evm-pa/ProtocolAdapter.sol";
import {Transaction} from "@anoma-evm-pa/Types.sol";

import {IPermit2} from "@permit2/src/interfaces/IPermit2.sol";
import {RiscZeroGroth16Verifier} from "@risc0-ethereum/groth16/RiscZeroGroth16Verifier.sol";
import {RiscZeroVerifierRouter} from "@risc0-ethereum/RiscZeroVerifierRouter.sol";

import {Test, Vm} from "forge-std/Test.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ERC20Example} from "../test/examples/ERC20.e.sol";

contract ERC20ForwarderE2ETest is Test {
    using Parsing for Vm;

    uint256 internal constant _ALICE_PRIVATE_KEY =
        0xc522337787f3037e9d0dcba4dc4c0e3d4eb7b1c65598d51c425574e8ce64d140;

    address internal constant _EMERGENCY_COMMITTEE = address(uint160(1));
    uint128 internal constant _TRANSFER_AMOUNT = 1000;

    address internal _alice;

    ProtocolAdapter internal _pa;
    ERC20Forwarder internal _fwd;
    IPermit2 internal _permit2;
    ERC20Example internal _erc20;

    function setUp() public {
        _alice = vm.addr(_ALICE_PRIVATE_KEY);

        vm.selectFork(vm.createFork("sepolia"));

        // Get the Permit2 contract
        _permit2 = IPermit2(
            address(0x000000000022D473030F116dDEE9F6B43aC78BA3)
        );

        // Deploy token and mint for alice
        _erc20 = new ERC20Example();

        // Deploy RISC Zero contracts
        (
            RiscZeroVerifierRouter router,
            ,
            RiscZeroGroth16Verifier verifier
        ) = new DeployRiscZeroContracts().run();

        // Deploy the protocol adapter
        _pa = new ProtocolAdapter(
            router,
            verifier.SELECTOR(),
            _EMERGENCY_COMMITTEE
        );

        // Deploy the ERC20 forwarder
        _fwd = new ERC20Forwarder({
            protocolAdapter: address(_pa),
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            calldataCarrierLogicRef: 0x81f8104fe367f5018a4bb0b259531be9ab35d3f1d51dea46c204bee154d5ee9e
        });
    }

    function test_execute_mint_transfer_burn() public {
        _erc20.mint({to: _alice, value: _TRANSFER_AMOUNT});
        vm.prank(_alice);
        _erc20.approve(address(_permit2), type(uint256).max);

        uint256 aliceBalanceBefore = _erc20.balanceOf(_alice);
        uint256 fwdBalanceBefore = _erc20.balanceOf(address(_fwd));

        // Mint
        {
            Transaction memory mintTx = vm.parseTransaction(
                "/test/examples/transactions/mint.bin"
            );
            ProtocolAdapter(_pa).execute(mintTx);

            assertEq(
                _erc20.balanceOf(_alice),
                aliceBalanceBefore - _TRANSFER_AMOUNT
            );
            assertEq(
                _erc20.balanceOf(address(_fwd)),
                fwdBalanceBefore + _TRANSFER_AMOUNT
            );
        }

        // Transfer
        {
            Transaction memory transferTx = vm.parseTransaction(
                "/test/examples/transactions/transfer.bin"
            );
            ProtocolAdapter(_pa).execute(transferTx);

            assertEq(
                _erc20.balanceOf(_alice),
                aliceBalanceBefore - _TRANSFER_AMOUNT
            );
            assertEq(
                _erc20.balanceOf(address(_fwd)),
                fwdBalanceBefore + _TRANSFER_AMOUNT
            );
        }

        // Burn
        {
            Transaction memory burnTx = vm.parseTransaction(
                "/test/examples/transactions/burn.bin"
            );
            ProtocolAdapter(_pa).execute(burnTx);

            assertEq(_erc20.balanceOf(_alice), aliceBalanceBefore);
            assertEq(_erc20.balanceOf(address(_fwd)), fwdBalanceBefore);
        }
    }
}
