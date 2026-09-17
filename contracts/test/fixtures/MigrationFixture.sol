// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {ERC20Example} from "anoma-forwarder-bases-3.0.0/test/examples/ERC20Example.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {DeployERC20ForwarderProxy} from "../../script/DeployERC20ForwarderProxy.s.sol";
import {DeployERC20ForwarderMigration} from "../../script/migration/DeployERC20ForwarderMigration.s.sol";
import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {DeployERC20ForwarderProxyMock} from "../mocks/DeployERC20ForwarderProxy.m.sol";
import {ERC20ForwarderV1Mock} from "../mocks/ERC20ForwarderV1.m.sol";
import {ProtocolAdapterMock} from "../mocks/ProtocolAdapter.m.sol";
import {SafeFixture} from "./SafeFixture.sol";

/// @notice A test fixture providing the starting point of a migration on a chain that records both forwarders: a
/// stopped stand-in for the v1 protocol adapter, a V1 forwarder holding a token balance, and a real V2 forwarder
/// proxy — each installed at the address the records name — plus the emergency committee Safe. It builds them
/// locally instead of forking the chain.
abstract contract MigrationFixture is SafeFixture {
    uint256 internal constant _CHAIN_ID = 11155111;
    uint128 internal constant _AMOUNT = 42;

    address internal immutable _PROTOCOL_ADAPTER_V2 = makeAddr("protocol adapter v2");

    ProtocolAdapterMock internal _protocolAdapterV1;
    address internal _committee;
    address internal _committeeOwner;
    address internal _wallet;
    address internal _forwarderV1;
    address internal _forwarderV2;
    ERC20Example internal _token;
    IERC20[] internal _tokens;

    function setUp() public {
        // Keep the scripts on the simulation branch regardless of the shell environment.
        vm.setEnv("SAFE_BROADCAST", "false");

        DeployERC20ForwarderProxy proxyDeployScript = new DeployERC20ForwarderProxy();
        _wallet = proxyDeployScript.PROXY_OWNER_STAGING();
        _committeeOwner = makeAddr("safe owner");
        _committee = _deploySafeAt(_committeeOwner, proxyDeployScript.PROXY_OWNER_PRODUCTION());

        _protocolAdapterV1 = new ProtocolAdapterMock(address(this));
        _protocolAdapterV1.emergencyStop();

        // Deployed before the chain ID changes, because the deploy script refuses a chain with a recorded deployment.
        (address proxy,,,) = new DeployERC20ForwarderProxyMock(_PROTOCOL_ADAPTER_V2).run({isProduction: false});

        _forwarderV1 = RecordedDeployments.forwarderV1(_CHAIN_ID);
        _forwarderV2 = RecordedDeployments.forwarderProxy({isProduction: false, chainId: _CHAIN_ID});

        _install({
            source: address(
                new ERC20ForwarderV1Mock({protocolAdapter: address(_protocolAdapterV1), emergencyCommittee: _committee})
            ),
            target: _forwarderV1
        });
        _install({source: proxy, target: _forwarderV2});

        _token = new ERC20Example();
        _token.mint(_forwarderV1, _AMOUNT);
        _tokens.push(_token);

        vm.chainId(_CHAIN_ID);
    }

    /// @notice Deploys the migration contract of the staging environment through its deploy script.
    /// @return migration The migration contract, owned by the deployment wallet.
    function _deployMigration() internal returns (ERC20ForwarderMigration migration) {
        migration = new DeployERC20ForwarderMigration().run(false);
    }

    /// @notice Installs a deployed contract at the address the records name, which is where the scripts look for it.
    /// @param source The deployed contract.
    /// @param target The recorded address.
    function _install(address source, address target) internal {
        vm.etch(target, source.code);
        vm.copyStorage(source, target);
    }
}
