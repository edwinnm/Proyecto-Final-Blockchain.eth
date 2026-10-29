// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";

contract Deploy is Script {
    function run() external returns (CertificateRegistry registry) {
        vm.startBroadcast();
        registry = new CertificateRegistry(msg.sender);
        registry.grantRole(registry.ISSUER_ROLE(), msg.sender);
        vm.stopBroadcast();
        console.log("CertificateRegistry:", address(registry));
    }
}
