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
        (address committee, uint256 count, uint256 throughBlock) = _run(bytes32(0), 1_000_000, forkBlock);
        assertEq(committee, vm.parseJsonAddress(json, ".chains.84532.audit.emergencyCommittee"));
        assertEq(count, vm.parseJsonUint(json, ".chains.84532.audit.wrappedEventCount"));
        assertEq(throughBlock, forkBlock);
    }

    function test_highVolumeSepoliaHistoryCompletes() public {
        _assertRecordedAudit("sepolia", ".chains.11155111", 2_000_000);
    }

    function test_arbitrumUsesL2RpcBlockRange() public {
        _assertRecordedAudit("arbitrum", ".chains.42161", 100_000_000);
    }

    function test_missingWrappedTokenFailsClosed() public {
        address token = makeAddr("wrapped token");
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("different token");
        vm.expectRevert(abi.encodeWithSelector(MissingWrappedToken.selector, token));
        this.checkToken(token, tokens);
        tokens[0] = token;
        this.checkToken(token, tokens);
    }

    function test_emptyOrPartialHistoryFailsExpectedCount() public {
        vm.expectRevert(abi.encodeWithSelector(UnexpectedWrappedEventCount.selector, 3_010, 0));
        this.checkExpectedEvents(3_010, 0);
        vm.expectRevert(abi.encodeWithSelector(UnexpectedWrappedEventCount.selector, 3_010, 3_009));
        this.checkExpectedEvents(3_010, 3_009);
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

    function checkToken(address observed, address[] memory expected) public pure {
        _checkToken(observed, expected);
    }

    function checkExpectedEvents(uint256 expected, uint256 actual) public pure {
        _checkExpectedEvents(expected, actual);
    }

    function _assertRecordedAudit(string memory rpcAlias, string memory key, uint256 blockSpan) internal {
        string memory json = vm.readFile("script/migration/tokens.json");
        uint256 auditBlock = vm.parseJsonUint(json, string.concat(key, ".audit.blockNumber"));
        vm.createSelectFork(vm.envOr("MIGRATION_FORK_RPC", rpcAlias), auditBlock);
        (address committee, uint256 count, uint256 throughBlock) = _run(bytes32(0), blockSpan, auditBlock);
        assertEq(committee, vm.parseJsonAddress(json, string.concat(key, ".audit.emergencyCommittee")));
        assertEq(count, vm.parseJsonUint(json, string.concat(key, ".audit.wrappedEventCount")));
        assertEq(throughBlock, auditBlock);
    }
}
