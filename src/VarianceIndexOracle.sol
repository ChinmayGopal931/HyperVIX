// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./interfaces/L1Read.sol";
import {UD60x18, ud, unwrap, convert} from "prb-math/UD60x18.sol";

contract VarianceIndexOracle {
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

    uint public cumulativeVariance;
    uint public lastTwapUpdateTime;

    // --- Events ---
    event VarianceUpdated(uint indexed newVariance, uint indexed annualizedVariance, uint indexed timestamp);

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
        if    (!success || data.length    = = 0)  {
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
            uint               lastAnnualizedVar = getAnnualizedVariance();
            cumulativeVariance +                 = lastAnnualizedVar * timeElapsed;
        }
        lastTwapUpdateTime = block.timestamp;

        // --- 2. Fetch New Price ---
        uint64 newPrice  = _getMarkPrice(underlyingAssetId);
        if     (newPrice = = 0) revert ZeroPrice();

        if (lastPrice     = = 0)  {
               lastPrice      = newPrice;
               lastUpdateTime = block.timestamp;
            return;
        }
        uint logReturnSquaredRaw;
        if (newPrice > lastPrice)  {
            uint pctChange           = ((uint(newPrice) - uint(lastPrice)) * 1e18) / uint(lastPrice);
                 logReturnSquaredRaw = (pctChange * pctChange) / 1e18;
        } else {
            uint pctChange           = ((uint(lastPrice) - uint(newPrice)) * 1e18) / uint(lastPrice);
                 logReturnSquaredRaw = (pctChange * pctChange) / 1e18;
        }

        UD60x18 logReturnSquared  = ud(logReturnSquaredRaw);
        UD60x18 lambdaUD          = ud(lambda);
        UD60x18 oneMinusLambda    = ud(1e18) - lambdaUD;
        UD60x18 currentVarianceUD = ud(currentVariance);

        UD60x18 term1       = lambdaUD * currentVarianceUD;
        UD60x18 term2       = oneMinusLambda * logReturnSquared;
        UD60x18 newVariance = term1 + term2;

        // --- 5. Update State ---
        currentVariance = unwrap(newVariance);
        lastPrice       = newPrice;
        lastUpdateTime  = block.timestamp;

        emit VarianceUpdated(currentVariance, getAnnualizedVariance(), block.timestamp);
    }

    function getVarianceState()
        external
        view
        returns
        (uint
        cumulativeVar,
        uint
        lastUpdate)
    {
        uint timeElapsed            = block.timestamp - lastTwapUpdateTime;
        uint projectedCumulativeVar = cumulativeVariance + (getAnnualizedVariance() * timeElapsed);
        return (projectedCumulativeVar, block.timestamp);
    }

    function getAnnualizedVariance()
        public
        view
        returns
        (uint)
    {
        return currentVariance * annualizationFactor;
    }

    function getAnnualizedVolatility()
        public
        view
        returns
        (uint)
    {
        if (currentVariance == 0) return 0;

        UD60x18 annualizedVariance = ud(getAnnualizedVariance());
        return unwrap(annualizedVariance.sqrt());
    }

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
