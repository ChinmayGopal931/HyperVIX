# HyperVIX

HyperVIX is a decentralized protocol enabling traders to speculate on the future realized volatility of crypto assets through synthetic perpetual markets. The protocol tracks real-time, on-chain volatility indices using a virtual AMM (vAMM) system.
![Uploading WhatsApp Image 2025-08-24 at 11.37.40.jpeg…]()



## 🏗️ Architecture

The protocol consists of two core smart contracts:

### 1. VolatilityIndexOracle.sol
The foundational data layer that calculates real-time volatility using an Exponentially Weighted Moving Average (EWMA) model.

**Key Features:**
- Gas-efficient EWMA calculation: `σ²ₜ = λσ²ₜ₋₁ + (1-λ)r²ₜ`
- Manipulation-resistant through TWAP mechanisms
- Configurable decay factor (λ) and annualization parameters
- Real-time price feed integration via L1Read interface

### 2. VolatilityPerpetual.sol
The main trading contract implementing a virtual AMM for volatility perpetuals.

**Key Features:**
- Virtual AMM using constant product formula: x × y = k
- Collateralized trading with configurable leverage (up to 10x default)
- Automated funding rate mechanism
- Liquidation system with insurance fund backing
- Position management with PnL tracking

## 📊 Mathematical Model

### EWMA Volatility Calculation
```
σ²ₜ = λ × σ²ₜ₋₁ + (1-λ) × rₜ²

Where:
- σ²ₜ = current variance
- λ = decay factor (e.g., 0.94)
- rₜ = log return: ln(Pₜ/Pₜ₋₁)
```

### Virtual AMM Pricing
```
Mark Price = vQuoteAssetReserve / vBaseAssetReserve

For long trades: Δy = y × (x/(x-Δx) - 1)
For short trades: Δy = y × (1 - x/(x+Δx))
```

### Funding Rate
```
Premium = MarkPriceTWAP - IndexPriceTWAP
FundingRate = Premium / 24
```

## 🚀 Deployment

### Prerequisites
- Foundry toolkit
- Node.js & npm
- Environment variables configured

### Environment Setup
```bash
cp .env.example .env
# Edit .env with your configuration
```

### Build & Test
```bash
forge build
forge test
forge test -vvv  # verbose output
```

### Deploy
```bash
# Deploy to local network
forge script script/DeployHyperVIX.s.sol --fork-url $RPC_URL --private-key $PRIVATE_KEY

# Deploy to testnet/mainnet
forge script script/DeployHyperVIX.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

## 🔧 Configuration

### Oracle Parameters
- **Lambda (λ)**: Decay factor for EWMA (default: 0.94)
- **Annualization Factor**: Updates per year (default: 8760 for hourly)
- **Initial Variance**: Starting volatility estimate (default: 0.04 for 20%)

### Perpetual Parameters
- **Max Leverage**: Maximum position leverage (default: 10x)
- **Maintenance Margin**: Liquidation threshold (default: 5%)
- **Liquidation Fee**: Fee for liquidators (default: 1%)
- **Trading Fee**: Fee per trade (default: 0.1%)
- **Funding Interval**: Time between funding settlements (default: 1 hour)

### vAMM Initial Setup
- **Base Reserve**: Initial vVOL tokens (default: 1M)
- **Quote Reserve**: Initial collateral (default: 200K USDC)
- **Opening Price**: Quote/Base ratio (default: 0.2 = 20%)

## 📝 Usage Examples

### Opening a Long Position
```solidity
// Approve collateral
collateralToken.approve(address(perpetual), marginAmount);

// Open long position: 1000 vVOL with 10K USDC margin
perpetual.openPosition(1000 * 1e18, 10000 * 1e6);
```

### Closing a Position
```solidity
// Close entire position
perpetual.closePosition();
```

### Oracle Updates (Keeper)
```solidity
// Update volatility index (hourly)
oracle.takePriceSnapshot();

// Settle funding rates (hourly)
perpetual.settleFunding();
```

### Liquidation
```solidity
// Check if position is liquidatable
bool canLiquidate = perpetual.isLiquidatable(trader);

// Liquidate underwater position
perpetual.liquidate(trader);
```

## 🔒 Security Features

### Oracle Security
- **Keeper-only updates**: Only authorized addresses can update prices
- **TWAP resistance**: Time-weighted averages prevent manipulation
- **Price validation**: Zero price protection and bounds checking

### Trading Security
- **Leverage limits**: Configurable maximum leverage
- **Maintenance margins**: Automatic liquidation triggers
- **Insurance fund**: Covers underwater positions
- **Slippage protection**: vAMM provides predictable pricing

### Access Control
- **Owner-only governance**: Critical parameters protected
- **Keeper authorization**: Oracle updates restricted
- **Emergency functions**: Pause/unpause capabilities

## 🧪 Testing

### Test Coverage
- **Oracle Tests**: EWMA calculations, price updates, TWAP functionality
- **Perpetual Tests**: Position management, liquidations, funding
- **Integration Tests**: End-to-end trading scenarios
- **Fuzz Tests**: Edge cases and random inputs

### Run Tests
```bash
# All tests
forge test

# Specific test file
forge test --match-contract VolatilityIndexOracleTest

# Gas reporting
forge test --gas-report

# Coverage
forge coverage
```

## 📊 Monitoring & Analytics

### Key Metrics
- **Current Volatility**: Real-time annualized volatility
- **Mark vs Index**: Premium/discount to index
- **Open Interest**: Total position sizes
- **Funding Rate**: Current funding payments
- **Liquidation Ratio**: Health of positions

### Events for Indexing
- `VolatilityUpdated`: New volatility calculations
- `PositionOpened/Closed`: Trading activity
- `FundingSettled`: Funding rate updates
- `Liquidated`: Liquidation events

## 🔧 Keeper Infrastructure

### Required Keepers
1. **Oracle Keeper**: Updates price feeds hourly
2. **Funding Keeper**: Settles funding rates hourly
3. **Liquidation Bots**: Monitor and liquidate positions

### Keeper Rewards
- **Gas reimbursement**: For oracle/funding updates
- **Liquidation fees**: 1% of liquidated notional value
- **MEV opportunities**: Front-running protection

## 🌟 Advanced Features

### Coming Soon
- **Multi-asset support**: BTC, ETH, and other crypto volatilities
- **Cross-margining**: Portfolio-based margining
- **Options integration**: Vol surface construction
- **DAO governance**: Community parameter control

### Extensibility
- **Plugin architecture**: Custom volatility models
- **Oracle aggregation**: Multiple price feed support
- **Risk management**: Dynamic parameter adjustment

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit pull request

## 📄 License

MIT License - see LICENSE file for details

## ⚠️ Disclaimers

- **Experimental protocol**: Use at your own risk
- **High volatility**: Positions can be liquidated quickly
- **Smart contract risk**: Audit findings don't guarantee safety
- **Regulatory risk**: Check local regulations before use

## 📞 Support

- **Documentation**: [docs.hypervix.io](https://docs.hypervix.io)
- **Discord**: [discord.gg/hypervix](https://discord.gg/hypervix)
- **Twitter**: [@HyperVIX](https://twitter.com/HyperVIX)
- **GitHub Issues**: Bug reports and feature requests
# HyperVIX
