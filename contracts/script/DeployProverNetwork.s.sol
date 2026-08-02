// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ProverNetwork} from "../src/ProverNetwork.sol";

contract DeployProverNetwork is Script {
    function run() external {
        vm.startBroadcast();
        ProverNetwork net = new ProverNetwork(1 ether);
        console2.log("ProverNetwork", address(net));
        vm.stopBroadcast();
    }
}
