// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SupportedNetworks} from "anoma-risc0-deployments-1.2.2/src/SupportedNetworks.sol";
import {Script} from "forge-std-1.16.2/src/Script.sol";
import {Vm} from "forge-std-1.16.2/src/Vm.sol";
import {LibBytes} from "solady-0.1.26/src/utils/LibBytes.sol";
import {IERC20ForwarderV1} from "./../../src/migration/IERC20ForwarderV1.sol";

/// @notice Verifies V1 deployment and Wrapped token coverage.
contract AuditERC20ForwarderTokens is Script, SupportedNetworks {
    error InvalidDeployment();
    error MissingWrappedToken(address token);
    error InvalidBlockSpan();
    error InvalidAuditRange();
    error UnexpectedWrappedEventCount(uint256 expected, uint256 actual);

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
        return _run(deploymentTransaction, blockSpan, _rpcBlockNumber());
    }

    function _run(bytes32 deploymentTransaction, uint256 blockSpan, uint256 auditThroughBlock)
        internal
        returns (address committee, uint256 wrappedEvents, uint256 throughBlock)
    {
        throughBlock = auditThroughBlock;
        string memory json = vm.readFile("script/migration/tokens.json");
        string memory key = string.concat(".chains.", vm.toString(block.chainid));
        IERC20ForwarderV1 v1 = IERC20ForwarderV1(vm.parseJsonAddress(json, string.concat(key, ".forwarderV1")));
        address[] memory tokens = vm.parseJsonAddressArray(json, string.concat(key, ".tokens"));
        uint256 recordedBlock = vm.parseJsonUint(json, string.concat(key, ".audit.blockNumber"));
        uint256 expectedEvents = vm.parseJsonUint(json, string.concat(key, ".audit.wrappedEventCount"));
        if (deploymentTransaction == bytes32(0)) {
            deploymentTransaction = vm.parseJsonBytes32(json, string.concat(key, ".audit.deploymentTransaction"));
        }
        uint256 deploymentBlock;
        (committee, deploymentBlock) = _deployment(v1, deploymentTransaction, throughBlock);
        require(deploymentBlock <= recordedBlock && recordedBlock <= throughBlock, InvalidAuditRange());

        wrappedEvents = _scan({
            v1: v1, tokens: tokens, fromBlock: deploymentBlock, throughBlock: recordedBlock, blockSpan: blockSpan
        });
        _checkExpectedEvents(expectedEvents, wrappedEvents);
        if (recordedBlock < throughBlock) {
            wrappedEvents += _scan({
                v1: v1, tokens: tokens, fromBlock: recordedBlock + 1, throughBlock: throughBlock, blockSpan: blockSpan
            });
        }
    }

    function _deployment(IERC20ForwarderV1 v1, bytes32 deploymentTransaction, uint256 throughBlock)
        internal
        returns (address committee, uint256 deploymentBlock)
    {
        string memory params = string.concat("[\"", vm.toString(deploymentTransaction), "\"]");
        string memory transaction = _rpc("eth_getTransactionByHash", params);
        string memory receipt = _rpc("eth_getTransactionReceipt", params);
        deploymentBlock = vm.parseUint(vm.parseJsonString(receipt, ".blockNumber"));
        require(
            vm.parseUint(vm.parseJsonString(receipt, ".status")) == 1 && deploymentBlock <= throughBlock,
            InvalidDeployment()
        );
        committee = _committee(v1, transaction, receipt);
    }

    function _rpcBlockNumber() internal returns (uint256 rpcBlockNumber) {
        string[] memory command = new string[](4);
        command[0] = "cast";
        command[1] = "block-number";
        command[2] = "--rpc-url";
        command[3] = vm.rpcUrl(vm.envOr("MIGRATION_FORK_RPC", _supportedNetworks[block.chainid]));
        rpcBlockNumber = vm.parseUint(string(vm.ffi(command)));
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

    function _scan(
        IERC20ForwarderV1 v1,
        address[] memory tokens,
        uint256 fromBlock,
        uint256 throughBlock,
        uint256 blockSpan
    ) internal view returns (uint256 wrappedEvents) {
        for (uint256 start = fromBlock; start <= throughBlock;) {
            uint256 end = start + (blockSpan - 1 < throughBlock - start ? blockSpan - 1 : throughBlock - start);
            wrappedEvents += _summarizeLogs(v1, tokens, start, end);
            start = end + 1;
        }
    }

    function _summarizeLogs(IERC20ForwarderV1 v1, address[] memory tokens, uint256 fromBlock, uint256 toBlock)
        internal
        view
        returns (uint256 count)
    {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = keccak256("Wrapped(address,address,uint128)");
        Vm.EthGetLogs[] memory entries = vm.eth_getLogs(fromBlock, toBlock, address(v1), topics);
        count = entries.length;
        for (uint256 i = 0; i < count; ++i) {
            require(entries[i].topics.length > 1, InvalidDeployment());
            _checkToken(address(uint160(uint256(entries[i].topics[1]))), tokens);
        }
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

    function _checkToken(address observed, address[] memory expected) internal pure {
        for (uint256 i = 0; i < expected.length; ++i) {
            if (expected[i] == observed) {
                return;
            }
        }
        revert MissingWrappedToken(observed);
    }

    function _checkExpectedEvents(uint256 expected, uint256 actual) internal pure {
        require(actual == expected, UnexpectedWrappedEventCount(expected, actual));
    }
}
