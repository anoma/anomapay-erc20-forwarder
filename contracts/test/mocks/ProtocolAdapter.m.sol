// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.7.0/access/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts-5.7.0/utils/Pausable.sol";

contract ProtocolAdapterMock is Ownable, Pausable {
    mapping(bytes32 nullifier => bool isContained) internal _nullifierSet;
    mapping(bytes32 root => bool isContained) internal _commitmentTreeRoots;

    constructor(address emergencyStopCaller) Ownable(emergencyStopCaller) {}

    function mockAddNullifier(bytes32 nullifier) external {
        _nullifierSet[nullifier] = true;
    }

    function mockAddCommitmentTreeRoot(bytes32 root) external {
        _commitmentTreeRoots[root] = true;
    }

    function emergencyStop() external onlyOwner whenNotPaused {
        _pause();
    }

    function isNullifierContained(bytes32 nullifier) external view returns (bool isContained) {
        isContained = _nullifierSet[nullifier];
    }

    function isCommitmentTreeRootContained(bytes32 root) external view returns (bool isContained) {
        isContained = _commitmentTreeRoots[root];
    }

    function isEmergencyStopped() public view returns (bool isStopped) {
        isStopped = paused();
    }
}
