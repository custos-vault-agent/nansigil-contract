// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import {
    AttestationInvalid,
    AttestationStale,
    NanSigil,
    NotUpgradeAuthority,
    ZeroAddress
} from "../src/NanSigil.sol";
import {NanSigilProxy} from "../src/NanSigilProxy.sol";
import {NanSigilStorage} from "../src/NanSigilStorage.sol";

contract NanSigilTest is Test {
    NanSigil internal sigil;
    address internal implementation;

    address internal authority = makeAddr("authority");
    address internal relayer = makeAddr("relayer");
    address internal alice = makeAddr("alice");
    uint256 internal attestorKey = 0xA77E5;
    address internal attestorAddr;

    function setUp() public {
        attestorAddr = vm.addr(attestorKey);
        implementation = address(new NanSigil());
        sigil = NanSigil(
            address(
                new NanSigilProxy(
                    implementation, abi.encodeCall(NanSigil.initialize, (authority, attestorAddr))
                )
            )
        );
        vm.warp(1_700_000_000);
    }

    function _hash(address wallet, string memory label, int256 pnl, uint16 winRate, uint64 ts)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(wallet, label, pnl, winRate, ts));
    }

    function _signWith(uint256 key, bytes32 hash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, MessageHashUtils.toEthSignedMessageHash(hash));
        return abi.encodePacked(r, s, v);
    }

    function _submit(uint256 key, address wallet, string memory label, int256 pnl, uint16 winRate, uint64 ts)
        internal
    {
        bytes memory sig = _signWith(key, _hash(wallet, label, pnl, winRate, ts));
        vm.prank(relayer);
        sigil.submit(wallet, label, pnl, winRate, ts, sig);
    }

    /* ------------------------------ submit ------------------------------- */

    function test_anyoneCanRelayAttestorSignedPayload() public {
        uint64 ts = uint64(block.timestamp);
        _submit(attestorKey, alice, "Smart Trader", 42_000, 61, ts);

        (bool valid, address signer) = sigil.verify(alice, "Smart Trader", 42_000, 61, ts);
        assertTrue(valid);
        assertEq(signer, attestorAddr);
        (bytes32 h, uint64 storedTs) = sigil.latest(alice);
        assertEq(h, _hash(alice, "Smart Trader", 42_000, 61, ts));
        assertEq(storedTs, ts);
    }

    function test_wrongSignerReverts() public {
        vm.expectRevert(AttestationInvalid.selector);
        _submit(0xB0B, alice, "Smart Trader", 42_000, 61, uint64(block.timestamp));
    }

    function test_replayOfOlderOrSamePayloadReverts() public {
        uint64 ts = uint64(block.timestamp);
        _submit(attestorKey, alice, "Fund", 90_000, 65, ts);

        vm.expectRevert(AttestationStale.selector);
        _submit(attestorKey, alice, "Smart Trader", 42_000, 61, ts);
        vm.expectRevert(AttestationStale.selector);
        _submit(attestorKey, alice, "Smart Trader", 42_000, 61, ts - 1);
    }

    function test_futureTimestampBeyondSkewReverts() public {
        vm.expectRevert(AttestationStale.selector);
        _submit(attestorKey, alice, "Fund", 1, 1, uint64(block.timestamp + 6 minutes));
        _submit(attestorKey, alice, "Fund", 1, 1, uint64(block.timestamp + 4 minutes)); // within skew
    }

    function test_newerPayloadSupersedesOlder() public {
        uint64 ts = uint64(block.timestamp);
        _submit(attestorKey, alice, "Smart Trader", 42_000, 61, ts);
        _submit(attestorKey, alice, "Fund", 90_000, 65, ts + 1);

        (bool validOld,) = sigil.verify(alice, "Smart Trader", 42_000, 61, ts);
        (bool validNew,) = sigil.verify(alice, "Fund", 90_000, 65, ts + 1);
        assertFalse(validOld);
        assertTrue(validNew);
    }

    function test_walletsAreIndependent() public {
        uint64 ts = uint64(block.timestamp);
        address bob = makeAddr("bob");
        _submit(attestorKey, alice, "Fund", 1, 1, ts);
        (, uint64 bobTs) = sigil.latest(bob);
        assertEq(bobTs, 0);
        _submit(attestorKey, bob, "Whale", 2, 2, ts); // same ts as alice's is fine: per-wallet cursor
    }

    /* ------------------------------ verify ------------------------------- */

    function test_verifyWrongPlaintextReturnsFalse() public {
        uint64 ts = uint64(block.timestamp);
        _submit(attestorKey, alice, "Smart Trader", 42_000, 61, ts);
        (bool valid, address signer) = sigil.verify(alice, "Fund", 42_000, 61, ts);
        assertFalse(valid);
        assertEq(signer, address(0));
    }

    function test_verifyFailsAfterAttestorRotation() public {
        uint64 ts = uint64(block.timestamp);
        _submit(attestorKey, alice, "Fund", 1, 1, ts);
        vm.prank(authority);
        sigil.setAttestor(makeAddr("newAttestor"));
        (bool valid,) = sigil.verify(alice, "Fund", 1, 1, ts);
        assertFalse(valid); // old signature no longer matches the current attestor
    }

    /* ------------------------------- admin ------------------------------- */

    function test_adminOnlyUpgradeAuthority() public {
        vm.prank(alice);
        vm.expectRevert(NotUpgradeAuthority.selector);
        sigil.setAttestor(alice);
        vm.prank(alice);
        vm.expectRevert(NotUpgradeAuthority.selector);
        sigil.transferUpgradeAuthority(alice);
        vm.prank(alice);
        vm.expectRevert(NotUpgradeAuthority.selector);
        sigil.upgradeToAndCall(implementation, "");
    }

    function test_transferUpgradeAuthority() public {
        vm.prank(authority);
        sigil.transferUpgradeAuthority(alice);
        assertEq(sigil.upgradeAuthority(), alice);
        vm.prank(authority);
        vm.expectRevert(NotUpgradeAuthority.selector);
        sigil.setAttestor(alice);
    }

    function test_zeroAddressesRejected() public {
        vm.prank(authority);
        vm.expectRevert(ZeroAddress.selector);
        sigil.setAttestor(address(0));
        vm.expectRevert(); // InvalidInitialization on the implementation
        NanSigil(implementation).initialize(authority, attestorAddr);
    }

    /* ------------------------------ storage ------------------------------ */

    function test_storageSlotMatchesErc7201() public pure {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("nansigil.storage")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(NanSigilStorage.SLOT, expected);
    }
}
