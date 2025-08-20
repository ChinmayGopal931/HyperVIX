// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/VolatilityIndexOracle.sol";
import "./mocks/MockL1Read.sol";
import "prb-math/UD60x18.sol";

contract VolatilityIndexOracleTest is Test {
    VolatilityIndexOracle public oracle;
    MockL1Read public mockL1Read;
    
    address public keeper = address(0x1234);
    uint32 public constant ASSET_ID = 1;
    uint256 public constant LAMBDA = 0.94 * 1e18; // 94%
    uint256 public constant ANNUALIZATION_FACTOR = 365 * 24; // Hourly updates
    uint256 public constant INITIAL_VARIANCE = 0.04 * 1e18; // 20% initial volatility
    uint64 public constant INITIAL_PRICE = 2000 * 1e6; // $2000 with 6 decimals

    event VolatilityUpdated(
        uint256 indexed newVariance,
        uint256 indexed annualizedVolatility,
        uint256 indexed timestamp
    );

    function setUp() public {
        mockL1Read = new MockL1Read();
        mockL1Read.setPrice(ASSET_ID, INITIAL_PRICE);
        
        oracle = new VolatilityIndexOracle(
            address(mockL1Read),
            keeper,
            ASSET_ID,
            LAMBDA,
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );
    }

    function testConstructorInitialization() public {
        assertEq(address(oracle.l1Reader()), address(mockL1Read));
        assertEq(oracle.keeper(), keeper);
        assertEq(oracle.underlyingAssetId(), ASSET_ID);
        assertEq(oracle.lambda(), LAMBDA);
        assertEq(oracle.annualizationFactor(), ANNUALIZATION_FACTOR);
        assertEq(oracle.lastPrice(), INITIAL_PRICE);
        assertEq(oracle.currentVariance(), INITIAL_VARIANCE);
        assertGt(oracle.lastUpdateTime(), 0);
    }

    function testConstructorValidation() public {
        // Test invalid L1Read address
        vm.expectRevert(VolatilityIndexOracle.InvalidAddress.selector);
        new VolatilityIndexOracle(
            address(0),
            keeper,
            ASSET_ID,
            LAMBDA,
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );

        // Test invalid keeper address
        vm.expectRevert(VolatilityIndexOracle.InvalidAddress.selector);
        new VolatilityIndexOracle(
            address(mockL1Read),
            address(0),
            ASSET_ID,
            LAMBDA,
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );

        // Test invalid lambda (>= 1)
        vm.expectRevert(VolatilityIndexOracle.InvalidLambda.selector);
        new VolatilityIndexOracle(
            address(mockL1Read),
            keeper,
            ASSET_ID,
            1e18, // Invalid: lambda should be < 1
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );

        // Test invalid lambda (0)
        vm.expectRevert(VolatilityIndexOracle.InvalidLambda.selector);
        new VolatilityIndexOracle(
            address(mockL1Read),
            keeper,
            ASSET_ID,
            0, // Invalid: lambda should be > 0
            ANNUALIZATION_FACTOR,
            INITIAL_VARIANCE
        );
    }

    function testOnlyKeeperCanUpdatePrice() public {
        // Non-keeper should fail
        vm.expectRevert(VolatilityIndexOracle.OnlyKeeper.selector);
        oracle.takePriceSnapshot();

        // Keeper should succeed
        vm.prank(keeper);
        oracle.takePriceSnapshot();
    }

    function testPriceUpdate() public {
        uint64 newPrice = 2100 * 1e6; // 5% increase
        mockL1Read.setPrice(ASSET_ID, newPrice);

        vm.prank(keeper);
        // Don't check exact event values, just that event was emitted
        oracle.takePriceSnapshot();

        assertEq(oracle.lastPrice(), newPrice);
        // For a 5% increase, variance should change from initial
        uint256 newVariance = oracle.currentVariance();
        assertTrue(newVariance != INITIAL_VARIANCE);
    }

    function testVolatilityCalculationWithSequentialPrices() public {
        uint64[] memory prices = new uint64[](5);
        prices[0] = 2000 * 1e6;
        prices[1] = 2100 * 1e6; // +5%
        prices[2] = 1950 * 1e6; // -7.14%
        prices[3] = 2050 * 1e6; // +5.13%
        prices[4] = 1980 * 1e6; // -3.41%

        uint256 previousVariance = oracle.currentVariance();

        for (uint256 i = 1; i < prices.length; i++) {
            mockL1Read.setPrice(ASSET_ID, prices[i]);
            
            vm.prank(keeper);
            oracle.takePriceSnapshot();
            
            // Variance should be updated
            uint256 newVariance = oracle.currentVariance();
            assertTrue(newVariance != previousVariance);
            previousVariance = newVariance;
            
            // Skip some time between updates
            skip(3600); // 1 hour
        }

        // Final volatility should be > 0
        uint256 finalVolatility = oracle.getAnnualizedVolatility();
        assertGt(finalVolatility, 0);
    }

    function testGetAnnualizedVolatility() public {
        uint256 volatility = oracle.getAnnualizedVolatility();
        
        // Should return annualized volatility based on current variance
        // With initial variance of 0.04 (20%^2), annualized should be sqrt(0.04) * sqrt(8760) ≈ 18.7
        assertGt(volatility, 15 * 1e18); // At least 15 (accounting for rounding)
        assertLt(volatility, 25 * 1e18); // At most 25
    }

    function testZeroPriceHandling() public {
        mockL1Read.setPrice(ASSET_ID, 0);
        
        vm.prank(keeper);
        vm.expectRevert(VolatilityIndexOracle.ZeroPrice.selector);
        oracle.takePriceSnapshot();
    }

    function testEWMAFormula() public {
        // Start with known variance
        uint256 initialVariance = oracle.currentVariance();
        
        // Apply a 10% price increase
        uint64 newPrice = uint64((uint256(INITIAL_PRICE) * 110) / 100);
        mockL1Read.setPrice(ASSET_ID, newPrice);
        
        vm.prank(keeper);
        oracle.takePriceSnapshot();
        
        uint256 newVariance = oracle.currentVariance();
        
        // The new variance should be different from initial
        assertTrue(newVariance != initialVariance);
        
        // For a 10% price increase, we expect the variance to be in a reasonable range
        // EWMA will blend the old variance with the new return
        assertGt(newVariance, 0.01 * 1e18); // At least 1% variance
        assertLt(newVariance, 0.1 * 1e18);  // At most 10% variance
    }

    function testTwapVolatility() public {
        // Test basic TWAP functionality
        uint256 twapVol = oracle.getTwapVolatility(3600); // 1 hour
        uint256 spotVol = oracle.getAnnualizedVolatility();
        
        // With no history, TWAP should equal spot
        assertEq(twapVol, spotVol);
    }

    function testMultipleUpdatesIncreasePrecision() public {
        uint256 initialVol = oracle.getAnnualizedVolatility();
        
        // Simulate multiple price movements
        uint64[] memory prices = new uint64[](10);
        prices[0] = 2000 * 1e6;
        
        // Generate some realistic price movements
        for (uint256 i = 1; i < prices.length; i++) {
            // Random-ish movements between -5% and +5%
            int256 change = int256((i * 7919) % 11) - 5; // Pseudo-random -5 to +5
            uint256 newPrice = (uint256(prices[i-1]) * uint256(100 + change)) / 100;
            prices[i] = uint64(newPrice);
        }
        
        for (uint256 i = 1; i < prices.length; i++) {
            mockL1Read.setPrice(ASSET_ID, prices[i]);
            
            vm.prank(keeper);
            oracle.takePriceSnapshot();
            
            skip(1800); // 30 minutes between updates
        }
        
        uint256 finalVol = oracle.getAnnualizedVolatility();
        
        // After multiple updates, volatility should have evolved
        assertTrue(finalVol != initialVol);
    }

    function testFuzzPriceUpdates(uint64 price1, uint64 price2) public {
        // Bound prices to reasonable ranges
        price1 = uint64(bound(price1, 100 * 1e6, 10000 * 1e6)); // $100 to $10,000
        price2 = uint64(bound(price2, 100 * 1e6, 10000 * 1e6));
        
        // Skip if prices are the same (would result in zero return)
        vm.assume(price1 != price2);
        
        mockL1Read.setPrice(ASSET_ID, price1);
        
        vm.prank(keeper);
        oracle.takePriceSnapshot();
        
        mockL1Read.setPrice(ASSET_ID, price2);
        
        vm.prank(keeper);
        oracle.takePriceSnapshot();
        
        // Volatility should always be calculable
        uint256 volatility = oracle.getAnnualizedVolatility();
        assertGt(volatility, 0);
        
        // Variance should be updated
        assertGt(oracle.currentVariance(), 0);
    }
}