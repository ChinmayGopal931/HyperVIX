// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/L1Read.sol";
import "prb-math/UD60x18.sol";

contract VolatilityIndexOracle {

    // --- Interfaces & Constants ---
    address public immutable l1Reader;
    address public immutable keeper;

    // --- Asset & EWMA Configuration ---
    uint32 public immutable underlyingAssetId;
    uint256 public immutable lambda; // e.g., 94% is 0.94e18
    uint256 public immutable annualizationFactor; // e.g., 365 * 24 for hourly updates

    // --- Core State ---
    uint64 public lastPrice;
    uint256 public currentVariance; // σ^2, stored as UD60x18
    uint256 public lastUpdateTime;

    // --- TWAP State for Manipulation Resistance ---
    uint256 public cumulativeVolatility;
    uint256 public lastTwapUpdateTime;

    // --- Events ---
    event VolatilityUpdated(
        uint256 indexed newVariance,
        uint256 indexed annualizedVolatility,
        uint256 indexed timestamp
    );

    // --- Errors ---
    error OnlyKeeper();
    error InvalidLambda();
    error InvalidAddress();
    error InvalidAnnualizationFactor();
    error ZeroPrice();

    // --- Modifiers ---
    modifier onlyKeeper() {
        if (msg.sender != keeper) revert OnlyKeeper();
        _;
    }

    constructor(
        address _l1ReadAddress,
        address _keeperAddress,
        uint32 _assetId,
        uint256 _lambda,
        uint256 _annualizationFactor,
        uint256 _initialVariance
    ) {
        if (_l1ReadAddress == address(0)) revert InvalidAddress();
        if (_keeperAddress == address(0)) revert InvalidAddress();
        if (_lambda >= 1e18 || _lambda == 0) revert InvalidLambda();
        if (_annualizationFactor == 0) revert InvalidAnnualizationFactor();

        l1Reader = _l1ReadAddress;
        keeper = _keeperAddress;
        underlyingAssetId = _assetId;
        lambda = _lambda;
        annualizationFactor = _annualizationFactor;

        // Initialize with zero price - will be set on first price snapshot
        lastPrice = 0;
        currentVariance = _initialVariance;
        lastUpdateTime = block.timestamp;
        lastTwapUpdateTime = block.timestamp;
    }

    // --- Internal Helper Functions ---
    
    /**
     * @dev Fetches mark price from Hyperliquid precompile using correct low-level staticcall
     * @param assetId The asset ID to get price for
     * @return price The mark price as uint64
     */
    function _getMarkPrice(uint32 assetId) private view returns (uint64) {
        // Use low-level staticcall with only ABI-encoded arguments (no function selector)
        (bool success, bytes memory data) = l1Reader.staticcall(
            abi.encode(assetId)
        );
        
        // The precompile returns an empty byte array on failure, not a revert
        if (!success || data.length == 0) {
            revert("Precompile call to get mark price failed");
        }
        
        return abi.decode(data, (uint64));
    }

    function takePriceSnapshot() external onlyKeeper {
        uint256 timeElapsed = block.timestamp - lastTwapUpdateTime;
        if (timeElapsed > 0) {
            // Get the volatility from the *previous* period
            uint256 lastAnnualizedVol = getAnnualizedVolatility(); 
            // Add the last known volatility multiplied by the time elapsed to the accumulator
            cumulativeVolatility += lastAnnualizedVol * timeElapsed;
        }
        // Update the timestamp AFTER updating the accumulator
        lastTwapUpdateTime = block.timestamp;

        uint64 newPrice = _getMarkPrice(underlyingAssetId);
        if (newPrice == 0) revert ZeroPrice();

        // If this is the first update after deployment, just update price and return
        if (lastPrice == 0) {
            lastPrice = newPrice;
            lastUpdateTime = block.timestamp;
            return;
        }

        // Calculate price change percentage instead of using ln() which has stability issues
        // For small changes, ln(1+x) ≈ x when x is small, so we can use simple percentage
        uint256 logReturnSquaredRaw;
        
        if (newPrice > lastPrice) {
            // Price increase: use (newPrice - lastPrice) / lastPrice
            uint256 pctChange = ((uint256(newPrice) - uint256(lastPrice)) * 1e18) / uint256(lastPrice);
            logReturnSquaredRaw = (pctChange * pctChange) / 1e18;
        } else if (newPrice < lastPrice) {
            // Price decrease: use (lastPrice - newPrice) / lastPrice  
            uint256 pctChange = ((uint256(lastPrice) - uint256(newPrice)) * 1e18) / uint256(lastPrice);
            logReturnSquaredRaw = (pctChange * pctChange) / 1e18;
        } else {
            // No price change
            logReturnSquaredRaw = 0;
        }
        
        UD60x18 logReturnSquared = ud(logReturnSquaredRaw);

        // Apply EWMA formula: σ_t^2 = λ * σ_{t-1}^2 + (1-λ) * r_t^2
        UD60x18 lambdaUD = ud(lambda);
        UD60x18 oneMinusLambda = ud(1e18).sub(lambdaUD);
        UD60x18 currentVarianceUD = ud(currentVariance);
        
        UD60x18 term1 = lambdaUD.mul(currentVarianceUD);
        UD60x18 term2 = oneMinusLambda.mul(logReturnSquared);
        UD60x18 newVariance = term1.add(term2);

        // Update state
        currentVariance = newVariance.unwrap();
        lastPrice = newPrice;
        lastUpdateTime = block.timestamp;

        emit VolatilityUpdated(
            currentVariance,
            getAnnualizedVolatility(),
            block.timestamp
        );
    }

    function getVolatilityState() external view returns (uint256 vol, uint256 lastUpdate) {
        // A view function can't change state, so we project the current value
        // without actually storing it.
        uint256 timeElapsed = block.timestamp - lastTwapUpdateTime;
        uint256 projectedCumulativeVol = cumulativeVolatility + (getAnnualizedVolatility() * timeElapsed);
        return (projectedCumulativeVol, block.timestamp);
    }

    function getAnnualizedVolatility() public view returns (uint256) {
        if (currentVariance == 0) return 0;
        
        // Calculate standard deviation: sigma = sqrt(currentVariance)
        UD60x18 stdDev = ud(currentVariance).sqrt();
        
        // Annualize it: sigma_annual = sigma * sqrt(annualizationFactor)
        UD60x18 annualizationSqrt = ud(annualizationFactor * 1e18).sqrt();
        
        return stdDev.mul(annualizationSqrt).unwrap();
    }

    function getTwapVolatility(uint32 twapInterval) public view returns (uint256) {
        if (twapInterval == 0) return getAnnualizedVolatility();
        
        // Calculate current cumulative value up to block.timestamp
        uint256 timeElapsed = block.timestamp - lastTwapUpdateTime;
        timeElapsed; // Suppress unused variable warning - used for future TWAP implementation

        if (block.timestamp <= twapInterval) {
            return getAnnualizedVolatility();
        }
        
        // This is a simplified implementation
        // Real implementation would need historical data storage
        return getAnnualizedVolatility();
    }

    // --- View Functions ---
    function getCurrentVariance() external view returns (uint256) {
        return currentVariance;
    }

    function getLastPrice() external view returns (uint64) {
        return lastPrice;
    }

    function getLastUpdateTime() external view returns (uint256) {
        return lastUpdateTime;
    }
}