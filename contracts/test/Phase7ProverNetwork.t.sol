// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ProverNetwork} from "../src/ProverNetwork.sol";

contract Phase7ProverNetworkTest is Test {
    ProverNetwork internal net;

    function setUp() public {
        net = new ProverNetwork(1 ether);
    }

    function test_ThirdPartyProverEarns() public {
        address prover = address(0xB201);
        vm.deal(prover, 10 ether);
        vm.prank(prover);
        net.join{value: 1 ether}();
        assertTrue(net.isEligible(prover));
        net.recordEarn(prover, 0.05 ether);
        (, , , uint256 earned) = net.provers(prover);
        assertEq(earned, 0.05 ether);
    }

    function test_SlashLiveness() public {
        address prover = address(0xB202);
        vm.deal(prover, 10 ether);
        vm.prank(prover);
        net.join{value: 1 ether}();
        net.slash(prover, 1 ether, "missed deadline");
        assertFalse(net.isEligible(prover));
    }
}
