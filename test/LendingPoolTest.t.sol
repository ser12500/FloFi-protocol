// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockToken} from "../src/MockToken.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    uint8 public priceFeedDecimals = 8;
    int256 public price = 2000 * 1e8;
    uint256 public updatedAt;

    constructor() {
        updatedAt = block.timestamp;
    }

    function setPrice(int256 _price, uint256 _updatedAt) external {
        price = _price;
        updatedAt = _updatedAt;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (1, price, 0, updatedAt, 1);
    }

    function decimals() external view override returns (uint8) {
        return priceFeedDecimals;
    }

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
        priceFeed.setPrice(2000 * 1e8, block.timestamp);
        pool = new LendingPool(address(token), address(priceFeed));

        token.transfer(user1, 10000 * 1e18);
        token.transfer(user2, 10000 * 1e18);
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
        uint256 amount = 1000 * 1e18;
        vm.prank(user1);
        pool.deposit(amount);

        assertEq(pool.s_balances(user1), amount);
        assertEq(pool.s_totalDeposits(), amount);
        assertEq(token.balanceOf(address(pool)), amount);
    }

    function testWithdraw() public {
        uint256 amount = 1000 * 1e18;
        vm.startPrank(user1);
        pool.deposit(amount);
        pool.withdraw(amount);
        vm.stopPrank();

        assertEq(pool.s_balances(user1), 0);
        assertEq(pool.s_totalDeposits(), 0);
        assertEq(token.balanceOf(user1), 10000 * 1e18);
    }

    function testBorrow() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 borrowAmount = 100 * 1e18;
        uint256 ethPrice = 2000 * 1e8 * 1e10; // 18 decimals
        uint256 requiredCollateral = borrowAmount * 150 / 100 * 1e18 / ethPrice;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: requiredCollateral}(borrowAmount);

        assertEq(pool.s_borrows(user2), borrowAmount);
        assertEq(pool.s_collaterals(user2), requiredCollateral);
        assertEq(pool.s_totalBorrows(), borrowAmount);
        assertEq(token.balanceOf(user2), (10000 + 100) * 1e18);
    }

    function testLiquidateWithBonus() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 borrowAmount = 100 * 1e18;
        uint256 ethPrice = 2000 * 1e8 * 1e10;
        uint256 requiredCollateral = borrowAmount * 150 / 100 * 1e18 / ethPrice;
        uint256 s_totalCollateral = 2000 * 1e8 * 1e10;
        payable(address(pool)).transfer(s_totalCollateral);

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: requiredCollateral}(borrowAmount);

        vm.prank(address(this));
        priceFeed.setPrice(1000 * 1e8, block.timestamp);

        uint256 before = liquidator.balance;
        vm.prank(liquidator);
        pool.liquidate(user2);

        assertEq(pool.s_borrows(user2), 0);
        assertEq(pool.s_collaterals(user2), 0);
        assertGt(liquidator.balance, before);
    }

    function testInterestRate() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 borrowAmount = 500 * 1e18;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: 1 ether}(borrowAmount);

        uint256 expectedRate = 2 * 1e16 + (500 * 1e18 / 1000) * 20 * 1e16 / 1e18; // 2% + 50% * 20% = 12%
        assertEq(pool.getInterestRate(), expectedRate);
    }

    function test_RevertWhen_BorrowWithInsufficientCollateral() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 borrowAmount = 100 * 1e18;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        vm.expectRevert("Insufficient collateral");
        pool.borrow{value: 0}(borrowAmount);
    }

    function test_RevertWhen_DepositWhilePaused() public {
        vm.prank(user1);
        pool.pause();

        vm.prank(user2);
        vm.expectRevert("EnforcedPause()");
        pool.deposit(1000 * 1e18);
    }

    function test_RevertWhen_BorrowWhilePaused() public {
        vm.prank(user1);
        pool.deposit(1000 * 1e18);

        vm.prank(address(this));
        pool.pause();

        vm.prank(user2);
        vm.expectRevert("EnforcedPause()");
        pool.borrow{value: 1 ether}(100 * 1e18);
    }

    function testUpdateInterest() public {
        uint256 depositAmount = 1000 * 1e18;
        uint256 borrowAmount = 500 * 1e18;

        vm.prank(user1);
        pool.deposit(depositAmount);

        vm.prank(user2);
        pool.borrow{value: 1 ether}(borrowAmount);

        skip(365 days);
        pool.updateInterest(user1);

        assertEq(pool.s_totalBorrows(), borrowAmount);
    }

    function testFuzzDeposit(uint256 amount) public {
        vm.assume(amount > 0 && amount <= token.balanceOf(user1));
        vm.prank(user1);
        pool.deposit(amount);
        assertEq(pool.s_balances(user1), amount);
    }

    function testFuzzWithdraw(uint256 amount) public {
        vm.assume(amount > 0 && amount <= token.balanceOf(user1));
        vm.startPrank(user1);
        pool.deposit(amount);
        pool.withdraw(amount);
        vm.stopPrank();

        assertEq(pool.s_balances(user1), 0);
        assertEq(token.balanceOf(user1), 10000 * 1e18);
    }

    function testFuzzBorrow(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1000 * 1e18);
        vm.prank(user1);
        pool.deposit(1000 * 1e18);

        uint256 ethPrice = 2000 * 1e8 * 1e10;
        uint256 requiredCollateral = amount * 150 / 100 * 1e18 / ethPrice;

        vm.prank(user2);
        pool.borrow{value: requiredCollateral}(amount);

        assertEq(pool.s_borrows(user2), amount);
    }
}
