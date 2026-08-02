// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProgramRegistry} from "./ProgramRegistry.sol";
import {ICoprocessorConsumer} from "./interfaces/ICoprocessorConsumer.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @notice Phase 1 request router with lifecycle + ETH bounty escrow.
contract RequestRouter {
    enum Status {
        None,
        Pending,
        Fulfilled,
        Expired,
        Refunded
    }

    struct Request {
        bytes32 programId;
        bytes32 programVKey;
        bytes input;
        address callback;
        address requester;
        uint256 bounty;
        uint64 createdAt;
        uint64 expiresAt;
        Status status;
    }

    ProgramRegistry public immutable registry;
    address public fulfillment;
    address public owner;
    mapping(address => bool) public allowedFulfillers;
    bool public allowlistEnabled;

    uint256 public nextRequestId;
    mapping(uint256 => Request) public requests;
    /// @notice Bounty token per request; `address(0)` means native ETH.
    mapping(uint256 => address) public bountyToken;
    uint64 public defaultTimeout = 1 days;

    event ComputationRequested(
        uint256 indexed requestId,
        bytes32 indexed programId,
        bytes32 programVKey,
        bytes input,
        address callback,
        address requester,
        uint256 bounty,
        uint64 expiresAt
    );
    event RequestFulfilled(uint256 indexed requestId, address fulfiller);
    event RequestRefunded(uint256 indexed requestId, address requester, uint256 amount);
    event FulfillerUpdated(address indexed fulfiller, bool allowed);

    error InvalidCallback();
    error NotFulfillment();
    error NotOwner();
    error BadStatus();
    error NotExpired();
    error NotRequester();
    error FulfillerNotAllowed();
    error InvalidToken();
    error ZeroBounty();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address registry_) {
        registry = ProgramRegistry(registry_);
        owner = msg.sender;
        allowlistEnabled = true;
        allowedFulfillers[msg.sender] = true;
    }

    function setFulfillment(address fulfillment_) external onlyOwner {
        require(fulfillment == address(0) || msg.sender == owner, "set once or owner");
        fulfillment = fulfillment_;
    }

    function setAllowlistEnabled(bool enabled) external onlyOwner {
        allowlistEnabled = enabled;
    }

    function setFulfiller(address fulfiller, bool allowed) external onlyOwner {
        allowedFulfillers[fulfiller] = allowed;
        emit FulfillerUpdated(fulfiller, allowed);
    }

    function setDefaultTimeout(uint64 t) external onlyOwner {
        defaultTimeout = t;
    }

    function request(bytes32 programId, bytes calldata input, address callback, uint64 timeout)
        external
        payable
        returns (uint256 requestId)
    {
        if (callback == address(0)) revert InvalidCallback();
        (bytes32 programVKey,) = registry.requireActive(programId);
        uint64 expiresAt = uint64(block.timestamp) + (timeout == 0 ? defaultTimeout : timeout);
        requestId = ++nextRequestId;
        requests[requestId] = Request({
            programId: programId,
            programVKey: programVKey,
            input: input,
            callback: callback,
            requester: msg.sender,
            bounty: msg.value,
            createdAt: uint64(block.timestamp),
            expiresAt: expiresAt,
            status: Status.Pending
        });
        emit ComputationRequested(
            requestId, programId, programVKey, input, callback, msg.sender, msg.value, expiresAt
        );
    }

    /// @notice Escrow an ERC-20 bounty (pull via allowance) instead of ETH.
    function requestErc20(
        bytes32 programId,
        bytes calldata input,
        address callback,
        uint64 timeout,
        address token,
        uint256 amount
    ) external returns (uint256 requestId) {
        if (callback == address(0)) revert InvalidCallback();
        if (token == address(0)) revert InvalidToken();
        if (amount == 0) revert ZeroBounty();
        (bytes32 programVKey,) = registry.requireActive(programId);
        uint64 expiresAt = uint64(block.timestamp) + (timeout == 0 ? defaultTimeout : timeout);
        requestId = ++nextRequestId;
        requests[requestId] = Request({
            programId: programId,
            programVKey: programVKey,
            input: input,
            callback: callback,
            requester: msg.sender,
            bounty: amount,
            createdAt: uint64(block.timestamp),
            expiresAt: expiresAt,
            status: Status.Pending
        });
        bountyToken[requestId] = token;
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "transferFrom");
        emit ComputationRequested(
            requestId, programId, programVKey, input, callback, msg.sender, amount, expiresAt
        );
    }

    function assertFulfiller(address fulfiller) external view {
        if (allowlistEnabled && !allowedFulfillers[fulfiller]) revert FulfillerNotAllowed();
    }

    function markFulfilled(uint256 requestId) external returns (uint256 bounty) {
        if (msg.sender != fulfillment) revert NotFulfillment();
        Request storage r = requests[requestId];
        if (r.status != Status.Pending) revert BadStatus();
        r.status = Status.Fulfilled;
        bounty = r.bounty;
        r.bounty = 0;
        address token = bountyToken[requestId];
        if (bounty > 0) {
            if (token == address(0)) {
                (bool paid,) = payable(msg.sender).call{value: bounty}("");
                require(paid, "bounty forward failed");
            } else {
                require(IERC20(token).transfer(msg.sender, bounty), "erc20 forward");
            }
        }
        emit RequestFulfilled(requestId, tx.origin);
    }

    function getRequest(uint256 requestId)
        external
        view
        returns (
            bytes32 programId,
            bytes32 programVKey,
            address callback,
            address requester,
            uint256 bounty,
            uint64 createdAt,
            uint64 expiresAt,
            Status status,
            bytes memory input
        )
    {
        Request storage r = requests[requestId];
        return (
            r.programId,
            r.programVKey,
            r.callback,
            r.requester,
            r.bounty,
            r.createdAt,
            r.expiresAt,
            r.status,
            r.input
        );
    }

    function refund(uint256 requestId) external {
        Request storage r = requests[requestId];
        if (r.requester != msg.sender) revert NotRequester();
        if (r.status != Status.Pending) revert BadStatus();
        if (block.timestamp < r.expiresAt) revert NotExpired();
        r.status = Status.Refunded;
        uint256 amount = r.bounty;
        r.bounty = 0;
        address token = bountyToken[requestId];
        if (token == address(0)) {
            (bool paid,) = payable(msg.sender).call{value: amount}("");
            require(paid, "refund failed");
        } else {
            require(IERC20(token).transfer(msg.sender, amount), "erc20 refund");
        }
        emit RequestRefunded(requestId, msg.sender, amount);
    }
}
