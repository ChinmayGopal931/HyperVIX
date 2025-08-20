// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/VolatilityIndexOracle.sol";
import "../src/VolatilityPerpetual.sol";
import "../src/HyperVIXKeeper.sol";
import "../src/MockUSDC.sol";

contract DeployComplete is Script {
    // Hyperliquid precompile addresses
    address constant MARK_PX_PRECOMPILE = 0x0000000000000000000000000000000000000806;
    
    // Configuration constants
    uint32 constant ASSET_ID = 3; // Working asset ID on Hyperliquid testnet
    uint256 constant LAMBDA = 0.94 * 1e18; // 94% decay factor
    uint256 constant ANNUALIZATION_FACTOR = 365 * 24; // Hourly updates
    uint256 constant INITIAL_VARIANCE = 0.04 * 1e18; // 20% annualized volatility
    
    // vAMM initial reserves
    uint256 constant INITIAL_BASE_RESERVE = 1_000_000e18; // 1M vVOL
    uint256 constant INITIAL_QUOTE_RESERVE = 200_000e6;   // 200K USDC (6 decimals)

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== DEPLOYING COMPLETE HYPERVIX SYSTEM ===");
        console.log("Deployer:", deployer);
        console.log("Asset ID:", ASSET_ID);
        console.log("");

        // 1. Deploy MockUSDC
        console.log("1. Deploying MockUSDC...");
        MockUSDC mockUSDC = new MockUSDC();
        console.log("   MockUSDC deployed at:", address(mockUSDC));

        // 2. Deploy VolatilityIndexOracle with correct precompile
        console.log("2. Deploying VolatilityIndexOracle...");
        VolatilityIndexOracle oracle = new VolatilityIndexOracle(
            MARK_PX_PRECOMPILE, // Use precompile directly
            deployer, // Deployer as keeper
            ASSET_ID,
            LAMBDA,
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );
        console.log("   VolatilityIndexOracle deployed at:", address(oracle));

        // 3. Deploy VolatilityPerpetual
        console.log("3. Deploying VolatilityPerpetual...");
        VolatilityPerpetual perpetual = new VolatilityPerpetual(
            address(oracle),
            address(mockUSDC),
            INITIAL_BASE_RESERVE,
            INITIAL_QUOTE_RESERVE
        );
        console.log("   VolatilityPerpetual deployed at:", address(perpetual));

        // 4. Deploy HyperVIXKeeper
        console.log("4. Deploying HyperVIXKeeper...");
        HyperVIXKeeper keeper = new HyperVIXKeeper(
            address(oracle),
            address(perpetual)
        );
        console.log("   HyperVIXKeeper deployed at:", address(keeper));

        // 5. Setup permissions
        console.log("5. Setting up permissions...");
        keeper.authorizeKeeper(deployer, true);
        console.log("   Deployer authorized as keeper");

        // 6. Fund a test wallet with USDC
        address testWallet = 0xD89091e7F5cE9f179B62604f658a5DD0E726e600;
        mockUSDC.mint(testWallet, 1_010_000e6); // 1.01M USDC
        console.log("   Funded test wallet with USDC:", testWallet);

        // 7. Test oracle functionality
        console.log("6. Testing oracle...");
        uint256 initialVol = oracle.getAnnualizedVolatility();
        console.log("   Initial volatility:", initialVol);

        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("// FRONTEND CONTRACT ADDRESSES");
        console.log("const CONTRACTS = {");
        console.log('  VolatilityIndexOracle: "', vm.toString(address(oracle)), '",');
        console.log('  VolatilityPerpetual:   "', vm.toString(address(perpetual)), '",');
        console.log('  HyperVIXKeeper:        "', vm.toString(address(keeper)), '",');
        console.log('  MockUSDC:              "', vm.toString(address(mockUSDC)), '"');
        console.log("};");
        console.log("");
        console.log("// TEST WALLET (pre-funded with USDC)");
        console.log("const TEST_WALLET = \"", vm.toString(testWallet), "\";");
        console.log("");
        console.log("All contracts deployed and ready for frontend integration!");

        vm.stopBroadcast();
    }
}