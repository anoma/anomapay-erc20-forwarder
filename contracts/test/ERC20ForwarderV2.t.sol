// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TransactionExample} from "@anoma-evm-pa-testing/examples/transactions/Transaction.e.sol";
import {DeployRiscZeroContracts} from "@anoma-evm-pa-testing/script/DeployRiscZeroContracts.s.sol";

import {ProtocolAdapter} from "@anoma-evm-pa/ProtocolAdapter.sol";
import {NullifierSet} from "@anoma-evm-pa/state/NullifierSet.sol";
import {Transaction} from "@anoma-evm-pa/Types.sol";

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin-contracts/utils/types/Time.sol";
import {ISignatureTransfer} from "@permit2/src/interfaces/IPermit2.sol";
import {RiscZeroGroth16Verifier} from "@risc0-ethereum/groth16/RiscZeroGroth16Verifier.sol";
import {RiscZeroVerifierRouter} from "@risc0-ethereum/RiscZeroVerifierRouter.sol";
import {Vm} from "forge-std/Test.sol";

import {ProtocolAdapterSpecificForwarderBase} from "../src/bases/ProtocolAdapterSpecificForwarderBase.sol";
import {ERC20ForwarderV2} from "../src/drafts/ERC20ForwarderV2.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ERC20ForwarderPermit2} from "../src/ERC20ForwarderPermit2.sol";
import {ERC20Example} from "../test/examples/ERC20.e.sol";
import {ERC20ForwarderTest} from "./ERC20Forwarder.t.sol";
import {Permit2Signature} from "./libs/Permit2Signature.sol";

contract ERC20ForwarderV2Test is ERC20ForwarderTest {
    using ERC20ForwarderPermit2 for ERC20ForwarderPermit2.Witness;
    using Permit2Signature for Vm;

    bytes32 internal constant _NULLIFIER = bytes32(type(uint256).max);

    ProtocolAdapter internal _paV1;
    ProtocolAdapter internal _paV2;

    ERC20Forwarder internal _fwdV1;
    ERC20ForwarderV2 internal _fwdV2;

    bytes internal _defaultMigrateInput;

    function setUp() public override {
        _alicePrivateKey = 0xc522337787f3037e9d0dcba4dc4c0e3d4eb7b1c65598d51c425574e8ce64d140;
        _alice = vm.addr(_alicePrivateKey);

        // Deploy token and mint for alice
        _erc20 = new ERC20Example();

        // Get the Permit2 contract
        _permit2 = _permit2Contract();

        // Deploy RISC Zero contracts
        (
            RiscZeroVerifierRouter router,
            ,
            RiscZeroGroth16Verifier verifier
        ) = new DeployRiscZeroContracts().run({
                admin: msg.sender,
                guardian: msg.sender
            });

        // Deploy the protocol adapter
        _paV1 = new ProtocolAdapter(
            router,
            verifier.SELECTOR(),
            _EMERGENCY_COMMITTEE
        );

        _paV2 = new ProtocolAdapter(
            router,
            verifier.SELECTOR(),
            _EMERGENCY_COMMITTEE
        );

        _fwdV1 = new ERC20Forwarder({
            protocolAdapter: address(_paV1),
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            calldataCarrierLogicRef: _CALLDATA_CARRIER_LOGIC_REF
        });
        _pa = _paV2;

        // Deploy the ERC20 forwarder
        _fwdV2 = new ERC20ForwarderV2({
            protocolAdapter: address(_paV2),
            calldataCarrierLogicRef: _CALLDATA_CARRIER_LOGIC_REF,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            protocolAdapterV1: address(_paV1),
            erc20ForwarderV1: address(_fwdV1)
        });
        _fwd = _fwdV2;

        _defaultPermit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: address(_erc20),
                amount: _TRANSFER_AMOUNT
            }),
            nonce: 123,
            deadline: Time.timestamp() + 5 minutes
        });

        _defaultPermitSig = vm.permitWitnessTransferFromSignature({
            domainSeparator: _permit2.DOMAIN_SEPARATOR(),
            permit: _defaultPermit,
            privateKey: _alicePrivateKey,
            spender: address(_fwd),
            witness: ERC20ForwarderPermit2.Witness(_ACTION_TREE_ROOT).hash()
        });

        _defaultWrapInput = abi.encode(
            /*       callType */ ERC20ForwarderV2.CallTypeV2.Wrap,
            /*           from */ _alice,
            /*         permit */ _defaultPermit,
            /* actionTreeRoot */ _ACTION_TREE_ROOT,
            /*      signature */ _defaultPermitSig
        );

        _defaultUnwrapInput = abi.encode(
            /* callType */ ERC20ForwarderV2.CallTypeV2.Unwrap,
            /*    token */ address(_erc20),
            /*       to */ _alice,
            /*   amount */ _TRANSFER_AMOUNT
        );

        _defaultMigrateInput = abi.encode(
            /*  callType */ ERC20ForwarderV2.CallTypeV2.Migrate,
            /*     token */ address(_erc20),
            /*    amount */ _TRANSFER_AMOUNT,
            /* nullifier */ _NULLIFIER
        );
    }

    function test_constructor_reverts_if_the_protocol_adapter_v1_address_is_zero()
        public
    {
        vm.expectRevert(
            ProtocolAdapterSpecificForwarderBase.ZeroNotAllowed.selector,
            address(_fwdV2)
        );
        new ERC20ForwarderV2({
            protocolAdapter: address(_paV2),
            calldataCarrierLogicRef: _CALLDATA_CARRIER_LOGIC_REF,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            protocolAdapterV1: address(0),
            erc20ForwarderV1: address(_fwdV1)
        });
    }

    function test_constructor_reverts_if_the_erc20_forwarder_v1_address_is_zero()
        public
    {
        vm.expectRevert(
            ProtocolAdapterSpecificForwarderBase.ZeroNotAllowed.selector,
            address(_fwdV2)
        );
        new ERC20ForwarderV2({
            protocolAdapter: address(_paV2),
            calldataCarrierLogicRef: _CALLDATA_CARRIER_LOGIC_REF,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            protocolAdapterV1: address(_pa),
            erc20ForwarderV1: address(0)
        });
    }

    function test_migrate_reverts_if_the_resource_to_migrate_has_already_been_consumed()
        public
    {
        Transaction memory txn = TransactionExample.transaction();
        bytes32 nullifier = txn
            .actions[0]
            .complianceVerifierInputs[0]
            .instance
            .consumed
            .nullifier;

        assertEq(_paV1.isNullifierContained(nullifier), false);
        _paV1.execute(txn);
        assertEq(_paV1.isNullifierContained(nullifier), true);

        // Stop the PA.
        vm.prank(_paV1.owner());
        _paV1.emergencyStop();

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        _fwdV1.setEmergencyCaller(address(_fwdV2));

        bytes memory input = abi.encode(
            ERC20ForwarderV2.CallTypeV2.Migrate,
            address(0),
            uint128(0),
            nullifier
        );

        vm.prank(address(_paV2));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20ForwarderV2.ResourceAlreadyConsumed.selector,
                nullifier
            ),
            address(_fwdV2)
        );
        _fwdV2.forwardCall({
            logicRef: _CALLDATA_CARRIER_LOGIC_REF,
            input: input
        });
    }

    function test_migrate_reverts_if_the_resource_has_already_been_migrated()
        public
    {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        // Stop the PA.
        vm.prank(_paV1.owner());
        _paV1.emergencyStop();

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        _fwdV1.setEmergencyCaller(address(_fwdV2));

        vm.startPrank(address(_paV2));
        _fwdV2.forwardCall({
            logicRef: _CALLDATA_CARRIER_LOGIC_REF,
            input: _defaultMigrateInput
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                NullifierSet.PreExistingNullifier.selector,
                _NULLIFIER
            ),
            address(_fwdV2)
        );
        _fwdV2.forwardCall({
            logicRef: _CALLDATA_CARRIER_LOGIC_REF,
            input: _defaultMigrateInput
        });
    }

    function test_migrate_transfers_funds_from_V1_to_V2_forwarder() public {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        assertEq(_erc20.balanceOf(address(_fwdV1)), _TRANSFER_AMOUNT);
        assertEq(_erc20.balanceOf(address(_fwdV2)), 0);

        // Stop the PA.
        vm.prank(_paV1.owner());
        _paV1.emergencyStop();

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        _fwdV1.setEmergencyCaller(address(_fwdV2));

        vm.prank(address(_paV2));

        vm.expectEmit(address(_fwdV2));
        emit ERC20Forwarder.Wrapped({
            token: address(_erc20),
            from: address(_fwdV1),
            amount: _TRANSFER_AMOUNT
        });

        vm.expectEmit(address(_fwdV1));
        emit ERC20Forwarder.Unwrapped({
            token: address(_erc20),
            to: address(_fwdV2),
            amount: _TRANSFER_AMOUNT
        });

        vm.expectEmit(address(_erc20));
        emit IERC20.Transfer({
            from: address(_fwdV1),
            to: address(_fwdV2),
            value: _TRANSFER_AMOUNT
        });

        _fwdV2.forwardCall({
            logicRef: _CALLDATA_CARRIER_LOGIC_REF,
            input: _defaultMigrateInput
        });

        assertEq(_erc20.balanceOf(address(_fwdV1)), 0);
        assertEq(_erc20.balanceOf(address(_fwdV2)), _TRANSFER_AMOUNT);
    }
}
