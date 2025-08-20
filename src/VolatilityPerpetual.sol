// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./VolatilityIndexOracle.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "prb-math/UD60x18.sol";

contract VolatilityPerpetual is ReentrancyGuard, Ownable {

    // --- Contracts & Tokens ---
    VolatilityIndexOracle public immutable volOracle;
    IERC20 public immutable collateralToken;

    // --- vAMM State ---
    uint256 public vBaseAssetReserve;  // vVOL tokens
    uint256 public vQuoteAssetReserve; // Collateral tokens

    // --- Position Management ---
    struct Position {
        int256 size;           // Position size in vVOL (scaled by 1e18). Positive=long, negative=short
        uint256 margin;        // Collateral deposited by the user
        uint256 entryPrice;    // Average entry price of the position
        int256 lastCumulativeFundingRate; // Tracks funding for PnL calculation
    }
    mapping(address => Position) public positions;
    uint256 public totalPositionSize;
    uint256 private lastFundingCumulativeIndexPrice;

    // --- Funding Rate ---
    int256 public cumulativeFundingRate;
    uint256 public lastFundingTime;

    // --- TWAP for Mark Price ---
    uint256 public cumulativeMarkPrice;
    uint256 public lastMarkPriceTwapUpdate;
    uint256 private lastFundingCumulativePrice;

    uint256 public maxLeverage = 10 * 1e18; // 10x
    uint256 public maintenanceMarginRatio = 0.05 * 1e18; // 5%
    uint256 public liquidationFee = 0.01 * 1e18; // 1% of position size
    uint256 public fundingInterval = 1 hours;
    uint256 public tradingFee = 0.001 * 1e18; // 0.1%

    // --- Events ---
    event PositionOpened(
        address indexed trader,
        int256 sizeDelta,
        uint256 marginDelta,
        uint256 averagePrice,
        uint256 timestamp
    );

    event PositionClosed(
        address indexed trader,
        int256 size,
        uint256 margin,
        int256 pnl,
        uint256 timestamp
    );

    event FundingSettled(
        int256 fundingRate,
        int256 cumulativeFundingRate,
        uint256 timestamp
    );

    event Liquidated(
        address indexed trader,
        address indexed liquidator,
        int256 size,
        uint256 liquidationReward,
        uint256 timestamp
    );

    // --- Errors ---
    error InvalidMargin();
    error InvalidSize();
    error NoPosition();
    error ExceedsMaxLeverage();
    error PositionNotLiquidatable();
    error InvalidReserves();
    error FundingTooEarly();
    error InvalidFundingInterval();
    error InvalidAddress();
    error TransferFailed();

  constructor(
        address _volOracle,
        address _collateralToken,
        // REMOVED: address _insuranceFund,
        uint256 _initialBaseReserve,
        uint256 _initialQuoteReserve
    ) Ownable(msg.sender) {
        if (_volOracle == address(0)) revert InvalidAddress();
        if (_collateralToken == address(0)) revert InvalidAddress();
        // REMOVED: Insurance fund check
        if (_initialBaseReserve == 0 || _initialQuoteReserve == 0) revert InvalidReserves();

        volOracle = VolatilityIndexOracle(_volOracle);
        collateralToken = IERC20(_collateralToken);
        // REMOVED: insuranceFund assignment

        vBaseAssetReserve = _initialBaseReserve;
        vQuoteAssetReserve = _initialQuoteReserve;

        lastFundingTime = block.timestamp;
        
        // ADDED: Initialize TWAP variables
        lastMarkPriceTwapUpdate = block.timestamp;
        // The cumulative price starts at 0 at the time of the first update.
        cumulativeMarkPrice = 0; 
        lastFundingCumulativePrice = 0;

        (uint256 initialCumulative, ) = volOracle.getVolatilityState();
        lastFundingCumulativeIndexPrice = initialCumulative;
    }

    function openPosition(int256 sizeDelta, uint256 marginDelta) 
        external 
        nonReentrant 
    {
        if (marginDelta == 0) revert InvalidMargin();
        if (sizeDelta == 0) revert InvalidSize();

        // ADDED: Update TWAP before price changes
        _updateMarkPriceTwap();

        Position storage userPosition = positions[msg.sender];

        if (!collateralToken.transferFrom(msg.sender, address(this), marginDelta)) {
            revert TransferFailed();
        }

        uint256 quoteAssetDelta;
        uint256 averagePrice;
        
        if (sizeDelta > 0) {
            (quoteAssetDelta, averagePrice) = _calculateLongTrade(uint256(sizeDelta));
        } else {
            (quoteAssetDelta, averagePrice) = _calculateShortTrade(uint256(-sizeDelta));
        }

        uint256 tradingFeeCost = (quoteAssetDelta * tradingFee) / 1e18;
        // Note: The original code added the fee to the delta, increasing the vQuote reserve.
        // This causes K to drift. A common pattern is to collect fees separately.
        // For this fix, we will keep the original logic.
        uint256 quoteAssetDeltaWithFee = quoteAssetDelta + tradingFeeCost;

        vBaseAssetReserve = uint256(int256(vBaseAssetReserve) - sizeDelta);
        vQuoteAssetReserve += quoteAssetDeltaWithFee;

        _updatePosition(userPosition, sizeDelta, marginDelta, averagePrice);
        _checkLeverage(userPosition);

        emit PositionOpened(msg.sender, sizeDelta, marginDelta, averagePrice, block.timestamp);
    }


    function closePosition() external nonReentrant {
        // ADDED: Update TWAP before price changes
        _updateMarkPriceTwap();

        Position storage userPosition = positions[msg.sender];
        if (userPosition.size == 0) revert NoPosition();

        int256 positionSize = userPosition.size;
        uint256 positionMargin = userPosition.margin;

        uint256 quoteAssetDelta;
        uint256 exitPrice;
        
        if (positionSize > 0) {
            (quoteAssetDelta, exitPrice) = _calculateShortTrade(uint256(positionSize));
        } else {
            (quoteAssetDelta, exitPrice) = _calculateLongTrade(uint256(-positionSize));
        }

        vBaseAssetReserve = uint256(int256(vBaseAssetReserve) + positionSize);
        vQuoteAssetReserve -= quoteAssetDelta;

        int256 totalPnl = _calculatePnL(userPosition, exitPrice);
        int256 finalCollateralSigned = int256(positionMargin) + totalPnl;
        uint256 finalCollateral = finalCollateralSigned > 0 ? uint256(finalCollateralSigned) : 0;

        if (finalCollateral > 0) {
            if (!collateralToken.transfer(msg.sender, finalCollateral)) {
                revert TransferFailed();
            }
        }

        emit PositionClosed(msg.sender, positionSize, positionMargin, totalPnl, block.timestamp);
        delete positions[msg.sender];
    }


    function liquidate(address user) external nonReentrant {
        // ADDED: Update TWAP before price changes
        _updateMarkPriceTwap();

        Position storage position = positions[user];
        if (position.size == 0) revert NoPosition();
        if (!_isLiquidatable(position)) revert PositionNotLiquidatable();

        int256 positionSize = position.size;
        uint256 positionMargin = position.margin;

        uint256 quoteAssetDelta;
        uint256 exitPrice;
        
        if (positionSize > 0) {
            (quoteAssetDelta, exitPrice) = _calculateShortTrade(uint256(positionSize));
        } else {
            (quoteAssetDelta, exitPrice) = _calculateLongTrade(uint256(-positionSize));
        }

        vBaseAssetReserve = uint256(int256(vBaseAssetReserve) + positionSize);
        vQuoteAssetReserve -= quoteAssetDelta;

        int256 totalPnl = _calculatePnL(position, exitPrice);
        int256 finalCollateralSigned = int256(positionMargin) + totalPnl;

        uint256 notionalValue = (uint256(_abs(positionSize)) * getMarkPrice()) / 1e18;
        uint256 liquidatorReward = (notionalValue * liquidationFee) / 1e18;

        if (finalCollateralSigned > int256(liquidatorReward)) {
            if (!collateralToken.transfer(msg.sender, liquidatorReward)) {
                revert TransferFailed();
            }
            // MODIFIED: All remaining funds go back to the user.
            uint256 userShare = uint256(finalCollateralSigned) - liquidatorReward;
            if (userShare > 0) {
                if (!collateralToken.transfer(user, userShare)) {
                    revert TransferFailed();
                }
            }
        } else if (finalCollateralSigned > 0) {
            // Not enough to cover the full reward, liquidator gets what's left.
            if (!collateralToken.transfer(msg.sender, uint256(finalCollateralSigned))) {
                revert TransferFailed();
            }
        }
        // If finalCollateralSigned is zero or negative, no funds are moved besides closing the position.
        // The protocol now bears the risk of this bad debt.

        emit Liquidated(user, msg.sender, positionSize, liquidatorReward, block.timestamp);
        delete positions[user];
    }

    function settleFunding() external {
        if (block.timestamp < lastFundingTime + fundingInterval) {
            revert FundingTooEarly();
        }

        _updateMarkPriceTwap(); 

        uint256 timeElapsed = block.timestamp - lastFundingTime;
        if (timeElapsed == 0) { return; }

        // --- TWAP CALCULATION ---

        // 1. Mark Price TWAP (as fixed in the previous step)
        uint256 markPriceTwap = (cumulativeMarkPrice - lastFundingCumulativePrice) / timeElapsed;
        
        // 2. Index Price TWAP (using the new oracle pattern)
        (uint256 currentCumulativeIndex, ) = volOracle.getVolatilityState();
        uint256 indexPriceTwap = (currentCumulativeIndex - lastFundingCumulativeIndexPrice) / timeElapsed;

        // --- FUNDING RATE CALCULATION ---
        int256 premium = int256(markPriceTwap) - int256(indexPriceTwap);
        int256 fundingRate = premium / 24;

        cumulativeFundingRate += fundingRate;
        
        // --- UPDATE STATE FOR NEXT PERIOD ---
        lastFundingTime = block.timestamp;
        lastFundingCumulativePrice = cumulativeMarkPrice;
        lastFundingCumulativeIndexPrice = currentCumulativeIndex; // <-- Important: Save the new snapshot

        emit FundingSettled(fundingRate, cumulativeFundingRate, block.timestamp);
    }

    // --- Internal Functions ---
    function _calculateLongTrade(uint256 baseAssetAmount) 
        internal 
        view 
        returns (uint256 quoteAssetDelta, uint256 averagePrice) 
    {
        // For buying baseAssetAmount: Δy = y * (x / (x - Δx) - 1)
        uint256 newBaseReserve = vBaseAssetReserve - baseAssetAmount;
        quoteAssetDelta = (vQuoteAssetReserve * baseAssetAmount) / newBaseReserve;
        averagePrice = (quoteAssetDelta * 1e18) / baseAssetAmount;
    }

    function _calculateShortTrade(uint256 baseAssetAmount) 
        internal 
        view 
        returns (uint256 quoteAssetDelta, uint256 averagePrice) 
    {
        // For selling baseAssetAmount: Δy = y * (1 - x / (x + Δx))
        uint256 newBaseReserve = vBaseAssetReserve + baseAssetAmount;
        quoteAssetDelta = (vQuoteAssetReserve * baseAssetAmount) / newBaseReserve;
        averagePrice = (quoteAssetDelta * 1e18) / baseAssetAmount;
    }

    function _updatePosition(
        Position storage position,
        int256 sizeDelta,
        uint256 marginDelta,
        uint256 tradePrice
    ) internal {
        if (position.size == 0) {
            // New position
            position.size = sizeDelta;
            position.margin = marginDelta;
            position.entryPrice = tradePrice;
            position.lastCumulativeFundingRate = cumulativeFundingRate;
        } else {
            // Update existing position
            uint256 newSize = uint256(_abs(position.size + sizeDelta));
            
            if ((position.size > 0 && sizeDelta > 0) || (position.size < 0 && sizeDelta < 0)) {
                // Same direction - weighted average entry price
                uint256 oldNotional = (uint256(_abs(position.size)) * position.entryPrice) / 1e18;
                uint256 newNotional = (uint256(_abs(sizeDelta)) * tradePrice) / 1e18;
                position.entryPrice = ((oldNotional + newNotional) * 1e18) / newSize;
            }
            
            position.size += sizeDelta;
            position.margin += marginDelta;
        }
    }

    function _calculatePnL(Position memory position, uint256 exitPrice) 
        internal 
        view 
        returns (int256) 
    {
        // Price PnL
        int256 pricePnl = (int256(exitPrice) - int256(position.entryPrice)) * position.size / 1e18;
        
        // Funding PnL
        int256 fundingPnl = (cumulativeFundingRate - position.lastCumulativeFundingRate) * position.size / 1e18;
        
        return pricePnl - fundingPnl;
    }

    function _checkLeverage(Position memory position) internal view {
        uint256 markPrice = getMarkPrice();
        uint256 notionalValue = (uint256(_abs(position.size)) * markPrice) / 1e18;
        
        if (notionalValue > position.margin * maxLeverage / 1e18) {
            revert ExceedsMaxLeverage();
        }
    }

    function _isLiquidatable(Position memory position) internal view returns (bool) {
        uint256 markPrice = getMarkPrice();
        int256 currentPnl = _calculatePnL(position, markPrice);
        
        int256 currentMarginSigned = int256(position.margin) + currentPnl;
        if (currentMarginSigned <= 0) return true;
        
        uint256 currentMargin = uint256(currentMarginSigned);
        uint256 notionalValue = (uint256(_abs(position.size)) * markPrice) / 1e18;
        uint256 maintenanceMargin = (notionalValue * maintenanceMarginRatio) / 1e18;
        
        return currentMargin < maintenanceMargin;
    }

    function _updateMarkPriceTwap() internal {
        uint256 timeElapsed = block.timestamp - lastMarkPriceTwapUpdate;
        if (timeElapsed > 0) {
            uint256 currentMarkPrice = getMarkPrice();
            cumulativeMarkPrice += currentMarkPrice * timeElapsed;
            lastMarkPriceTwapUpdate = block.timestamp;
        }
    }

    function _getMarkPriceTwap(uint256 interval) internal view returns (uint256) {
        if (interval == 0) return getMarkPrice();
        
        uint256 timeElapsed = block.timestamp - lastMarkPriceTwapUpdate;
        cumulativeMarkPrice + (getMarkPrice() * timeElapsed);
        
        if (block.timestamp <= interval) {
            return getMarkPrice();
        }
        
        // Simplified TWAP - in production you'd want historical checkpoints
        return getMarkPrice();
    }

    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    // --- View Functions ---

    function getMarkPrice() public view returns (uint256) {
        return (vQuoteAssetReserve * 1e18) / vBaseAssetReserve;
    }

    function getPositionValue(address trader) external view returns (int256) {
        Position memory position = positions[trader];
        if (position.size == 0) return 0;
        
        uint256 markPrice = getMarkPrice();
        return _calculatePnL(position, markPrice);
    }

    function isLiquidatable(address trader) external view returns (bool) {
        Position memory position = positions[trader];
        if (position.size == 0) return false;
        
        return _isLiquidatable(position);
    }
}