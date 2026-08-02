// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICoprocessorConsumer} from "./interfaces/ICoprocessorConsumer.sol";

/// @notice Phase 0 minimal request router: emit ComputationRequested for orchestrator.
contract MinimalRequestRouter {
    struct Request {
        bytes32 programVKey;
        uint64 a;
        uint64 b;
        address callback;
        address requester;
        uint256 bounty;
        bool fulfilled;
        bool exists;
    }

    uint256 public nextRequestId;
    mapping(uint256 => Request) public requests;

    event ComputationRequested(
        uint256 indexed requestId,
        bytes32 indexed programVKey,
        uint64 a,
        uint64 b,
        address callback,
        address requester,
        uint256 bounty
    );

    address public fulfillment;

    error InvalidCallback();
    error NotFulfillment();
    error UnknownRequest();
    error AlreadyFulfilled();

    function setFulfillment(address fulfillment_) external {
        require(fulfillment == address(0), "fulfillment already set");
        fulfillment = fulfillment_;
    }

    function request(bytes32 programVKey, uint64 a, uint64 b, address callback)
        external
        payable
        returns (uint256 requestId)
    {
        if (callback == address(0)) revert InvalidCallback();
        requestId = ++nextRequestId;
        requests[requestId] = Request({
            programVKey: programVKey,
            a: a,
            b: b,
            callback: callback,
            requester: msg.sender,
            bounty: msg.value,
            fulfilled: false,
            exists: true
        });
        emit ComputationRequested(requestId, programVKey, a, b, callback, msg.sender, msg.value);
    }

    function markFulfilled(uint256 requestId) external returns (uint256 bounty) {
        if (msg.sender != fulfillment) revert NotFulfillment();
        Request storage r = requests[requestId];
        if (!r.exists) revert UnknownRequest();
        if (r.fulfilled) revert AlreadyFulfilled();
        r.fulfilled = true;
        bounty = r.bounty;
        r.bounty = 0;
        if (bounty > 0) {
            (bool paid,) = payable(msg.sender).call{value: bounty}("");
            require(paid, "bounty forward failed");
        }
    }
}
