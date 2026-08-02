// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SP1VerifierGateway} from "@sp1-contracts/SP1VerifierGateway.sol";
import {SP1Verifier as SP1VerifierGroth16} from "@sp1-contracts/v6.1.0/SP1VerifierGroth16.sol";
import {MinimalRequestRouter} from "../src/MinimalRequestRouter.sol";
import {MinimalFulfillment} from "../src/MinimalFulfillment.sol";
import {MockConsumer} from "../src/MockConsumer.sol";
import {MockSP1Verifier} from "../src/MockSP1Verifier.sol";

/// @notice Milestone B: real SP1VerifierGateway rejects mock proofs; accepts only routed Groth16.
contract Sp1GatewayLiveTest is Test {
    SP1VerifierGateway internal gateway;
    SP1VerifierGroth16 internal groth16;
    MinimalRequestRouter internal router;
    MinimalFulfillment internal fulfillment;
    MockConsumer internal consumer;
    bytes32 internal vkey = bytes32(uint256(0xA11CE));

    function setUp() public {
        gateway = new SP1VerifierGateway(address(this));
        groth16 = new SP1VerifierGroth16();
        gateway.addRoute(address(groth16));
        router = new MinimalRequestRouter();
        fulfillment = new MinimalFulfillment(address(router), address(gateway));
        router.setFulfillment(address(fulfillment));
        consumer = new MockConsumer();
    }

    function test_GatewayRouteRegistered() public view {
        bytes4 selector = bytes4(groth16.VERIFIER_HASH());
        (address verifier, bool frozen) = gateway.routes(selector);
        assertEq(verifier, address(groth16));
        assertFalse(frozen);
    }

    function testRevert_MockProofAgainstRealGateway() public {
        MockSP1Verifier mock = new MockSP1Verifier();
        uint256 id = router.request(vkey, 2, 3, address(consumer));
        bytes memory pv = abi.encode(uint64(2), uint64(3), uint64(5));
        bytes memory mockProof = mock.mockProof(vkey, pv);
        // Real gateway: first 4 bytes are not a registered Groth16 selector → RouteNotFound
        vm.expectRevert();
        fulfillment.fulfill(id, pv, mockProof);
    }

    function testRevert_EmptyProof() public {
        uint256 id = router.request(vkey, 1, 1, address(consumer));
        bytes memory pv = abi.encode(uint64(1), uint64(1), uint64(2));
        vm.expectRevert();
        fulfillment.fulfill(id, pv, hex"");
    }
}
