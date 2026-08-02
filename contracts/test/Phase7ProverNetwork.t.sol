// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ProverNetwork} from "../src/ProverNetwork.sol";

contract Phase7ProverNetworkTest is Test {
    ProverNetwork internal net;
    address internal proverA = address(0xB201);
    address internal proverB = address(0xB202);
    address internal orchestrator = address(0xABCD);

    function setUp() public {
        net = new ProverNetwork(1 ether);
        vm.deal(proverA, 10 ether);
        vm.deal(proverB, 10 ether);
        net.setAssigner(orchestrator);
    }

    function _joinBoth() internal {
        vm.prank(proverA);
        net.join{value: 1 ether}();
        vm.prank(proverB);
        net.join{value: 2 ether}();
        assertTrue(net.isEligible(proverA));
        assertTrue(net.isEligible(proverB));
        assertEq(net.proverCount(), 2);
    }

    function test_ThirdPartyProverEarns() public {
        vm.prank(proverA);
        net.join{value: 1 ether}();
        net.recordEarn(proverA, 0.05 ether);
        (, , , uint256 earned,) = net.provers(proverA);
        assertEq(earned, 0.05 ether);
    }

    function test_SlashLiveness() public {
        vm.prank(proverA);
        net.join{value: 1 ether}();
        net.slash(proverA, 1 ether, "missed deadline");
        assertFalse(net.isEligible(proverA));
    }

    function test_TwoFulfillersRoundRobinAssignAndEarn() public {
        _joinBoth();
        (address first,) = net.nextEligible(0);
        (address second,) = net.nextEligible(1);
        assertTrue(first == proverA || first == proverB);
        assertTrue(second == proverA || second == proverB);
        assertTrue(first != second);

        vm.prank(orchestrator);
        net.assignJob(1, first, 0.1 ether);
        vm.prank(orchestrator);
        net.assignJob(2, second, 0.2 ether);

        vm.prank(orchestrator);
        net.completeJob(1);
        vm.prank(orchestrator);
        net.completeJob(2);

        (, , , uint256 earnedA,) = net.provers(first);
        (, , , uint256 earnedB,) = net.provers(second);
        assertEq(earnedA, 0.1 ether);
        assertEq(earnedB, 0.2 ether);
    }

    function test_SlashMissedJob() public {
        _joinBoth();
        vm.prank(orchestrator);
        net.assignJob(99, proverA, 0.05 ether);
        net.slashMissedJob(99, 1 ether, "timeout");
        assertFalse(net.isEligible(proverA));
        (address assignee, bool open,) = net.jobs(99);
        assertEq(assignee, proverA);
        assertFalse(open);
        assertTrue(net.isEligible(proverB));
    }

    function test_NonAssignerCannotAssign() public {
        _joinBoth();
        vm.prank(proverA);
        vm.expectRevert(ProverNetwork.NotAssigner.selector);
        net.assignJob(1, proverB, 1);
    }

    function test_CannotDoubleAssign() public {
        _joinBoth();
        vm.prank(orchestrator);
        net.assignJob(1, proverA, 1);
        vm.prank(orchestrator);
        vm.expectRevert(ProverNetwork.AlreadyAssigned.selector);
        net.assignJob(1, proverB, 1);
    }
}
