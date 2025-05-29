// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

///@author Sergey Kerhet
/// @title LendingPool - A decentralized lending and borrowing protocol with Chainlink price feeds
/// @notice Allows users to deposit tokens, borrow against ETH collateral, and liquidate undercollateralized positions
contract LendingPool is Ownable, ReentrancyGuard {
    /////////////////////
    // State Variables
    /////////////////////

    IERC20 public immutable token; // Token of the pool (e.g., DAI)
    AggregatorV3Interface public immutable priceFeed; // Chainlink ETH/USD price feed
    mapping(address => uint256) public balances; // User deposit balances
    mapping(address => uint256) public borrows; // User borrow balances
    mapping(address => uint256) public collaterals; // User ETH collateral
    uint256 public totalDeposits; // Total deposited tokens
    uint256 public totalBorrows; // Total borrowed tokens
    uint256 public constant COLLATERAL_RATIO = 150; // 150% collateralization ratio
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // Liquidation at 120% collateral value
    uint256 public constant LIQUIDATION_BONUS = 5; // 5% bonus for liquidators
    uint256 public constant BASE_RATE = 2 * 1e16; // Base interest rate: 2%
    uint256 public constant RATE_SLOPE = 20 * 1e16; // Slope for dynamic rate: 20%
    uint256 public constant MAX_PRICE_AGE = 1 hours; // Maximum age of price data

    /////////////////////
    // Events
    /////////////////////

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount, uint256 collateral);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed user, uint256 amount, uint256 bonus);

    /// @notice Initializes the lending pool with a token and Chainlink price feed
    /// @param _token Address of the ERC-20 token (e.g., DAI)
    /// @param _priceFeed Address of the Chainlink ETH/USD price feed
    constructor(address _token, address _priceFeed) Ownable(msg.sender) {
        token = IERC20(_token);
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Deposits tokens into the lending pool
    /// @param amount Amount of tokens to deposit
    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        balances[msg.sender] += amount;
        totalDeposits += amount;
        emit Deposit(msg.sender, amount);
    }

    /// @notice Withdraws tokens from the lending pool
    /// @param amount Amount of tokens to withdraw
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(totalDeposits >= amount, "Insufficient pool funds");
        require(isSolvent(msg.sender), "User is insolvent");

        balances[msg.sender] -= amount;
        totalDeposits -= amount;
        require(token.transfer(msg.sender, amount), "Transfer failed");
        emit Withdraw(msg.sender, amount);
    }

    /// @notice Borrows tokens using ETH as collateral
    /// @param amount Amount of tokens to borrow
    function borrow(uint256 amount) external payable nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(token.balanceOf(address(this)) >= amount, "Insufficient pool funds");

        uint256 ethPrice = getLatestPrice();
        require(ethPrice > 0, "Invalid price");
        uint256 requiredCollateral = (amount * COLLATERAL_RATIO * 1e18) / (100 * ethPrice);
        require(msg.value >= requiredCollateral, "Insufficient collateral");

        borrows[msg.sender] += amount;
        collaterals[msg.sender] += msg.value;
        totalBorrows += amount;
        require(token.transfer(msg.sender, amount), "Transfer failed");
        emit Borrow(msg.sender, amount, msg.value);
    }

    /// @notice Repays borrowed tokens and retrieves collateral
    /// @param amount Amount of tokens to repay
    function repay(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(borrows[msg.sender] >= amount, "Insufficient borrow balance");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        uint256 collateralToReturn = (amount * COLLATERAL_RATIO * 1e18) / (100 * getLatestPrice());
        borrows[msg.sender] -= amount;
        collaterals[msg.sender] -= collateralToReturn;
        totalBorrows -= amount;
        payable(msg.sender).transfer(collateralToReturn);
        emit Repay(msg.sender, amount);
    }

    /// @notice Liquidates an undercollateralized position, rewarding the liquidator
    /// @param user Address of the user to liquidate
    function liquidate(address user) external nonReentrant {
        require(!isSolvent(user), "User is solvent");
        uint256 borrowAmount = borrows[user];
        uint256 collateral = collaterals[user];
        uint256 bonus = (collateral * LIQUIDATION_BONUS) / 100;
        uint256 totalCollateral = collateral + bonus;

        borrows[user] = 0;
        collaterals[user] = 0;
        totalBorrows -= borrowAmount;
        payable(msg.sender).transfer(totalCollateral);
        emit Liquidate(user, borrowAmount, bonus);
    }

    /// @notice Checks if a user is solvent based on collateral value
    /// @param user Address of the user
    /// @return True if the user's collateral meets the liquidation threshold
    function isSolvent(address user) public view returns (bool) {
        if (borrows[user] == 0) return true;
        uint256 ethPrice = getLatestPrice();
        uint256 collateralValue = (collaterals[user] * ethPrice) / 1e18;
        uint256 requiredCollateral = (borrows[user] * LIQUIDATION_THRESHOLD) / 100;
        return collateralValue >= requiredCollateral;
    }

    /// @notice Calculates the current interest rate based on utilization
    /// @return Interest rate (in percentage * 1e18)
    function getInterestRate() public view returns (uint256) {
        if (totalDeposits == 0) return BASE_RATE;
        uint256 utilizationRate = (totalBorrows * 1e18) / totalDeposits;
        return BASE_RATE + ((utilizationRate * RATE_SLOPE) / 1e18);
    }

    /// @notice Fetches the latest ETH/USD price from Chainlink
    /// @return Price in USD (18 decimals)
    function getLatestPrice() public view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        require(block.timestamp <= updatedAt + MAX_PRICE_AGE, "Price too old");
        return uint256(price) * 1e10; // Convert 8 decimals to 18 decimals
    }
}
