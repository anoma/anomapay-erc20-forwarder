// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TransactionExample} from "@anoma-evm-pa-testing/examples/transactions/Transaction.e.sol";
import {DeployRiscZeroContracts} from "@anoma-evm-pa-testing/script/DeployRiscZeroContracts.s.sol";

import {ProtocolAdapter} from "@anoma-evm-pa/ProtocolAdapter.sol";
import {CommitmentTree} from "@anoma-evm-pa/state/CommitmentTree.sol";
import {NullifierSet} from "@anoma-evm-pa/state/NullifierSet.sol";
import {Transaction} from "@anoma-evm-pa/Types.sol";

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin-contracts/utils/types/Time.sol";
import {ISignatureTransfer} from "@permit2/src/interfaces/IPermit2.sol";
import {RiscZeroGroth16Verifier} from "@risc0-ethereum/groth16/RiscZeroGroth16Verifier.sol";
import {RiscZeroVerifierRouter} from "@risc0-ethereum/RiscZeroVerifierRouter.sol";
import {Vm} from "forge-std/Test.sol";

import {ForwarderBase} from "../src/bases/ForwarderBase.sol";
import {ERC20ForwarderV2} from "../src/drafts/ERC20ForwarderV2.sol";
import {ERC20ForwarderV3} from "../src/drafts/ERC20ForwarderV3.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ERC20ForwarderPermit2} from "../src/ERC20ForwarderPermit2.sol";
import {ERC20Example} from "../test/examples/ERC20.e.sol";
import {ERC20ForwarderTest} from "./ERC20Forwarder.t.sol";
import {Permit2Signature} from "./libs/Permit2Signature.sol";

contract ERC20ForwarderV3Test is ERC20ForwarderTest {
    using ERC20ForwarderPermit2 for ERC20ForwarderPermit2.Witness;
    using Permit2Signature for Vm;

    bytes32 internal constant _NULLIFIER = bytes32(type(uint256).max);

    bytes32 internal _logicRefV1;
    bytes32 internal _logicRefV2;
    bytes32 internal _logicRefV3;

    ProtocolAdapter internal _paV1;
    ProtocolAdapter internal _paV2;
    ProtocolAdapter internal _paV3;

    ERC20Forwarder internal _fwdV1;
    ERC20ForwarderV2 internal _fwdV2;
    ERC20ForwarderV3 internal _fwdV3;

    bytes internal _defaultMigrateV1Input;
    bytes internal _defaultMigrateV2Input;

    function setUp() public override {
        _alicePrivateKey = 0xc522337787f3037e9d0dcba4dc4c0e3d4eb7b1c65598d51c425574e8ce64d140;
        _alice = vm.addr(_alicePrivateKey);

        // Deploy token and mint for alice
        _erc20 = new ERC20Example();

        // Get the Permit2 contract
        _permit2 = _permit2Contract();

        // Deploy RISC Zero contracts
        (RiscZeroVerifierRouter router,, RiscZeroGroth16Verifier verifier) =
            new DeployRiscZeroContracts().run({admin: msg.sender, guardian: msg.sender});

        // Deploy the protocol adapter
        _paV1 = new ProtocolAdapter(router, verifier.SELECTOR(), _EMERGENCY_COMMITTEE);
        _logicRefV1 = bytes32(uint256(1));

        _paV2 = new ProtocolAdapter(router, verifier.SELECTOR(), _EMERGENCY_COMMITTEE);
        _logicRefV2 = bytes32(uint256(2));

        _paV3 = new ProtocolAdapter(router, verifier.SELECTOR(), _EMERGENCY_COMMITTEE);
        _logicRefV3 = bytes32(uint256(3));

        _pa = _paV3;
        _logicRef = _logicRefV3;

        _fwdV1 = new ERC20Forwarder({
            protocolAdapter: address(_paV1), emergencyCommittee: _EMERGENCY_COMMITTEE, logicRef: _logicRefV1
        });

        _fwdV2 = new ERC20ForwarderV2({
            protocolAdapterV2: address(_paV2),
            logicRefV2: _logicRefV2,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: _fwdV1
        });

        _fwdV3 = new ERC20ForwarderV3({
            protocolAdapterV3: address(_paV3),
            logicRefV3: _logicRefV3,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: _fwdV1,
            erc20ForwarderV2: _fwdV2
        });

        _fwd = _fwdV3;

        _defaultPermit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(_erc20), amount: _TRANSFER_AMOUNT}),
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

        _defaultWrapInput = abi.encode( /*       callType */
            ERC20ForwarderV2.CallTypeV2.Wrap,
            /*           from */
            _alice,
            /*         permit */
            _defaultPermit,
            /* actionTreeRoot */
            _ACTION_TREE_ROOT,
            /*      signature */
            _defaultPermitSig
        );

        _defaultUnwrapInput = abi.encode( /* callType */
            ERC20ForwarderV2.CallTypeV2.Unwrap,
            /*    token */
            address(_erc20),
            /*       to */
            _alice,
            /*   amount */
            _TRANSFER_AMOUNT
        );

        _defaultMigrateV1Input = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* nullifier */
            _NULLIFIER,
            /*      root */
            CommitmentTree(_paV1).latestCommitmentTreeRoot(),
            /*  logicRef */
            _logicRefV1,
            /* forwarder */
            address(_fwdV1)
        );

        _defaultMigrateV2Input = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* nullifier */
            _NULLIFIER,
            /*      root */
            CommitmentTree(_paV2).latestCommitmentTreeRoot(),
            /*  logicRef */
            _logicRefV2,
            /* forwarder */
            address(_fwdV2)
        );
    }

    function test_constructor_reverts_if_the_erc20_forwarder_v2_address_is_zero() public {
        vm.expectRevert(ForwarderBase.ZeroNotAllowed.selector, address(_fwdV3));
        new ERC20ForwarderV3({
            protocolAdapterV3: address(_paV3),
            logicRefV3: _logicRefV3,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: _fwdV1,
            erc20ForwarderV2: ERC20ForwarderV2(address(0))
        });
    }

    function test_migrateV1_reverts_if_the_v1_resource_to_migrate_has_already_been_consumed() public {
        Transaction memory txn = TransactionExample.transaction();
        bytes32 nullifier = txn.actions[0].complianceVerifierInputs[0].instance.consumed.nullifier;

        assertEq(_paV1.isNullifierContained(nullifier), false);
        _paV1.execute(txn);
        assertEq(_paV1.isNullifierContained(nullifier), true);

        _emergencyStopPaV1AndSetEmergencyCaller();
        _emergencyStopPaV2AndSetEmergencyCaller();

        bytes memory input =
            abi.encode(ERC20ForwarderV3.CallTypeV3.MigrateV1, address(0), uint128(0), nullifier, "", "", "");

        vm.prank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV2.ResourceAlreadyConsumed.selector, nullifier), address(_fwdV2)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: input});
    }

    function test_migrateV2_reverts_if_the_v2_resource_to_migrate_has_already_been_consumed() public {
        Transaction memory txn = TransactionExample.transaction();
        bytes32 nullifier = txn.actions[0].complianceVerifierInputs[0].instance.consumed.nullifier;

        assertEq(_paV2.isNullifierContained(nullifier), false);
        _paV2.execute(txn);
        assertEq(_paV2.isNullifierContained(nullifier), true);

        _emergencyStopPaV2AndSetEmergencyCaller();

        bytes memory input =
            abi.encode(ERC20ForwarderV3.CallTypeV3.MigrateV2, address(0), uint128(0), nullifier, "", "", "");

        vm.prank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV2.ResourceAlreadyConsumed.selector, nullifier), address(_fwdV3)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: input});
    }

    function test_migrateV1_reverts_if_the_v1_resource_has_already_been_migrated() public {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        _emergencyStopPaV1AndSetEmergencyCaller();
        _emergencyStopPaV2AndSetEmergencyCaller();

        vm.startPrank(address(_paV3));
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV1Input});

        vm.expectRevert(abi.encodeWithSelector(NullifierSet.PreExistingNullifier.selector, _NULLIFIER), address(_fwdV2));
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV1Input});
    }

    function test_migrateV2_reverts_if_the_v2_resource_has_already_been_migrated() public {
        // Fund the forwarder v2.
        _erc20.mint({to: address(_fwdV2), value: _TRANSFER_AMOUNT});

        _emergencyStopPaV2AndSetEmergencyCaller();

        vm.startPrank(address(_paV3));
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV2Input});

        vm.expectRevert(abi.encodeWithSelector(NullifierSet.PreExistingNullifier.selector, _NULLIFIER), address(_fwdV3));
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV2Input});
    }

    function test_migrateV1_reverts_if_the_commitment_tree_root_v1_is_incorrect() public virtual {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        _emergencyStopPaV1AndSetEmergencyCaller();
        _emergencyStopPaV2AndSetEmergencyCaller();

        bytes32 expectedCommitmentTreeRootV1 = CommitmentTree(_paV1).latestCommitmentTreeRoot();
        bytes32 incorrectCommitmentTreeRootV1 = bytes32(type(uint256).max / 2);

        bytes memory migrateV1InputWithIncorrectCommitmentTreeRootV1 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* nullifier */
            _NULLIFIER,
            /*      root */
            incorrectCommitmentTreeRootV1,
            /*  logicRef */
            _logicRefV1,
            /* forwarder */
            address(_fwdV1)
        );

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20ForwarderV2.InvalidMigrationCommitmentTreeRootV1.selector,
                expectedCommitmentTreeRootV1,
                incorrectCommitmentTreeRootV1
            ),
            address(_fwdV2)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: migrateV1InputWithIncorrectCommitmentTreeRootV1});
    }

    function test_migrateV2_reverts_if_the_commitment_tree_root_v2_is_incorrect() public virtual {
        // Fund the forwarder v2.
        _erc20.mint({to: address(_fwdV2), value: _TRANSFER_AMOUNT});

        _emergencyStopPaV2AndSetEmergencyCaller();

        bytes32 expectedCommitmentTreeRootV2 = CommitmentTree(_paV2).latestCommitmentTreeRoot();
        bytes32 incorrectCommitmentTreeRootV2 = bytes32(type(uint256).max / 2);

        bytes memory migrateV2InputWithIncorrectCommitmentTreeRootV2 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* nullifier */
            _NULLIFIER,
            /*      root */
            incorrectCommitmentTreeRootV2,
            /*  logicRef */
            _logicRefV1,
            /* forwarder */
            address(_fwdV2)
        );

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20ForwarderV3.InvalidMigrationCommitmentTreeRootV2.selector,
                expectedCommitmentTreeRootV2,
                incorrectCommitmentTreeRootV2
            ),
            address(_fwdV3)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: migrateV2InputWithIncorrectCommitmentTreeRootV2});
    }

    function test_migrateV1_reverts_if_the_logic_ref_v1_is_incorrect() public virtual {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        _emergencyStopPaV1AndSetEmergencyCaller();
        _emergencyStopPaV2AndSetEmergencyCaller();

        bytes32 incorrectLogicRefV1 = bytes32(type(uint256).max / 2);

        bytes memory migrateV1InputWithIncorrectLogicRefV1 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* nullifier */
            _NULLIFIER,
            /*      root */
            CommitmentTree(_paV1).latestCommitmentTreeRoot(),
            /*  logicRef */
            incorrectLogicRefV1,
            /* forwarder */
            address(_fwdV1)
        );

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20ForwarderV2.InvalidMigrationLogicRefV1.selector, _logicRefV1, incorrectLogicRefV1
            ),
            address(_fwdV2)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: migrateV1InputWithIncorrectLogicRefV1});
    }

    function test_migrateV2_reverts_if_the_logic_ref_v2_is_incorrect() public virtual {
        // Fund the forwarder v2.
        _erc20.mint({to: address(_fwdV2), value: _TRANSFER_AMOUNT});

        _emergencyStopPaV2AndSetEmergencyCaller();

        bytes32 incorrectLogicRefV2 = bytes32(type(uint256).max / 2);

        bytes memory migrateV2InputWithIncorrectLogicRefV2 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* nullifier */
            _NULLIFIER,
            /*      root */
            CommitmentTree(_paV2).latestCommitmentTreeRoot(),
            /*  logicRef */
            incorrectLogicRefV2,
            /* forwarder */
            address(_fwdV2)
        );

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20ForwarderV3.InvalidMigrationLogicRefV2.selector, _logicRefV2, incorrectLogicRefV2
            ),
            address(_fwdV3)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: migrateV2InputWithIncorrectLogicRefV2});
    }

    function test_migrateV1_reverts_if_the_forwarder_v1_is_incorrect() public virtual {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        _emergencyStopPaV1AndSetEmergencyCaller();
        _emergencyStopPaV2AndSetEmergencyCaller();

        address incorrectForwarderV1 = address(type(uint160).max);

        bytes memory migrateV1InputWithIncorrectLabelRefV1 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* nullifier */
            _NULLIFIER,
            /*      root */
            CommitmentTree(_paV1).latestCommitmentTreeRoot(),
            /*  logicRef */
            _logicRefV1,
            /* forwarder */
            incorrectForwarderV1
        );

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV2.InvalidForwarderV1.selector, address(_fwdV1), incorrectForwarderV1),
            address(_fwdV2)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: migrateV1InputWithIncorrectLabelRefV1});
    }

    function test_migrateV2_reverts_if_the_forwarder_v2_is_incorrect() public virtual {
        // Fund the forwarder v2.
        _erc20.mint({to: address(_fwdV2), value: _TRANSFER_AMOUNT});

        _emergencyStopPaV2AndSetEmergencyCaller();

        address incorrectForwarderV2 = address(type(uint160).max / 2);

        bytes memory migrateV2InputWithIncorrectLabelRefV2 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* nullifier */
            _NULLIFIER,
            /*      root */
            CommitmentTree(_paV2).latestCommitmentTreeRoot(),
            /*  logicRef */
            _logicRefV2,
            /* forwarder */
            incorrectForwarderV2
        );

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV3.InvalidForwarderV2.selector, address(_fwdV2), incorrectForwarderV2),
            address(_fwdV3)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: migrateV2InputWithIncorrectLabelRefV2});
    }

    function test_migrateV1_transfers_funds_from_forwarder_V1() public {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        assertEq(_erc20.balanceOf(address(_fwdV1)), _TRANSFER_AMOUNT);
        assertEq(_erc20.balanceOf(address(_fwdV2)), 0);
        assertEq(_erc20.balanceOf(address(_fwdV3)), 0);

        _emergencyStopPaV1AndSetEmergencyCaller();
        _emergencyStopPaV2AndSetEmergencyCaller();

        vm.prank(address(_paV3));

        vm.expectEmit(address(_fwdV3));
        emit ERC20Forwarder.Wrapped({token: address(_erc20), from: address(_fwdV2), amount: _TRANSFER_AMOUNT});

        vm.expectEmit(address(_fwdV2));
        emit ERC20Forwarder.Wrapped({token: address(_erc20), from: address(_fwdV1), amount: _TRANSFER_AMOUNT});

        vm.expectEmit(address(_fwdV1));
        emit ERC20Forwarder.Unwrapped({token: address(_erc20), to: address(_fwdV2), amount: _TRANSFER_AMOUNT});

        vm.expectEmit(address(_erc20));
        emit IERC20.Transfer({from: address(_fwdV1), to: address(_fwdV2), value: _TRANSFER_AMOUNT});

        vm.expectEmit(address(_fwdV2));
        emit ERC20Forwarder.Unwrapped({token: address(_erc20), to: address(_fwdV3), amount: _TRANSFER_AMOUNT});

        vm.expectEmit(address(_erc20));
        emit IERC20.Transfer({from: address(_fwdV2), to: address(_fwdV3), value: _TRANSFER_AMOUNT});

        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV1Input});

        assertEq(_erc20.balanceOf(address(_fwdV1)), 0);
        assertEq(_erc20.balanceOf(address(_fwdV2)), 0);
        assertEq(_erc20.balanceOf(address(_fwdV3)), _TRANSFER_AMOUNT);
    }

    function test_migrateV2_transfers_funds_from_forwarder_V2() public {
        _erc20.mint({to: address(_fwdV2), value: _TRANSFER_AMOUNT});

        assertEq(_erc20.balanceOf(address(_fwdV2)), _TRANSFER_AMOUNT);
        assertEq(_erc20.balanceOf(address(_fwdV3)), 0);

        _emergencyStopPaV2AndSetEmergencyCaller();

        vm.prank(address(_paV3));

        vm.expectEmit(address(_fwdV3));
        emit ERC20Forwarder.Wrapped({token: address(_erc20), from: address(_fwdV2), amount: _TRANSFER_AMOUNT});

        vm.expectEmit(address(_fwdV2));
        emit ERC20Forwarder.Unwrapped({token: address(_erc20), to: address(_fwdV3), amount: _TRANSFER_AMOUNT});

        vm.expectEmit(address(_erc20));
        emit IERC20.Transfer({from: address(_fwdV2), to: address(_fwdV3), value: _TRANSFER_AMOUNT});

        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV2Input});

        assertEq(_erc20.balanceOf(address(_fwdV2)), 0);
        assertEq(_erc20.balanceOf(address(_fwdV3)), _TRANSFER_AMOUNT);
    }

    function _emergencyStopPaV1AndSetEmergencyCaller() internal {
        // Stop the PA.
        vm.prank(_paV1.owner());
        _paV1.emergencyStop();

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        _fwdV1.setEmergencyCaller(address(_fwdV2));
    }

    function _emergencyStopPaV2AndSetEmergencyCaller() internal {
        // Stop the PA.
        vm.prank(_paV2.owner());
        _paV2.emergencyStop();

        // Set the ERC20ForwarderV3 as the emergency caller of ERC20ForwarderV2.
        vm.prank(_EMERGENCY_COMMITTEE);
        _fwdV2.setEmergencyCaller(address(_fwdV3));
    }
}
