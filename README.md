# nansigil-contract

The on-chain half of NanSigil: wallet reputation attestations signed off-chain by an attestor and relayed on-chain by anyone. Any contract can verify one.

- `src/NanSigil.sol`: UUPS implementation. `submit` relays an attestor-signed payload, keyed by wallet, newer-than-stored only. `verify` recomputes the hash from plaintext and checks the signer. `latest` returns the stored hash and timestamp.
- `src/interfaces/INanSigil.sol`: what a consuming contract imports.
- `src/NanSigilProxy.sol`: the permanent address.

The signed payload is `keccak256(abi.encode(wallet, label, pnl, winRate, timestamp))` under EIP-191 (`toEthSignedMessageHash`). The signing service lives in `custos-attestation`.

```bash
forge test
cp .env.example .env && make deploy      # writes deployments/anvil.json
make abi                                 # abi/NanSigil.json for clients
```

Consumers bind an attestation to their own records: Custos, for example, looks up `latest(agent.creator)`.
