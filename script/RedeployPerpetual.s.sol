// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/VolatilityIndexOracle.sol";
import "../src/VolatilityPerpetual.sol";
import "../src/HyperVIXKeeper.sol";

contract RedeployPerpetual is Script {
    // Use existing oracle address
    address constant ORACLE_ADDRESS = 0x721241e831f773BC29E4d39d057ff97fD578c772;
    
    // Use new MockUSDC address
    address constant NEW_USDC_ADDRESS = 0x87fd4d8532c3F5bF5a391402F05814c6863f4e2a;
    
    // vAMM initial reserves (same as before)
    uint256 constant INITIAL_BASE_RESERVE = 1_000_000e18; // 1M vVOL
    uint256 constant INITIAL_QUOTE_RESERVE = 200_000e6;   // 200K USDC (6 decimals)

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("Redeploying VolatilityPerpetual with correct MockUSDC...");
        console.log("Deployer:", deployer);
        console.log("Oracle (existing):", ORACLE_ADDRESS);
        console.log("MockUSDC (new):", NEW_USDC_ADDRESS);

        // Deploy NEW VolatilityPerpetual with correct USDC address
        VolatilityPerpetual newPerpetual = new VolatilityPerpetual(
            ORACLE_ADDRESS,
            NEW_USDC_ADDRESS,
            INITIAL_BASE_RESERVE,
            INITIAL_QUOTE_RESERVE
        );
        console.log("NEW VolatilityPerpetual deployed at:", address(newPerpetual));

        // Deploy NEW HyperVIXKeeper with updated addresses
        HyperVIXKeeper newKeeper = new HyperVIXKeeper(
            ORACLE_ADDRESS,
            address(newPerpetual)
        );
        console.log("NEW HyperVIXKeeper deployed at:", address(newKeeper));

        // Authorize deployer as keeper
        newKeeper.authorizeKeeper(deployer, true);
        console.log("Deployer authorized as keeper");

        console.log("=== UPDATED CONTRACT ADDRESSES ===");
        console.log("VolatilityIndexOracle:", ORACLE_ADDRESS);
        console.log("VolatilityPerpetual:", address(newPerpetual));
        console.log("HyperVIXKeeper:", address(newKeeper));
        console.log("MockUSDC:", NEW_USDC_ADDRESS);

        vm.stopBroadcast();
    }
}