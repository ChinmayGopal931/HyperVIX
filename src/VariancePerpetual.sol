// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./VarianceIndexOracle.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "prb-math/UD60x18.sol";

contract VolatilityPerpetual is ReentrancyGuard, Ownable {

    // --- Contracts & Tokens ---
    VarianceIndexOracle public immutable volOracle;
    IERC20 public immutable collateralToken;
    uint8 public immutable collateralDecimals;
    uint256 private immutable collateralScalingFactor;

    // --- vAMM State ---
    uint256 public vBaseAssetReserve;  // vVOL tokens
    uint256 public vQuoteAssetReserve; // Collateral tokens

    // --- Position Management ---
    struct Position {
        int256 size; 
        uint256 margin;
        uint256 entryPrice;
        int256 lastCumulativeFundingRate;
    }
    mapping(address => Position) public positions;
    uint256 public totalPositionSize;
    uint256 private lastFundingCumulativeIndexPrice;
    
    // --- Open Interest Tracking ---
    uint256 public totalLongSize;   // Total size of all long positions
    uint256 public totalShortSize;  // Total size of all short positions

    // --- Funding Rate ---
    int256 public cumulativeFundingRate;
    uint256 public lastFundingTime;

    // --- TWAP for Mark Price ---
    uint256 public cumulativeMarkPrice;
    uint256 public lastMarkPriceTwapUpdate;
    uint256 private lastFundingCumulativePrice;

    uint256 public maxLeverage = 10 * 1e18; 
    uint256 public maintenanceMarginRatio = 0.05 * 1e18; 
    uint256 public liquidationFee = 0.01 * 1e18; 
    uint256 public fundingInterval = 1 hours;
    uint256 public tradingFee = 0.001 * 1e18;

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
        uint256 _initialBaseReserve,
        uint256 _initialQuoteReserve
    ) Ownable(msg.sender) {
        if (_volOracle == address(0)) revert InvalidAddress();
        if (_collateralToken == address(0)) revert InvalidAddress();
        if (_initialBaseReserve == 0 || _initialQuoteReserve == 0) revert InvalidReserves();

        volOracle = VarianceIndexOracle(_volOracle);
        collateralToken = IERC20(_collateralToken);
        collateralDecimals = 6;
        collateralScalingFactor = 10**(18 - collateralDecimals);

        vBaseAssetReserve = _initialBaseReserve;
        vQuoteAssetReserve = _initialQuoteReserve * collateralScalingFactor;

        lastFundingTime = block.timestamp;
        
        lastMarkPriceTwapUpdate = block.timestamp;
        cumulativeMarkPrice = 0; 
        lastFundingCumulativePrice = 0;

        (uint256 initialCumulative, ) = volOracle.getVarianceState();
        lastFundingCumulativeIndexPrice = initialCumulative;
    }

    function openPosition(int256 sizeDelta, uint256 marginDelta) 
        external 
        nonReentrant 
    {
        if (marginDelta == 0) revert InvalidMargin();
        if (sizeDelta == 0) revert InvalidSize();

        _updateMarkPriceTwap();

        Position storage userPosition = positions[msg.sender];

        if (!collateralToken.transferFrom(msg.sender, address(this), marginDelta)) {
            revert TransferFailed();
        }

        // Scale margin to 18 decimals for internal accounting
        uint256 scaledMarginDelta = marginDelta * collateralScalingFactor;

        uint256 quoteAssetDelta;
        uint256 averagePrice;
        
        if (sizeDelta > 0) {
            (quoteAssetDelta, averagePrice) = _calculateLongTrade(uint256(sizeDelta));
        } else {
            (quoteAssetDelta, averagePrice) = _calculateShortTrade(uint256(-sizeDelta));
        }

        uint256 tradingFeeCost = (quoteAssetDelta * tradingFee) / 1e18;
        uint256 quoteAssetDeltaWithFee = quoteAssetDelta + tradingFeeCost;

        vBaseAssetReserve = uint256(int256(vBaseAssetReserve) - sizeDelta);
        vQuoteAssetReserve += quoteAssetDeltaWithFee;

        _updatePosition(userPosition, sizeDelta, scaledMarginDelta, averagePrice);
        _checkLeverage(userPosition);

        emit PositionOpened(msg.sender, sizeDelta, marginDelta, averagePrice, block.timestamp);
    }


    function closePosition() external nonReentrant {
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
            // Un-scale collateral before transferring
            uint256 amountToTransfer = finalCollateral / collateralScalingFactor;
            if (!collateralToken.transfer(msg.sender, amountToTransfer)) {
                revert TransferFailed();
            }
        }

        emit PositionClosed(msg.sender, positionSize, positionMargin, totalPnl, block.timestamp);
        delete positions[msg.sender];
    }


    function liquidate(address user) external nonReentrant {
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
            // Un-scale liquidator reward before transferring
            uint256 rewardToTransfer = liquidatorReward / collateralScalingFactor;
            if (!collateralToken.transfer(msg.sender, rewardToTransfer)) {
                revert TransferFailed();
            }
            uint256 userShare = uint256(finalCollateralSigned) - liquidatorReward;
            if (userShare > 0) {
                // Un-scale user share before transferring
                uint256 userShareToTransfer = userShare / collateralScalingFactor;
                if (!collateralToken.transfer(user, userShareToTransfer)) {
                    revert TransferFailed();
                }
            }
        } else if (finalCollateralSigned > 0) {
            uint256 amountToTransfer = uint256(finalCollateralSigned) / collateralScalingFactor;
            if (!collateralToken.transfer(msg.sender, amountToTransfer)) {
                revert TransferFailed();
            }
        }

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


        uint256 markPriceTwap = (cumulativeMarkPrice - lastFundingCumulativePrice) / timeElapsed;
        
        (uint256 currentCumulativeIndex, ) = volOracle.getVarianceState();
        uint256 indexPriceTwap = (currentCumulativeIndex - lastFundingCumulativeIndexPrice) / timeElapsed;

        int256 premium = int256(markPriceTwap) - int256(indexPriceTwap);
        int256 fundingRate = premium / 24;

        cumulativeFundingRate += fundingRate;
        
        // --- UPDATE STATE FOR NEXT PERIOD ---
        lastFundingTime = block.timestamp;
        lastFundingCumulativePrice = cumulativeMarkPrice;
        lastFundingCumulativeIndexPrice = currentCumulativeIndex;

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
        uint256 newBaseReserve = vBaseAssetReserve + baseAssetAmount;
        quoteAssetDelta = (vQuoteAssetReserve * baseAssetAmount) / newBaseReserve;
        averagePrice = (quoteAssetDelta * 1e18) / baseAssetAmount;
    }

    function _updateOpenInterest(int256 oldSize, int256 newSize) internal {
        if (oldSize > 0) {
            totalLongSize -= uint256(oldSize);
        } else if (oldSize < 0) {
            totalShortSize -= uint256(-oldSize);
        }
        
        if (newSize > 0) {
            totalLongSize += uint256(newSize);
        } else if (newSize < 0) {
            totalShortSize += uint256(-newSize);
        }
    }

    function _updatePosition(
        Position storage position,
        int256 sizeDelta,
        uint256 marginDelta,
        uint256 tradePrice
    ) internal {
        int256 oldSize = position.size;
        
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
                uint256 oldNotional = (uint256(_abs(position.size)) * position.entryPrice) / 1e18;
                uint256 newNotional = (uint256(_abs(sizeDelta)) * tradePrice) / 1e18;
                position.entryPrice = ((oldNotional + newNotional) * 1e18) / newSize;
            }
            
            position.size += sizeDelta;
            position.margin += marginDelta;
        }
        
        // Update Open Interest tracking
        _updateOpenInterest(oldSize, position.size);
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

    struct PositionDetails {
        int256 size;
        uint256 margin;
        uint256 entryPrice;
        int256 unrealizedPnl;
        uint256 notionalValue;
        uint256 leverage;    
        uint256 marginRatio;    
        bool isLiquidatable;
        uint256 markPrice;
    }

    function getPositionDetails(address trader) external view returns (PositionDetails memory) {
        Position memory pos = positions[trader];
        if (pos.size == 0) {
            return PositionDetails(0, 0, 0, 0, 0, 0, 0, false, getMarkPrice());
        }

        uint256 markPrice = getMarkPrice();
        int256 pnl = _calculatePnL(pos, markPrice);
        uint256 notional = (uint256(_abs(pos.size)) * markPrice) / 1e18;
        
        // Calculate current margin (initial margin + unrealized PnL)
        int256 currentMarginSigned = int256(pos.margin) + pnl;
        uint256 marginRatio = 0;
        uint256 leverage = 0;
        
        if (currentMarginSigned > 0 && notional > 0) {
            marginRatio = (uint256(currentMarginSigned) * 1e18) / notional;
            leverage = (notional * 1e18) / uint256(currentMarginSigned);
        } else if (pos.margin > 0) {
            // Fallback to initial margin if current margin is negative
            leverage = (notional * 1e18) / pos.margin;
        }

        return PositionDetails({
            size: pos.size,
            margin: pos.margin,
            entryPrice: pos.entryPrice,
            unrealizedPnl: pnl,
            notionalValue: notional,
            leverage: leverage,
            marginRatio: marginRatio,
            isLiquidatable: _isLiquidatable(pos),
            markPrice: markPrice
        });
    }

    // --- Open Interest View Functions ---
    function getTotalOpenInterest() external view returns (uint256 totalLongs, uint256 totalShorts, uint256 netExposure) {
        totalLongs = totalLongSize;
        totalShorts = totalShortSize;
        netExposure = totalLongs > totalShorts ? 
            totalLongs - totalShorts : 
            totalShorts - totalLongs;
    }

    // --- Trade Preview and Slippage ---
    function getTradePreview(int256 sizeDelta) 
        external 
        view 
        returns (uint256 averagePrice, uint256 priceImpact, uint256 tradingFeeCost) 
    {
        if (sizeDelta == 0) return (0, 0, 0);

        uint256 initialPrice = getMarkPrice();
        uint256 quoteAssetDelta;
        
        if (sizeDelta > 0) {
            (quoteAssetDelta, averagePrice) = _calculateLongTrade(uint256(sizeDelta));
        } else {
            (quoteAssetDelta, averagePrice) = _calculateShortTrade(uint256(-sizeDelta));
        }

        // Calculate trading fee
        tradingFeeCost = (quoteAssetDelta * tradingFee) / 1e18;

        // Price impact is the percentage difference from the mark price
        if (averagePrice > initialPrice) {
            priceImpact = ((averagePrice - initialPrice) * 1e18) / initialPrice;
        } else {
            priceImpact = ((initialPrice - averagePrice) * 1e18) / initialPrice;
        }
    }

    function getRequiredMargin(int256 sizeDelta) external view returns (uint256 minMarginRequired) {
        if (sizeDelta == 0) return 0;
        
        uint256 quoteAssetDelta;
        uint256 averagePrice;
        
        if (sizeDelta > 0) {
            (quoteAssetDelta, averagePrice) = _calculateLongTrade(uint256(sizeDelta));
        } else {
            (quoteAssetDelta, averagePrice) = _calculateShortTrade(uint256(-sizeDelta));
        }
        
        uint256 tradingFeeCost = (quoteAssetDelta * tradingFee) / 1e18;
        uint256 totalCost = quoteAssetDelta + tradingFeeCost;
        
        minMarginRequired = (totalCost * 1e18) / maxLeverage;
    }

    function getLiquidationPrice(address trader) external view returns (uint256 liquidationPrice) {
        Position memory pos = positions[trader];
        if (pos.size == 0) return 0;
        
        int256 sizeAbs = int256(_abs(pos.size));
        int256 marginSigned = int256(pos.margin);
        int256 entryPriceSigned = int256(pos.entryPrice);
        int256 maintenanceRatio = int256(maintenanceMarginRatio);
        
        int256 coefficient = (pos.size * 1e18) - (sizeAbs * maintenanceRatio);
        int256 constantTerm = (entryPriceSigned * pos.size) - (marginSigned * 1e18);
        
        if (coefficient == 0) return 0; // Edge case
        
        int256 liquidationPriceSigned = constantTerm / coefficient;
        
        return liquidationPriceSigned > 0 ? uint256(liquidationPriceSigned) : 0;
    }
}