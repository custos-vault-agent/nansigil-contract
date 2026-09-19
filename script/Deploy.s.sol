// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {NanSigil} from "../src/NanSigil.sol";
import {NanSigilProxy} from "../src/NanSigilProxy.sol";

/// @notice Deploys NanSigil (implementation + UUPS proxy) and records the addresses in
///         DEPLOYMENT_FILE (default deployments/anvil.json). ATTESTOR_ADDRESS defaults
///         to the deployer.
contract DeployScript is Script {
    using stdJson for string;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address attestor = vm.envOr("ATTESTOR_ADDRESS", deployer);
        string memory file = vm.envOr("DEPLOYMENT_FILE", string("deployments/anvil.json"));

        vm.startBroadcast(deployerKey);
        address implementation = address(new NanSigil());
        address proxy = address(
            new NanSigilProxy(implementation, abi.encodeCall(NanSigil.initialize, (deployer, attestor)))
        );
        vm.stopBroadcast();

        string memory json = "deployment";
        vm.serializeAddress(json, "nansigil", proxy);
        vm.serializeAddress(json, "nansigilImplementation", implementation);
        string memory out = vm.serializeAddress(json, "attestor", attestor);
        vm.writeJson(out, file);

        console2.log("NanSigil proxy", proxy);
        console2.log("implementation", implementation);
        console2.log("attestor", attestor);
    }
}
