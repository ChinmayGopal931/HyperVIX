// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/VolatilityIndexOracle.sol";
import "../src/VolatilityPerpetual.sol";
import "../src/HyperVIXKeeper.sol";
import "../src/interfaces/L1Read.sol";

contract DeployHyperVIX is Script {
    // Configuration constants
    uint32 constant ASSET_ID = 1; // ETH asset ID
    uint256 constant LAMBDA = 0.94 * 1e18; // 94% decay factor
    uint256 constant ANNUALIZATION_FACTOR = 365 * 24; // Hourly updates
    uint256 constant INITIAL_VARIANCE = 0.04 * 1e18; // Corresponds to 20% annualized volatility (sqrt(0.04))
    
    // vAMM initial reserves (should reflect initial market price)
    uint256 constant INITIAL_BASE_RESERVE = 1_000_000e18; // 1M vVOL
    uint256 constant INITIAL_QUOTE_RESERVE = 200_000e18;  // 200K USDC, setting initial price to 0.20

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // For Hyperliquid L1, we use the L1Read contract directly
        address l1ReadAddress = address(new L1Read());
        address collateralTokenAddress = vm.envAddress("COLLATERAL_TOKEN_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying HyperVIX contracts on Hyperliquid L1...");
        console.log("Deployer:", deployer);
        console.log("L1 Read Contract:", l1ReadAddress);
        console.log("Collateral Token:", collateralTokenAddress);

        // Test precompile connectivity
        console.log("Testing Hyperliquid precompiles...");
        L1Read l1Read = L1Read(l1ReadAddress);
        try l1Read.markPx(ASSET_ID) returns (uint64 price) {
            console.log("Mark price for asset", ASSET_ID, ":", price);
        } catch {
            console.log("WARNING: Could not fetch mark price - precompiles may not be available");
        }

        // Deploy VolatilityIndexOracle with deployer as initial keeper
        VolatilityIndexOracle oracle = new VolatilityIndexOracle(
            l1ReadAddress,
            deployer, // Use deployer as initial keeper
            ASSET_ID,
            LAMBDA,
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );

        console.log("VolatilityIndexOracle deployed at:", address(oracle));

        // Deploy VolatilityPerpetual
        VolatilityPerpetual perpetual = new VolatilityPerpetual(
            address(oracle),
            collateralTokenAddress,
            INITIAL_BASE_RESERVE,
            INITIAL_QUOTE_RESERVE
        );

        console.log("VolatilityPerpetual deployed at:", address(perpetual));

        // Deploy HyperVIXKeeper
        HyperVIXKeeper keeper = new HyperVIXKeeper(
            address(oracle),
            address(perpetual)
        );

        console.log("HyperVIXKeeper deployed at:", address(keeper));

        // Set keeper as authorized in the keeper contract
        keeper.authorizeKeeper(deployer, true);
        console.log("Deployer authorized as keeper");

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Oracle Address:", address(oracle));
        console.log("Perpetual Address:", address(perpetual));
        console.log("Keeper Address:", address(keeper));
        console.log("Initial vAMM Price (Quote/Base):", (INITIAL_QUOTE_RESERVE * 1e18) / INITIAL_BASE_RESERVE);
        console.log("Asset ID:", ASSET_ID);
        console.log("Lambda (decay factor):", LAMBDA);
        console.log("Annualization Factor:", ANNUALIZATION_FACTOR);

        vm.stopBroadcast();
    }
}