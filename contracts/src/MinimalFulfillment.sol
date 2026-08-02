// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISP1Verifier} from "./interfaces/ISP1Verifier.sol";
import {ICoprocessorConsumer} from "./interfaces/ICoprocessorConsumer.sol";
import {MinimalRequestRouter} from "./MinimalRequestRouter.sol";

/// @notice Phase 0 fulfillment: vendor-compatible verifyProof → callback.
contract MinimalFulfillment {
    /// @dev Must match lib PublicValuesStruct field order.
    struct PublicValues {
        uint64 a;
        uint64 b;
        uint64 sum;
    }

    MinimalRequestRouter public immutable router;
    ISP1Verifier public immutable verifier;

    event Fulfilled(uint256 indexed requestId, bytes journal, address fulfiller);
    event BountyPaid(uint256 indexed requestId, address fulfiller, uint256 amount);

    error UnknownRequest();
    error AlreadyFulfilled();
    error PublicValuesMismatch();
    error CallbackFailed();

    constructor(address router_, address verifier_) {
        router = MinimalRequestRouter(router_);
        verifier = ISP1Verifier(verifier_);
    }

    function fulfill(uint256 requestId, bytes calldata publicValues, bytes calldata proof)
        external
    {
        (
            bytes32 programVKey,
            uint64 a,
            uint64 b,
            address callback,
            ,
            ,
            bool fulfilled,
            bool exists
        ) = _loadRequest(requestId);

        if (!exists) revert UnknownRequest();
        if (fulfilled) revert AlreadyFulfilled();

        PublicValues memory pv = abi.decode(publicValues, (PublicValues));
        if (pv.a != a || pv.b != b) revert PublicValuesMismatch();
        // Match guest wrapping_add policy.
        uint64 expectedSum;
        unchecked {
            expectedSum = a + b;
        }
        if (pv.sum != expectedSum) revert PublicValuesMismatch();

        verifier.verifyProof(programVKey, publicValues, proof);

        uint256 paidBounty = router.markFulfilled(requestId);

        (bool ok,) = callback.call(
            abi.encodeWithSelector(ICoprocessorConsumer.receiveCoprocessorResult.selector, publicValues)
        );
        if (!ok) revert CallbackFailed();

        if (paidBounty > 0) {
            (bool paid,) = payable(msg.sender).call{value: paidBounty}("");
            require(paid, "bounty transfer failed");
            emit BountyPaid(requestId, msg.sender, paidBounty);
        }

        emit Fulfilled(requestId, publicValues, msg.sender);
    }

    function _loadRequest(uint256 requestId)
        internal
        view
        returns (
            bytes32 programVKey,
            uint64 a,
            uint64 b,
            address callback,
            address requester,
            uint256 bounty,
            bool fulfilled,
            bool exists
        )
    {
        (programVKey, a, b, callback, requester, bounty, fulfilled, exists) = router.requests(requestId);
    }

    receive() external payable {}
}
