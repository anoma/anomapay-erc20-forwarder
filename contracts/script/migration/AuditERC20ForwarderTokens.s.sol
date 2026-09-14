// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SupportedNetworks} from "anoma-risc0-deployments-1.2.2/src/SupportedNetworks.sol";
import {Script} from "forge-std-1.16.2/src/Script.sol";
import {LibBytes} from "solady-0.1.26/src/utils/LibBytes.sol";
import {LibString} from "solady-0.1.26/src/utils/LibString.sol";
import {IERC20ForwarderV1} from "./../../src/migration/IERC20ForwarderV1.sol";

/// @notice Verifies V1 deployment and Wrapped token coverage.
contract AuditERC20ForwarderTokens is Script, SupportedNetworks {
    error InvalidDeployment();
    error MissingWrappedToken(address token);
    error InvalidBlockSpan();

    /// @notice Audits deployment and events through the current block, read-only.
    /// @param deploymentTransaction V1 creation tx; zero uses the recorded tx.
    /// @param blockSpan Maximum blocks per request, matching provider limits.
    /// @return committee The committee recovered from V1 constructor arguments.
    /// @return wrappedEvents The Wrapped events scanned since deployment.
    /// @return throughBlock The last scanned block.
    function run(bytes32 deploymentTransaction, uint256 blockSpan)
        public
        returns (address committee, uint256 wrappedEvents, uint256 throughBlock)
    {
        require(blockSpan > 0, InvalidBlockSpan());
        string memory json = vm.readFile("script/migration/tokens.json");
        string memory key = string.concat(".chains.", vm.toString(block.chainid));
        IERC20ForwarderV1 v1 = IERC20ForwarderV1(vm.parseJsonAddress(json, string.concat(key, ".forwarderV1")));
        address[] memory tokens = vm.parseJsonAddressArray(json, string.concat(key, ".tokens"));
        if (deploymentTransaction == bytes32(0)) {
            deploymentTransaction = vm.parseJsonBytes32(json, string.concat(key, ".audit.deploymentTransaction"));
        }
        uint256 deploymentBlock;
        (committee, deploymentBlock) = _deployment(v1, deploymentTransaction);
        throughBlock = block.number;
        for (uint256 start = deploymentBlock; start <= throughBlock;) {
            uint256 end = start + (blockSpan - 1 < throughBlock - start ? blockSpan - 1 : throughBlock - start);
            string memory bounds = string.concat(",\"fromBlock\":\"", LibString.toMinimalHexString(start), "\"");
            bounds = string.concat(bounds, ",\"toBlock\":\"", LibString.toMinimalHexString(end));
            bounds = string.concat(bounds, "\"}]");
            string memory filter = string.concat("[{\"address\":\"", vm.toString(address(v1)), "\",\"topics\":[\"");
            filter = string.concat(filter, vm.toString(keccak256("Wrapped(address,address,uint128)")), "\"]");
            filter = string.concat(filter, bounds);
            wrappedEvents += _checkLogs(_rpc("eth_getLogs", filter), tokens);
            start = end + 1;
        }
    }

    function _deployment(IERC20ForwarderV1 v1, bytes32 deploymentTransaction)
        internal
        returns (address committee, uint256 deploymentBlock)
    {
        string memory params = string.concat("[\"", vm.toString(deploymentTransaction), "\"]");
        string memory transaction = _rpc("eth_getTransactionByHash", params);
        string memory receipt = _rpc("eth_getTransactionReceipt", params);
        deploymentBlock = vm.parseUint(vm.parseJsonString(receipt, ".blockNumber"));
        require(
            vm.parseUint(vm.parseJsonString(receipt, ".status")) == 1 && deploymentBlock <= block.number,
            InvalidDeployment()
        );
        committee = _committee(v1, transaction, receipt);
    }

    function _rpc(string memory method, string memory params) internal returns (string memory json) {
        string[] memory command = new string[](7);
        command[0] = "cast";
        command[1] = "rpc";
        command[2] = method;
        command[3] = params;
        command[4] = "--raw";
        command[5] = "--rpc-url";
        command[6] = vm.rpcUrl(vm.envOr("MIGRATION_FORK_RPC", _supportedNetworks[block.chainid]));
        json = string(vm.ffi(command));
    }

    function _committee(IERC20ForwarderV1 v1, string memory transaction, string memory receipt)
        internal
        view
        returns (address committee)
    {
        bytes memory input = vm.parseJsonBytes(transaction, ".input");
        require(input.length >= 96, InvalidDeployment());
        address pa;
        bytes32 logic;
        (pa, logic, committee) = abi.decode(LibBytes.slice(input, input.length - 96), (address, bytes32, address));
        require(
            pa == v1.getProtocolAdapter() && logic == v1.getLogicRef() && committee != address(0), InvalidDeployment()
        );
        // JSON null is ABI-encoded as bytes32(0), covering ordinary CREATE transactions.
        address factory = abi.decode(vm.parseJson(transaction, ".to"), (address));
        address created;
        if (factory == address(0)) {
            created = vm.parseJsonAddress(receipt, ".contractAddress");
        } else {
            require(factory == 0x4e59b44847b379578588920cA78FbF26c0B4956C, InvalidDeployment());
            created = vm.computeCreate2Address({
                salt: abi.decode(input, (bytes32)),
                initCodeHash: keccak256(LibBytes.slice(input, 32)),
                deployer: factory
            });
        }
        require(created == address(v1), InvalidDeployment());
    }

    function _checkLogs(string memory entries, address[] memory tokens) internal view returns (uint256 count) {
        uint256 tokenCount = tokens.length;
        for (;; ++count) {
            string memory entry = string.concat(".[", vm.toString(count), "]");
            if (!vm.keyExistsJson(entries, entry)) break;
            bytes32 topic = vm.parseJsonBytes32(entries, string.concat(entry, ".topics[1]"));
            address token = address(uint160(uint256(topic)));
            bool listed;
            for (uint256 j = 0; j < tokenCount; ++j) {
                if (tokens[j] == token) {
                    listed = true;
                    break;
                }
            }
            require(listed, MissingWrappedToken(token));
        }
    }
}
