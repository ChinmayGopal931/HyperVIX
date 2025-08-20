// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";

contract DeployMockUSDC is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying MockUSDC to Hyperliquid Testnet...");
        console.log("Deployer:", deployer);

        // Deploy MockUSDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC deployed at:", address(usdc));
        
        // Check initial balance
        uint256 deployerBalance = usdc.balanceOf(deployer);
        console.log("Deployer initial balance:", deployerBalance / 1e6);
        
        // Fund the specified wallet
        address targetWallet = 0xD89091e7F5cE9f179B62604f658a5DD0E726e600;
        uint256 fundAmount = 10000 * 1e6; // 10,000 USDC
        
        usdc.mint(targetWallet, fundAmount);
        console.log("Funded wallet:", targetWallet);
        console.log("Amount funded:", fundAmount / 1e6);
        
        // Verify the balance
        uint256 targetBalance = usdc.balanceOf(targetWallet);
        console.log("Target wallet balance:", targetBalance / 1e6);
        
        // Also fund a few other addresses for testing
        address[] memory testAddresses = new address[](3);
        testAddresses[0] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Common test address
        testAddresses[1] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Another test address  
        testAddresses[2] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Another test address
        
        usdc.fundAddresses(testAddresses, 5000 * 1e6); // 5k USDC each
        console.log("Funded 3 additional test addresses");
        
        console.log("=== MockUSDC Deployment Summary ===");
        console.log("Contract Address:", address(usdc));
        console.log("Deployer Balance:", deployerBalance / 1e6);
        console.log("Target Wallet:", targetWallet);
        console.log("Target Balance:", targetBalance / 1e6);
        
        console.log("=== Usage Instructions ===");
        console.log("1. Use this address in your frontend");
        console.log("2. Call faucet() to get more test USDC");
        console.log("3. Standard ERC20 functions work normally");
        console.log("4. Update CONTRACTS.USDC in frontend config");

        vm.stopBroadcast();
    }
}