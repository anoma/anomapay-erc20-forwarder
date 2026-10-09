// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.7.0/proxy/ERC1967/ERC1967Proxy.sol";
import {ILogicRefDenylist} from "anoma-pa-evm-2.0.0-rc.9/src/interfaces/ILogicRefDenylist.sol";
import {IProtocolAdapter} from "anoma-pa-evm-2.0.0-rc.9/src/interfaces/IProtocolAdapter.sol";
import {ProtocolAdapter} from "anoma-pa-evm-2.0.0-rc.9/src/ProtocolAdapter.sol";
import {LogicRefDenylist} from "anoma-pa-evm-2.0.0-rc.9/src/state/LogicRefDenylist.sol";
import {TxGen} from "anoma-pa-evm-2.0.0-rc.9/test/libs/TxGen.sol";
import {DeployRiscZeroContractsMock} from "anoma-risc0-deployments-1.2.4/test/script/DeployRiscZeroContractsMock.s.sol";
import {Test, Vm} from "forge-std-1.17.0/src/Test.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.2/src/Upgrades.sol";
import {RiscZeroVerifierRouter} from "risc0-risc0-ethereum-3.0.1/contracts/src/RiscZeroVerifierRouter.sol";
import {RiscZeroMockVerifier} from "risc0-risc0-ethereum-3.0.1/contracts/src/test/RiscZeroMockVerifier.sol";

import {EmergencyMigratingERC20Forwarder} from "../../src/draft/EmergencyMigratingERC20Forwarder.sol";
import {IEmergencyMigratingERC20Forwarder} from "../../src/draft/IEmergencyMigratingERC20Forwarder.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";

/// @dev Runs the v2 protocol adapter of pa-evm with a RISC Zero mock verifier, so transactions need no real proofs.
contract EmergencyMigratingERC20ForwarderIntegrationTest is Test {
    using TxGen for Vm;

    bytes32 internal constant _VULNERABLE_LOGIC_REF = bytes32(uint256(1));
    bytes32 internal constant _NEW_LOGIC_REF = bytes32(uint256(2));
    bytes32 internal constant _LABEL_REF = bytes32(uint256(3));
    uint128 internal constant _QUANTITY = 1000;

    address internal immutable _PROTOCOL_ADAPTER_OWNER = makeAddr("protocol adapter owner");
    address internal immutable _FORWARDER_OWNER = makeAddr("forwarder owner");
    address internal immutable _TOKEN = makeAddr("token");

    RiscZeroMockVerifier internal _mockVerifier;
    ProtocolAdapter internal _protocolAdapter;
    EmergencyMigratingERC20Forwarder internal _forwarder;

    function setUp() public {
        RiscZeroVerifierRouter router;
        (router,, _mockVerifier) = new DeployRiscZeroContractsMock().run();

        address implementation = address(
            new ProtocolAdapter({
                riscZeroVerifierRouter: address(router), riscZeroVerifierSelector: _mockVerifier.SELECTOR()
            })
        );
        _protocolAdapter = ProtocolAdapter(
            address(
                new ERC1967Proxy(implementation, abi.encodeCall(ProtocolAdapter.initialize, (_PROTOCOL_ADAPTER_OWNER)))
            )
        );

        _forwarder = EmergencyMigratingERC20Forwarder(
            Upgrades.deployUUPSProxy(
                "ERC20Forwarder.sol:ERC20Forwarder",
                abi.encodeCall(
                    ERC20Forwarder.initialize, (address(_protocolAdapter), _VULNERABLE_LOGIC_REF, _FORWARDER_OWNER)
                )
            )
        );
    }

    function test_execute_emergency_migrates_a_resource_after_the_protocol_adapter_denies_its_logic_ref() public {
        // Create a resource with the vulnerable logic ref.
        TxGen.Resource memory resource = _resource({nonce: 1, logicRef: _VULNERABLE_LOGIC_REF, ephemeral: false});
        _protocolAdapter.execute(
            _transaction({
                consumed: _withoutAppData(_resource({nonce: 0, logicRef: _VULNERABLE_LOGIC_REF, ephemeral: true})),
                created: _withoutAppData(resource)
            })
        );
        bytes32 nullifier = TxGen.nullifier({resource: resource, nullifierKey: 0});
        bytes32 root = _protocolAdapter.latestCommitmentTreeRoot();

        // Deny the logic ref for consumed and for created resources.
        ILogicRefDenylist.DeniedLogicRef[] memory denials = new ILogicRefDenylist.DeniedLogicRef[](2);
        denials[0] = ILogicRefDenylist.DeniedLogicRef({logicRef: _VULNERABLE_LOGIC_REF, consumed: true});
        denials[1] = ILogicRefDenylist.DeniedLogicRef({logicRef: _VULNERABLE_LOGIC_REF, consumed: false});
        vm.prank(_PROTOCOL_ADAPTER_OWNER);
        _protocolAdapter.denyLogicRefs(denials);

        // Check that the adapter no longer consumes the resource.
        IProtocolAdapter.Transaction memory transfer = _transaction({
            consumed: _withoutAppData(resource),
            created: _withoutAppData(_resource({nonce: 2, logicRef: _VULNERABLE_LOGIC_REF, ephemeral: false}))
        });
        vm.expectRevert(
            abi.encodeWithSelector(LogicRefDenylist.ResourceWithDeniedLogicRef.selector, _VULNERABLE_LOGIC_REF, true)
        );
        _protocolAdapter.execute(transfer);

        // Check that the adapter creates no resource with the logic ref. It checks the denylists before the delta
        // proof, so the transaction needs no consumed resource.
        IProtocolAdapter.Transaction memory creation = _transaction({
            consumed: new TxGen.ResourceAndAppData[](0),
            created: _withoutAppData(_resource({nonce: 3, logicRef: _VULNERABLE_LOGIC_REF, ephemeral: false}))
        });
        vm.expectRevert(
            abi.encodeWithSelector(LogicRefDenylist.ResourceWithDeniedLogicRef.selector, _VULNERABLE_LOGIC_REF, false)
        );
        _protocolAdapter.execute(creation);

        // Upgrade the forwarder to the new logic ref and list the vulnerable one.
        address implementation = address(new EmergencyMigratingERC20Forwarder({forwarderV1: makeAddr("V1 forwarder")}));
        bytes32[] memory vulnerableLogicRefs = new bytes32[](1);
        vulnerableLogicRefs[0] = _VULNERABLE_LOGIC_REF;
        vm.prank(_FORWARDER_OWNER);
        _forwarder.upgradeToAndCall({
            newImplementation: implementation,
            data: abi.encodeCall(EmergencyMigratingERC20Forwarder.reinitialize, (_NEW_LOGIC_REF, vulnerableLogicRefs))
        });

        // Emergency-migrate the resource: a trigger with the new logic ref calls the forwarder, and the transaction
        // creates a resource of the same kind and quantity as the trigger.
        IProtocolAdapter.Transaction memory migration = _transaction({
            consumed: _withAppData({
                resource: _resource({nonce: 4, logicRef: _NEW_LOGIC_REF, ephemeral: true}),
                appData: _migrateCall({nullifier: nullifier, root: root})
            }),
            created: _withoutAppData(_resource({nonce: 5, logicRef: _NEW_LOGIC_REF, ephemeral: false}))
        });
        vm.expectEmit(address(_forwarder));
        emit IEmergencyMigratingERC20Forwarder.Migrated({
            token: _TOKEN, vulnerableLogicRef: _VULNERABLE_LOGIC_REF, nullifier: nullifier
        });
        _protocolAdapter.execute(migration);

        assertTrue(_forwarder.isNullifierMigrated(nullifier), "the forwarder records the nullifier");
        assertFalse(_protocolAdapter.isNullifierContained(nullifier), "the adapter does not consume the resource");
    }

    /// @dev Builds a transaction of one action, mock-proven against the empty kind table.
    function _transaction(TxGen.ResourceAndAppData[] memory consumed, TxGen.ResourceAndAppData[] memory created)
        internal
        returns (IProtocolAdapter.Transaction memory txn)
    {
        TxGen.ResourceLists[] memory actions = new TxGen.ResourceLists[](1);
        actions[0] = TxGen.ResourceLists({consumed: consumed, created: created});
        txn = vm.transaction({mockVerifier: _mockVerifier, actionResources: actions});
    }

    /// @dev The external payload of a trigger that emergency-migrates the resource with the nullifier.
    function _migrateCall(bytes32 nullifier, bytes32 root)
        internal
        view
        returns (IProtocolAdapter.AppData memory appData)
    {
        EmergencyMigratingERC20Forwarder.MigrateEntry[] memory entries =
            new EmergencyMigratingERC20Forwarder.MigrateEntry[](1);
        entries[0] = EmergencyMigratingERC20Forwarder.MigrateEntry({
            nullifier: nullifier,
            commitmentTreeRoot: root,
            vulnerableLogicRef: _VULNERABLE_LOGIC_REF,
            forwarder: address(_forwarder)
        });
        bytes memory input =
            abi.encode(EmergencyMigratingERC20Forwarder.EmergencyMigratingCallType.Migrate, _TOKEN, _QUANTITY, entries);

        appData = TxGen.emptyAppData();
        appData.externalPayload = new IProtocolAdapter.ExpirableBlob[](1);
        appData.externalPayload[0] = IProtocolAdapter.ExpirableBlob({
            deletionCriterion: IProtocolAdapter.DeletionCriterion.Immediately,
            blob: abi.encode(address(_forwarder), input, bytes(""))
        });
    }

    function _resource(uint256 nonce, bytes32 logicRef, bool ephemeral)
        internal
        pure
        returns (TxGen.Resource memory resource)
    {
        resource = TxGen.mockResource({
            nonce: bytes32(nonce), logicRef: logicRef, labelRef: _LABEL_REF, quantity: _QUANTITY
        });
        resource.ephemeral = ephemeral;
    }

    function _withoutAppData(TxGen.Resource memory resource)
        internal
        pure
        returns (TxGen.ResourceAndAppData[] memory resources)
    {
        resources = _withAppData({resource: resource, appData: TxGen.emptyAppData()});
    }

    function _withAppData(TxGen.Resource memory resource, IProtocolAdapter.AppData memory appData)
        internal
        pure
        returns (TxGen.ResourceAndAppData[] memory resources)
    {
        resources = new TxGen.ResourceAndAppData[](1);
        resources[0] = TxGen.ResourceAndAppData({resource: resource, appData: appData});
    }
}
