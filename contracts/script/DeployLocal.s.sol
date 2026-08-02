// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MockSP1Verifier} from "../src/MockSP1Verifier.sol";
import {MinimalRequestRouter} from "../src/MinimalRequestRouter.sol";
import {MinimalFulfillment} from "../src/MinimalFulfillment.sol";
import {MockConsumer} from "../src/MockConsumer.sol";

/// @notice Deploys Phase 0 stack on Anvil (mock SP1 verifier).
contract DeployLocal is Script {
    function run() external {
        vm.startBroadcast();

        MockSP1Verifier verifier = new MockSP1Verifier();
        MinimalRequestRouter router = new MinimalRequestRouter();
        MinimalFulfillment fulfillment = new MinimalFulfillment(address(router), address(verifier));
        router.setFulfillment(address(fulfillment));
        MockConsumer consumer = new MockConsumer();

        console2.log("MockSP1Verifier", address(verifier));
        console2.log("MinimalRequestRouter", address(router));
        console2.log("MinimalFulfillment", address(fulfillment));
        console2.log("MockConsumer", address(consumer));

        vm.stopBroadcast();
    }
}
