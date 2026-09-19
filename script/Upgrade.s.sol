// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {NanSigil} from "../src/NanSigil.sol";

/// @notice Deploys a new implementation and upgrades the proxy recorded in DEPLOYMENT_FILE.
contract UpgradeScript is Script {
    using stdJson for string;

    function run() external {
        uint256 authorityKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        string memory file = vm.envOr("DEPLOYMENT_FILE", string("deployments/anvil.json"));
        address proxy = vm.readFile(file).readAddress(".nansigil");

        vm.startBroadcast(authorityKey);
        address implementation = address(new NanSigil());
        NanSigil(proxy).upgradeToAndCall(implementation, "");
        vm.stopBroadcast();

        vm.writeJson(vm.toString(implementation), file, ".nansigilImplementation");
        console2.log("upgraded", proxy, "to", implementation);
    }
}
