// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {SP1VerifierGateway} from "@sp1-contracts/SP1VerifierGateway.sol";
import {SP1Verifier as SP1VerifierGroth16} from "@sp1-contracts/v6.1.0/SP1VerifierGroth16.sol";
import {MinimalRequestRouter} from "../src/MinimalRequestRouter.sol";
import {MinimalFulfillment} from "../src/MinimalFulfillment.sol";
import {MockConsumer} from "../src/MockConsumer.sol";

/// @notice Deploy Phase 0 app stack against the official SP1VerifierGateway + Groth16 verifier.
/// @dev Milestone B: no MockSP1Verifier. Route must match the proof selector from sp1-sdk Groth16.
contract DeploySp1Local is Script {
    function run() external {
        uint256 pk = vm.envOr(
            "PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        SP1VerifierGateway gateway = new SP1VerifierGateway(deployer);
        SP1VerifierGroth16 verifier = new SP1VerifierGroth16();
        gateway.addRoute(address(verifier));

        MinimalRequestRouter router = new MinimalRequestRouter();
        MinimalFulfillment fulfillment = new MinimalFulfillment(address(router), address(gateway));
        router.setFulfillment(address(fulfillment));
        MockConsumer consumer = new MockConsumer();

        console2.log("SP1VerifierGateway", address(gateway));
        console2.log("SP1VerifierGroth16", address(verifier));
        console2.log("MinimalRequestRouter", address(router));
        console2.log("MinimalFulfillment", address(fulfillment));
        console2.log("MockConsumer", address(consumer));
        console2.log("VERIFIER_HASH");
        console2.logBytes32(verifier.VERIFIER_HASH());

        vm.stopBroadcast();
    }
}
