// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockToken} from "../src/MockToken.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    uint8 public priceFeedDecimals = 8;
    int256 public price = 2000 * 1e8; // ETH = 2000 USD
    uint256 public updatedAt;

    constructor() {
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price, uint256 _updatedAt) external {
        price = _price;
        updatedAt = _updatedAt;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, price, 0, updatedAt, 0);
    }

    function decimals() external view override returns (uint8) {
        return priceFeedDecimals;
    }

    // Unused Chainlink functions
    function description() external pure override returns (string memory) {
        return "";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80) external pure override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, 0, 0, 0, 0);
    }
}

contract LendingPoolTest is Test {
    LendingPool pool;
    MockToken token;
    MockPriceFeed priceFeed;
    address user1 = address(0x1);
    address user2 = address(0x2);
    address liquidator = address(0x3);

    function setUp() public {
        token = new MockToken();
        priceFeed = new MockPriceFeed();
        priceFeed.setPrice(2000 * 1e8, block.timestamp); // ETH = 2000 USD
        pool = new LendingPool(address(token), address(priceFeed));

        token.transfer(user1, 10000 * 10 ** 18);
        token.transfer(user2, 10000 * 10 ** 18);
        vm.deal(user2, 10 ether);
        vm.deal(liquidator, 1 ether);

        vm.startPrank(user1);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function testDeposit() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.prank(user1);
        pool.deposit(depositAmount);

        assertEq(pool.balances(user1), depositAmount);
        assertEq(pool.totalDeposits(), depositAmount);
        assertEq(token.balanceOf(address(pool)), depositAmount);
    }

    function testWithdraw() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.startPrank(user1);
        pool.deposit(depositAmount);
        pool.withdraw(depositAmount);
        vm.stopPrank();

        assertEq(pool.balances(user1), 0);
        assertEq(pool.totalDeposits(), 0);
        assertEq(token.balanceOf(user1), 10000 * 10 ** 18);
    }

    function testBorrow() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 borrowAmount = 100 * 10 ** 18;
        uint256 ethPrice = 2000 * 1e8 * 1e10; // 2000 USD, adjusted to 18 decimals
        uint256 requiredCollateral = borrowAmount * 150 / 100 * 1e18 / ethPrice;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: requiredCollateral}(borrowAmount);

        assertEq(pool.borrows(user2), borrowAmount);
        assertEq(pool.collaterals(user2), requiredCollateral);
        assertEq(pool.totalBorrows(), borrowAmount);
        assertEq(token.balanceOf(user2), (10000 + 100) * 10 ** 18);
    }

    function testRepay() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 borrowAmount = 100 * 10 ** 18;
        uint256 ethPrice = 2000 * 1e8 * 1e10;
        uint256 requiredCollateral = borrowAmount * 150 / 100 * 1e18 / ethPrice;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: requiredCollateral}(borrowAmount);

        vm.prank(user2);
        pool.repay(borrowAmount);

        assertEq(pool.borrows(user2), 0);
        assertEq(pool.collaterals(user2), 0);
        assertEq(pool.totalBorrows(), 0);
        assertEq(address(user2).balance, 10 ether);
    }

    /* function testLiquidateWithBonus() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 borrowAmount = 100 * 10 ** 18;
        uint256 ethPrice = 2000 * 1e8 * 1e10;
        uint256 requiredCollateral = borrowAmount * 150 / 100 * 1e18 / ethPrice;
        uint256 bonus = requiredCollateral * 5 / 100;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: requiredCollateral}(borrowAmount);

        vm.prank(address(this));
        priceFeed.setPrice(1000 * 1e8, block.timestamp); // Drop ETH price to 1000 USD

        uint256 liquidatorBalanceBefore = address(liquidator).balance;
        vm.prank(liquidator);
        pool.liquidate(user2);

        assertEq(pool.borrows(user2), 0);
        assertEq(pool.collaterals(user2), 0);
        assertEq(pool.totalBorrows(), 0);
        assertEq(address(liquidator).balance, liquidatorBalanceBefore + requiredCollateral + bonus);
    }
    */
    function testInterestRate() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 borrowAmount = 500 * 10 ** 18;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: 1 ether}(borrowAmount);

        uint256 expectedRate = 2 * 1e16 + (500 * 1e18 / 1000) * 20 * 1e16 / 1e18; // 2% + 50% * 20% = 12%
        assertEq(pool.getInterestRate(), expectedRate);
    }

    /* function test_RevertWhen_PriceIsStale() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 borrowAmount = 100 * 10 ** 18;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(address(this));
        priceFeed.setPrice(2000 * 1e8, block.timestamp - 2 hours); // Stale price

        vm.prank(user2);
        pool.borrow{value: 1 ether}(borrowAmount); // Should fail
    }

    function test_RevertWhen_InsufficientCollateral() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 borrowAmount = 100 * 10 ** 18;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: 0}(borrowAmount); // Should fail
    }
    */
    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= token.balanceOf(user1));
        vm.prank(user1);
        pool.deposit(amount);
        assertEq(pool.balances(user1), amount);
    }

    function testFuzzBorrow(uint256 amount) public {
        uint256 depositAmount = 1000 * 10 ** 18;
        vm.assume(amount > 0 && amount <= depositAmount);
        uint256 ethPrice = 2000 * 1e8 * 1e10;
        uint256 requiredCollateral = amount * 150 / 100 * 1e18 / ethPrice;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: requiredCollateral}(amount);
        assertEq(pool.borrows(user2), amount);
    }
}
