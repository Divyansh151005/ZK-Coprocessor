// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "./interfaces/ISP1Verifier.sol";
import {RequestRouter} from "./RequestRouter.sol";
import {CallbackDispatcher} from "./CallbackDispatcher.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @notice Phase 1 fulfillment adapter around vendor ISP1Verifier.
contract Fulfillment {
    /// @dev Phase 1 journal binds requestId for replay protection.
    struct PublicValuesV1 {
        uint256 requestId;
        uint64 a;
        uint64 b;
        uint64 sum;
    }

    RequestRouter public immutable router;
    ISP1Verifier public immutable verifier;
    CallbackDispatcher public immutable dispatcher;

    event Fulfilled(uint256 indexed requestId, bytes journal, address fulfiller);
    event BountyPaid(uint256 indexed requestId, address fulfiller, uint256 amount);

    error PublicValuesMismatch();
    error CallbackFailed();

    constructor(address router_, address verifier_, address dispatcher_) {
        router = RequestRouter(router_);
        verifier = ISP1Verifier(verifier_);
        dispatcher = CallbackDispatcher(dispatcher_);
    }

    function fulfill(uint256 requestId, bytes calldata publicValues, bytes calldata proof) external {
        router.assertFulfiller(msg.sender);

        (
            ,
            bytes32 programVKey,
            address callback,
            ,
            ,
            ,
            ,
            RequestRouter.Status status,
            bytes memory input
        ) = router.getRequest(requestId);
        require(status == RequestRouter.Status.Pending, "not pending");

        PublicValuesV1 memory pv = abi.decode(publicValues, (PublicValuesV1));
        if (pv.requestId != requestId) revert PublicValuesMismatch();

        // Phase 1 input encoding for add guest: abi.encode(uint64 a, uint64 b)
        (uint64 a, uint64 b) = abi.decode(input, (uint64, uint64));
        if (pv.a != a || pv.b != b) revert PublicValuesMismatch();
        uint64 expectedSum;
        unchecked {
            expectedSum = a + b;
        }
        if (pv.sum != expectedSum) revert PublicValuesMismatch();

        verifier.verifyProof(programVKey, publicValues, proof);

        uint256 bounty = router.markFulfilled(requestId);
        bool ok = dispatcher.dispatch(callback, publicValues);
        if (!ok) revert CallbackFailed();

        if (bounty > 0) {
            address token = router.bountyToken(requestId);
            if (token == address(0)) {
                (bool paid,) = payable(msg.sender).call{value: bounty}("");
                require(paid, "bounty transfer failed");
            } else {
                require(IERC20(token).transfer(msg.sender, bounty), "erc20 bounty");
            }
            emit BountyPaid(requestId, msg.sender, bounty);
        }
        emit Fulfilled(requestId, publicValues, msg.sender);
    }

    receive() external payable {}
}
