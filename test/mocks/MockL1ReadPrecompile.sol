// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title MockL1ReadPrecompile
/// @notice Mocks the behavior of the Hyperliquid L1Read precompile.
/// This contract should be deployed and then etched to the precompile address using vm.etch
contract MockL1ReadPrecompile {
    mapping(uint32 => uint64) public mockPrices;
    uint64 public defaultPrice;

    /// @notice When the precompile address is called, this fallback decodes the
    /// asset ID and returns the corresponding mock price.
    fallback(bytes calldata data) external returns (bytes memory) {
        if (data.length == 0) {
            return abi.encode(defaultPrice);
        }
        
        uint32 assetId = abi.decode(data, (uint32));
        uint64 price = mockPrices[assetId];
        
        // If no specific price set for this asset, return default
        if (price == 0) {
            price = defaultPrice;
        }
        
        return abi.encode(price);
    }

    /// @notice A setter function that allows tests to define the mock price
    /// for a specific asset ID.
    function setPrice(uint32 assetId, uint64 price) external {
        mockPrices[assetId] = price;
    }

    /// @notice Set default price for all assets
    function setDefaultPrice(uint64 _price) external {
        defaultPrice = _price;
    }

    /// @notice Get the current mock price for an asset
    function getPrice(uint32 assetId) external view returns (uint64) {
        uint64 price = mockPrices[assetId];
        return price == 0 ? defaultPrice : price;
    }
}