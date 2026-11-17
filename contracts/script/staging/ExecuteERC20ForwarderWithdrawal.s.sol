// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UUPSUpgradeable} from "@openzeppelin-contracts-5.7.0/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin-contracts-5.7.0/token/ERC20/IERC20.sol";
import {Options} from "openzeppelin-foundry-upgrades-0.4.4/src/Options.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades-0.4.4/src/Upgrades.sol";

import {IWithdrawingERC20Forwarder} from "../../src/staging/IWithdrawingERC20Forwarder.sol";
import {WithdrawingERC20Forwarder} from "../../src/staging/WithdrawingERC20Forwarder.sol";
import {StagingScript} from "./StagingScript.s.sol";

/// @title ExecuteERC20ForwarderWithdrawal
/// @author Anoma Foundation, 2026
/// @notice A script that upgrades the staging environment ERC20 forwarder proxy to `WithdrawingERC20Forwarder` and
/// sends the full balance of each token of the chain to the dev wallet in the same call, as the proxy owner.
/// @custom:security-contact security@anoma.foundation
contract ExecuteERC20ForwarderWithdrawal is StagingScript {
    /// @notice The CREATE2 salt for the withdrawing implementation deployment.
    bytes32 public constant IMPLEMENTATION_SALT = "WithdrawingERC20ForwarderImpl";

    /// @notice The dev wallet, which receives the tokens.
    address public constant RECIPIENT = 0x990c1773C28B985c2cf32C0a920192bD8717C871;

    /// @notice The chain ID of Sepolia.
    uint256 internal constant _SEPOLIA = 11_155_111;

    /// @notice The chain ID of Monad.
    uint256 internal constant _MONAD = 143;

    /// @notice Thrown if the script lists no tokens for the chain.
    error NoTokensListed(uint256 chainId);

    /// @notice Thrown if the proxy still holds a token after the withdrawal.
    error TokenNotWithdrawn(IERC20 token, uint256 balance);

    /// @notice Thrown if the recipient did not receive the full amount of a token.
    error AmountNotReceived(IERC20 token, uint256 expected, uint256 actual);

    /// @notice Upgrades the recorded staging proxy to the withdrawing implementation and withdraws the tokens of the
    /// chain, as the proxy owner. It deploys the implementation only if it is not deployed. Without `--broadcast`, the
    /// script runs locally.
    /// @return implementation The withdrawing implementation.
    /// @return tokens The withdrawn tokens.
    /// @return amounts The withdrawn amount of each token.
    function run() public returns (address implementation, IERC20[] memory tokens, uint256[] memory amounts) {
        tokens = _tokens();
        address proxy = _requireRecordedProxy({isProduction: false});
        address owner = _stagingOwner({proxy: proxy});

        uint256 count = tokens.length;
        amounts = new uint256[](count);
        uint256[] memory recipientBalancesBefore = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            amounts[i] = tokens[i].balanceOf(proxy);
            recipientBalancesBefore[i] = tokens[i].balanceOf(RECIPIENT);
        }

        Options memory opts;
        Upgrades.validateUpgrade("WithdrawingERC20Forwarder.sol:WithdrawingERC20Forwarder", opts);

        implementation = vm.computeCreate2Address({
            salt: IMPLEMENTATION_SALT,
            initCodeHash: keccak256(
                abi.encodePacked(type(WithdrawingERC20Forwarder).creationCode, abi.encode(RECIPIENT))
            )
        });

        vm.startBroadcast(owner);
        if (implementation.code.length == 0) {
            implementation = address(new WithdrawingERC20Forwarder{salt: IMPLEMENTATION_SALT}(RECIPIENT));
        }
        UUPSUpgradeable(proxy)
            .upgradeToAndCall(implementation, abi.encodeCall(IWithdrawingERC20Forwarder.withdraw, (tokens)));
        vm.stopBroadcast();

        for (uint256 i = 0; i < count; ++i) {
            uint256 balance = tokens[i].balanceOf(proxy);
            require(balance == 0, TokenNotWithdrawn({token: tokens[i], balance: balance}));

            uint256 received = tokens[i].balanceOf(RECIPIENT) - recipientBalancesBefore[i];
            require(
                received == amounts[i], AmountNotReceived({token: tokens[i], expected: amounts[i], actual: received})
            );
        }
    }

    /// @notice Returns the tokens that the staging ERC20 forwarder of the chain holds, and reverts if the script lists
    /// none for the chain.
    /// @return tokens The tokens to withdraw.
    function _tokens() internal view virtual returns (IERC20[] memory tokens) {
        tokens = new IERC20[](2);
        if (block.chainid == _SEPOLIA) {
            tokens[0] = IERC20(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238); // USDC
            tokens[1] = IERC20(0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14); // WETH
        } else if (block.chainid == _MONAD) {
            tokens[0] = IERC20(0x754704Bc059F8C67012fEd69BC8A327a5aafb603); // USDC
            tokens[1] = IERC20(0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A); // WMON
        } else {
            revert NoTokensListed({chainId: block.chainid});
        }
    }
}
