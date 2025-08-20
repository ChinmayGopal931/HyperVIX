// HyperVIX Frontend Integration - Contract ABIs and Addresses
// Copy this file to your frontend project

// Network Configuration
export const NETWORK_CONFIG = {
  chainId: 998,
  name: "Hyperliquid Testnet",
  rpcUrl: "https://rpc.hyperliquid-testnet.xyz/evm",
  blockExplorer: "https://app.hyperliquid.xyz/",
  nativeCurrency: {
    name: "ETH",
    symbol: "ETH", 
    decimals: 18
  }
};

// Contract Addresses (Hyperliquid Testnet)
export const CONTRACTS = {
  // Core HyperVIX Contracts (UPDATED v2.0 - All compatible with MockUSDC)
  L1Read: "0xA4Ff3884260a944cfdEFAd872e7af7772e9eD167",
  VolatilityIndexOracle: "0x721241e831f773BC29E4d39d057ff97fD578c772", 
  VolatilityPerpetual: "0xF23220ccE9f4CF81c999BC0A582020FA38094E60", // ✅ NEW - Uses MockUSDC
  HyperVIXKeeper: "0x3c52aB878821dA382F2069B2f7e839F1C49b81bF", // ✅ NEW - Updated
  
  // MockUSDC Token - Deployed for testing purposes
  USDC: "0x87fd4d8532c3F5bF5a391402F05814c6863f4e2a" // ✅ Standard ERC20 with faucet
};

// Contract deployment block (for event filtering)
export const DEPLOYMENT_BLOCKS = {
  L1Read: 30007529,
  VolatilityIndexOracle: 30007529,
  VolatilityPerpetual: 30007529, 
  HyperVIXKeeper: 30007529
};

// VolatilityIndexOracle ABI - All essential functions
export const ORACLE_ABI = [
  // View Functions
  "function getAnnualizedVolatility() view returns (uint256)",
  "function getCurrentVariance() view returns (uint256)", 
  "function getLastPrice() view returns (uint64)",
  "function getLastUpdateTime() view returns (uint256)",
  "function getTwapVolatility(uint32 twapInterval) view returns (uint256)",
  "function getVolatilityState() view returns (uint256 vol, uint256 lastUpdate)",
  
  // State Variables (public getters)
  "function l1Reader() view returns (address)",
  "function keeper() view returns (address)", 
  "function underlyingAssetId() view returns (uint32)",
  "function lambda() view returns (uint256)",
  "function annualizationFactor() view returns (uint256)",
  "function lastPrice() view returns (uint64)",
  "function currentVariance() view returns (uint256)",
  "function lastUpdateTime() view returns (uint256)",
  "function cumulativeVolatility() view returns (uint256)",
  "function lastTwapUpdateTime() view returns (uint256)",
  
  // Write Functions
  "function takePriceSnapshot()",
  
  // Events
  "event VolatilityUpdated(uint256 indexed newVariance, uint256 indexed annualizedVolatility, uint256 indexed timestamp)"
];

// VolatilityPerpetual ABI - All essential functions  
export const PERPETUAL_ABI = [
  // View Functions
  "function getMarkPrice() view returns (uint256)",
  "function positions(address user) view returns (tuple(int256 size, uint256 margin, uint256 entryPrice, int256 lastCumulativeFundingRate))",
  "function getPositionValue(address trader) view returns (int256)",
  "function isLiquidatable(address trader) view returns (bool)",
  
  // State Variables (public getters)
  "function volOracle() view returns (address)",
  "function collateralToken() view returns (address)",
  "function vBaseAssetReserve() view returns (uint256)",
  "function vQuoteAssetReserve() view returns (uint256)",
  "function totalPositionSize() view returns (uint256)",
  "function cumulativeFundingRate() view returns (int256)",
  "function lastFundingTime() view returns (uint256)",
  "function cumulativeMarkPrice() view returns (uint256)",
  "function lastMarkPriceTwapUpdate() view returns (uint256)",
  "function maxLeverage() view returns (uint256)",
  "function maintenanceMarginRatio() view returns (uint256)",
  "function liquidationFee() view returns (uint256)",
  "function fundingInterval() view returns (uint256)",
  "function tradingFee() view returns (uint256)",
  
  // Write Functions
  "function openPosition(int256 sizeDelta, uint256 marginDelta)",
  "function closePosition()",
  "function liquidate(address user)",
  "function settleFunding()",
  
  // Events
  "event PositionOpened(address indexed trader, int256 sizeDelta, uint256 marginDelta, uint256 averagePrice, uint256 timestamp)",
  "event PositionClosed(address indexed trader, int256 size, uint256 margin, int256 pnl, uint256 timestamp)",
  "event FundingSettled(int256 fundingRate, int256 cumulativeFundingRate, uint256 timestamp)",
  "event Liquidated(address indexed trader, address indexed liquidator, int256 size, uint256 liquidationReward, uint256 timestamp)"
];

// HyperVIXKeeper ABI - All essential functions
export const KEEPER_ABI = [
  // View Functions
  "function isOracleUpdateDue() view returns (bool)",
  "function isFundingUpdateDue() view returns (bool)", 
  "function getNextOracleUpdate() view returns (uint256)",
  "function getNextFundingUpdate() view returns (uint256)",
  
  // State Variables (public getters)
  "function oracle() view returns (address)",
  "function perpetual() view returns (address)",
  "function lastOracleUpdate() view returns (uint256)",
  "function lastFundingUpdate() view returns (uint256)",
  "function oracleUpdateInterval() view returns (uint256)",
  "function authorizedKeepers(address) view returns (bool)",
  
  // Write Functions
  "function updateOracle()",
  "function settleFunding()",
  "function updateBoth()",
  "function authorizeKeeper(address keeper, bool authorized)",
  "function setOracleUpdateInterval(uint256 interval)",
  
  // Events
  "event OracleUpdated(uint256 timestamp)",
  "event FundingSettled(uint256 timestamp)",
  "event KeeperAuthorized(address indexed keeper, bool authorized)",
  "event IntervalUpdated(uint256 newInterval)"
];

// Standard ERC20 ABI (for USDC and other tokens)
export const ERC20_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address owner) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function transferFrom(address from, address to, uint256 amount) returns (bool)",
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event Approval(address indexed owner, address indexed spender, uint256 value)"
];

// MockUSDC ABI (includes faucet function)
export const MOCK_USDC_ABI = [
  ...ERC20_ABI,
  "function faucet(address to, uint256 amount)",
  "function mint(address to, uint256 amount)",
  "function burn(uint256 amount)"
];

// Utility function to initialize all contracts
export const initializeContracts = (provider, signer = null) => {
  const contracts = {
    oracle: new ethers.Contract(
      CONTRACTS.VolatilityIndexOracle,
      ORACLE_ABI,
      signer || provider
    ),
    perpetual: new ethers.Contract(
      CONTRACTS.VolatilityPerpetual, 
      PERPETUAL_ABI,
      signer || provider
    ),
    keeper: new ethers.Contract(
      CONTRACTS.HyperVIXKeeper,
      KEEPER_ABI,
      signer || provider
    ),
    usdc: new ethers.Contract(
      CONTRACTS.USDC,
      MOCK_USDC_ABI, // Use MockUSDC ABI which includes faucet function
      signer || provider
    )
  };
  
  return contracts;
};

// Constants for calculations
export const CONSTANTS = {
  // Decimals
  PRICE_DECIMALS: 6,        // USDC has 6 decimals
  POSITION_DECIMALS: 18,    // Position sizes in 1e18
  VOLATILITY_DECIMALS: 18,  // Volatility in 1e18
  
  // Asset IDs
  ETH_ASSET_ID: 1,
  BTC_ASSET_ID: 3,
  
  // Update intervals
  ORACLE_UPDATE_INTERVAL: 3600,  // 1 hour in seconds
  FUNDING_INTERVAL: 3600,        // 1 hour in seconds
  
  // Risk parameters
  MAX_LEVERAGE: 10,              // 10x maximum leverage
  MAINTENANCE_MARGIN_RATIO: 0.05, // 5%
  LIQUIDATION_FEE: 0.01,         // 1%
  TRADING_FEE: 0.001             // 0.1%
};

// Helper functions for frontend
export const helpers = {
  // Convert between different decimal formats
  formatPrice: (price) => (price / Math.pow(10, CONSTANTS.PRICE_DECIMALS)).toFixed(6),
  formatPosition: (size) => (size / Math.pow(10, CONSTANTS.POSITION_DECIMALS)).toFixed(6),
  formatVolatility: (vol) => ((vol / Math.pow(10, CONSTANTS.VOLATILITY_DECIMALS)) * 100).toFixed(2) + '%',
  
  // Parse input values to contract format
  parsePrice: (price) => Math.floor(price * Math.pow(10, CONSTANTS.PRICE_DECIMALS)),
  parsePosition: (size) => (size * Math.pow(10, CONSTANTS.POSITION_DECIMALS)).toString(),
  
  // Calculate leverage
  calculateLeverage: (positionSize, margin, markPrice) => {
    const notional = positionSize * markPrice / Math.pow(10, CONSTANTS.POSITION_DECIMALS);
    const marginUSD = margin / Math.pow(10, CONSTANTS.PRICE_DECIMALS);
    return notional / marginUSD;
  },
  
  // Format timestamps
  formatTimestamp: (timestamp) => new Date(timestamp * 1000).toLocaleString(),
  
  // Check if position is long or short
  isLongPosition: (size) => size > 0,
  
  // Calculate funding rate
  calculateFundingRate: (cumulativeRate, lastRate) => (cumulativeRate - lastRate) / Math.pow(10, CONSTANTS.VOLATILITY_DECIMALS)
};

// Example usage for frontend teams:
/*
import { initializeContracts, CONTRACTS, NETWORK_CONFIG, helpers } from './frontend-abis.js';
import { ethers } from 'ethers';

// Initialize provider and contracts
const provider = new ethers.providers.JsonRpcProvider(NETWORK_CONFIG.rpcUrl);
const contracts = initializeContracts(provider);

// Get current volatility
const volatility = await contracts.oracle.getAnnualizedVolatility();
console.log('Current volatility:', helpers.formatVolatility(volatility));

// Get user position
const position = await contracts.perpetual.positions(userAddress);
console.log('Position size:', helpers.formatPosition(position.size));
console.log('Is long position:', helpers.isLongPosition(position.size));
*/