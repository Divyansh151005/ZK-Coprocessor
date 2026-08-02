// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockSP1Verifier} from "../src/MockSP1Verifier.sol";
import {MinimalRequestRouter} from "../src/MinimalRequestRouter.sol";
import {MinimalFulfillment} from "../src/MinimalFulfillment.sol";
import {MockConsumer} from "../src/MockConsumer.sol";

contract Phase0LifecycleTest is Test {
    MockSP1Verifier internal verifier;
    MinimalRequestRouter internal router;
    MinimalFulfillment internal fulfillment;
    MockConsumer internal consumer;

    bytes32 internal constant VKEY = bytes32(uint256(0xA11CE));

    receive() external payable {}

    function setUp() public {
        verifier = new MockSP1Verifier();
        router = new MinimalRequestRouter();
        fulfillment = new MinimalFulfillment(address(router), address(verifier));
        router.setFulfillment(address(fulfillment));
        consumer = new MockConsumer();
    }

    function _publicValues(uint64 a, uint64 b) internal pure returns (bytes memory) {
        uint64 sum;
        unchecked {
            sum = a + b;
        }
        return abi.encode(a, b, sum);
    }

    function _proof(bytes memory publicValues) internal view returns (bytes memory) {
        return verifier.mockProof(VKEY, publicValues);
    }

    function test_HappyPath_RequestProveCallback() public {
        uint64 a = 2;
        uint64 b = 3;
        uint256 id = router.request(VKEY, a, b, address(consumer));

        bytes memory pv = _publicValues(a, b);
        bytes memory proof = _proof(pv);

        fulfillment.fulfill(id, pv, proof);

        assertEq(consumer.receiveCount(), 1);
        assertEq(consumer.lastJournal(), pv);

        (,,,,,, bool fulfilled,) = router.requests(id);
        assertTrue(fulfilled);
    }

    function testRevert_BadProof() public {
        uint256 id = router.request(VKEY, 2, 3, address(consumer));
        bytes memory pv = _publicValues(2, 3);
        bytes memory bad = hex"deadbeef";
        vm.expectRevert();
        fulfillment.fulfill(id, pv, bad);
    }

    function testRevert_WrongPublicValues() public {
        uint256 id = router.request(VKEY, 2, 3, address(consumer));
        // Wrong sum
        bytes memory pv = abi.encode(uint64(2), uint64(3), uint64(99));
        bytes memory proof = _proof(pv);
        vm.expectRevert(MinimalFulfillment.PublicValuesMismatch.selector);
        fulfillment.fulfill(id, pv, proof);
    }

    function testRevert_TamperedInputsInJournal() public {
        uint256 id = router.request(VKEY, 2, 3, address(consumer));
        bytes memory pv = _publicValues(9, 9);
        bytes memory proof = _proof(pv);
        vm.expectRevert(MinimalFulfillment.PublicValuesMismatch.selector);
        fulfillment.fulfill(id, pv, proof);
    }

    function testRevert_DoubleFulfill() public {
        uint256 id = router.request(VKEY, 1, 1, address(consumer));
        bytes memory pv = _publicValues(1, 1);
        bytes memory proof = _proof(pv);
        fulfillment.fulfill(id, pv, proof);
        vm.expectRevert(MinimalRequestRouter.AlreadyFulfilled.selector);
        fulfillment.fulfill(id, pv, proof);
    }

    function testRevert_WrongVkeyProofBinding() public {
        uint256 id = router.request(VKEY, 4, 5, address(consumer));
        bytes memory pv = _publicValues(4, 5);
        // Proof bound to a different vkey
        bytes memory proof = verifier.mockProof(bytes32(uint256(0xBAD)), pv);
        vm.expectRevert(MockSP1Verifier.InvalidMockProof.selector);
        fulfillment.fulfill(id, pv, proof);
    }

    function test_BountyPaidToFulfiller() public {
        address fulfiller = address(0xBEEF);
        vm.deal(address(this), 1 ether);
        uint256 id = router.request{value: 0.05 ether}(VKEY, 10, 20, address(consumer));

        bytes memory pv = _publicValues(10, 20);
        bytes memory proof = _proof(pv);

        uint256 beforeBal = fulfiller.balance;
        vm.prank(fulfiller);
        fulfillment.fulfill(id, pv, proof);
        assertEq(fulfiller.balance - beforeBal, 0.05 ether);
    }
}
