// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Consumer callback surface for the ZK coprocessor (Phase 0 API).
interface ICoprocessorConsumer {
    /// @dev Receives the verified journal bytes (abi-encoded public values).
    function receiveCoprocessorResult(bytes calldata journal) external;
}
