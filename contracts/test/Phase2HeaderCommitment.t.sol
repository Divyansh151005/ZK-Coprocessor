// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockSP1Verifier} from "../src/MockSP1Verifier.sol";
import {HeaderCommitment} from "../src/HeaderCommitment.sol";

contract Phase2HeaderCommitmentTest is Test {
    MockSP1Verifier internal verifier;
    HeaderCommitment internal headers;
    bytes32 internal updaterVKey = bytes32(uint256(0x0901));

    function setUp() public {
        verifier = new MockSP1Verifier();
        headers = new HeaderCommitment(address(verifier), updaterVKey);
    }

    function _pv(uint64 start, bytes32 root, bytes32 prev, bytes32 next)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(start, root, prev, next);
    }

    function test_CommitBatch() public {
        bytes32 root = keccak256("batch0");
        bytes32 nextSnap = keccak256("snap1");
        bytes memory pv = _pv(0, root, bytes32(0), nextSnap);
        bytes memory proof = verifier.mockProof(updaterVKey, pv);
        headers.commitBatch(pv, proof);
        assertEq(headers.historicalRoots(0), root);
        assertEq(headers.pmmrSnapshotId(), nextSnap);
        assertTrue(headers.isKnownSnapshot(nextSnap));
    }

    function testRevert_BadProof() public {
        bytes memory pv = _pv(0, keccak256("r"), bytes32(0), keccak256("s"));
        vm.expectRevert();
        headers.commitBatch(pv, hex"dead");
    }

    function testRevert_BadStart() public {
        bytes memory pv = _pv(1, keccak256("r"), bytes32(0), keccak256("s"));
        bytes memory proof = verifier.mockProof(updaterVKey, pv);
        vm.expectRevert(HeaderCommitment.BadStart.selector);
        headers.commitBatch(pv, proof);
    }

    function testRevert_DuplicateRoot() public {
        bytes32 root = keccak256("batch0");
        bytes32 nextSnap = keccak256("snap1");
        bytes memory pv = _pv(0, root, bytes32(0), nextSnap);
        headers.commitBatch(pv, verifier.mockProof(updaterVKey, pv));
        bytes memory pv2 = _pv(0, keccak256("other"), nextSnap, keccak256("snap2"));
        bytes memory proof2 = verifier.mockProof(updaterVKey, pv2);
        vm.expectRevert(HeaderCommitment.RootExists.selector);
        headers.commitBatch(pv2, proof2);
    }
}
