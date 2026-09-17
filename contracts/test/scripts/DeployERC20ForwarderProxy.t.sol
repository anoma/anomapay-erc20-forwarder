// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.7.0/proxy/ERC1967/ERC1967Proxy.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {DeployERC20ForwarderProxy} from "../../script/DeployERC20ForwarderProxy.s.sol";
import {Parameters} from "../../script/Parameters.sol";
import {ERC20Forwarder} from "../../src/ERC20Forwarder.sol";
import {DeploymentsFixture} from "../fixtures/DeploymentsFixture.sol";
import {DeployERC20ForwarderProxyMock} from "../mocks/DeployERC20ForwarderProxy.m.sol";

/// @notice Checks the proxy deploy script against a fresh chain, forwarding for a given protocol adapter because the
/// records name no test deployment. The deployments it records are checked in `Deployments.t.sol` and its promotion
/// gates instead.
contract DeployERC20ForwarderProxyTest is DeploymentsFixture {
    address internal immutable _PROTOCOL_ADAPTER = makeAddr("protocol adapter");

    function test_run_succeeds_for_a_staging_deployment() public {
        _expectDeployment({isProduction: false});
    }

    function test_run_succeeds_for_a_production_deployment() public {
        _expectDeployment({isProduction: true});
    }

    function test_run_deploys_the_predicted_proxy() public {
        DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxyMock(_PROTOCOL_ADAPTER);
        (address predictedProxy, address predictedImplementation) = script.predict({isProduction: false});

        (address proxy, address implementation,,) = script.run({isProduction: false});

        assertEq(proxy, predictedProxy, "the proxy lands at another address");
        assertEq(implementation, predictedImplementation, "the implementation lands at another address");
    }

    function test_run_deploys_distinct_proxies_sharing_the_implementation() public {
        DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxyMock(_PROTOCOL_ADAPTER);
        (address stagingProxy, address stagingImplementation,,) = script.run({isProduction: false});
        (address productionProxy, address productionImplementation,,) = script.run({isProduction: true});

        assertNotEq(stagingProxy, productionProxy, "staging and production proxy addresses are equal");
        assertEq(stagingImplementation, productionImplementation, "staging and production implementations differ");
    }

    function test_run_reverts_if_the_chain_has_a_recorded_deployment() public {
        RecordedDeployments.Deployment[] memory deployments = _recordedDeployments({isProduction: false});

        for (uint256 i = 0; i < deployments.length; ++i) {
            vm.chainId(deployments[i].chainId);

            DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxyMock(_PROTOCOL_ADAPTER);

            vm.expectRevert(
                abi.encodeWithSelector(
                    DeployERC20ForwarderProxy.DeploymentAlreadyRecorded.selector,
                    _environmentName({isProduction: false}),
                    deployments[i].chainId
                )
            );
            script.run({isProduction: false});
        }
    }

    function test_run_reverts_if_the_records_name_no_protocol_adapter() public {
        DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxy();

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployERC20ForwarderProxy.ProtocolAdapterNotRecorded.selector,
                _environmentName({isProduction: false}),
                block.chainid
            )
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_proxy_is_already_deployed() public {
        DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxyMock(_PROTOCOL_ADAPTER);
        (address proxy,,,) = script.run({isProduction: false});

        vm.expectRevert(abi.encodeWithSelector(DeployERC20ForwarderProxy.ProxyAlreadyDeployed.selector, proxy));
        script.run({isProduction: false});
    }

    /// @notice Runs the deploy script for the environment and checks that the proxy lands at the predicted
    /// deterministic address, delegates to a deployed implementation, and is initialized with the environment owner,
    /// the protocol adapter and the logic ref.
    /// @param isProduction Whether to deploy the production or the staging environment proxy.
    function _expectDeployment(bool isProduction) private {
        DeployERC20ForwarderProxy script = new DeployERC20ForwarderProxyMock(_PROTOCOL_ADAPTER);
        (address proxy, address implementation,,) = script.run({isProduction: isProduction});

        address owner = isProduction ? Parameters.FWD_MULTISIG : Parameters.DEPLOYMENT_WALLET;
        address predicted = vm.computeCreate2Address(
            isProduction ? Parameters.PROXY_SALT_PRODUCTION : Parameters.PROXY_SALT_STAGING,
            keccak256(
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(
                        implementation,
                        abi.encodeCall(ERC20Forwarder.initialize, (_PROTOCOL_ADAPTER, Parameters.LOGIC_REF, owner))
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
            ERC20Forwarder(proxy).getLogicRef(),
            Parameters.LOGIC_REF,
            string.concat(environment, ": proxy logic ref differs")
        );
    }
}
