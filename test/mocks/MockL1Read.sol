// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../src/interfaces/L1Read.sol";

contract MockL1Read is L1Read {
    mapping(uint32 => uint64) private prices;
    
    function setPrice(uint32 assetId, uint64 price) external {
        prices[assetId] = price;
    }
    
    function markPx(uint32 assetId) external view override returns (uint64) {
        return prices[assetId];
    }
}