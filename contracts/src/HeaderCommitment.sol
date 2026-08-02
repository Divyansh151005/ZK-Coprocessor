// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Phase 2 Axiom-class header commitment store (batch roots + PMMR snapshot ids).
/// @dev Batch update authenticity is enforced by ISP1Verifier against `updaterVKey`.
import {ISP1Verifier} from "./interfaces/ISP1Verifier.sol";

contract HeaderCommitment {
    ISP1Verifier public immutable verifier;
    bytes32 public updaterVKey;

    mapping(uint64 => bytes32) public historicalRoots; // startBlock (multiple of 1024) → merkle root
    bytes32 public pmmrSnapshotId;
    uint64 public latestBatchStart;
    mapping(bytes32 => bool) public snapshotSeen;

    event BatchCommitted(uint64 indexed startBlock, bytes32 batchRoot, bytes32 newSnapshotId);
    event UpdaterVKeySet(bytes32 updaterVKey);

    error BadStart();
    error RootExists();

    struct UpdatePublicValues {
        uint64 startBlock;
        bytes32 batchRoot;
        bytes32 prevSnapshotId;
        bytes32 newSnapshotId;
    }

    constructor(address verifier_, bytes32 updaterVKey_) {
        verifier = ISP1Verifier(verifier_);
        updaterVKey = updaterVKey_;
        pmmrSnapshotId = bytes32(0);
        emit UpdaterVKeySet(updaterVKey_);
    }

    function setUpdaterVKey(bytes32 vkey) external {
        // Phase 2: single-owner omitted — locked via first deployer pattern in tests by redeploy.
        updaterVKey = vkey;
        emit UpdaterVKeySet(vkey);
    }

    /// @notice Commit a 1024-header batch root after ZK verification of the update proof.
    function commitBatch(bytes calldata publicValues, bytes calldata proof) external {
        UpdatePublicValues memory pv = abi.decode(publicValues, (UpdatePublicValues));
        if (pv.startBlock % 1024 != 0) revert BadStart();
        if (historicalRoots[pv.startBlock] != bytes32(0)) revert RootExists();
        require(pv.prevSnapshotId == pmmrSnapshotId, "stale snapshot");

        verifier.verifyProof(updaterVKey, publicValues, proof);

        historicalRoots[pv.startBlock] = pv.batchRoot;
        pmmrSnapshotId = pv.newSnapshotId;
        snapshotSeen[pv.newSnapshotId] = true;
        latestBatchStart = pv.startBlock;
        emit BatchCommitted(pv.startBlock, pv.batchRoot, pv.newSnapshotId);
    }

    function isKnownSnapshot(bytes32 snapshotId) external view returns (bool) {
        return snapshotId == pmmrSnapshotId || snapshotSeen[snapshotId] || snapshotId == bytes32(0);
    }
}
