// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts-5.6.1/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin-contracts-5.6.1/utils/types/Time.sol";
import {IForwarder} from "anoma-pa-evm-1.2.0-rc.0/src/interfaces/IForwarder.sol";
import {ProtocolAdapter} from "anoma-pa-evm-1.2.0-rc.0/src/ProtocolAdapter.sol";
import {DeployRiscZeroContracts} from "anoma-risc0-deployments-1.0.0-rc.1/script/DeployRiscZeroContracts.s.sol";
import {Test, Vm} from "forge-std-1.15.0/src/Test.sol";
import {RiscZeroGroth16Verifier} from "risc0-risc0-ethereum-3.0.1/contracts/src/groth16/RiscZeroGroth16Verifier.sol";
import {RiscZeroVerifierRouter} from "risc0-risc0-ethereum-3.0.1/contracts/src/RiscZeroVerifierRouter.sol";
import {WETH} from "solady-0.1.26/src/tokens/WETH.sol";
import {
    IAllowanceTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IAllowanceTransfer.sol";
import {
    IPermit2,
    ISignatureTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IPermit2.sol";

import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ERC20ForwarderPermit2} from "../src/ERC20ForwarderPermit2.sol";
import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";
import {INativeTokenReceiver} from "../src/interfaces/INativeTokenReceiver.sol";

import {ERC20Example} from "./examples/ERC20.e.sol";
import {Permit2Signature} from "./libs/Permit2Signature.sol";
import {DeployPermit2} from "./script/DeployPermit2.s.sol";

contract GenericCallForwarderTest is Test {
    using ERC20ForwarderPermit2 for ERC20ForwarderPermit2.Witness;
    using Permit2Signature for Vm;

    address internal constant _EMERGENCY_COMMITTEE = address(uint160(1));
    uint128 internal constant _TRANSFER_AMOUNT = 1000;
    bytes internal constant _EXPECTED_OUTPUT = "";
    bytes32 internal constant _ACTION_TREE_ROOT = bytes32(uint256(0));

    bytes32 internal _erc20ResourceLogicRef;
    bytes32 internal _genericCallResourceLogicRef;

    address internal _alice;
    uint256 internal _alicePrivateKey;

    ProtocolAdapter internal _pa;
    IForwarder internal _erc20Fwd;
    IForwarder internal _genericCallFwd;

    IPermit2 internal _permit2;
    WETH internal _weth;

    ISignatureTransfer.PermitTransferFrom internal _defaultPermit;
    bytes32 internal _defaultPermitSigR;
    bytes32 internal _defaultPermitSigS;
    uint8 internal _defaultPermitSigV;
    bytes internal _defaultWrapInput;
    bytes internal _defaultUnwrapInput;

    function setUp() public virtual {
        _erc20ResourceLogicRef = bytes32(uint256(1));
        _genericCallResourceLogicRef = bytes32(uint256(2));

        _alicePrivateKey = 0xc522337787f3037e9d0dcba4dc4c0e3d4eb7b1c65598d51c425574e8ce64d140;
        _alice = vm.addr(_alicePrivateKey);

        _weth = new WETH();

        // Deploy the Permit2 contract
        _permit2 = new DeployPermit2().run();

        // Deploy RISC Zero contracts
        (RiscZeroVerifierRouter router,, RiscZeroGroth16Verifier verifier) =
            new DeployRiscZeroContracts().run({admin: msg.sender, guardian: msg.sender});

        // Deploy the protocol adapter
        _pa = new ProtocolAdapter(router, verifier.SELECTOR(), _EMERGENCY_COMMITTEE);

        // Deploy the ERC20 forwarder
        _erc20Fwd = new ERC20Forwarder({
            protocolAdapter: address(_pa), emergencyCommittee: _EMERGENCY_COMMITTEE, logicRef: _erc20ResourceLogicRef
        });
        _genericCallFwd =
            new GenericCallForwarder({protocolAdapter: address(_pa), logicRef: _genericCallResourceLogicRef});

        _defaultPermit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(_weth), amount: _TRANSFER_AMOUNT}),
            nonce: 123,
            deadline: Time.timestamp() + 5 minutes
        });

        (_defaultPermitSigR, _defaultPermitSigS, _defaultPermitSigV) = vm.permitWitnessTransferFromSignature({
            domainSeparator: _permit2.DOMAIN_SEPARATOR(),
            permit: _defaultPermit,
            privateKey: _alicePrivateKey,
            spender: address(_erc20Fwd),
            witness: ERC20ForwarderPermit2.Witness(_ACTION_TREE_ROOT).hash()
        });

        _defaultWrapInput = abi.encode(
            /*       callType */
            ERC20Forwarder.CallType.Wrap,
            /*          token */
            _defaultPermit.permitted.token,
            /*         amount */
            _defaultPermit.permitted.amount,
            /*      wrap data */
            ERC20Forwarder.WrapData({
                nonce: _defaultPermit.nonce,
                deadline: _defaultPermit.deadline,
                owner: _alice,
                actionTreeRoot: _ACTION_TREE_ROOT,
                r: _defaultPermitSigR,
                s: _defaultPermitSigS,
                v: _defaultPermitSigV
            })
        );

        _defaultUnwrapInput = abi.encode( /* callType */
            ERC20Forwarder.CallType.Unwrap,
            /*       token */
            address(_weth),
            /*      amount */
            _TRANSFER_AMOUNT,
            /* unwrap data */
            ERC20Forwarder.UnwrapData({receiver: address(_genericCallFwd)})
        );
    }

    function test_calls_allow_swapping_fund_on_a_dex() public {
        uint128 minAmountOut = _TRANSFER_AMOUNT / 2;
        ERC20Example tokenA = new ERC20Example();
        ERC20Example tokenB = new ERC20Example();
        MockDexRouter dexRouter = new MockDexRouter(address(_permit2));
        tokenB.mint(address(dexRouter), minAmountOut);

        // Fund ERC20Forwarder with tokenA
        tokenA.mint(address(_erc20Fwd), _TRANSFER_AMOUNT);

        assertEq(tokenA.balanceOf(address(_erc20Fwd)), _TRANSFER_AMOUNT);
        assertEq(tokenA.balanceOf(address(_genericCallFwd)), 0);
        assertEq(tokenB.balanceOf(address(_genericCallFwd)), 0);
        assertEq(tokenB.balanceOf(address(_erc20Fwd)), 0);

        // Unwrap tokenA from ERC20Forwarder into GenericCallForwarder
        {
            bytes memory unwrapInput = abi.encode(
                ERC20Forwarder.CallType.Unwrap,
                address(tokenA),
                _TRANSFER_AMOUNT,
                ERC20Forwarder.UnwrapData({receiver: address(_genericCallFwd)})
            );

            vm.prank(address(_pa));
            bytes memory output1 = _erc20Fwd.forwardCall({logicRef: _erc20ResourceLogicRef, input: unwrapInput});
            assertEq(keccak256(output1), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(tokenA.balanceOf(address(_erc20Fwd)), 0);
        assertEq(tokenA.balanceOf(address(_genericCallFwd)), _TRANSFER_AMOUNT);

        // Swap tokenA for tokenB via MockDexRouter and approve Permit2 to pull tokenB for the subsequent wrap
        {
            uint48 expiration = uint48(Time.timestamp() + 5 minutes);

            address[] memory path = new address[](2);
            path[0] = address(tokenA);
            path[1] = address(tokenB);

            GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](4);

            // 3a: Approve Permit2 to spend tokenA, then grant DEX router a Permit2 allowance to pull it
            calls[0] = GenericCallForwarder.Call({
                to: address(tokenA),
                value: 0,
                data: abi.encodeCall(IERC20.approve, (address(_permit2), _TRANSFER_AMOUNT))
            });
            calls[1] = GenericCallForwarder.Call({
                to: address(_permit2),
                value: 0,
                data: abi.encodeCall(
                    IAllowanceTransfer.approve,
                    (address(tokenA), address(dexRouter), uint160(_TRANSFER_AMOUNT), expiration)
                )
            });

            // 3b: Swap _TRANSFER_AMOUNT of tokenA for minAmountOut of tokenB
            calls[2] = GenericCallForwarder.Call({
                to: address(dexRouter),
                value: 0,
                data: abi.encodeCall(
                    MockDexRouter.swapExactTokensForTokens,
                    (_TRANSFER_AMOUNT, minAmountOut, path, address(_genericCallFwd), expiration)
                )
            });

            // 3c: Approve Permit2 to spend tokenB so ERC20Forwarder can wrap it via permitWitnessTransferFrom
            calls[3] = GenericCallForwarder.Call({
                to: address(tokenB), value: 0, data: abi.encodeCall(IERC20.approve, (address(_permit2), minAmountOut))
            });

            vm.prank(address(_pa));
            bytes memory output2 =
                _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
            assertEq(keccak256(output2), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(tokenA.balanceOf(address(_genericCallFwd)), 0);
        assertEq(tokenB.balanceOf(address(_genericCallFwd)), minAmountOut);
        assertEq(tokenB.balanceOf(address(_erc20Fwd)), 0);

        // Wrap tokenB from GenericCallForwarder into ERC20Forwarder.
        // GenericCallForwarder implements ERC-1271 and always returns the magic value, so any r, s, v bytes are valid.
        {
            bytes memory wrapTokenBInput = abi.encode(
                ERC20Forwarder.CallType.Wrap,
                address(tokenB),
                minAmountOut,
                ERC20Forwarder.WrapData({
                    nonce: 456,
                    deadline: Time.timestamp() + 5 minutes,
                    owner: address(_genericCallFwd),
                    actionTreeRoot: _ACTION_TREE_ROOT,
                    r: bytes32(0),
                    s: bytes32(0),
                    v: 27
                })
            );

            vm.prank(address(_pa));
            bytes memory output3 = _erc20Fwd.forwardCall({logicRef: _erc20ResourceLogicRef, input: wrapTokenBInput});
            assertEq(keccak256(output3), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(tokenB.balanceOf(address(_genericCallFwd)), 0);
        assertEq(tokenB.balanceOf(address(_erc20Fwd)), minAmountOut);
    }

    function test_calls_allow_to_unwrap_native_tokens() public {
        // Fund ERC20 Forwarder with WETH
        {
            vm.deal(address(_erc20Fwd), _TRANSFER_AMOUNT);
            vm.prank(address(_erc20Fwd));
            _weth.deposit{value: _TRANSFER_AMOUNT}();
        }

        assertEq(_weth.balanceOf(address(_erc20Fwd)), _TRANSFER_AMOUNT);
        assertEq(_weth.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_alice.balance, 0);

        // Mock ERC20Forwarder call (triggered by TokenTransfer resource)
        {
            // Unwrap WETH-R into the generic call forwarder
            vm.prank(address(_pa));
            bytes memory output1 = _erc20Fwd.forwardCall({logicRef: _erc20ResourceLogicRef, input: _defaultUnwrapInput});
            assertEq(keccak256(output1), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(_weth.balanceOf(address(_erc20Fwd)), 0);
        assertEq(_weth.balanceOf(address(_genericCallFwd)), _TRANSFER_AMOUNT);
        assertEq(_alice.balance, 0);

        // Mock GenericCallForwarder call (triggered by GenericCall resource)
        {
            GenericCallForwarder.Call[] memory genericCalls = new GenericCallForwarder.Call[](2);
            // Call 1: Unwrap WETH
            genericCalls[0] = GenericCallForwarder.Call({
                to: address(_weth), value: 0, data: abi.encodeCall(WETH.withdraw, uint256(_TRANSFER_AMOUNT))
            });
            // Call 2: Transfer ETH
            genericCalls[1] = GenericCallForwarder.Call({to: _alice, value: _TRANSFER_AMOUNT, data: ""});
            bytes memory _unwrapWethAndTransferEthInput = abi.encode(genericCalls);

            vm.prank(address(_pa));
            vm.expectEmit(address(_genericCallFwd));
            emit INativeTokenReceiver.NativeTokenReceived({sender: address(_weth), amount: _TRANSFER_AMOUNT});

            bytes memory output2 = _genericCallFwd.forwardCall({
                logicRef: _genericCallResourceLogicRef, input: _unwrapWethAndTransferEthInput
            });
            assertEq(keccak256(output2), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(_weth.balanceOf(address(_erc20Fwd)), 0);
        assertEq(_weth.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_alice.balance, _TRANSFER_AMOUNT);
    }
}

contract MockDexRouter {
    using SafeERC20 for IERC20;

    IAllowanceTransfer internal immutable _PERMIT2;

    constructor(address permit2) {
        _PERMIT2 = IAllowanceTransfer(permit2);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external returns (uint256 amountOut) {
        _PERMIT2.transferFrom(msg.sender, address(this), SafeCast.toUint160(amountIn), path[0]);
        amountOut = amountOutMin;
        IERC20(path[path.length - 1]).safeTransfer(to, amountOut);
    }
}
