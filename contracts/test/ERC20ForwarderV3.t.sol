// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.5.0/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin-contracts-5.5.0/utils/types/Time.sol";
import {ProtocolAdapter} from "anoma-pa-evm-1.0.0/src/ProtocolAdapter.sol";
import {CommitmentTree} from "anoma-pa-evm-1.0.0/src/state/CommitmentTree.sol";
import {NullifierSet} from "anoma-pa-evm-1.0.0/src/state/NullifierSet.sol";
import {Transaction} from "anoma-pa-evm-1.0.0/src/Types.sol";
import {DeployRiscZeroContracts} from "anoma-pa-evm-1.0.0/test/script/DeployRiscZeroContracts.s.sol";
import {Vm} from "forge-std-1.14.0/src/Test.sol";
import {RiscZeroGroth16Verifier} from "risc0-risc0-ethereum-3.0.1/contracts/src/groth16/RiscZeroGroth16Verifier.sol";
import {RiscZeroVerifierRouter} from "risc0-risc0-ethereum-3.0.1/contracts/src/RiscZeroVerifierRouter.sol";
import {
    ISignatureTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IPermit2.sol";

import {ForwarderBase} from "../src/bases/ForwarderBase.sol";
import {ERC20ForwarderV2} from "../src/drafts/ERC20ForwarderV2.sol";
import {ERC20ForwarderV3} from "../src/drafts/ERC20ForwarderV3.sol";
import {ERC20Forwarder} from "../src/ERC20Forwarder.sol";
import {ERC20ForwarderPermit2} from "../src/ERC20ForwarderPermit2.sol";
import {ERC20Example, ERC20WithFeeExample} from "../test/examples/ERC20.e.sol";
import {ERC20ForwarderTest} from "./ERC20Forwarder.t.sol";
import {TransactionExample} from "./examples/Transaction.e.sol";
import {Permit2Signature} from "./libs/Permit2Signature.sol";

contract ERC20ForwarderV3Test is ERC20ForwarderTest {
    using ERC20ForwarderPermit2 for ERC20ForwarderPermit2.Witness;
    using Permit2Signature for Vm;
    using TransactionExample for Vm;

    bytes32 internal constant _NULLIFIER = bytes32(type(uint256).max);

    bytes32 internal _logicRefV1;
    bytes32 internal _logicRefV2;
    bytes32 internal _logicRefV3;

    RiscZeroVerifierRouter internal _router;
    RiscZeroGroth16Verifier internal _verifier;

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
        _erc20FeeAdd = new ERC20WithFeeExample({isFeeAdded: true});
        _erc20FeeSub = new ERC20WithFeeExample({isFeeAdded: false});

        // Get the Permit2 contract
        _permit2 = _permit2Contract();

        // Deploy RISC Zero contracts
        (_router,, _verifier) = new DeployRiscZeroContracts().run({admin: msg.sender, guardian: msg.sender});

        _logicRefV1 = bytes32(uint256(1));
        _logicRefV2 = bytes32(uint256(2));
        _logicRefV3 = bytes32(uint256(3));
        _logicRef = _logicRefV3;

        (_paV1, _paV2, _paV3, _fwdV1) = _deployContracts();
        _pa = _paV3;

        // Stop the PAv1.
        vm.prank(_paV1.owner());
        _paV1.emergencyStop();

        _fwdV2 = new ERC20ForwarderV2({
            protocolAdapterV2: address(_paV2),
            logicRefV2: _logicRefV2,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: _fwdV1
        });

        // Stop the PAv2.
        vm.prank(_paV2.owner());
        _paV2.emergencyStop();

        _fwdV3 = new ERC20ForwarderV3({
            protocolAdapterV3: address(_paV3),
            logicRefV3: _logicRefV3,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: _fwdV1,
            erc20ForwarderV2: _fwdV2
        });
        _fwd = _fwdV3;

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        _fwdV1.setEmergencyCaller(address(_fwdV2));

        // Set the ERC20ForwarderV3 as the emergency caller of ERC20ForwarderV2.
        vm.prank(_EMERGENCY_COMMITTEE);
        _fwdV2.setEmergencyCaller(address(_fwdV3));

        _defaultPermit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(_erc20), amount: _TRANSFER_AMOUNT}),
            nonce: 123,
            deadline: Time.timestamp() + 5 minutes
        });

        (_defaultPermitSigR, _defaultPermitSigS, _defaultPermitSigV) = vm.permitWitnessTransferFromSignature({
            domainSeparator: _permit2.DOMAIN_SEPARATOR(),
            permit: _defaultPermit,
            privateKey: _alicePrivateKey,
            spender: address(_fwd),
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
            /*    token */
            address(_erc20),
            /*   amount */
            _TRANSFER_AMOUNT,
            /* unwrap data */
            ERC20Forwarder.UnwrapData({receiver: _alice})
        );

        _defaultMigrateV1Input = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*     token */
            address(_erc20),
            /*    amount */
            _TRANSFER_AMOUNT,
            /* migrate v1 data */
            ERC20ForwarderV2.MigrateV1Data({
                nullifier: _NULLIFIER,
                rootV1: CommitmentTree(_paV1).latestCommitmentTreeRoot(),
                logicRefV1: _logicRefV1,
                forwarderV1: address(_fwdV1)
            })
        );

        _defaultMigrateV2Input = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*           token */
            address(_erc20),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v2 data */
            ERC20ForwarderV3.MigrateV2Data({
                nullifier: _NULLIFIER,
                rootV2: CommitmentTree(_paV2).latestCommitmentTreeRoot(),
                logicRefV2: _logicRefV2,
                forwarderV2: address(_fwdV2)
            })
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

    function test_constructor_reverts_if_the_protocol_adapter_v2_has_not_been_stopped() public {
        (ProtocolAdapter paV1, ProtocolAdapter paV2, ProtocolAdapter paV3, ERC20Forwarder fwdV1) = _deployContracts();

        // Stop the PAv1.
        vm.prank(paV1.owner());
        paV1.emergencyStop();

        ERC20ForwarderV2 fwdV2 = new ERC20ForwarderV2({
            protocolAdapterV2: address(paV2),
            logicRefV2: _logicRefV2,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: fwdV1
        });

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        fwdV1.setEmergencyCaller(address(fwdV2));

        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV3.UnstoppedProtocolAdapterV2.selector, address(paV2)), address(fwdV2)
        );
        new ERC20ForwarderV3({
            protocolAdapterV3: address(paV3),
            logicRefV3: _logicRefV3,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: fwdV1,
            erc20ForwarderV2: fwdV2
        });
    }

    function test_migrateV1_reverts_if_the_v1_resource_to_migrate_has_already_been_consumed() public {
        (ProtocolAdapter paV1, ProtocolAdapter paV2, ProtocolAdapter paV3, ERC20Forwarder fwdV1) = _deployContracts();

        Transaction memory txn = vm.exampleTransaction();
        bytes32 nullifier = txn.actions[0].complianceVerifierInputs[0].instance.consumed.nullifier;

        assertEq(paV1.isNullifierContained(nullifier), false);
        paV1.execute(txn);
        assertEq(paV1.isNullifierContained(nullifier), true);

        // Stop the PAv1.
        vm.prank(paV1.owner());
        paV1.emergencyStop();

        // Stop the PAv2.
        vm.prank(paV2.owner());
        paV2.emergencyStop();

        ERC20ForwarderV2 fwdV2 = new ERC20ForwarderV2({
            protocolAdapterV2: address(paV2),
            logicRefV2: _logicRefV2,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: fwdV1
        });

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        fwdV1.setEmergencyCaller(address(fwdV2));

        ERC20ForwarderV3 fwdV3 = new ERC20ForwarderV3({
            protocolAdapterV3: address(paV3),
            logicRefV3: _logicRefV3,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: fwdV1,
            erc20ForwarderV2: fwdV2
        });

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        fwdV2.setEmergencyCaller(address(fwdV3));

        bytes memory input = abi.encode(
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            address(_erc20),
            uint128(0),
            nullifier,
            bytes32(0),
            bytes32(0),
            address(0)
        );

        vm.prank(address(paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV2.ResourceAlreadyConsumed.selector, nullifier), address(fwdV2)
        );
        fwdV3.forwardCall({logicRef: _logicRefV3, input: input});
    }

    function test_migrateV2_reverts_if_the_v2_resource_to_migrate_has_already_been_consumed() public {
        (ProtocolAdapter paV1, ProtocolAdapter paV2, ProtocolAdapter paV3, ERC20Forwarder fwdV1) = _deployContracts();

        // Stop the PAv1.
        vm.prank(paV1.owner());
        paV1.emergencyStop();

        ERC20ForwarderV2 fwdV2 = new ERC20ForwarderV2({
            protocolAdapterV2: address(paV2),
            logicRefV2: _logicRefV2,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: fwdV1
        });

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        fwdV1.setEmergencyCaller(address(fwdV2));

        Transaction memory txn = vm.exampleTransaction();
        bytes32 nullifier = txn.actions[0].complianceVerifierInputs[0].instance.consumed.nullifier;

        assertEq(paV2.isNullifierContained(nullifier), false);
        paV2.execute(txn);
        assertEq(paV2.isNullifierContained(nullifier), true);

        // Stop the PAv2.
        vm.prank(paV2.owner());
        paV2.emergencyStop();

        ERC20ForwarderV3 fwdV3 = new ERC20ForwarderV3({
            protocolAdapterV3: address(paV3),
            logicRefV3: _logicRefV3,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            erc20ForwarderV1: fwdV1,
            erc20ForwarderV2: fwdV2
        });

        // Set the ERC20ForwarderV2 as the emergency caller of ERC20ForwarderV1.
        vm.prank(_EMERGENCY_COMMITTEE);
        fwdV2.setEmergencyCaller(address(fwdV3));

        bytes memory input = abi.encode(
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            address(_erc20),
            uint128(0),
            nullifier,
            bytes32(0),
            bytes32(0),
            address(0)
        );

        vm.prank(address(paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV2.ResourceAlreadyConsumed.selector, nullifier), address(fwdV3)
        );
        fwdV3.forwardCall({logicRef: _logicRefV3, input: input});
    }

    function test_migrateV1_reverts_if_the_v1_resource_has_already_been_migrated() public {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        vm.startPrank(address(_paV3));
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV1Input});

        vm.expectRevert(abi.encodeWithSelector(NullifierSet.PreExistingNullifier.selector, _NULLIFIER), address(_fwdV2));
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV1Input});
    }

    function test_migrateV2_reverts_if_the_v2_resource_has_already_been_migrated() public {
        // Fund the forwarder v2.
        _erc20.mint({to: address(_fwdV2), value: _TRANSFER_AMOUNT});

        vm.startPrank(address(_paV3));
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV2Input});

        vm.expectRevert(abi.encodeWithSelector(NullifierSet.PreExistingNullifier.selector, _NULLIFIER), address(_fwdV3));
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: _defaultMigrateV2Input});
    }

    function test_migrateV1_reverts_if_the_commitment_tree_root_v1_is_incorrect() public {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        bytes32 expectedCommitmentTreeRootV1 = CommitmentTree(_paV1).latestCommitmentTreeRoot();
        bytes32 incorrectCommitmentTreeRootV1 = bytes32(type(uint256).max / 2);

        bytes memory migrateV1InputWithIncorrectCommitmentTreeRootV1 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*           token */
            address(_erc20),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v1 data */
            ERC20ForwarderV2.MigrateV1Data({
                nullifier: _NULLIFIER,
                rootV1: incorrectCommitmentTreeRootV1,
                logicRefV1: _logicRefV1,
                forwarderV1: address(_fwdV1)
            })
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

        bytes32 expectedCommitmentTreeRootV2 = CommitmentTree(_paV2).latestCommitmentTreeRoot();
        bytes32 incorrectCommitmentTreeRootV2 = bytes32(type(uint256).max / 2);

        bytes memory migrateV2InputWithIncorrectCommitmentTreeRootV2 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*           token */
            address(_erc20),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v2 data */
            ERC20ForwarderV3.MigrateV2Data({
                nullifier: _NULLIFIER,
                rootV2: incorrectCommitmentTreeRootV2,
                logicRefV2: _logicRefV2,
                forwarderV2: address(_fwdV2)
            })
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

        bytes32 incorrectLogicRefV1 = bytes32(type(uint256).max / 2);

        bytes memory migrateV1InputWithIncorrectLogicRefV1 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*           token */
            address(_erc20),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v1 data */
            ERC20ForwarderV2.MigrateV1Data({
                nullifier: _NULLIFIER,
                rootV1: CommitmentTree(_paV1).latestCommitmentTreeRoot(),
                logicRefV1: incorrectLogicRefV1,
                forwarderV1: address(_fwdV1)
            })
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

        bytes32 incorrectLogicRefV2 = bytes32(type(uint256).max / 2);

        bytes memory migrateV2InputWithIncorrectLogicRefV2 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*           token */
            address(_erc20),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v2 data */
            ERC20ForwarderV3.MigrateV2Data({
                nullifier: _NULLIFIER,
                rootV2: CommitmentTree(_paV2).latestCommitmentTreeRoot(),
                logicRefV2: incorrectLogicRefV2,
                forwarderV2: address(_fwdV2)
            })
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

        address incorrectForwarderV1 = address(type(uint160).max);

        bytes memory migrateV1InputWithIncorrectLabelRefV1 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*           token */
            address(_erc20),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v1 data */
            ERC20ForwarderV2.MigrateV1Data({
                nullifier: _NULLIFIER,
                rootV1: CommitmentTree(_paV1).latestCommitmentTreeRoot(),
                logicRefV1: _logicRefV1,
                forwarderV1: incorrectForwarderV1
            })
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

        address incorrectForwarderV2 = address(type(uint160).max / 2);

        bytes memory migrateV2InputWithIncorrectLabelRefV2 = abi.encode( /*  callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*           token */
            address(_erc20),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v2 data */
            ERC20ForwarderV3.MigrateV2Data({
                nullifier: _NULLIFIER,
                rootV2: CommitmentTree(_paV2).latestCommitmentTreeRoot(),
                logicRefV2: _logicRefV2,
                forwarderV2: incorrectForwarderV2
            })
        );

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20ForwarderV3.InvalidForwarderV2.selector, address(_fwdV2), incorrectForwarderV2),
            address(_fwdV3)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: migrateV2InputWithIncorrectLabelRefV2});
    }

    function test_migrateV1_reverts_if_the_amount_deposited_into_fwd_v2_is_not_the_migrate_amount() public {
        // Fund the forwarder v1.
        _erc20FeeSub.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        bytes memory input = abi.encode(
            /*        callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV1,
            /*           token */
            address(_erc20FeeSub),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v1 data */
            ERC20ForwarderV2.MigrateV1Data({
                nullifier: _NULLIFIER,
                rootV1: CommitmentTree(_paV1).latestCommitmentTreeRoot(),
                logicRefV1: _logicRefV1,
                forwarderV1: address(_fwdV1)
            })
        );

        uint256 actualDepositAmount = _TRANSFER_AMOUNT - _erc20FeeSub.FEE();

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Forwarder.BalanceMismatch.selector, _TRANSFER_AMOUNT, actualDepositAmount),
            address(_fwdV2)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: input});
    }

    function test_migrateV2_reverts_if_the_amount_deposited_into_fwd_v3_is_not_the_migrate_amount() public {
        // Fund the forwarder v2.
        _erc20FeeSub.mint({to: address(_fwdV2), value: _TRANSFER_AMOUNT});

        bytes memory input = abi.encode(
            /*        callType */
            ERC20ForwarderV3.CallTypeV3.MigrateV2,
            /*           token */
            address(_erc20FeeSub),
            /*          amount */
            _TRANSFER_AMOUNT,
            /* migrate v2 data */
            ERC20ForwarderV3.MigrateV2Data({
                nullifier: _NULLIFIER,
                rootV2: CommitmentTree(_paV2).latestCommitmentTreeRoot(),
                logicRefV2: _logicRefV2,
                forwarderV2: address(_fwdV2)
            })
        );

        uint256 actualDepositAmount = _TRANSFER_AMOUNT - _erc20FeeSub.FEE();

        vm.startPrank(address(_paV3));
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Forwarder.BalanceMismatch.selector, _TRANSFER_AMOUNT, actualDepositAmount),
            address(_fwdV3)
        );
        _fwdV3.forwardCall({logicRef: _logicRefV3, input: input});
    }

    function test_migrateV1_reverts_if_the_input_length_is_wrong() public {
        bytes memory inputWithWrongLength = abi.encodePacked(_defaultMigrateV1Input, uint256(0));

        vm.prank(address(_pa));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Forwarder.InvalidInputLength.selector,
                _defaultMigrateV1Input.length - _GENERIC_INPUT_OFFSET,
                inputWithWrongLength.length - _GENERIC_INPUT_OFFSET
            ),
            address(_fwd)
        );
        _fwd.forwardCall({logicRef: _logicRef, input: inputWithWrongLength});
    }

    function test_migrateV2_reverts_if_the_input_length_is_wrong() public {
        bytes memory inputWithWrongLength = abi.encodePacked(_defaultMigrateV2Input, uint256(0));

        vm.prank(address(_pa));
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Forwarder.InvalidInputLength.selector,
                _defaultMigrateV2Input.length - _GENERIC_INPUT_OFFSET,
                inputWithWrongLength.length - _GENERIC_INPUT_OFFSET
            ),
            address(_fwd)
        );
        _fwd.forwardCall({logicRef: _logicRef, input: inputWithWrongLength});
    }

    function test_migrateV1_transfers_funds_from_forwarder_V1() public {
        // Fund the forwarder v1.
        _erc20.mint({to: address(_fwdV1), value: _TRANSFER_AMOUNT});

        assertEq(_erc20.balanceOf(address(_fwdV1)), _TRANSFER_AMOUNT);
        assertEq(_erc20.balanceOf(address(_fwdV2)), 0);
        assertEq(_erc20.balanceOf(address(_fwdV3)), 0);

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

    function _deployContracts()
        internal
        returns (ProtocolAdapter paV1, ProtocolAdapter paV2, ProtocolAdapter paV3, ERC20Forwarder fwdV1)
    {
        paV1 = new ProtocolAdapter(_router, _verifier.SELECTOR(), _EMERGENCY_COMMITTEE);
        paV2 = new ProtocolAdapter(_router, _verifier.SELECTOR(), _EMERGENCY_COMMITTEE);
        paV3 = new ProtocolAdapter(_router, _verifier.SELECTOR(), _EMERGENCY_COMMITTEE);
        fwdV1 = new ERC20Forwarder({
            protocolAdapter: address(paV1), emergencyCommittee: _EMERGENCY_COMMITTEE, logicRef: _logicRefV1
        });
    }
}
