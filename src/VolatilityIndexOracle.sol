// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/L1Read.sol";
import {UD60x18, ud, unwrap, convert} from "prb-math/UD60x18.sol";

contract VolatilityIndexOracle {
    // --- Interfaces & Constants ---
    address public immutable l1Reader;
    address public immutable keeper;

    // --- Asset & EWMA Configuration ---
    uint32 public immutable underlyingAssetId;
    uint   public immutable lambda;
    uint   public immutable annualizationFactor;

    // --- Core State ---
    uint64 public lastPrice;
    uint   public currentVariance;
    uint   public lastUpdateTime;

    uint public cumulativeVolatility;
    uint public lastTwapUpdateTime;

    // --- Events ---
    event VolatilityUpdated(
        uint indexed newVariance, uint indexed annualizedVolatility, uint indexed timestamp
    );

    // --- Errors ---
    error OnlyKeeper();
    error InvalidLambda();
    error InvalidAddress();
    error InvalidAnnualizationFactor();
    error ZeroPrice();

    // --- Modifiers ---
    modifier onlyKeeper()  {
        if (msg.sender != keeper) revert OnlyKeeper();
        _;
    }

    constructor(
        address  _l1ReadAddress,
        address  _keeperAddress,
        uint32   _assetId,
        uint     _lambda,
        uint     _annualizationFactor,
        uint     _initialVariance
    )  {
        if (_l1ReadAddress       = = address(0)) revert InvalidAddress();
        if (_keeperAddress       = = address(0)) revert InvalidAddress();
        if (_lambda >            = 1e18 || _lambda == 0) revert InvalidLambda();
        if (_annualizationFactor = = 0) revert InvalidAnnualizationFactor();

        l1Reader            = _l1ReadAddress;
        keeper              = _keeperAddress;
        underlyingAssetId   = _assetId;
        lambda              = _lambda;
        annualizationFactor = _annualizationFactor;

        // Initialize with zero price - will be set on first price snapshot
        lastPrice          = 0;
        currentVariance    = _initialVariance;
        lastUpdateTime     = block.timestamp;
        lastTwapUpdateTime = block.timestamp;
    }

    // --- Internal Helper Functions ---
    function _getMarkPrice(uint32 assetId)
        private
        view
        returns
        (uint64)
    {
        (bool success, bytes memory data) = l1Reader.staticcall(abi.encode(assetId));

        if (!success || data.length == 0)  {
            revert("Precompile call to get mark price failed");
        }

        return abi.decode(data, (uint64));
    }

    function takePriceSnapshot()
        external
        onlyKeeper
    {
        uint timeElapsed = block.timestamp - lastTwapUpdateTime;
        if (timeElapsed > 0)  {
            uint                 lastAnnualizedVol = getAnnualizedVolatility();
            cumulativeVolatility +                 = lastAnnualizedVol * timeElapsed;
        }
        lastTwapUpdateTime = block.timestamp;

        uint64 newPrice  = _getMarkPrice(underlyingAssetId);
        if     (newPrice = = 0) revert ZeroPrice();

        if (lastPrice     = = 0)  {
               lastPrice      = newPrice;
               lastUpdateTime = block.timestamp;
            return;
        }

        uint logReturnSquaredRaw;

        if (newPrice > lastPrice)  {
            // Price increase: use (newPrice - lastPrice) / lastPrice
            uint pctChange           = ((uint(newPrice) - uint(lastPrice)) * 1e18) / uint(lastPrice);
                 logReturnSquaredRaw = (pctChange * pctChange) / 1e18;
        } else if (newPrice < lastPrice)  {
            // Price decrease: use (lastPrice - newPrice) / lastPrice
            uint pctChange           = ((uint(lastPrice) - uint(newPrice)) * 1e18) / uint(lastPrice);
                 logReturnSquaredRaw = (pctChange * pctChange) / 1e18;
        } else {
            // No price change
            logReturnSquaredRaw = 0;
        }

        UD60x18 logReturnSquared = ud(logReturnSquaredRaw);

        UD60x18 lambdaUD          = ud(lambda);
        UD60x18 oneMinusLambda    = ud(1e18) - lambdaUD;
        UD60x18 currentVarianceUD = ud(currentVariance);

        UD60x18 term1       = lambdaUD * currentVarianceUD;
        UD60x18 term2       = oneMinusLambda * logReturnSquared;
        UD60x18 newVariance = term1 + term2;

        // Update state
        currentVariance = unwrap(newVariance);
        lastPrice       = newPrice;
        lastUpdateTime  = block.timestamp;

        emit VolatilityUpdated(currentVariance, getAnnualizedVolatility(), block.timestamp);
    }

    function getVolatilityState()
        external
        view
        returns
        (uint
        vol,
        uint
        lastUpdate)
    {
        uint timeElapsed            = block.timestamp - lastTwapUpdateTime;
        uint projectedCumulativeVol = cumulativeVolatility + (getAnnualizedVolatility() * timeElapsed);
        return (projectedCumulativeVol, block.timestamp);
    }

    function getAnnualizedVolatility()
        public
        view
        returns
        (uint)
    {
        if (currentVariance == 0) return 0;

        UD60x18 stdDev = ud(currentVariance).sqrt();

        UD60x18 annualizationSqrt = ud(annualizationFactor * 1e18).sqrt();

        return unwrap(stdDev * annualizationSqrt);
    }

    // --- View Functions ---
    function getCurrentVariance()
        external
        view
        returns
        (uint)
    {
        return currentVariance;
    }

    function getLastPrice()
        external
        view
        returns
        (uint64)
    {
        return lastPrice;
    }

    function getLastUpdateTime()
        external
        view
        returns
        (uint)
    {
        return lastUpdateTime;
    }
}