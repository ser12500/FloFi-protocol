// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {LendingPool} from "../src/LendingPool.sol";
import "../src/MockToken.sol";
import {MockPriceFeed} from "test/LendingPoolTest.t.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        MockToken token = new MockToken();
        // Для Sepolia, Arbitrum, Optimism  Chainlink ETH/USD:
        // - Sepolia: 0x694AA1769357215DE4FAC081bf1f309aDC325306
        // - Arbitrum: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612
        // - Optimism: 0x13e3Ee699D1909E989722E753853AE30b17e08c5
        address priceFeed = address(new MockPriceFeed()); // Для Anvil
        LendingPool pool = new LendingPool(address(token), priceFeed);
        vm.stopBroadcast();

        console.log("MockToken deployed at:", address(token));
        console.log("MockPriceFeed deployed at:", address(priceFeed));
        console.log("LendingPool deployed at:", address(pool));
    }
}
