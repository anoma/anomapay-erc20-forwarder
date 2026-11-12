// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IImplementation} from "anoma-forwarder-bases-3.1.0/src/interfaces/IImplementation.sol";
import {SupportedNetworks} from "anoma-risc0-deployments-2.0.0/src/SupportedNetworks.sol";
import {Test} from "forge-std-1.17.0/src/Test.sol";
import {LibString} from "solady-0.1.26/src/utils/LibString.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {DeployERC20ForwarderImplementation} from "../../script/DeployERC20ForwarderImplementation.s.sol";
import {Parameters} from "../../script/Parameters.sol";

/// @notice A test fixture providing the ERC20 forwarder deployments recorded per environment in `deployments.json` —
/// the single source of truth for the deterministic deployments — through the generated `RecordedDeployments` library.
abstract contract DeploymentsFixture is SupportedNetworks, Test {
    using LibString for *;

    /// @notice Checks that every recorded proxy delegates to the implementation this source version predicts, which
    /// proves the environment runs this source. The record is not a term in the comparison — the chain answers what
    /// it runs.
    /// @param isProduction Whether to check the production or the staging environment.
    function _expectSourceImplementations(bool isProduction) internal {
        RecordedDeployments.Deployment[] memory deployments = _recordedDeployments(isProduction);
        address sourceImplementation = new DeployERC20ForwarderImplementation().predict();

        for (uint256 i = 0; i < deployments.length; ++i) {
            address implementation = abi.decode(
                _call({
                    chainId: deployments[i].chainId,
                    target: deployments[i].proxy.addr,
                    data: abi.encodeCall(IImplementation.getImplementation, ())
                }),
                (address)
            );
            assertEq(
                implementation,
                sourceImplementation,
                string.concat(
                    _deploymentContext({isProduction: isProduction, chainId: deployments[i].chainId}),
                    ": does not run the source implementation"
                )
            );
        }
    }

    /// @notice Returns the result of a call to an account on a supported network, run by the network's RPC endpoint.
    /// @param chainId The chain ID of the network.
    /// @param target The account to call.
    /// @param data The calldata.
    /// @return result The return data.
    /// @dev The endpoint runs the call, because forge cannot fork Monad and the other networks in one run.
    function _call(uint256 chainId, address target, bytes memory data) internal returns (bytes memory result) {
        string memory network = _supportedNetworks[chainId];
        assertGt(bytes(network).length, 0, string.concat(chainId.toString(), ": unsupported network"));

        vm.serializeAddress({objectKey: "transaction", valueKey: "to", value: target});
        string memory transaction = vm.serializeBytes({objectKey: "transaction", valueKey: "data", value: data});
        result =
            vm.rpc({urlOrAlias: network, method: "eth_call", params: string.concat("[", transaction, ",\"latest\"]")});
        assertGt(result.length, 0, string.concat(network, ": ", vm.toString(target), " returned no data"));
    }

    /// @notice Checks that every recorded proxy sits at the address its genesis deployment determines under the
    /// environment salt — the check that the first deployment of an environment used the right salt.
    /// @param isProduction Whether to check the production or the staging environment.
    function _expectGenesisDeployments(bool isProduction) internal pure {
        bytes32 salt = isProduction ? Parameters.PROXY_SALT_PRODUCTION : Parameters.PROXY_SALT_STAGING;

        RecordedDeployments.Deployment[] memory deployments = _recordedDeployments(isProduction);

        for (uint256 i = 0; i < deployments.length; ++i) {
            RecordedDeployments.Proxy memory recordedProxy = deployments[i].proxy;

            bytes memory constructorArgs =
                abi.encode(recordedProxy.initialImplementation, recordedProxy.initializerData);
            bytes memory initCode = abi.encodePacked(recordedProxy.creationCode, constructorArgs);

            address expectedProxyAddress = vm.computeCreate2Address(salt, keccak256(initCode));

            assertEq(
                expectedProxyAddress,
                recordedProxy.addr,
                string.concat(
                    _deploymentContext({isProduction: isProduction, chainId: deployments[i].chainId}),
                    ": recorded proxy address differs"
                )
            );
        }
    }

    /// @notice Returns the deployments of an environment, as `RecordedDeployments` records them.
    /// @param isProduction Whether to return the production or the staging environment.
    /// @return deployments The recorded deployments.
    function _recordedDeployments(bool isProduction)
        internal
        pure
        returns (RecordedDeployments.Deployment[] memory deployments)
    {
        deployments = isProduction ? RecordedDeployments.production() : RecordedDeployments.staging();
    }

    /// @notice Returns the name of an environment, which keys its deployments in `deployments.json`.
    /// @param isProduction Whether to name the production or the staging environment.
    /// @return name The environment name.
    function _environmentName(bool isProduction) internal pure returns (string memory name) {
        name = isProduction ? "production" : "staging";
    }

    /// @notice Returns the `<environment>, <chain ID>` prefix identifying a recorded deployment in assert messages.
    /// @param isProduction Whether the deployment belongs to the production or the staging environment.
    /// @param chainId The chain ID of the deployment.
    /// @return context The assert message prefix.
    function _deploymentContext(bool isProduction, uint256 chainId) internal pure returns (string memory context) {
        context = string.concat(_environmentName(isProduction), ", ", chainId.toString());
    }

    /// @notice Returns whether a version is a release, i.e. carries no prerelease suffix.
    /// @param version The version to check.
    /// @return isRelease Whether the version is a release.
    function _isRelease(string memory version) internal pure returns (bool isRelease) {
        isRelease = version.indexOf("-") == LibString.NOT_FOUND;
    }

    /// @notice Returns whether a version is a release candidate, i.e. carries an `-rc.<number>` prerelease suffix.
    /// Any other prerelease (`-alpha.1`, `-rc`, `-rc.x`) is not one.
    /// @param version The version to check.
    /// @return isReleaseCandidate Whether the version is a release candidate.
    function _isReleaseCandidate(string memory version) internal pure returns (bool isReleaseCandidate) {
        uint256 separator = version.indexOf("-");
        if (separator == LibString.NOT_FOUND) {
            return false;
        }

        string memory suffix = version.slice(separator + 1);
        if (!suffix.startsWith("rc.")) {
            return false;
        }

        string memory number = suffix.slice(3);
        isReleaseCandidate = bytes(number).length != 0 && number.is7BitASCII(LibString.DIGITS_7_BIT_ASCII);
    }
}
