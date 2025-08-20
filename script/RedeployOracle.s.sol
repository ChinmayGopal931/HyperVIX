// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/VolatilityIndexOracle.sol";
import "../src/HyperVIXKeeper.sol";

contract RedeployOracle is Script {
    // Use the mark price precompile address directly
    address constant MARK_PX_PRECOMPILE = 0x0000000000000000000000000000000000000806;
    
    // Existing contracts
    address constant PERPETUAL_ADDRESS = 0xF23220ccE9f4CF81c999BC0A582020FA38094E60;
    address constant KEEPER_ADDRESS = 0x3c52aB878821dA382F2069B2f7e839F1C49b81bF;
    
    // Oracle configuration - try with your PERP_ID=3
    uint32 constant ASSET_ID = 3; // Use your PERP_ID from .env
    uint256 constant LAMBDA = 0.94 * 1e18; // 94% decay factor
    uint256 constant ANNUALIZATION_FACTOR = 365 * 24; // Hourly updates
    uint256 constant INITIAL_VARIANCE = 0.04 * 1e18; // 20% annualized volatility

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("Redeploying VolatilityIndexOracle with correct precompile usage...");
        console.log("Deployer:", deployer);
        console.log("Mark Price Precompile:", MARK_PX_PRECOMPILE);
        console.log("Asset ID:", ASSET_ID);

        // Deploy NEW VolatilityIndexOracle with correct precompile address
        VolatilityIndexOracle newOracle = new VolatilityIndexOracle(
            MARK_PX_PRECOMPILE, // Use precompile address directly
            deployer, // Deployer as keeper
            ASSET_ID, // Try asset ID 3
            LAMBDA,
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );
        console.log("NEW VolatilityIndexOracle deployed at:", address(newOracle));

        // Test the precompile call immediately
        console.log("Testing precompile call...");
        try newOracle.getAnnualizedVolatility() returns (uint256 vol) {
            console.log("Initial volatility:", vol);
        } catch {
            console.log("Initial volatility call failed - may need price snapshot first");
        }

        console.log("=== UPDATED ORACLE ADDRESS ===");
        console.log("NEW VolatilityIndexOracle:", address(newOracle));
        console.log("VolatilityPerpetual:", PERPETUAL_ADDRESS);
        console.log("HyperVIXKeeper:", KEEPER_ADDRESS);
        console.log("");
        console.log("IMPORTANT: You need to deploy a new HyperVIXKeeper with this oracle address!");

        vm.stopBroadcast();
    }
}