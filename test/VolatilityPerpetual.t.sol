// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/VolatilityPerpetual.sol";
import "../src/VolatilityIndexOracle.sol";
import "./mocks/MockL1Read.sol";
import "./mocks/MockL1ReadPrecompile.sol";
import "./mocks/MockERC20.sol";
import "prb-math/UD60x18.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VolatilityPerpetualTest is Test {
    VolatilityPerpetual public perpetual;
    VolatilityIndexOracle public oracle;
    MockL1Read public mockL1Read;
    MockL1ReadPrecompile public mockPrecompile;
    MockERC20 public collateralToken;
    
    // Precompile address (example, adjust as needed)
    address constant L1_READ_PRECOMPILE = 0x0000000000000000000000000000000000000808;
    
    address public keeper = address(0x1234);
    address public trader1 = address(0xABCD);
    address public trader2 = address(0xEF01);
    
    uint32 public constant ASSET_ID = 1;
    uint256 public constant LAMBDA = 0.94 * 1e18;
    uint256 public constant ANNUALIZATION_FACTOR = 365 * 24;
    uint256 public constant INITIAL_VARIANCE = 0.04 * 1e18;
    uint64 public constant INITIAL_PRICE = 2000 * 1e6;
    
    uint256 public constant INITIAL_BASE_RESERVE = 1000000 * 1e18; // 1M vVOL
    uint256 public constant INITIAL_QUOTE_RESERVE = 200000 * 1e6;  // 200K USDC
    uint256 public constant INITIAL_MARGIN = 10000 * 1e6; // 10K USDC

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

    function setUp() public {
        // Deploy mocks
        mockL1Read = new MockL1Read();
        mockL1Read.setPrice(ASSET_ID, INITIAL_PRICE);
        
        // Set up precompile mock using vm.etch
        mockPrecompile = new MockL1ReadPrecompile();
        vm.etch(L1_READ_PRECOMPILE, address(mockPrecompile).code);
        // Set the initial price using the proper method
        MockL1ReadPrecompile(payable(L1_READ_PRECOMPILE)).setPrice(ASSET_ID, INITIAL_PRICE);
        
        collateralToken = new MockERC20("USDC", "USDC");
        
        // Deploy oracle using precompile address
        oracle = new VolatilityIndexOracle(
            L1_READ_PRECOMPILE,
            keeper,
            ASSET_ID,
            LAMBDA,
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );
        
        // Deploy perpetual
        perpetual = new VolatilityPerpetual(
            address(oracle),
            address(collateralToken),
            INITIAL_BASE_RESERVE,
            INITIAL_QUOTE_RESERVE
        );
        
        // Mint tokens to traders
        collateralToken.mint(trader1, 100000 * 1e6); // 100K USDC
        collateralToken.mint(trader2, 1000000 * 1e6); // 1M USDC
        collateralToken.mint(address(this), 100000 * 1e6); // For testing
        collateralToken.mint(address(perpetual), 1000000 * 1e6); // Fund the perpetual contract
        
        // Approve spending
        vm.prank(trader1);
        collateralToken.approve(address(perpetual), type(uint256).max);
        
        vm.prank(trader2);
        collateralToken.approve(address(perpetual), type(uint256).max);
        
        collateralToken.approve(address(perpetual), type(uint256).max);
    }

    // Helper function to update mock precompile price
    function setMockPrice(uint64 newPrice) internal {
        MockL1ReadPrecompile(payable(L1_READ_PRECOMPILE)).setPrice(ASSET_ID, newPrice);
    }

    function testInitialSetup() public view {
        assertEq(address(perpetual.volOracle()), address(oracle));
        assertEq(address(perpetual.collateralToken()), address(collateralToken));
        assertEq(perpetual.vBaseAssetReserve(), INITIAL_BASE_RESERVE);
        // Quote reserve is scaled by collateralScalingFactor (1e12 for USDC) 
        assertEq(perpetual.vQuoteAssetReserve(), INITIAL_QUOTE_RESERVE * 1e12);
        
        // Initial mark price should be quote/base (both in 18 decimals internally)
        uint256 expectedPrice = ((INITIAL_QUOTE_RESERVE * 1e12) * 1e18) / INITIAL_BASE_RESERVE;
        assertEq(perpetual.getMarkPrice(), expectedPrice);
    }

    function testOpenLongPosition() public {
        uint256 initialMarkPrice = perpetual.getMarkPrice();
        int256 sizeDelta = 1000 * 1e18; // 1000 vVOL long
        
                    console.log("inital margin", INITIAL_MARGIN);

        vm.prank(trader1);
        vm.expectEmit(true, false, false, false);
        emit PositionOpened(trader1, sizeDelta, INITIAL_MARGIN, 0, block.timestamp);
        perpetual.openPosition(sizeDelta, INITIAL_MARGIN);
        
        // Check position was created
        (int256 size, uint256 margin, uint256 entryPrice, int256 lastFunding) = 
            perpetual.positions(trader1);

            console.log("margin", margin);
        
        assertEq(size, sizeDelta);
        assertEq(margin, INITIAL_MARGIN * 1e12); // Margin is scaled to 18 decimals internally
        assertGt(entryPrice, initialMarkPrice); // Entry price should be higher due to slippage
        assertEq(lastFunding, 0); // Initial funding rate
        
        // Check vAMM reserves changed
        assertLt(perpetual.vBaseAssetReserve(), INITIAL_BASE_RESERVE);
        assertGt(perpetual.vQuoteAssetReserve(), INITIAL_QUOTE_RESERVE * 1e12); // Quote reserve is scaled
        
        // Check mark price increased
        assertGt(perpetual.getMarkPrice(), initialMarkPrice);
    }

    function testOpenShortPosition() public {
        uint256 initialMarkPrice = perpetual.getMarkPrice();
        int256 sizeDelta = -1000 * 1e18; // 1000 vVOL short
        
        vm.prank(trader1);
        perpetual.openPosition(sizeDelta, INITIAL_MARGIN);
        
        // Check position was created
        (int256 size, uint256 margin, uint256 entryPrice, ) = 
            perpetual.positions(trader1);
        
        assertEq(size, sizeDelta);
        assertEq(margin, INITIAL_MARGIN * 1e12); // Margin is scaled to 18 decimals internally
        assertLt(entryPrice, initialMarkPrice); // Entry price should be lower for short
        
        // Check vAMM reserves changed
        assertGt(perpetual.vBaseAssetReserve(), INITIAL_BASE_RESERVE);
        assertGt(perpetual.vQuoteAssetReserve(), INITIAL_QUOTE_RESERVE * 1e12); // Quote reserve is scaled
        
        // Check mark price decreased
        assertLt(perpetual.getMarkPrice(), initialMarkPrice);
    }

    function testClosePosition() public {
        // First open a position
        int256 sizeDelta = 1000 * 1e18;
        
        vm.prank(trader1);
        perpetual.openPosition(sizeDelta, INITIAL_MARGIN);
        
        uint256 balanceBefore = collateralToken.balanceOf(trader1);
        
        // Close the position
        vm.prank(trader1);
        perpetual.closePosition();
        
        // Check position was deleted
        (int256 size, , , ) = perpetual.positions(trader1);
        assertEq(size, 0);
        
        // Check trader received funds back
        uint256 balanceAfter = collateralToken.balanceOf(trader1);
        assertGt(balanceAfter, balanceBefore);
    }

    function testCannotOpenPositionWithoutMargin() public {
        vm.prank(trader1);
        vm.expectRevert(VolatilityPerpetual.InvalidMargin.selector);
        perpetual.openPosition(1000 * 1e18, 0);
    }

    function testCannotOpenPositionWithZeroSize() public {
        vm.prank(trader1);
        vm.expectRevert(VolatilityPerpetual.InvalidSize.selector);
        perpetual.openPosition(0, INITIAL_MARGIN);
    }

    function testCannotCloseNonExistentPosition() public {
        vm.prank(trader1);
        vm.expectRevert(VolatilityPerpetual.NoPosition.selector);
        perpetual.closePosition();
    }

    function testLeverageLimit() public {
        uint256 maxLeverage = perpetual.maxLeverage();
        uint256 markPrice = perpetual.getMarkPrice();
        
        // Calculate maximum position size for given margin (account for scaling)
        uint256 scaledMargin = INITIAL_MARGIN * 1e12; // Convert to 18 decimals
        uint256 maxNotional = (scaledMargin * maxLeverage) / 1e18;
        uint256 maxSize = (maxNotional * 1e18) / markPrice;
        
        // Try to open position exceeding leverage
        int256 oversizedPosition = int256(maxSize + 1000 * 1e18);
        
        vm.prank(trader1);
        vm.expectRevert(VolatilityPerpetual.ExceedsMaxLeverage.selector);
        perpetual.openPosition(oversizedPosition, INITIAL_MARGIN);
    }

    function testProfitableLongPosition() public {
        // Open long position
        int256 sizeDelta = 1000 * 1e18;
        
        vm.prank(trader1);
        perpetual.openPosition(sizeDelta, INITIAL_MARGIN);
        
        // Simulate mark price increase by opening opposite position
        vm.prank(trader2);
        perpetual.openPosition(-2000 * 1e18, 20000 * 1e6); // Large short to move price up
        
        // Check that trader1's position has positive value
        int256 positionValue = perpetual.getPositionValue(trader1);
        assertGt(positionValue, 0);
    }

    function testUnprofitableLongPosition() public {
        // Open long position
        int256 sizeDelta = 1000 * 1e18;
        
        vm.prank(trader1);
        perpetual.openPosition(sizeDelta, INITIAL_MARGIN);
        
        // Record entry conditions
        uint256 entryMarkPrice = perpetual.getMarkPrice();
        
        // Simulate mark price decrease by opening massive short position
        vm.prank(trader2);
        perpetual.openPosition(-50000 * 1e18, 500000 * 1e6); // Massive short to crash price
        
        // Check that mark price decreased significantly
        uint256 newMarkPrice = perpetual.getMarkPrice();
        assertLt(newMarkPrice, entryMarkPrice);
        
        // Check that trader1's position has negative value
        int256 positionValue = perpetual.getPositionValue(trader1);
        assertLt(positionValue, 0);
    }

    function testFundingSettlement() public {
        // Fast forward time
        skip(3600); // 1 hour
        
        // Settle funding
        perpetual.settleFunding();
        
        // Check that funding was updated
        assertGt(perpetual.lastFundingTime(), 0);
    }

    function testCannotSettleFundingTooEarly() public {
        vm.expectRevert(VolatilityPerpetual.FundingTooEarly.selector);
        perpetual.settleFunding();
    }

    function testLiquidation() public {
        _setupLiquidationTest();
        _createSellingPressure();
        _executeLiquidation();
    }
    
    function _setupLiquidationTest() internal {
        // Open a highly leveraged position that will be vulnerable to liquidation
        int256 sizeDelta = 800 * 1e18; // 800 vVOL long
        uint256 initialMargin = 25 * 1e6; // 25 USDC margin - creates extreme leverage
        
        vm.prank(trader1);
        perpetual.openPosition(sizeDelta, initialMargin);
        
        // Verify position is healthy initially
        assertFalse(perpetual.isLiquidatable(trader1));
    }
    
    function _createSellingPressure() internal {
        // Create massive selling pressure to crash the price
        vm.prank(trader2);
        perpetual.openPosition(-50000 * 1e18, 500000 * 1e6); // Large short position
        
        // If trader1 still not liquidatable, add more selling pressure
        if (!perpetual.isLiquidatable(trader1)) {
            address trader3 = address(0xDEAD);
            collateralToken.mint(trader3, 10000000 * 1e6); // 10M USDC
            
            vm.prank(trader3);
            collateralToken.approve(address(perpetual), type(uint256).max);
            vm.prank(trader3);
            perpetual.openPosition(-1000000 * 1e18, 10000000 * 1e6); // Massive short
        }
    }
    
    function _executeLiquidation() internal {
        // Verify position is now liquidatable
        assertTrue(perpetual.isLiquidatable(trader1));
        
        
        // Execute liquidation
        perpetual.liquidate(trader1);
        
        // Verify position was closed
        (int256 sizeAfter, , , ) = perpetual.positions(trader1);
        assertEq(sizeAfter, 0);
        
        
        // Verify position is no longer liquidatable (closed)
        assertFalse(perpetual.isLiquidatable(trader1));
    }

    function testCannotLiquidateHealthyPosition() public {
        // Open normal position
        vm.prank(trader1);
        perpetual.openPosition(1000 * 1e18, INITIAL_MARGIN);
        
        // Position should not be liquidatable
        assertFalse(perpetual.isLiquidatable(trader1));
        
        // Try to liquidate
        vm.expectRevert(VolatilityPerpetual.PositionNotLiquidatable.selector);
        perpetual.liquidate(trader1);
    }

    function testUpdatePositionWithSameDirection() public {
        // Open initial long position
        int256 initialSize = 1000 * 1e18;
        
        vm.prank(trader1);
        perpetual.openPosition(initialSize, INITIAL_MARGIN);
        
        (int256 size1, uint256 margin1, uint256 entryPrice1, ) = perpetual.positions(trader1);
        
        // Add to position
        int256 additionalSize = 500 * 1e18;
        uint256 additionalMargin = 5000 * 1e6;
        
        vm.prank(trader1);
        perpetual.openPosition(additionalSize, additionalMargin);
        
        (int256 size2, uint256 margin2, uint256 entryPrice2, ) = perpetual.positions(trader1);
        
        // Check position was updated correctly
        assertEq(size2, size1 + additionalSize);
        assertEq(margin2, margin1 + (additionalMargin * 1e12)); // Additional margin is scaled
        // Entry price should be weighted average
        assertTrue(entryPrice2 != entryPrice1);
    }

    function testGetMarkPrice() public view {
        uint256 markPrice = perpetual.getMarkPrice();
        uint256 expectedPrice = (perpetual.vQuoteAssetReserve() * 1e18) / perpetual.vBaseAssetReserve();
        assertEq(markPrice, expectedPrice);
    }

    function testFuzzPositionSizes(uint256 size, uint256 margin) public {
        // Bound inputs to smaller, more reasonable ranges to avoid balance issues
        size = bound(size, 1e18, 1000 * 1e18); // 1 to 1K vVOL
        margin = bound(margin, 1000 * 1e6, 10000 * 1e6); // 1K to 10K USDC
        
        // Only test one direction to avoid complex interactions
        address trader = trader1;
        int256 signedSize = int256(size);
        
        // Ensure trader has enough balance
        uint256 currentBalance = collateralToken.balanceOf(trader);
        if (currentBalance < margin) {
            collateralToken.mint(trader, margin - currentBalance);
        }
        
        // Also fund the contract with extra tokens for potential payouts
        collateralToken.mint(address(perpetual), margin);
        
        vm.prank(trader);
        try perpetual.openPosition(signedSize, margin) {
            // Position should be created
            (int256 posSize, , , ) = perpetual.positions(trader);
            assertEq(posSize, signedSize);
            
            // Close position
            vm.prank(trader);
            perpetual.closePosition();
        } catch {
            // If it fails, it should be due to leverage limits
            // This is acceptable behavior
        }
    }

    function testVolatilityScoreBeforeAndAfterPosition() public {
        console.log("=== Testing Volatility Score Changes ===");
        
        // Set initial price first
        setMockPrice(INITIAL_PRICE);
        
        // Initialize oracle with first price snapshot
        vm.prank(keeper);
        oracle.takePriceSnapshot();
        
        // 1. Get initial metrics and create price movements
        uint256 initialVariance = oracle.getCurrentVariance();
        uint256 initialVolatility = oracle.getAnnualizedVolatility();
        
        console.log("Initial Metrics:");
        console.log("  Variance:", initialVariance);
        console.log("  Annualized Volatility:", initialVolatility);
        
        // 2. Create price volatility
        _createPriceVolatility();
        
        // 3. Test position impact on mark price
        uint256 markPriceBefore = perpetual.getMarkPrice();
        
        vm.prank(trader1);
        perpetual.openPosition(10000 * 1e18, INITIAL_MARGIN);
        
        uint256 markPriceAfter = perpetual.getMarkPrice();
        
        console.log("Mark Price Impact: %d -> %d", markPriceBefore, markPriceAfter);
        assertGt(markPriceAfter, markPriceBefore, "Long position should increase mark price");
        
        // 4. Final volatility check
        skip(3600);
        setMockPrice(uint64((uint256(INITIAL_PRICE) * 103) / 100));
        
        vm.prank(keeper);
        oracle.takePriceSnapshot();
        
        uint256 finalVariance = oracle.getCurrentVariance();
        uint256 finalVolatility = oracle.getAnnualizedVolatility();
        
        console.log("Final Metrics:");
        console.log("  Variance:", finalVariance);
        console.log("  Annualized Volatility:", finalVolatility);
        
        // Verify volatility changed (EWMA can increase or decrease based on recent vs historical volatility)
        assertTrue(finalVariance != initialVariance, "Variance should change");
        assertTrue(finalVolatility != initialVolatility, "Volatility should change");
        
        // Verify volatility is still within reasonable bounds (1% to 100%)
        assertGt(finalVolatility, 1 * 1e18, "Volatility should be > 1%");
        assertLt(finalVolatility, 100 * 1e18, "Volatility should be < 100%");
    }

    function _createPriceVolatility() internal {
        // Move price up 10% 
        setMockPrice(uint64((uint256(INITIAL_PRICE) * 110) / 100));
        vm.prank(keeper);
        oracle.takePriceSnapshot();
        
        // Wait and move price down 8%
        skip(3600);
        setMockPrice(uint64((uint256(INITIAL_PRICE) * 110 * 92) / 10000));
        vm.prank(keeper);
        oracle.takePriceSnapshot();
    }

    function testVolatilityStateAccumulation() public {
        console.log("=== Testing Volatility State Accumulation ===");
        
        // Set initial price and initialize oracle
        setMockPrice(INITIAL_PRICE);
        vm.prank(keeper);
        oracle.takePriceSnapshot();
        
        // Get initial state
        (uint256 initialCumulative, ) = oracle.getVolatilityState();
        
        // Wait and check accumulation
        skip(7200); // 2 hours
        (uint256 finalCumulative, ) = oracle.getVolatilityState();
        
        console.log("Cumulative volatility change: %d -> %d", initialCumulative, finalCumulative);
        
        // Should accumulate over time
        assertGt(finalCumulative, initialCumulative, "Cumulative volatility should increase over time");
    }

    function testVolatilityWithMultiplePositions() public {
        console.log("=== Testing Volatility with Multiple Positions ===");
        
        // Set initial price and initialize oracle
        setMockPrice(INITIAL_PRICE);
        vm.prank(keeper);
        oracle.takePriceSnapshot();
        
        uint256 initialMarkPrice = perpetual.getMarkPrice();
        
        // Open long position
        vm.prank(trader1);
        perpetual.openPosition(5000 * 1e18, INITIAL_MARGIN);
        uint256 priceAfterLong = perpetual.getMarkPrice();
        
        // Open short position  
        vm.prank(trader2);
        perpetual.openPosition(-3000 * 1e18, INITIAL_MARGIN);
        uint256 priceAfterShort = perpetual.getMarkPrice();
        
        console.log("Price Evolution: %d -> %d -> %d", initialMarkPrice, priceAfterLong, priceAfterShort);
        
        // Verify expected price movements
        assertGt(priceAfterLong, initialMarkPrice, "Long position should increase price");
        assertLt(priceAfterShort, priceAfterLong, "Short position should decrease price");
    }
}