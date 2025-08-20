// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/VolatilityIndexOracle.sol";
import "../src/VolatilityPerpetual.sol";
import "../src/HyperVIXKeeper.sol";
import "../src/interfaces/L1Read.sol";

contract DeployTestnet is Script {
    // Configuration constants
    uint32 constant ASSET_ID = 1; // ETH asset ID on Hyperliquid
    uint256 constant LAMBDA = 0.94 * 1e18; // 94% decay factor
    uint256 constant ANNUALIZATION_FACTOR = 365 * 24; // Hourly updates
    uint256 constant INITIAL_VARIANCE = 0.04 * 1e18; // 20% annualized volatility
    
    // vAMM initial reserves
    uint256 constant INITIAL_BASE_RESERVE = 1_000_000e18; // 1M vVOL
    uint256 constant INITIAL_QUOTE_RESERVE = 200_000e6;   // 200K USDC (6 decimals)

    // Use the USDC address from your .env file
    address constant TESTNET_USDC = 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Use USDC address from your .env file
        address collateralTokenAddress;
        try vm.envAddress("USDC_TOKEN_ADDRESS") returns (address addr) {
            collateralTokenAddress = addr;
        } catch {
            collateralTokenAddress = TESTNET_USDC;
        }
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying HyperVIX to Hyperliquid Testnet");
        console.log("Deployer:", deployer);
        console.log("Collateral Token:", collateralTokenAddress);

        // Deploy L1Read contract for Hyperliquid precompiles
        L1Read l1Read = new L1Read();
        console.log("L1Read contract deployed at:", address(l1Read));

        // Skip precompile testing during deployment - will test after deployment

        // Deploy VolatilityIndexOracle
        VolatilityIndexOracle oracle = new VolatilityIndexOracle(
            address(l1Read),
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

        // Authorize deployer as keeper
        keeper.authorizeKeeper(deployer, true);
        console.log("Deployer authorized as keeper");

        // Get initial values
        uint256 initialMarkPrice = perpetual.getMarkPrice();
        
        console.log("=== Deployment Summary ===");
        console.log("L1Read:", address(l1Read));
        console.log("Oracle:", address(oracle));
        console.log("Perpetual:", address(perpetual));
        console.log("Keeper:", address(keeper));
        console.log("Initial vAMM Price:", initialMarkPrice);
        console.log("Asset ID:", ASSET_ID);
        console.log("Collateral Token:", collateralTokenAddress);

        vm.stopBroadcast();
    }
}