// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./VolatilityIndexOracle.sol";
import "./VolatilityPerpetual.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HyperVIXKeeper is Ownable, ReentrancyGuard {
    VolatilityIndexOracle public immutable oracle;
    VolatilityPerpetual public immutable perpetual;
    
    uint256 public lastOracleUpdate;
    uint256 public lastFundingUpdate;
    uint256 public oracleUpdateInterval = 1 hours;
    
    mapping(address => bool) public authorizedKeepers;
    
    event OracleUpdated(uint256 timestamp);
    event FundingSettled(uint256 timestamp);
    event KeeperAuthorized(address indexed keeper, bool authorized);
    event IntervalUpdated(uint256 newInterval);
    
    error UnauthorizedKeeper();
    error UpdateTooEarly();
    
    modifier onlyKeeper() {
        if (!authorizedKeepers[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedKeeper();
        }
        _;
    }
    
    constructor(address _oracle, address _perpetual) Ownable(msg.sender) {
        oracle = VolatilityIndexOracle(_oracle);
        perpetual = VolatilityPerpetual(_perpetual);
        lastOracleUpdate = block.timestamp;
        lastFundingUpdate = block.timestamp;
    }
    
    function updateOracle() external onlyKeeper nonReentrant {
        if (block.timestamp < lastOracleUpdate + oracleUpdateInterval) {
            revert UpdateTooEarly();
        }
        
        oracle.takePriceSnapshot();
        lastOracleUpdate = block.timestamp;
        
        emit OracleUpdated(block.timestamp);
    }
    
    function settleFunding() external onlyKeeper nonReentrant {
        uint256 fundingInterval = perpetual.fundingInterval();
        if (block.timestamp < lastFundingUpdate + fundingInterval) {
            revert UpdateTooEarly();
        }
        
        perpetual.settleFunding();
        lastFundingUpdate = block.timestamp;
        
        emit FundingSettled(block.timestamp);
    }
    
    function updateBoth() external onlyKeeper nonReentrant {
        // Update oracle if due
        if (block.timestamp >= lastOracleUpdate + oracleUpdateInterval) {
            oracle.takePriceSnapshot();
            lastOracleUpdate = block.timestamp;
            emit OracleUpdated(block.timestamp);
        }
        
        // Settle funding if due
        uint256 fundingInterval = perpetual.fundingInterval();
        if (block.timestamp >= lastFundingUpdate + fundingInterval) {
            perpetual.settleFunding();
            lastFundingUpdate = block.timestamp;
            emit FundingSettled(block.timestamp);
        }
    }
    
    function authorizeKeeper(address keeper, bool authorized) external onlyOwner {
        authorizedKeepers[keeper] = authorized;
        emit KeeperAuthorized(keeper, authorized);
    }
    
    function setOracleUpdateInterval(uint256 interval) external onlyOwner {
        require(interval > 0, "Invalid interval");
        oracleUpdateInterval = interval;
        emit IntervalUpdated(interval);
    }
    
    function isOracleUpdateDue() external view returns (bool) {
        return block.timestamp >= lastOracleUpdate + oracleUpdateInterval;
    }
    
    function isFundingUpdateDue() external view returns (bool) {
        uint256 fundingInterval = perpetual.fundingInterval();
        return block.timestamp >= lastFundingUpdate + fundingInterval;
    }
    
    function getNextOracleUpdate() external view returns (uint256) {
        return lastOracleUpdate + oracleUpdateInterval;
    }
    
    function getNextFundingUpdate() external view returns (uint256) {
        uint256 fundingInterval = perpetual.fundingInterval();
        return lastFundingUpdate + fundingInterval;
    }
}