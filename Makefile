-include .env
export

.PHONY: build test abi deploy upgrade

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
