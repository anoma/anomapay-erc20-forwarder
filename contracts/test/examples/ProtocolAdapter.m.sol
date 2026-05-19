// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";
import {Pausable} from "@openzeppelin-contracts-5.6.1/utils/Pausable.sol";

contract ProtocolAdapterMock is Ownable, Pausable {
    mapping(bytes32 nullifier => bool isContained) internal _nullifierSet;
    bytes32 internal _latestRoot;

    constructor(address emergencyStopCaller) Ownable(emergencyStopCaller) {}

    function mockAddNullifier(bytes32 nullifier) external {
        _nullifierSet[nullifier] = true;
    }

    function mockLatestCommitmentTreeRoot(bytes32 root) external {
        _latestRoot = root;
    }

    function emergencyStop() external onlyOwner whenNotPaused {
        _pause();
    }

    function isNullifierContained(bytes32 nullifier) external view returns (bool isContained) {
        isContained = _nullifierSet[nullifier];
    }

    function latestCommitmentTreeRoot() external view returns (bytes32 root) {
        root = _latestRoot;
    }

    function isEmergencyStopped() public view returns (bool isStopped) {
        isStopped = paused();
    }
}
