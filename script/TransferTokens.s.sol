// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MockToken.sol";

contract TransferTokens is Script {
    function run() external {
        vm.startBroadcast();
        MockToken token = MockToken(0x5FbDB2315678afecb367f032d93F642f64180aa3);
        token.transfer(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 10000 * 10 ** 18);
        vm.stopBroadcast();
    }
}
