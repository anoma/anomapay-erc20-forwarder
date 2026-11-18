// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std-1.17.0/src/Test.sol";
import {
    CompatibilityFallbackHandler
} from "safe-smart-account-1.5.0/contracts/handler/CompatibilityFallbackHandler.sol";
import {IOwnerManager} from "safe-smart-account-1.5.0/contracts/interfaces/IOwnerManager.sol";
import {Enum} from "safe-smart-account-1.5.0/contracts/libraries/Enum.sol";
import {SignMessageLib} from "safe-smart-account-1.5.0/contracts/libraries/SignMessageLib.sol";
import {SafeProxy} from "safe-smart-account-1.5.0/contracts/proxies/SafeProxy.sol";
import {Safe as SafeSmartAccount} from "safe-smart-account-1.5.0/contracts/Safe.sol";

/// @notice A test fixture providing a Safe deployment.
abstract contract SafeFixture is Test {
    /// @notice Deploys a Safe with a single owner and a threshold of one.
    function _deploySafe(address owner) internal returns (address safe) {
        address[] memory owners = new address[](1);
        owners[0] = owner;

        safe = _deploySafe({owners: owners, threshold: 1, fallbackHandler: address(0)});
    }

    /// @notice Deploys a Safe whose owners have the private keys `ownerKeys`, with the fallback handler that
    /// implements ERC-1271.
    function _deploySafe(uint256[] memory ownerKeys, uint256 threshold) internal returns (address safe) {
        address[] memory owners = new address[](ownerKeys.length);
        for (uint256 i = 0; i < ownerKeys.length; ++i) {
            owners[i] = vm.addr(ownerKeys[i]);
        }

        safe = _deploySafe({
            owners: owners, threshold: threshold, fallbackHandler: address(new CompatibilityFallbackHandler())
        });
    }

    /// @notice Deploys a Safe with the given owners, threshold and fallback handler.
    function _deploySafe(address[] memory owners, uint256 threshold, address fallbackHandler)
        internal
        returns (address safe)
    {
        safe = address(new SafeProxy(address(new SafeSmartAccount())));
        SafeSmartAccount(payable(safe))
            .setup({
                _owners: owners,
                _threshold: threshold,
                to: address(0),
                data: "",
                fallbackHandler: fallbackHandler,
                paymentToken: address(0),
                payment: 0,
                paymentReceiver: payable(address(0))
            });
    }

    /// @notice Deploys a Safe with a single owner and a threshold of one, and installs it at the target address.
    function _deploySafeAt(address owner, address target) internal returns (address safe) {
        address deployed = _deploySafe(owner);

        vm.etch(target, deployed.code);
        vm.copyStorage(deployed, target);

        safe = target;
    }

    /// @notice Approves `message` on chain for `safe` with a transaction that the owners with `ownerKeys` sign.
    function _approveSafeMessage(address safe, uint256[] memory ownerKeys, bytes memory message) internal {
        address signMessageLib = address(new SignMessageLib());
        bytes memory data = abi.encodeCall(SignMessageLib.signMessage, (message));
        bytes32 transactionHash = SafeSmartAccount(payable(safe))
            .getTransactionHash({
                to: signMessageLib,
                value: 0,
                data: data,
                operation: Enum.Operation.DelegateCall,
                safeTxGas: 0,
                baseGas: 0,
                gasPrice: 0,
                gasToken: address(0),
                refundReceiver: address(0),
                _nonce: SafeSmartAccount(payable(safe)).nonce()
            });

        SafeSmartAccount(payable(safe))
            .execTransaction({
                to: signMessageLib,
                value: 0,
                data: data,
                operation: Enum.Operation.DelegateCall,
                safeTxGas: 0,
                baseGas: 0,
                gasPrice: 0,
                gasToken: address(0),
                refundReceiver: payable(address(0)),
                signatures: _safeSignatures({ownerKeys: ownerKeys, hash: transactionHash})
            });
    }

    /// @notice Identifies a Safe by probing its owner set and threshold, which every set-up Safe links through
    /// `1 <= threshold <= owners.length`.
    function _isSafe(address account) internal view returns (bool isSafe) {
        if (account.code.length == 0) return false;

        address[] memory owners;
        try IOwnerManager(account).getOwners() returns (address[] memory result) {
            owners = result;
        } catch {
            return false;
        }

        uint256 threshold;
        try IOwnerManager(account).getThreshold() returns (uint256 result) {
            threshold = result;
        } catch {
            return false;
        }

        isSafe = threshold >= 1 && threshold <= owners.length;
    }

    /// @notice The hash that the owners of `safe` sign to approve `message` for ERC-1271.
    function _safeMessageHash(address safe, bytes memory message) internal view returns (bytes32 messageHash) {
        messageHash = CompatibilityFallbackHandler(safe).getMessageHash(message);
    }

    /// @notice The signatures of the owners with `ownerKeys` over `hash`, in the ascending order of their addresses
    /// that Safe requires.
    function _safeSignatures(uint256[] memory ownerKeys, bytes32 hash) internal pure returns (bytes memory signatures) {
        uint256[] memory sortedKeys = new uint256[](ownerKeys.length);
        for (uint256 i = 0; i < ownerKeys.length; ++i) {
            uint256 key = ownerKeys[i];
            uint256 j = i;
            for (; j > 0 && vm.addr(sortedKeys[j - 1]) > vm.addr(key); --j) {
                sortedKeys[j] = sortedKeys[j - 1];
            }
            sortedKeys[j] = key;
        }

        for (uint256 i = 0; i < sortedKeys.length; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(sortedKeys[i], hash);
            signatures = abi.encodePacked(signatures, r, s, v);
        }
    }
}
