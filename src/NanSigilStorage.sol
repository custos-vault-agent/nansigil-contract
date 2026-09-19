// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct Attestation {
    bytes32 attestHash;
    bytes signature;
    uint64 timestamp; // from the signed payload; a submission must be newer than this
}

/// @custom:storage-location erc7201:nansigil.storage
struct NanSigilLayout {
    address upgradeAuthority;
    address attestor; // signs payloads off-chain
    mapping(address wallet => Attestation) attestations;
}

library NanSigilStorage {
    /// @dev keccak256(abi.encode(uint256(keccak256("nansigil.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SLOT = 0xaf53f6f8243e5ea69841e6e21cb3adbb49243ff6cc4df66129af3ee99d9c1f00;

    function layout() internal pure returns (NanSigilLayout storage $) {
        assembly {
            $.slot := SLOT
        }
    }
}
