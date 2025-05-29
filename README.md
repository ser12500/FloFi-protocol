![alt text](image-1.png)              ![alt text](image-2.png)













                                                      Lending Protocol

A decentralized lending and borrowing protocol, showcasing a sleek and modern interface for DeFi interactions.

A decentralized lending and borrowing protocol built with Solidity, Foundry, and Chainlink, designed for seamless deployment on Ethereum (Sepolia) and Layer 2 networks (Arbitrum, Optimism). This protocol features dynamic interest rates, liquidation with bonuses, and an advanced React frontend for a user-friendly experience. Whether you're a developer building on top of the protocol or a user looking to deposit, borrow, or liquidate, this project offers a robust and secure DeFi solution.


✨ Features





Deposit: Users can deposit DAI into a liquidity pool to earn interest based on pool utilization.



Borrow: Borrow DAI by providing ETH as collateral with a 150% collateralization ratio.



Dynamic Interest Rates: Interest rates adjust dynamically based on the utilization rate (totalBorrows / totalDeposits), with a base rate of 2% and a 20% slope.



Liquidation: Undercollateralized positions (below 120%) can be liquidated, rewarding liquidators with a 5% bonus.



Chainlink Integration: Utilizes Chainlink ETH/USD price feeds with staleness checks for accurate pricing.



Advanced Frontend: A React-based interface with Web3.js, featuring:





Network switching (Sepolia, Arbitrum, Optimism).



Real-time balance, borrow, collateral, and ETH price updates.



Transaction history with links to Etherscan/Arbiscan/Optimistic Etherscan.



Error handling and loading states for a smooth user experience.



Multi-Chain Support: Deployable on Ethereum Sepolia, Arbitrum, and Optimism for low gas fees.



Comprehensive Testing: Foundry-based tests, including fuzz tests and Chainlink price staleness checks.

Overview of the protocol's architecture, illustrating the interaction between smart contracts, Chainlink price feeds, and the React frontend.

🛠️ Prerequisites

Before getting started, ensure you have the following installed:





Node.js: Required for running the React frontend.



Foundry: For compiling, testing, and deploying smart contracts.



MetaMask: Browser extension for interacting with the blockchain and frontend.



A compatible wallet with funds for gas fees on Sepolia, Arbitrum, or Optimism.

🚀 Installation

Follow these steps to set up the project locally:





Install Foundry:

curl -L https://foundry.paradigm.xyz | bash
foundryup



Clone the Repository:

git clone https://github.com/your-repo/lending-protocol.git
cd lending-protocol



Install Smart Contract Dependencies:

forge install openzeppelin/openzeppelin-contracts
forge install chainlink/contracts



Set Up the Frontend:

npm install -g serve
mkdir frontend
cp index.html frontend/
cd frontend
serve

📂 Project Structure

lending-protocol/
├── src/
│   ├── LendingPool.sol       # Core lending pool smart contract
│   ├── MockToken.sol        # Mock DAI token for testing
├── test/
│   ├── LendingPoolTest.t.sol # Foundry test suite
├── script/
│   ├── Deploy.s.sol          # Deployment script
├── frontend/
│   ├── index.html           # React frontend
├── foundry.toml             # Foundry configuration
├── README.md                # Project documentation

🌐 Deployment

1. Update the Deploy Script

In script/Deploy.s.sol, update the Chainlink price feed address for your target network:





Sepolia: 0x694AA1769357215DE4FAC081bf1f309aDC325306 (ETH/USD)



Arbitrum: 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612



Optimism: 0x13e3Ee699D1909E989722E753853AE30b17e08c5

2. Compile Contracts

forge build

3. Run Tests

forge test -vvv

4. Deploy to a Network

Set up your environment variables in a .env file with your SEPOLIA_RPC_URL, ARBITRUM_RPC_URL, OPTIMISM_RPC_URL, and PRIVATE_KEY.





Deploy to Sepolia:

source .env
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast



Deploy to Arbitrum:

forge script script/Deploy.s.sol --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast



Deploy to Optimism:

forge script script/Deploy.s.sol --rpc-url $OPTIMISM_RPC_URL --private-key $PRIVATE_KEY --broadcast

5. Update the Frontend

Update frontend/index.html with the deployed contract addresses for each network.

🖥️ Frontend Usage





Open http://localhost:3000 in a browser with MetaMask installed.



Connect MetaMask and select the desired network (Sepolia, Arbitrum, or Optimism).



Use the interface to:





Deposit DAI: Enter an amount, approve the token, and deposit into the pool.



Withdraw DAI: Withdraw your deposited DAI plus earned interest.



Borrow DAI: Provide ETH collateral (150% of borrow amount) to borrow DAI.



Repay DAI: Repay borrowed DAI to retrieve your collateral.



Liquidate: Liquidate undercollateralized positions and earn a 5% bonus.



View Data: Monitor real-time balances, borrow amounts, collateral, ETH price, and interest rates.



Check History: View transaction history with links to block explorers.

🔄 Example Interactions





Deposit: Approve and deposit 100 DAI to start earning interest.



Borrow: Borrow 10 DAI by providing 0.015 ETH as collateral (assuming ETH price is $1000).



Repay: Repay 10 DAI plus interest to unlock your ETH collateral.



Liquidate: Enter an undercollateralized user’s address to liquidate their position and earn a 5% bonus.



Switch Network: Use the dropdown to switch between Sepolia, Arbitrum, or Optimism.

🔒 Security Considerations





Reentrancy Protection: The protocol uses ReentrancyGuard to prevent reentrancy attacks.



Chainlink Price Feeds: ETH/USD price feeds include 1-hour staleness checks for reliability.



Static Analysis: Run slither src/LendingPool.sol to identify potential vulnerabilities.



Edge Cases: Tests cover zero deposits, insufficient collateral, stale prices, and insolvency scenarios.

🚀 Future Improvements





Governance: Add a governance system for updating parameters like collateral ratios.



Interest Accrual: Implement time-based interest accrual for more granular calculations.



Multi-Token Support: Extend the protocol to support additional tokens beyond DAI.



Frontend Enhancements: Add charts for pool utilization, interest rates, and user activity.

📜 License

This project is licensed under the MIT License. See the LICENSE file for details.

🤝 Contributing

Contributions are welcome! Please submit a pull request or open an issue on the GitHub repository.

📬 Contact

For questions or support, reach out via GitHub Issues.



Built with 💙 by the DeFi community for the DeFi community.