// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

library MathUtils {
    uint256 constant PRECISION = 1e18;
    
    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
    
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
    
    function mulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return (a * b) / c;
    }
    
    function percentage(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10000;
    }
    
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        
        return y;
    }
}