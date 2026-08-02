// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockSP1Verifier} from "../src/MockSP1Verifier.sol";
import {ProgramRegistry} from "../src/ProgramRegistry.sol";
import {RequestRouter} from "../src/RequestRouter.sol";
import {CallbackDispatcher} from "../src/CallbackDispatcher.sol";
import {Fulfillment} from "../src/Fulfillment.sol";
import {MockConsumer} from "../src/MockConsumer.sol";
import {ICoprocessorConsumer} from "../src/interfaces/ICoprocessorConsumer.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract ReentrantConsumer is ICoprocessorConsumer {
    Fulfillment public fulfillment;
    uint256 public attackId;
    bytes public attackPv;
    bytes public attackProof;
    bool public attacked;

    function setAttack(Fulfillment f, uint256 id, bytes memory pv, bytes memory proof) external {
        fulfillment = f;
        attackId = id;
        attackPv = pv;
        attackProof = proof;
    }

    function receiveCoprocessorResult(bytes calldata) external override {
        if (!attacked) {
            attacked = true;
            // Attempt reentrancy into fulfill — should fail at dispatcher nonReentrant or already fulfilled
            try fulfillment.fulfill(attackId, attackPv, attackProof) {} catch {}
        }
    }
}

contract Phase1GatewayTest is Test {
    MockSP1Verifier internal verifier;
    ProgramRegistry internal registry;
    RequestRouter internal router;
    CallbackDispatcher internal dispatcher;
    Fulfillment internal fulfillment;
    MockConsumer internal consumer;

    bytes32 internal elfHash = keccak256("elf");
    bytes32 internal vkey = bytes32(uint256(0xA11CE));
    bytes32 internal programId;

    function setUp() public {
        verifier = new MockSP1Verifier();
        registry = new ProgramRegistry();
        router = new RequestRouter(address(registry));
        dispatcher = new CallbackDispatcher();
        fulfillment = new Fulfillment(address(router), address(verifier), address(dispatcher));
        router.setFulfillment(address(fulfillment));
        consumer = new MockConsumer();
        programId = registry.register(elfHash, vkey, "ipfs://phase1");
    }

    function _pv(uint256 requestId, uint64 a, uint64 b) internal pure returns (bytes memory) {
        uint64 sum;
        unchecked {
            sum = a + b;
        }
        return abi.encode(requestId, a, b, sum);
    }

    function _proof(bytes memory publicValues) internal view returns (bytes memory) {
        return verifier.mockProof(vkey, publicValues);
    }

    function test_RegisterAndFulfill() public {
        bytes memory input = abi.encode(uint64(2), uint64(3));
        uint256 id = router.request{value: 0.01 ether}(programId, input, address(consumer), 0);
        bytes memory pv = _pv(id, 2, 3);
        fulfillment.fulfill(id, pv, _proof(pv));
        assertEq(consumer.receiveCount(), 1);
        assertEq(consumer.lastJournal(), pv);
    }

    function testRevert_BadProof() public {
        bytes memory input = abi.encode(uint64(1), uint64(1));
        uint256 id = router.request(programId, input, address(consumer), 0);
        bytes memory pv = _pv(id, 1, 1);
        vm.expectRevert();
        fulfillment.fulfill(id, pv, hex"00");
    }

    function testRevert_WrongVkeyBinding() public {
        bytes memory input = abi.encode(uint64(1), uint64(2));
        uint256 id = router.request(programId, input, address(consumer), 0);
        bytes memory pv = _pv(id, 1, 2);
        bytes memory proof = verifier.mockProof(bytes32(uint256(1)), pv);
        vm.expectRevert();
        fulfillment.fulfill(id, pv, proof);
    }

    function testRevert_DoubleFulfill() public {
        bytes memory input = abi.encode(uint64(4), uint64(5));
        uint256 id = router.request(programId, input, address(consumer), 0);
        bytes memory pv = _pv(id, 4, 5);
        bytes memory proof = _proof(pv);
        fulfillment.fulfill(id, pv, proof);
        vm.expectRevert(bytes("not pending"));
        fulfillment.fulfill(id, pv, proof);
    }

    function testRevert_RequestIdReplayBind() public {
        bytes memory input = abi.encode(uint64(1), uint64(1));
        uint256 id = router.request(programId, input, address(consumer), 0);
        bytes memory pv = _pv(id + 1, 1, 1); // wrong requestId in journal
        bytes memory proof = _proof(pv);
        vm.expectRevert(Fulfillment.PublicValuesMismatch.selector);
        fulfillment.fulfill(id, pv, proof);
    }

    function test_RefundAfterTimeout() public {
        bytes memory input = abi.encode(uint64(1), uint64(1));
        uint256 id = router.request{value: 0.02 ether}(programId, input, address(consumer), 100);
        vm.warp(block.timestamp + 101);
        uint256 before = address(this).balance;
        router.refund(id);
        assertEq(address(this).balance - before, 0.02 ether);
    }

    function testRevert_RefundTooEarly() public {
        bytes memory input = abi.encode(uint64(1), uint64(1));
        uint256 id = router.request{value: 0.02 ether}(programId, input, address(consumer), 1000);
        vm.expectRevert(RequestRouter.NotExpired.selector);
        router.refund(id);
    }

    function testRevert_Allowlist() public {
        address stranger = address(0xBEEF);
        bytes memory input = abi.encode(uint64(1), uint64(1));
        uint256 id = router.request(programId, input, address(consumer), 0);
        bytes memory pv = _pv(id, 1, 1);
        bytes memory proof = _proof(pv);
        vm.prank(stranger);
        vm.expectRevert(RequestRouter.FulfillerNotAllowed.selector);
        fulfillment.fulfill(id, pv, proof);
    }

    function test_InactiveProgramRejected() public {
        registry.deprecate(programId);
        bytes memory input = abi.encode(uint64(1), uint64(1));
        vm.expectRevert(ProgramRegistry.InactiveProgram.selector);
        router.request(programId, input, address(consumer), 0);
    }

    function test_Erc20RequestAndFulfill() public {
        MockERC20 token = new MockERC20();
        token.mint(address(this), 1_000 ether);
        token.approve(address(router), 100 ether);
        bytes memory input = abi.encode(uint64(2), uint64(3));
        uint256 id = router.requestErc20(programId, input, address(consumer), 0, address(token), 100 ether);
        assertEq(router.bountyToken(id), address(token));
        assertEq(token.balanceOf(address(router)), 100 ether);
        bytes memory pv = _pv(id, 2, 3);
        uint256 before = token.balanceOf(address(this));
        fulfillment.fulfill(id, pv, _proof(pv));
        assertEq(consumer.receiveCount(), 1);
        assertEq(token.balanceOf(address(this)) - before, 100 ether);
        assertEq(token.balanceOf(address(router)), 0);
    }

    function test_Erc20RefundAfterTimeout() public {
        MockERC20 token = new MockERC20();
        token.mint(address(this), 50 ether);
        token.approve(address(router), 50 ether);
        bytes memory input = abi.encode(uint64(1), uint64(1));
        uint256 id = router.requestErc20(programId, input, address(consumer), 100, address(token), 50 ether);
        vm.warp(block.timestamp + 101);
        uint256 before = token.balanceOf(address(this));
        router.refund(id);
        assertEq(token.balanceOf(address(this)) - before, 50 ether);
    }

    function testRevert_Erc20ZeroBounty() public {
        MockERC20 token = new MockERC20();
        bytes memory input = abi.encode(uint64(1), uint64(1));
        vm.expectRevert(RequestRouter.ZeroBounty.selector);
        router.requestErc20(programId, input, address(consumer), 0, address(token), 0);
    }

    function testRevert_Erc20InvalidToken() public {
        bytes memory input = abi.encode(uint64(1), uint64(1));
        vm.expectRevert(RequestRouter.InvalidToken.selector);
        router.requestErc20(programId, input, address(consumer), 0, address(0), 1);
    }

    receive() external payable {}
}
