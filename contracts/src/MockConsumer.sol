// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICoprocessorConsumer} from "./interfaces/ICoprocessorConsumer.sol";

/// @notice Test consumer that records the last verified journal.
contract MockConsumer is ICoprocessorConsumer {
    bytes public lastJournal;
    uint256 public receiveCount;

    event ResultReceived(bytes journal);

    function receiveCoprocessorResult(bytes calldata journal) external override {
        lastJournal = journal;
        receiveCount += 1;
        emit ResultReceived(journal);
    }
}
