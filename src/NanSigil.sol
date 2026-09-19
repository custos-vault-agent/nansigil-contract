// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {INanSigil} from "./interfaces/INanSigil.sol";
import {Attestation, NanSigilLayout, NanSigilStorage} from "./NanSigilStorage.sol";

error NotUpgradeAuthority();
error ZeroAddress();
/// @dev Signature does not recover to the current attestor.
error AttestationInvalid();
/// @dev Payload timestamp is not newer than the stored one (replay), or is in the future.
error AttestationStale();

event AttestorChanged(address indexed oldAttestor, address indexed newAttestor);
event UpgradeAuthorityChanged(address indexed oldAuthority, address indexed newAuthority);
/// @dev Full plaintext, so an indexer can serve `verify` inputs without a side channel.
event AttestationSubmitted(
    address indexed wallet, string label, int256 pnl, uint16 winRate, uint64 timestamp, bytes32 attestHash
);

/// @title NanSigil: wallet reputation, signed off-chain and verifiable by any contract.
///
/// @dev Pull model, like Pyth's `updatePriceFeeds`: the attestor signs
///      `keccak256(abi.encode(wallet, label, pnl, winRate, timestamp))` off-chain and
///      whoever holds the payload relays it. Storage is keyed by wallet, so an
///      attestation is about a person, not about any one consumer's object; a
///      consumer binds it to its own records (e.g. "this agent's creator") itself.
///
///      Not trustless: one attestor key, rotated by the upgrade authority.
contract NanSigil is INanSigil, Initializable, UUPSUpgradeable {
    /// @dev Skew tolerated on the payload timestamp; the attestor's clock vs. the chain's.
    uint64 internal constant MAX_FUTURE = 5 minutes;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyUpgradeAuthority() {
        if (msg.sender != NanSigilStorage.layout().upgradeAuthority) revert NotUpgradeAuthority();
        _;
    }

    function initialize(address upgradeAuthority_, address attestor_) external initializer {
        if (upgradeAuthority_ == address(0) || attestor_ == address(0)) revert ZeroAddress();
        NanSigilLayout storage $ = NanSigilStorage.layout();
        $.upgradeAuthority = upgradeAuthority_;
        $.attestor = attestor_;
    }

    /* ------------------------------- admin ------------------------------- */

    function setAttestor(address newAttestor) external onlyUpgradeAuthority {
        if (newAttestor == address(0)) revert ZeroAddress();
        NanSigilLayout storage $ = NanSigilStorage.layout();
        emit AttestorChanged($.attestor, newAttestor);
        $.attestor = newAttestor;
    }

    function transferUpgradeAuthority(address newAuthority) external onlyUpgradeAuthority {
        if (newAuthority == address(0)) revert ZeroAddress();
        NanSigilLayout storage $ = NanSigilStorage.layout();
        emit UpgradeAuthorityChanged($.upgradeAuthority, newAuthority);
        $.upgradeAuthority = newAuthority;
    }

    /* ----------------------------- attestations --------------------------- */

    /// @inheritdoc INanSigil
    function submit(
        address wallet,
        string calldata label,
        int256 pnl,
        uint16 winRate,
        uint64 timestamp,
        bytes calldata signature
    ) external {
        NanSigilLayout storage $ = NanSigilStorage.layout();
        Attestation storage current = $.attestations[wallet];
        if (timestamp <= current.timestamp || timestamp > block.timestamp + MAX_FUTURE) {
            revert AttestationStale();
        }

        bytes32 attestHash = _hash(wallet, label, pnl, winRate, timestamp);
        address signer = ECDSA.recoverCalldata(MessageHashUtils.toEthSignedMessageHash(attestHash), signature);
        if (signer != $.attestor) revert AttestationInvalid();

        $.attestations[wallet] =
            Attestation({attestHash: attestHash, signature: signature, timestamp: timestamp});
        emit AttestationSubmitted(wallet, label, pnl, winRate, timestamp, attestHash);
    }

    /// @inheritdoc INanSigil
    function verify(address wallet, string calldata label, int256 pnl, uint16 winRate, uint64 timestamp)
        external
        view
        returns (bool valid, address signer)
    {
        Attestation storage a = NanSigilStorage.layout().attestations[wallet];
        bytes32 attestHash = _hash(wallet, label, pnl, winRate, timestamp);
        if (attestHash != a.attestHash) return (false, address(0));

        signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(attestHash), a.signature);
        valid = signer == NanSigilStorage.layout().attestor;
    }

    /// @inheritdoc INanSigil
    function latest(address wallet) external view returns (bytes32 attestHash, uint64 timestamp) {
        Attestation storage a = NanSigilStorage.layout().attestations[wallet];
        return (a.attestHash, a.timestamp);
    }

    /* ------------------------------- views ------------------------------- */

    function attestor() external view returns (address) {
        return NanSigilStorage.layout().attestor;
    }

    function upgradeAuthority() external view returns (address) {
        return NanSigilStorage.layout().upgradeAuthority;
    }

    function version() external pure virtual returns (string memory) {
        return "1.0.0";
    }

    /* ------------------------------ internal ----------------------------- */

    function _hash(address wallet, string calldata label, int256 pnl, uint16 winRate, uint64 timestamp)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(wallet, label, pnl, winRate, timestamp));
    }

    function _authorizeUpgrade(address) internal override onlyUpgradeAuthority {}
}
