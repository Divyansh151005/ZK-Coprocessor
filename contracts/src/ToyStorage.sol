// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal storage toy for Anvil eth_getProof / MPT demos.
contract ToyStorage {
    // slot 0
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }
}
