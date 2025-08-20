// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "./MockPrecompiles.s.sol";
import "./DeployHyperVIX.s.sol";

contract DeployWithMocks is Script {
    function run() external {
        console.log("Setting up mock precompiles for local testing...");
        
        // First setup mock precompiles
        SetupMockPrecompiles mockSetup = new SetupMockPrecompiles();
        mockSetup.run();
        
        // Test the precompiles
        mockSetup.testPriceCall();
        
        console.log("Mock precompiles setup complete. Now deploying contracts...");
        
        // Then deploy the actual contracts
        DeployHyperVIX deployment = new DeployHyperVIX();
        deployment.run();
        
        console.log("Deployment with mocks completed successfully!");
    }
}