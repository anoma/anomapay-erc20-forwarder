// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.7.0/proxy/ERC1967/ERC1967Proxy.sol";

import {DeployERC20ForwarderProxy} from "../../script/DeployERC20ForwarderProxy.s.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {DeploymentsFixture} from "../fixtures/DeploymentsFixture.sol";

/// @notice Checks the proxy deploy script against a fresh chain. The deployments it records are checked in
/// `Deployments.t.sol` and its promotion gates instead.
contract DeployERC20ForwarderProxyTest is DeploymentsFixture {
    bytes32 internal constant _LOGIC_REF = bytes32(uint256(1));

    address internal immutable _PROTOCOL_ADAPTER = makeAddr("protocol adapter");

    function test_run_succeeds_for_a_staging_deployment() public {
        _expectDeployment({isProduction: false});
    }

    function test_run_succeeds_for_a_production_deployment() public {
        _expectDeployment({isProduction: true});
    }

    function test_run_deploys_distinct_proxies_sharing_the_implementation() public {
        DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxy();
        (address stagingProxy, address stagingImplementation,,) =
            script.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});
        (address productionProxy, address productionImplementation,,) =
            script.run({isProduction: true, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});

        assertNotEq(stagingProxy, productionProxy, "staging and production proxy addresses are equal");
        assertEq(stagingImplementation, productionImplementation, "staging and production implementations differ");
    }

    function test_run_reverts_if_the_chain_has_a_recorded_deployment() public {
        Deployment[] memory deployments = _recordedDeployments({isProduction: false});

        for (uint256 i = 0; i < deployments.length; ++i) {
            vm.chainId(deployments[i].chainId);

            DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxy();

            vm.expectRevert(
                abi.encodeWithSelector(
                    DeployERC20ForwarderProxy.DeploymentAlreadyRecorded.selector,
                    _environmentName({isProduction: false}),
                    deployments[i].chainId
                )
            );
            script.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});
        }
    }

    function test_run_reverts_if_the_proxy_is_already_deployed() public {
        DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxy();
        (address proxy,,,) = script.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});

        vm.expectRevert(abi.encodeWithSelector(DeployERC20ForwarderProxy.ProxyAlreadyDeployed.selector, proxy));
        script.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});
    }

    /// @notice Runs the deploy script for the environment and checks that the proxy lands at the predicted
    /// deterministic address, delegates to a deployed implementation, and is initialized with the environment owner.
    /// @param isProduction Whether to deploy the production or the staging environment proxy.
    function _expectDeployment(bool isProduction) private {
        DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxy();
        (address proxy, address implementation,,) =
            script.run({isProduction: isProduction, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});

        address owner = isProduction ? script.PROXY_OWNER_PRODUCTION() : script.PROXY_OWNER_STAGING();
        address predicted = vm.computeCreate2Address(
            isProduction ? script.PROXY_SALT_PRODUCTION() : script.PROXY_SALT_STAGING(),
            keccak256(
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(
                        implementation,
                        abi.encodeCall(ERC20Forwarder.initialize, (_PROTOCOL_ADAPTER, _LOGIC_REF, owner))
                    )
                )
            )
        );

        string memory environment = _environmentName(isProduction);

        assertEq(proxy, predicted, string.concat(environment, ": proxy address differs from the prediction"));
        assertGt(implementation.code.length, 0, string.concat(environment, ": implementation is not deployed"));
        assertEq(
            ERC20Forwarder(proxy).getImplementation(),
            implementation,
            string.concat(environment, ": proxy does not delegate to the implementation")
        );
        assertEq(ERC20Forwarder(proxy).owner(), owner, string.concat(environment, ": proxy owner differs"));
        assertEq(
            ERC20Forwarder(proxy).getProtocolAdapter(),
            _PROTOCOL_ADAPTER,
            string.concat(environment, ": proxy protocol adapter differs")
        );
        assertEq(
            ERC20Forwarder(proxy).getLogicRef(), _LOGIC_REF, string.concat(environment, ": proxy logic ref differs")
        );
    }
}
