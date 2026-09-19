// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Wallet reputation attestations, signed off-chain by an attestor and relayed
///         on-chain by anyone. This is the surface a consuming contract needs.
interface INanSigil {
    /// @notice Latest attestation for `wallet`: the hash of its plaintext and when it was signed.
    ///         `timestamp == 0` means never attested.
    function latest(address wallet) external view returns (bytes32 attestHash, uint64 timestamp);

    /// @notice Recomputes the hash from plaintext and checks it against what is stored
    ///         and who signed it. `valid` is true only if both match the current attestor.
    function verify(address wallet, string calldata label, int256 pnl, uint16 winRate, uint64 timestamp)
        external
        view
        returns (bool valid, address signer);

    /// @notice Relays an attestor-signed payload. Callable by anyone; must be newer than
    ///         the stored one for this wallet.
    function submit(
        address wallet,
        string calldata label,
        int256 pnl,
        uint16 winRate,
        uint64 timestamp,
        bytes calldata signature
    ) external;

    function attestor() external view returns (address);
}
