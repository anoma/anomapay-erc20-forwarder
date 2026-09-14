// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std-1.16.2/src/Test.sol";

import {AuditERC20ForwarderTokens} from "../../script/migration/AuditERC20ForwarderTokens.s.sol";
import {IERC20ForwarderV1} from "../../src/migration/IERC20ForwarderV1.sol";

contract AuditERC20ForwarderTokensTest is Test, AuditERC20ForwarderTokens {
    function test_realHexReceiptAndCompleteBaseSepoliaEventHistory() public {
        string memory json = vm.readFile("script/migration/tokens.json");
        uint256 forkBlock = vm.parseJsonUint(json, ".chains.84532.audit.blockNumber");
        vm.createSelectFork(vm.envOr("MIGRATION_FORK_RPC", string("base-sepolia")), forkBlock);
        (address committee, uint256 count, uint256 throughBlock) = run(bytes32(0), 1_000_000);
        assertEq(committee, vm.parseJsonAddress(json, ".chains.84532.audit.emergencyCommittee"));
        assertEq(count, vm.parseJsonUint(json, ".chains.84532.audit.wrappedEventCount"));
        assertEq(throughBlock, forkBlock);
    }

    function test_missingWrappedTokenFailsClosed() public {
        address token = makeAddr("wrapped token");
        string memory topic = vm.toString(bytes32(uint256(uint160(token))));
        string memory events = string.concat("[{\"topics\":[\"0x00\",\"", topic, "\"]}]");
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("different token");
        vm.expectRevert(abi.encodeWithSelector(MissingWrappedToken.selector, token));
        _checkLogs(events, tokens);
        tokens[0] = token;
        assertEq(_checkLogs(events, tokens), 1);
        assertEq(_checkLogs("[]", tokens), 0);
    }

    function test_rejectsForgedCreationReceiptAndConstructorArguments() public {
        address v1 = makeAddr("v1");
        address pa = makeAddr("pa");
        address committee = makeAddr("committee");
        bytes32 logic = bytes32(uint256(42));
        vm.mockCall(v1, abi.encodeCall(IERC20ForwarderV1.getProtocolAdapter, ()), abi.encode(pa));
        vm.mockCall(v1, abi.encodeCall(IERC20ForwarderV1.getLogicRef, ()), abi.encode(logic));
        bytes memory input = abi.encode(pa, logic, committee);
        string memory transaction = string.concat("{\"to\":null,\"input\":\"", vm.toString(input), "\"}");
        string memory receipt = string.concat("{\"contractAddress\":\"", vm.toString(v1), "\"}");
        assertEq(_committee(IERC20ForwarderV1(v1), transaction, receipt), committee);
        string memory wrongReceipt = string.concat("{\"contractAddress\":\"", vm.toString(pa), "\"}");
        vm.expectRevert(InvalidDeployment.selector);
        this.checkCommittee(IERC20ForwarderV1(v1), transaction, wrongReceipt);
        vm.mockCall(v1, abi.encodeCall(IERC20ForwarderV1.getLogicRef, ()), abi.encode(bytes32(0)));
        vm.expectRevert(InvalidDeployment.selector);
        this.checkCommittee(IERC20ForwarderV1(v1), transaction, receipt);
    }

    function test_zeroBlockSpanRevertsBeforeRpc() public {
        vm.expectRevert(InvalidBlockSpan.selector);
        run(bytes32(0), 0);
    }

    function checkCommittee(IERC20ForwarderV1 v1, string memory transaction, string memory receipt)
        public
        view
        returns (address committee)
    {
        committee = _committee(v1, transaction, receipt);
    }
}
