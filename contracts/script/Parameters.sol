// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Parameters as ProtocolAdapterParameters} from "anoma-pa-evm-2.0.0-rc.3/script/Parameters.sol";

/// @title Parameters
/// @author Anoma Foundation, 2026
/// @notice The deterministic deployment parameters — the CREATE2 salts, the environment proxy owners, and the logic ref
/// the proxies accept. They fix where a deployment lands, who may upgrade it and which resources it serves, so they are
/// held once here and read by the deploy scripts and their tests.
/// @custom:security-contact security@anoma.foundation
library Parameters {
    /// @notice The CREATE2 salt for the staging environment proxy deployment.
    bytes32 internal constant PROXY_SALT_STAGING = "ERC20ForwarderProxyStaging";

    /// @notice The CREATE2 salt for the production environment proxy deployment.
    bytes32 internal constant PROXY_SALT_PRODUCTION = "ERC20ForwarderProxyProduction";

    /// @notice The CREATE2 salt for the implementation deployment, shared by the staging and production environments.
    bytes32 internal constant IMPLEMENTATION_SALT = "ERC20ForwarderImpl";

    /// @notice The logic ref of the token transfer circuit, which the proxies are initialized with.
    bytes32 internal constant LOGIC_REF = 0xbc12323668c37c3d381ca798f11116f35fb1639d12239b29da7810df3985e7ad;

    /// @notice The deployment wallet, which owns the staging proxies and upgrades them instantly. The protocol adapter
    /// repository names the same wallet.
    address internal constant DEPLOYMENT_WALLET = ProtocolAdapterParameters.DEPLOYMENT_WALLET;

    /// @notice The forwarder multisig, a Safe that owns the production proxies and is the emergency committee of the V1
    /// forwarders.
    address internal constant FWD_MULTISIG = 0xc703402252Ce1251aa07e0815D50060d27fdd6C4;
}
