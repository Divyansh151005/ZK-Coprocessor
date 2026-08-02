// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Phase 1 program registry: programId → ELF hash + SP1 vkey.
contract ProgramRegistry {
    struct Program {
        bytes32 elfHash;
        bytes32 programVKey;
        string contentUri;
        bool active;
        address registrant;
    }

    mapping(bytes32 => Program) public programs;

    event ProgramRegistered(
        bytes32 indexed programId, bytes32 elfHash, bytes32 programVKey, string contentUri, address registrant
    );
    event ProgramDeprecated(bytes32 indexed programId);

    error AlreadyRegistered();
    error UnknownProgram();
    error InactiveProgram();

    function register(bytes32 elfHash, bytes32 programVKey, string calldata contentUri)
        external
        returns (bytes32 programId)
    {
        programId = keccak256(abi.encodePacked(programVKey, elfHash));
        if (programs[programId].registrant != address(0)) revert AlreadyRegistered();
        programs[programId] = Program({
            elfHash: elfHash,
            programVKey: programVKey,
            contentUri: contentUri,
            active: true,
            registrant: msg.sender
        });
        emit ProgramRegistered(programId, elfHash, programVKey, contentUri, msg.sender);
    }

    function deprecate(bytes32 programId) external {
        Program storage p = programs[programId];
        if (p.registrant == address(0)) revert UnknownProgram();
        require(msg.sender == p.registrant, "not registrant");
        p.active = false;
        emit ProgramDeprecated(programId);
    }

    function requireActive(bytes32 programId) external view returns (bytes32 programVKey, bytes32 elfHash) {
        Program storage p = programs[programId];
        if (p.registrant == address(0)) revert UnknownProgram();
        if (!p.active) revert InactiveProgram();
        return (p.programVKey, p.elfHash);
    }
}
