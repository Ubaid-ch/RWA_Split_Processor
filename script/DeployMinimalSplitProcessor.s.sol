// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MinimalSplitProcessor} from "../src/MinimalSplitProcessor.sol";

contract DeployMinimalSplitProcessor is Script {
    // Replace this with your actual company wallet
    address constant COMPANY_WALLET = 0x1b30Cf0Ce6e55fBbD6560C1Fc5447dB489A3883c;

    function run() external {
        // Load private key from env (from .env file or command line)
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        MinimalSplitProcessor processor = new MinimalSplitProcessor(COMPANY_WALLET);

        console.log("MinimalSplitProcessor deployed at:", address(processor));
        console.log("Company wallet:", processor.companyWallet());
        console.log("Company fee (bps):", processor.companyFeeBps());

        vm.stopBroadcast();
    }
}
