// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {MockSP1Verifier} from "../src/MockSP1Verifier.sol";
import {HeaderCommitment} from "../src/HeaderCommitment.sol";
import {ToyStorage} from "../src/ToyStorage.sol";
import {MinimalRequestRouter} from "../src/MinimalRequestRouter.sol";
import {MinimalFulfillment} from "../src/MinimalFulfillment.sol";
import {MockConsumer} from "../src/MockConsumer.sol";

/// @notice Anvil stack for header commitment + MPT demo (mock verifier).
contract DeployHeaderMptLocal is Script {
    bytes32 constant UPDATER_VKEY = bytes32(uint256(0x0a01));

    function run() external {
        vm.startBroadcast();
        MockSP1Verifier verifier = new MockSP1Verifier();
        HeaderCommitment headers = new HeaderCommitment(address(verifier), UPDATER_VKEY);
        ToyStorage toy = new ToyStorage();
        toy.setValue(42);
        MinimalRequestRouter router = new MinimalRequestRouter();
        MinimalFulfillment fulfillment = new MinimalFulfillment(address(verifier), address(router));
        MockConsumer consumer = new MockConsumer();
        vm.stopBroadcast();

        console2.log("MockSP1Verifier", address(verifier));
        console2.log("HeaderCommitment", address(headers));
        console2.log("ToyStorage", address(toy));
        console2.log("MinimalRequestRouter", address(router));
        console2.log("MinimalFulfillment", address(fulfillment));
        console2.log("MockConsumer", address(consumer));
        console2.log("UPDATER_VKEY");
        console2.logBytes32(UPDATER_VKEY);
    }
}
