// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";
import {ICoprocessorConsumer} from "./interfaces/ICoprocessorConsumer.sol";

/// @notice Phase 1 callback dispatcher with reentrancy guard + gas stipend.
contract CallbackDispatcher is ReentrancyGuard {
    uint256 public callbackGasStipend = 200_000;
    address public owner;

    event CallbackSucceeded(address indexed target, bytes journal);
    event CallbackFailed(address indexed target, bytes journal);

    error NotOwner();

    constructor() {
        owner = msg.sender;
    }

    function setCallbackGasStipend(uint256 stipend) external {
        if (msg.sender != owner) revert NotOwner();
        callbackGasStipend = stipend;
    }

    /// @return success Whether the consumer accepted the journal.
    function dispatch(address target, bytes calldata journal) external nonReentrant returns (bool success) {
        (success,) = target.call{gas: callbackGasStipend}(
            abi.encodeWithSelector(ICoprocessorConsumer.receiveCoprocessorResult.selector, journal)
        );
        if (success) emit CallbackSucceeded(target, journal);
        else emit CallbackFailed(target, journal);
    }
}
