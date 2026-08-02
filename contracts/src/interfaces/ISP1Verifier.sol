// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SP1 Verifier Interface (vendor-compatible)
/// @notice Mirrors succinctlabs/sp1-contracts ISP1Verifier so we can forge-install
///         the real package; this local copy is used until lib/ is installed.
interface ISP1Verifier {
    function verifyProof(
        bytes32 programVKey,
        bytes calldata publicValues,
        bytes calldata proofBytes
    ) external view;
}
