// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @author Sergey Kerhet
/// @title LendingPool - A decentralized lending and borrowing protocol with Chainlink price feeds
/// @notice Allows users to deposit tokens, borrow against ETH collateral, and liquidate undercollateralized positions
contract LendingPool is Ownable, ReentrancyGuard, Pausable {
    /////////////////////
    // State Variables
    /////////////////////

    IERC20 public immutable i_token; // Token of the pool (e.g., DAI)
    AggregatorV3Interface public immutable i_priceFeed; // Chainlink ETH/USD price feed

    mapping(address => uint256) public s_balances; // User deposit balances
    mapping(address => uint256) public s_borrows; // User borrow balances
    mapping(address => uint256) public s_collaterals; // User ETH collateral
    mapping(address => uint256) public lastAccrued;

    uint256 public s_totalDeposits; // Total deposited tokens
    uint256 public s_totalBorrows; // Total borrowed tokens

    uint256 public constant COLLATERAL_RATIO = 150; // 150% collateralization ratio
    uint256 public constant LIQUIDATION_THRESHOLD = 120; // Liquidation at 120% collateral value
    uint256 public constant LIQUIDATION_BONUS = 5; // 5% bonus for liquidators
    uint256 public constant BASE_RATE = 0.02e18; // Base interest rate: 2%
    uint256 public constant RATE_SLOPE = 0.2e18; // Slope for dynamic rate: 22%
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
        i_token = IERC20(_token);
        i_priceFeed = AggregatorV3Interface(_priceFeed);
    }

    /// @notice Deposits tokens into the lending pool
    /// @param amount Amount of tokens to deposit
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(i_token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        s_balances[msg.sender] += amount;
        s_totalDeposits += amount;
        emit Deposit(msg.sender, amount);
    }

    /// @notice Withdraws tokens from the lending pool
    /// @param amount Amount of tokens to withdraw
    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(s_balances[msg.sender] >= amount, "Insufficient balance");
        require(s_totalDeposits >= amount, "Insufficient pool funds");
        require(isSolvent(msg.sender), "User is insolvent");

        s_balances[msg.sender] -= amount;
        s_totalDeposits -= amount;
        require(i_token.transfer(msg.sender, amount), "Transfer failed");
        emit Withdraw(msg.sender, amount);
    }
    /// @notice Accrues interest on the user's borrow balance based on time passed and utilization rate
    /// @dev Uses simple interest model: interest = principal * rate * timeElapsed / (100 * 365 days)
    /// @param user Address whose interest is to be updated

    function updateInterest(address user) public {
        uint256 principal = s_borrows[user];
        if (principal == 0) return;

        uint256 timeElapsed = block.timestamp - lastAccrued[user];
        if (timeElapsed == 0) return;

        uint256 rate = getInterestRate();
        uint256 interest = (principal * rate * timeElapsed) / (1e18 * 365 days);

        s_borrows[user] += interest;
        s_totalBorrows += interest;
        lastAccrued[user] = block.timestamp;
    }

    /// @notice Borrows tokens using ETH as collateral
    /// @param amount Amount of tokens to borrow
    function borrow(uint256 amount) external payable nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        require(i_token.balanceOf(address(this)) >= amount, "Insufficient pool funds");
        uint256 ethPrice = getLatestPrice();
        updateInterest(msg.sender);

        uint256 requiredCollateral = (amount * COLLATERAL_RATIO * 1e18) / (100 * ethPrice);
        require(msg.value >= requiredCollateral, "Insufficient collateral");

        s_borrows[msg.sender] += amount;
        s_collaterals[msg.sender] += msg.value;
        s_totalBorrows += amount;

        require(i_token.transfer(msg.sender, amount), "Transfer failed");
        emit Borrow(msg.sender, amount, msg.value);
    }

    /// @notice Repays borrowed tokens and retrieves collateral
    /// @param amount Amount of tokens to repay
    function repay(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");

        updateInterest(msg.sender);

        uint256 debt = s_borrows[msg.sender];
        require(debt >= amount, "Insufficient borrow balance");
        require(i_token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        uint256 ethPrice = getLatestPrice();
        uint256 collateralToReturn = (amount * COLLATERAL_RATIO * 1e18) / (100 * ethPrice);

        s_borrows[msg.sender] = debt - amount;

        if (s_borrows[msg.sender] < 1e6) {
            s_borrows[msg.sender] = 0;
        }

        s_collaterals[msg.sender] -= collateralToReturn;
        s_totalBorrows -= amount;

        payable(msg.sender).transfer(collateralToReturn);
        emit Repay(msg.sender, amount);
    }

    /// @notice Liquidates an undercollateralized position, rewarding the caller with collateral + bonus
    /// @dev ETH is sent to the liquidator via `.call{value: amount}("")`.
    /// This is considered safe here because state is updated before the call, and function is protected with `nonReentrant`.
    /// Reference: https://consensys.github.io/smart-contract-best-practices/recommendations/#favor-pull-over-push-for-external-calls
    /// @param user Address of the user to liquidate
    function liquidate(address user) external nonReentrant whenNotPaused {
        require(!isSolvent(user), "User is solvent");

        uint256 borrowAmount = s_borrows[user];
        uint256 collateral = s_collaterals[user];
        uint256 bonus = (collateral * LIQUIDATION_BONUS) / 100;
        uint256 totalCollateral = collateral + bonus;

        s_borrows[user] = 0;
        s_collaterals[user] = 0;
        s_totalBorrows -= borrowAmount;
        (bool success,) = payable(msg.sender).call{value: totalCollateral}("");
        require(success, "ETH transfer failed");
    }

    /// @notice Checks if a user is solvent based on collateral value
    /// @param user Address of the user
    /// @return True if the user's collateral meets the liquidation threshold
    function isSolvent(address user) public view returns (bool) {
        if (s_borrows[user] == 0) return true;
        uint256 ethPrice = getLatestPrice();
        uint256 collateralValue = (s_collaterals[user] * ethPrice) / 1e18;
        uint256 requiredCollateral = (s_borrows[user] * LIQUIDATION_THRESHOLD) / 100;
        return collateralValue >= requiredCollateral;
    }

    /// @notice Calculates the current interest rate based on utilization
    /// @return Interest rate (in percentage * 1e18)
    function getInterestRate() public view returns (uint256) {
        if (s_totalDeposits == 0) return BASE_RATE;
        uint256 utilizationRate = (s_totalBorrows * 1e18) / s_totalDeposits;
        return BASE_RATE + ((utilizationRate * RATE_SLOPE) / 1e18);
    }

    /// @notice Fetches the latest ETH/USD price from Chainlink
    /// @return Price in USD (18 decimals)
    function getLatestPrice() public view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = i_priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        require(block.timestamp <= updatedAt + MAX_PRICE_AGE, "Price too old");
        return uint256(price) * 1e10; // Convert 8 decimals to 18 decimals
    }

    function pause() external {
        _pause();
    }

    function unpause() external {
        _unpause();
    }

    fallback() external payable {}
}
