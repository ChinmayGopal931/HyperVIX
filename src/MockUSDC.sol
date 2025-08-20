// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockUSDC is ERC20, Ownable {
    uint8 private constant DECIMALS = 6;
    
    constructor() ERC20("USD Coin (Test)", "USDC") Ownable(msg.sender) {
        // Mint initial supply to deployer
        _mint(msg.sender, 1000000 * 10**DECIMALS); // 1M USDC
    }
    
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
    
    // Faucet function - anyone can mint test USDC
    function faucet(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    // Mint function for owner
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    // Fund multiple addresses at once
    function fundAddresses(address[] calldata addresses, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            _mint(addresses[i], amount);
        }
    }
    
    // Emergency burn function
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}