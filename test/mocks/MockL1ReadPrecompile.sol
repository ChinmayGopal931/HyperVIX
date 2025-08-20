// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title MockL1ReadPrecompile
/// @notice Mocks the behavior of the Hyperliquid L1Read precompile.
/// This contract should be deployed and then etched to the precompile address using vm.etch
contract MockL1ReadPrecompile {
    uint64 public price;

    /// @notice When the precompile address is called, this fallback returns the mock price.
    /// The input data contains the assetId but we ignore it for simplicity in this mock.
    fallback(bytes calldata /*data*/) external returns (bytes memory) {
        return abi.encode(price);
    }

    /// @notice A setter function that allows tests to define the mock price.
    /// Note: This won't work after vm.etch since storage isn't copied, use vm.store instead
    function setPrice(uint64 _price) external {
        price = _price;
    }
}