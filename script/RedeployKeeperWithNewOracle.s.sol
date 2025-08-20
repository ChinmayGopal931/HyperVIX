// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/HyperVIXKeeper.sol";

contract RedeployKeeperWithNewOracle is Script {
    // NEW oracle address from previous deployment
    address constant NEW_ORACLE_ADDRESS = 0xA372981cF59ba0478DE6e6e502CE3c690eD6E01D;
    
    // Existing perpetual address
    address constant PERPETUAL_ADDRESS = 0xF23220ccE9f4CF81c999BC0A582020FA38094E60;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying NEW HyperVIXKeeper with fixed oracle...");
        console.log("Deployer:", deployer);
        console.log("Oracle (NEW):", NEW_ORACLE_ADDRESS);
        console.log("Perpetual:", PERPETUAL_ADDRESS);

        // Deploy NEW HyperVIXKeeper with correct oracle
        HyperVIXKeeper newKeeper = new HyperVIXKeeper(
            NEW_ORACLE_ADDRESS,
            PERPETUAL_ADDRESS
        );
        console.log("NEW HyperVIXKeeper deployed at:", address(newKeeper));

        // Authorize deployer as keeper
        newKeeper.authorizeKeeper(deployer, true);
        console.log("Deployer authorized as keeper");

        console.log("=== FINAL WORKING CONTRACT ADDRESSES ===");
        console.log("VolatilityIndexOracle:", NEW_ORACLE_ADDRESS);
        console.log("VolatilityPerpetual:", PERPETUAL_ADDRESS);
        console.log("HyperVIXKeeper:", address(newKeeper));
        console.log("MockUSDC:", "0x87fd4d8532c3F5bF5a391402F05814c6863f4e2a");

        vm.stopBroadcast();
    }
}