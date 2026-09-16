// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IProtocolAdapter} from "anoma-pa-evm-2.0.0-rc.1/src/interfaces/IProtocolAdapter.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {IProtocolAdapterSpecific} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IProtocolAdapterSpecific.sol";
import {Script} from "forge-std-1.16.2/src/Script.sol";
import {IOwnerManager} from "safe-smart-account-1.5.0/contracts/interfaces/IOwnerManager.sol";
import {Safe} from "safe-utils-0.0.22/src/Safe.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {IERC20ForwarderMigration} from "../../src/migration/IERC20ForwarderMigration.sol";
import {DeployERC20ForwarderProxy} from "../DeployERC20ForwarderProxy.s.sol";

/// @title MigrateERC20ForwarderAssets
/// @author Anoma Foundation, 2026
/// @notice A script to move one chain's ERC20 token custody from the V1 forwarder to the V2 forwarder proxy, once the
/// chain's v1 protocol adapter is stopped. `run` deploys the migration contract, which is the only contract that can
/// move the custody and can move it only to V2. `proposeCaller` then proposes making it the permanent emergency caller
/// of V1, and `proposeMigration` proposes the move itself. `verify` checks the moved custody against the chain. Both
/// forwarders come from the recorded deployments, so `--rpc-url` alone names the chain.
/// @dev Two Safe proposals carry the migration, and the same Safe executes both: it is the V1 emergency committee and
/// the migration owner. Execute the proposed caller assignment before proposing the move, so that the two proposals
/// take the Safe nonces in that order. The assignment cannot be undone: V1 accepts one emergency caller and keeps it.
/// @custom:security-contact security@anoma.foundation
contract MigrateERC20ForwarderAssets is Script {
    using Safe for *;

    Safe.Client internal _safe;

    /// @notice Thrown if the chain ran no V1 forwarder, i.e. it has no custody to move.
    error ForwarderV1NotRecorded(uint256 chainId);

    /// @notice Thrown if the environment records no V2 forwarder for the chain, i.e. it has no destination.
    error DeploymentNotRecorded(string environment, uint256 chainId);

    /// @notice Thrown if the V2 forwarder forwards for the same protocol adapter as V1, i.e. it does not replace V1.
    error SharedProtocolAdapter(address protocolAdapter);

    /// @notice Thrown if a contract has another owner than the expected one.
    error OwnerMismatch(address expected, address actual);

    /// @notice Thrown if the migration contract awaits an ownership transfer, which would move it out of the Safe's
    /// control the moment the successor accepts.
    error OwnershipTransferPending(address pendingOwner);

    /// @notice Thrown if the migration contract names another forwarder than the recorded V1 forwarder.
    error ForwarderV1Mismatch(address expected, address actual);

    /// @notice Thrown if the migration contract names another forwarder than the recorded V2 forwarder.
    error ForwarderV2Mismatch(address expected, address actual);

    /// @notice Thrown if V1 has another emergency caller than the expected one.
    error EmergencyCallerMismatch(address expected, address actual);

    /// @notice Thrown if the v1 protocol adapter is not stopped, which V1 requires for both emergency calls.
    error ProtocolAdapterNotStopped(address protocolAdapter);

    /// @notice Thrown if the V1 forwarder still holds a token, i.e. the move left it behind.
    error TokenNotMigrated(address token, uint256 balance);

    /// @notice Thrown if the simulated Safe execution of the transaction fails during a dry run.
    error TransactionSimulationFailed();

    /// @notice Deploys the migration contract, which the Safe owns and which moves the custody to the recorded V2
    /// forwarder of the environment. Without `--broadcast` the deployment is simulated locally.
    /// @dev The deployment is not deterministic, so a repeated run deploys a second contract. Pass the one this run
    /// reports to the proposals below.
    /// @param isProduction Whether the custody moves to the production or the staging V2 forwarder.
    /// @return migration The migration contract, owned by the Safe.
    function run(bool isProduction) public returns (ERC20ForwarderMigration migration) {
        (address forwarderV1, address forwarderV2) = _configuration(isProduction);
        address safe = _productionSafe();

        vm.broadcast();
        migration = new ERC20ForwarderMigration(forwarderV1, forwarderV2, safe);
    }

    /// @notice Proposes making the migration contract the permanent emergency caller of V1 to the Safe.
    /// @dev Without `--broadcast`, the Safe execution of the assignment is simulated instead of proposed. The Safe
    /// owners confirm and execute it in the Safe app. It cannot be undone.
    /// @param isProduction Whether the custody moves to the production or the staging V2 forwarder.
    /// @param migration The deployed migration contract to assign.
    /// @param proposer The Safe owner or delegate proposing the transaction.
    function proposeCaller(bool isProduction, ERC20ForwarderMigration migration, address proposer) public {
        (address forwarderV1,) = _checkedConfiguration({isProduction: isProduction, migration: migration});
        _requireEmergencyCaller({forwarderV1: forwarderV1, expected: address(0)});

        _propose({
            safe: _productionSafe(),
            target: forwarderV1,
            callData: abi.encodeCall(IEmergencyMigratable.setEmergencyCaller, (address(migration))),
            proposer: proposer
        });
    }

    /// @notice Proposes the custody move to the Safe, once it has executed the caller assignment.
    /// @dev Without `--broadcast`, the Safe execution of the move is simulated instead of proposed. The Safe owners
    /// confirm and execute it in the Safe app. The migration contract moves each token's full V1 balance and reverts
    /// unless V2 receives it, so a token left out of `tokens` is moved by a later proposal.
    /// @param isProduction Whether the custody moves to the production or the staging V2 forwarder.
    /// @param migration The deployed migration contract, already the emergency caller of V1.
    /// @param tokens The ERC20 tokens to move.
    /// @param proposer The Safe owner or delegate proposing the transaction.
    function proposeMigration(
        bool isProduction,
        ERC20ForwarderMigration migration,
        IERC20[] calldata tokens,
        address proposer
    ) public {
        (address forwarderV1,) = _checkedConfiguration({isProduction: isProduction, migration: migration});
        _requireEmergencyCaller({forwarderV1: forwarderV1, expected: address(migration)});

        _propose({
            safe: _productionSafe(),
            target: address(migration),
            callData: abi.encodeCall(IERC20ForwarderMigration.migrate, (tokens)),
            proposer: proposer
        });
    }

    /// @notice Checks the moved custody against the chain: the migration contract is the emergency caller of V1, and
    /// V1 holds none of the named tokens. Run it after the Safe has executed the move, because `proposeMigration`
    /// itself only ever sees the simulated state. Reverts on the first difference.
    /// @param isProduction Whether the custody moved to the production or the staging V2 forwarder.
    /// @param migration The deployed migration contract that moved the custody.
    /// @param tokens The ERC20 tokens the move covered.
    function verify(bool isProduction, ERC20ForwarderMigration migration, IERC20[] calldata tokens) public {
        (address forwarderV1,) = _checkedConfiguration({isProduction: isProduction, migration: migration});
        _requireEmergencyCaller({forwarderV1: forwarderV1, expected: address(migration)});

        for (uint256 i = 0; i < tokens.length; ++i) {
            uint256 balance = tokens[i].balanceOf(forwarderV1);
            require(balance == 0, TokenNotMigrated({token: address(tokens[i]), balance: balance}));
        }
    }

    /// @notice Returns the chain's recorded forwarders and checks the V2 forwarder against the chain: the
    /// environment's proxy owner owns it, and it forwards for another protocol adapter than V1.
    /// @param isProduction Whether the custody moves to the production or the staging V2 forwarder.
    /// @return forwarderV1 The chain's V1 forwarder, which holds the custody.
    /// @return forwarderV2 The environment's V2 forwarder of the chain, which receives it.
    function _configuration(bool isProduction) internal returns (address forwarderV1, address forwarderV2) {
        DeployERC20ForwarderProxy proxyDeployScript = new DeployERC20ForwarderProxy();

        forwarderV1 = RecordedDeployments.forwarderV1(block.chainid);
        require(forwarderV1 != address(0), ForwarderV1NotRecorded(block.chainid));

        forwarderV2 = RecordedDeployments.forwarderProxy({isProduction: isProduction, chainId: block.chainid});
        require(
            forwarderV2 != address(0),
            DeploymentNotRecorded(proxyDeployScript.environmentName(isProduction), block.chainid)
        );

        address expectedOwner =
            isProduction ? proxyDeployScript.PROXY_OWNER_PRODUCTION() : proxyDeployScript.PROXY_OWNER_STAGING();
        address actualOwner = ERC20Forwarder(forwarderV2).owner();
        require(actualOwner == expectedOwner, OwnerMismatch({expected: expectedOwner, actual: actualOwner}));

        address protocolAdapterV1 = IProtocolAdapterSpecific(forwarderV1).getProtocolAdapter();
        require(
            ERC20Forwarder(forwarderV2).getProtocolAdapter() != protocolAdapterV1,
            SharedProtocolAdapter(protocolAdapterV1)
        );
    }

    /// @notice Returns the chain's recorded forwarders and checks what the Safe proposals depend on besides them: the
    /// migration contract moves the custody between these two forwarders, the Safe alone controls it, and the v1
    /// protocol adapter is stopped.
    /// @param isProduction Whether the custody moves to the production or the staging V2 forwarder.
    /// @param migration The deployed migration contract.
    /// @return forwarderV1 The chain's V1 forwarder, which holds the custody.
    /// @return forwarderV2 The environment's V2 forwarder of the chain, which receives it.
    function _checkedConfiguration(bool isProduction, ERC20ForwarderMigration migration)
        internal
        returns (address forwarderV1, address forwarderV2)
    {
        (forwarderV1, forwarderV2) = _configuration(isProduction);

        address actualForwarderV1 = address(migration.FORWARDER_V1());
        require(
            actualForwarderV1 == forwarderV1, ForwarderV1Mismatch({expected: forwarderV1, actual: actualForwarderV1})
        );

        address actualForwarderV2 = migration.FORWARDER_V2();
        require(
            actualForwarderV2 == forwarderV2, ForwarderV2Mismatch({expected: forwarderV2, actual: actualForwarderV2})
        );

        address safe = _productionSafe();
        address actualOwner = migration.owner();
        require(actualOwner == safe, OwnerMismatch({expected: safe, actual: actualOwner}));

        address pendingOwner = migration.pendingOwner();
        require(pendingOwner == address(0), OwnershipTransferPending(pendingOwner));

        address protocolAdapterV1 = IProtocolAdapterSpecific(forwarderV1).getProtocolAdapter();
        require(IProtocolAdapter(protocolAdapterV1).isEmergencyStopped(), ProtocolAdapterNotStopped(protocolAdapterV1));
    }

    /// @notice Returns the Safe that carries the migration. It is the V1 emergency committee and the migration owner,
    /// and it owns the production proxies.
    /// @dev The audited chains all name this Safe as their V1 emergency committee. A chain that names another one
    /// fails the dry run, because V1 rejects an assignment from any other caller.
    /// @return safe The Safe.
    function _productionSafe() internal returns (address safe) {
        safe = new DeployERC20ForwarderProxy().PROXY_OWNER_PRODUCTION();
    }

    /// @notice Proposes a transaction to a Safe via the Safe Transaction Service.
    /// @dev Without `--broadcast`, the Safe execution of the transaction is simulated instead of proposed.
    /// @param safe The Safe to propose the transaction to.
    /// @param target The contract the Safe calls.
    /// @param callData The call to propose.
    /// @param proposer The Safe owner or delegate proposing the transaction.
    function _propose(address safe, address target, bytes memory callData, address proposer) internal {
        _safe.initialize(safe);

        if (Safe.isBroadcastMode()) {
            _safe.proposeTransaction(target, callData, proposer);
        } else {
            require(
                _safe.simulateTransactionMultiSigNoSign(target, callData, IOwnerManager(safe).getOwners()),
                TransactionSimulationFailed()
            );
        }
    }

    /// @notice Reverts unless V1 holds the expected emergency caller, which is what orders the two Safe proposals.
    /// @param forwarderV1 The chain's V1 forwarder.
    /// @param expected The emergency caller V1 must hold.
    function _requireEmergencyCaller(address forwarderV1, address expected) internal view {
        address actual = IEmergencyMigratable(forwarderV1).getEmergencyCaller();
        require(actual == expected, EmergencyCallerMismatch({expected: expected, actual: actual}));
    }
}
