// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {IProtocolAdapter} from "anoma-pa-evm-2.0.0-rc.1/src/interfaces/IProtocolAdapter.sol";
import {IEmergencyMigratable} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IEmergencyMigratable.sol";
import {IProtocolAdapterSpecific} from "anomapay-erc20-forwarder-1.0.1/src/interfaces/IProtocolAdapterSpecific.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {DeployERC20ForwarderProxy} from "../../script/DeployERC20ForwarderProxy.s.sol";
import {DeployERC20ForwarderMigration} from "../../script/migration/DeployERC20ForwarderMigration.s.sol";
import {MigrateERC20ForwarderAssets} from "../../script/migration/MigrateERC20ForwarderAssets.s.sol";
import {ERC20ForwarderMigration} from "../../src/migration/ERC20ForwarderMigration.sol";
import {DeploymentsFixture} from "../fixtures/DeploymentsFixture.sol";

/// @notice Moves the custody the deployed Sepolia V1 forwarder holds to the recorded staging forwarder, on a fork of
/// the chain. Sepolia carries the whole starting point of a real migration: its v1 protocol adapter is stopped
/// already, and its V1 forwarder still holds the wrapped tokens, so the test asserts that state instead of producing
/// it.
/// @dev The assertions compare the balances before and after the move, so they hold at any block, and the fork
/// follows the latest one.
/// @dev Gated the way the other tests reading a chain are: the promotion gate into `staging` sets the variable, and
/// the test skips everywhere else.
contract ERC20ForwarderMigrationForkTest is DeploymentsFixture {
    uint256 internal constant _CHAIN_ID = 11155111;

    /// @notice The tokens the V1 forwarder wrapped, which the migration has to move. Tokens transferred to it
    /// directly are left out, the way the migration proposal leaves them out.
    address[6] internal _wrappedTokens = [
        0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, // USDC
        0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8, // USDC
        0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14, // WETH
        0xFF34B3d4Aee8ddCd6F9AFFFB6Fe49bD371b8a357, // DAI
        0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0, // USDT
        0xF3F2b4815A58152c9BE53250275e8211163268BA //  USDT
    ];

    /// @notice Skips the test unless the staging deployments are verified against this source.
    modifier onlyStaging() {
        vm.skip(!vm.envOr("VERIFY_STAGING_DEPLOYMENTS", false), "VERIFY_STAGING_DEPLOYMENTS is not set");
        _;
    }

    function test_migrate_moves_every_wrapped_token_balance_to_the_recorded_forwarder() public onlyStaging {
        vm.createSelectFork(_supportedNetworks[_CHAIN_ID]);
        assertEq(block.chainid, _CHAIN_ID, "the fork runs another chain");

        address forwarderV1 = RecordedDeployments.forwarderV1(_CHAIN_ID);
        address forwarderV2 = RecordedDeployments.forwarderProxy({isProduction: false, chainId: _CHAIN_ID});
        DeployERC20ForwarderProxy proxyDeployScript = new DeployERC20ForwarderProxy();
        address committee = proxyDeployScript.PROXY_OWNER_PRODUCTION();
        address wallet = proxyDeployScript.PROXY_OWNER_STAGING();
        _requireStoppedProtocolAdapterV1(forwarderV1);

        IERC20[] memory tokens = _tokens();
        uint256[] memory balancesV1 = _balances({tokens: tokens, account: forwarderV1});
        uint256[] memory balancesV2 = _balances({tokens: tokens, account: forwarderV2});

        // Deployed through the script, so its checks run against the chain the migration acts on.
        ERC20ForwarderMigration migration = new DeployERC20ForwarderMigration().run(false);
        assertEq(migration.owner(), wallet, "the deployment wallet does not own the migration");

        // Read after the deployment: the address the migration lands on may hold a balance of its own already.
        uint256[] memory balancesBeforeMigration = _balances({tokens: tokens, account: address(migration)});

        vm.prank(committee);
        IEmergencyMigratable(forwarderV1).setEmergencyCaller(address(migration));

        vm.prank(wallet);
        migration.migrate(tokens);

        for (uint256 i = 0; i < tokens.length; ++i) {
            string memory context = string.concat(vm.toString(address(tokens[i])), ": ");

            assertEq(tokens[i].balanceOf(forwarderV1), 0, string.concat(context, "the source keeps a balance"));
            assertEq(
                tokens[i].balanceOf(forwarderV2),
                balancesV2[i] + balancesV1[i],
                string.concat(context, "the destination balance differs")
            );
            assertEq(
                tokens[i].balanceOf(address(migration)),
                balancesBeforeMigration[i],
                string.concat(context, "the migration took a balance")
            );
        }

        new MigrateERC20ForwarderAssets().verify({isProduction: false, migration: migration, tokens: tokens});
    }

    /// @notice Reverts unless the v1 protocol adapter of the forwarder is stopped, which both its emergency calls
    /// require. The stop cannot be undone, so the chain holds it from the day the committee executed it.
    /// @param forwarderV1 The deployed V1 forwarder.
    function _requireStoppedProtocolAdapterV1(address forwarderV1) private view {
        address protocolAdapter = IProtocolAdapterSpecific(forwarderV1).getProtocolAdapter();

        assertTrue(IProtocolAdapter(protocolAdapter).isEmergencyStopped(), "the v1 protocol adapter is not stopped");
    }

    /// @notice Returns the wrapped tokens as the migration takes them.
    /// @return tokens The wrapped tokens.
    function _tokens() private view returns (IERC20[] memory tokens) {
        tokens = new IERC20[](_wrappedTokens.length);

        for (uint256 i = 0; i < _wrappedTokens.length; ++i) {
            tokens[i] = IERC20(_wrappedTokens[i]);
        }
    }

    /// @notice Returns the account's balance of every token.
    /// @param tokens The tokens to read.
    /// @param account The account to read the balances of.
    /// @return balances The balances, in the order of the tokens.
    function _balances(IERC20[] memory tokens, address account) private view returns (uint256[] memory balances) {
        balances = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            balances[i] = tokens[i].balanceOf(account);
        }
    }
}
