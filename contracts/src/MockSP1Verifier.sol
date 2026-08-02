// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "./interfaces/ISP1Verifier.sol";

/// @notice Phase 0 MOCK verifier for local Anvil / Foundry.
/// @dev NOT for production. Accepts proofs whose first 4 bytes are magic `0x4d4f434b` ("MOCK")
///      and whose remaining bytes equal keccak256(publicValues || programVKey).
///      Swap address for real SP1VerifierGateway in production (Phase 4).
contract MockSP1Verifier is ISP1Verifier {
    bytes4 public constant MOCK_MAGIC = 0x4d4f434b;

    error InvalidMockProof();

    function verifyProof(
        bytes32 programVKey,
        bytes calldata publicValues,
        bytes calldata proofBytes
    ) external pure override {
        if (proofBytes.length < 36) revert InvalidMockProof();
        if (bytes4(proofBytes[0:4]) != MOCK_MAGIC) revert InvalidMockProof();
        bytes32 expected = keccak256(abi.encodePacked(publicValues, programVKey));
        bytes32 got;
        assembly {
            got := calldataload(add(proofBytes.offset, 4))
        }
        if (got != expected) revert InvalidMockProof();
    }

    /// @dev Helper for hosts / tests to build a valid mock proof.
    function mockProof(bytes32 programVKey, bytes calldata publicValues)
        external
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(MOCK_MAGIC, keccak256(abi.encodePacked(publicValues, programVKey)));
    }
}
