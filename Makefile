-include .env
export

.PHONY: build test abi deploy upgrade verify

build:
	forge build

test:
	forge test -vvv

abi: build
	mkdir -p abi
	jq '.abi' out/NanSigil.sol/NanSigil.json > abi/NanSigil.json

deploy: build
	mkdir -p deployments
	forge script script/Deploy.s.sol:DeployScript --rpc-url $(RPC_URL) --broadcast -vvvv

upgrade: build
	forge script script/Upgrade.s.sol:UpgradeScript --rpc-url $(RPC_URL) --broadcast -vvvv

# Verifies NanSigil on a block explorer. Addresses come from DEPLOYMENT_FILE and
# the constructor arguments from the chain. VERIFIER defaults to sourcify, which
# needs no key; an Etherscan-style or Blockscout explorer needs VERIFIER,
# VERIFIER_URL and usually VERIFIER_API_KEY.
#
# `initialize` received the deployer as upgrade authority and ATTESTOR_ADDRESS as
# attestor. Both can change afterwards, so pass INIT_AUTHORITY or INIT_ATTESTOR
# when they did. DRY_RUN=1 prints the arguments and verifies nothing.
verify: build
	@set -eu; \
	file=$${DEPLOYMENT_FILE:-deployments/anvil.json}; \
	test -f "$$file" || { echo "$$file not found"; exit 1; }; \
	impl=$$(jq -r .nansigilImplementation "$$file"); \
	proxy=$$(jq -r .nansigil "$$file"); \
	chain=$$(cast chain-id --rpc-url $(RPC_URL)); \
	flags="--chain $$chain --verifier $${VERIFIER:-sourcify} --watch"; \
	if [ -n "$${VERIFIER_URL:-}" ]; then flags="$$flags --verifier-url $$VERIFIER_URL"; fi; \
	if [ -n "$${VERIFIER_API_KEY:-}" ]; then flags="$$flags --verifier-api-key $$VERIFIER_API_KEY"; fi; \
	authority=$${INIT_AUTHORITY:-$$(cast call $$proxy "upgradeAuthority()(address)" --rpc-url $(RPC_URL))}; \
	attestor=$${INIT_ATTESTOR:-$$(cast call $$proxy "attestor()(address)" --rpc-url $(RPC_URL))}; \
	init=$$(cast calldata "initialize(address,address)" $$authority $$attestor); \
	args=$$(cast abi-encode "constructor(address,bytes)" $$impl $$init); \
	echo "==> NanSigil at $$impl"; \
	echo "==> NanSigilProxy at $$proxy"; \
	echo "    args $$args"; \
	if [ -n "$${DRY_RUN:-}" ]; then exit 0; fi; \
	forge verify-contract $$impl src/NanSigil.sol:NanSigil $$flags; \
	forge verify-contract $$proxy src/NanSigilProxy.sol:NanSigilProxy --constructor-args $$args $$flags
