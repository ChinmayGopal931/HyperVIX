// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Script.sol";
import "../src/interfaces/L1Read.sol";

contract MockMarkPxPrecompile {
    uint64 public price = 2000e6; // Default ETH price: $2000

    fallback(bytes calldata data) external returns (bytes memory) {
        uint32 assetId = abi.decode(data, (uint32));
        // Return different prices for different assets
        if (assetId == 1) return abi.encode(price); // ETH
        return abi.encode(uint64(1e6)); // Default to $1
    }

    function setPrice(uint64 _price) external {
        price = _price;
    }
}

contract MockSpotPxPrecompile {
    uint64 public price = 2000e6; // Default ETH price: $2000

    fallback(bytes calldata data) external returns (bytes memory) {
        uint32 assetId = abi.decode(data, (uint32));
        // Return different prices for different assets
        if (assetId == 1) return abi.encode(price); // ETH
        return abi.encode(uint64(1e6)); // Default to $1
    }

    function setPrice(uint64 _price) external {
        price = _price;
    }
}

contract MockOraclePxPrecompile {
    uint64 public price = 2000e6; // Default ETH price: $2000

    fallback(bytes calldata data) external returns (bytes memory) {
        uint32 assetId = abi.decode(data, (uint32));
        // Return different prices for different assets
        if (assetId == 1) return abi.encode(price); // ETH
        return abi.encode(uint64(1e6)); // Default to $1
    }

    function setPrice(uint64 _price) external {
        price = _price;
    }
}

contract SetupMockPrecompiles is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy mock precompiles
        MockMarkPxPrecompile markPxMock = new MockMarkPxPrecompile();
        MockSpotPxPrecompile spotPxMock = new MockSpotPxPrecompile();
        MockOraclePxPrecompile oraclePxMock = new MockOraclePxPrecompile();

        // Define precompile addresses
        address MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;
        address SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;
        address ORACLE_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000807;

        // Etch precompiles at their expected addresses
        vm.etch(MARK_PX_PRECOMPILE_ADDRESS, address(markPxMock).code);
        vm.etch(SPOT_PX_PRECOMPILE_ADDRESS, address(spotPxMock).code);
        vm.etch(ORACLE_PX_PRECOMPILE_ADDRESS, address(oraclePxMock).code);

        // Set initial price using vm.store (since vm.etch doesn't copy storage)
        vm.store(MARK_PX_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(2000e6)));
        vm.store(SPOT_PX_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(2000e6)));
        vm.store(ORACLE_PX_PRECOMPILE_ADDRESS, bytes32(uint256(0)), bytes32(uint256(2000e6)));

        console.log("Mock precompiles setup completed:");
        console.log("Mark Price Precompile:", MARK_PX_PRECOMPILE_ADDRESS);
        console.log("Spot Price Precompile:", SPOT_PX_PRECOMPILE_ADDRESS);
        console.log("Oracle Price Precompile:", ORACLE_PX_PRECOMPILE_ADDRESS);

        vm.stopBroadcast();
    }

    function testPriceCall() external {
        // Test if the precompiles work
        bool success;
        bytes memory result;
        address MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;

        (success, result) = MARK_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(uint32(1)));
        console.log("Mark price call success:", success);
        if (success) {
            console.log("Mark price result:", abi.decode(result, (uint64)));
        }
    }
}