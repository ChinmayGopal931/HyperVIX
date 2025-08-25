#!/usr/bin/env node

const { ethers } = require('ethers');
require('dotenv').config();

// Contract addresses from latest deployment
  const CONTRACTS = {
    VolatilityIndexOracle: "0x42336C82c4e727D98d37C626edF24eC44794157a",
    VolatilityPerpetual:   "0x4734c15878ff8f7EFd4a7D81A316B348808Ee7D7",
    HyperVIXKeeper:        "0xEe2722216acaC9700cebFe4F8998E29d4a16CeE7",
    MockUSDC:              "0xeA852122fFcADE7345761317b5465776a85Caa39"
  }

// Hyperliquid testnet RPC
const RPC_URL = process.env.RPC_URL || "https://rpc.hyperliquid-testnet.xyz/evm";

// Simple ABIs for the keeper functions
const KEEPER_ABI = [
    "function updateOracle() external",
    "function settleFunding() external",
    "function updateBoth() external",
    "function authorizedKeepers(address) external view returns (bool)",
    "function lastOracleUpdate() external view returns (uint256)",
    "function lastFundingUpdate() external view returns (uint256)",
    "function isOracleUpdateDue() external view returns (bool)",
    "function isFundingUpdateDue() external view returns (bool)",
    "function owner() external view returns (address)"
];

const ORACLE_ABI = [
    "function takePriceSnapshot() external",
    "function getLastUpdateTime() external view returns (uint256)",
    "function getAnnualizedVolatility() external view returns (uint256)"
];

const PERPETUAL_ABI = [
    "function settleFunding() external",
    "function lastFundingTime() external view returns (uint256)",
    "function fundingInterval() external view returns (uint256)"
];

class HyperVIXKeeper {
    constructor() {
        // Create provider with retry and polling settings
        this.provider = new ethers.JsonRpcProvider(RPC_URL, undefined, {
            staticNetwork: true,
            pollingInterval: 10000, // 10 seconds
            batchMaxCount: 1
        });
        this.wallet = new ethers.Wallet(process.env.PRIVATE_KEY, this.provider);
        
        this.keeperContract = new ethers.Contract(
            CONTRACTS.HyperVIXKeeper,
            KEEPER_ABI,
            this.wallet
        );
        
        this.oracleContract = new ethers.Contract(
            CONTRACTS.VolatilityIndexOracle,
            ORACLE_ABI,
            this.wallet
        );
        
        this.perpetualContract = new ethers.Contract(
            CONTRACTS.VolatilityPerpetual,
            PERPETUAL_ABI,
            this.wallet
        );
        
        this.isRunning = false;
        this.UPDATE_INTERVAL = 15000; // 60 seconds (slower to avoid rate limits)
        this.FUNDING_INTERVAL = 3600000; // 1 hour
    }

    async retryCall(fn, retries = 3, delay = 2000) {
        for (let i = 0; i < retries; i++) {
            try {
                return await fn();
            } catch (error) {
                if (i === retries - 1) throw error;
                if (error.message.includes('rate limited')) {
                    console.log(`⏳ Rate limited, waiting ${delay}ms before retry ${i + 1}/${retries}`);
                    await new Promise(resolve => setTimeout(resolve, delay));
                    delay *= 2; // Exponential backoff
                } else {
                    throw error;
                }
            }
        }
    }

    async initialize() {
        console.log("🚀 Initializing HyperVIX Keeper Bot...");
        console.log("Wallet Address:", this.wallet.address);
        
        // Check if authorized with retry
        const isAuthorized = await this.retryCall(async () => {
            return await this.keeperContract.authorizedKeepers(this.wallet.address);
        });
        
        if (!isAuthorized) {
            throw new Error("❌ Wallet is not authorized as keeper!");
        }
        
        console.log("✅ Keeper authorization confirmed");
        
        // Check current state with retry
        const lastUpdate = await this.retryCall(() => this.keeperContract.lastOracleUpdate());
        const lastFunding = await this.retryCall(() => this.keeperContract.lastFundingUpdate());
        const currentVIX = await this.retryCall(() => this.oracleContract.getAnnualizedVolatility());
        
        console.log("📊 Current System State:");
        console.log("  Last Update:", new Date(Number(lastUpdate) * 1000).toISOString());
        console.log("  Last Funding:", new Date(Number(lastFunding) * 1000).toISOString());
        console.log("  Current VIX:", ethers.formatUnits(currentVIX, 18));
        console.log("");
    }

    async updateOracle() {
        try {
            console.log("📈 Updating oracle...");
            const tx = await this.keeperContract.updateOracle({
                gasLimit: 500000,
                gasPrice: 500000000 // 0.5 gwei
            });
            
            console.log("  Transaction:", tx.hash);
            const receipt = await tx.wait();
            
            if (receipt.status === 1) {
                const newVIX = await this.oracleContract.getAnnualizedVolatility();
                console.log("  ✅ Oracle updated - New VIX:", ethers.formatUnits(newVIX, 18));
                return true;
            } else {
                console.log("  ❌ Transaction failed");
                return false;
            }
        } catch (error) {
            console.log("  ⚠️ Oracle update failed:", error.message);
            return false;
        }
    }

    async settleFunding() {
        try {
            console.log("💰 Settling funding...");
            const tx = await this.keeperContract.settleFunding({
                gasLimit: 500000,
                gasPrice: 500000000 // 0.5 gwei
            });
            
            console.log("  Transaction:", tx.hash);
            const receipt = await tx.wait();
            
            if (receipt.status === 1) {
                console.log("  ✅ Funding settled successfully");
                return true;
            } else {
                console.log("  ❌ Transaction failed");
                return false;
            }
        } catch (error) {
            console.log("  ⚠️ Funding settlement failed:", error.message);
            return false;
        }
    }

    async checkAndUpdate() {
        
        try {
            // Check if updates are due
            const oracleUpdateDue = await this.retryCall(() => this.keeperContract.isOracleUpdateDue());
            
            // Check funding directly from perpetual
            const lastFundingTime = await this.retryCall(() => this.perpetualContract.lastFundingTime());
            const fundingInterval = await this.retryCall(() => this.perpetualContract.fundingInterval());
            const currentTime = Math.floor(Date.now() / 1000);
            const fundingUpdateDue = currentTime >= (Number(lastFundingTime) + Number(fundingInterval));
            
            console.log(`⏰ [${new Date().toISOString()}] Checking system...`);
            console.log(`  Oracle update due: ${oracleUpdateDue}`);
            console.log(`  Funding update due: ${fundingUpdateDue}`);
            
            // Use updateBoth() if either update is due
            if (oracleUpdateDue || fundingUpdateDue) {
                await this.updateBoth();
            } else {
                console.log("  ✅ System up to date");
            }
            
        } catch (error) {
            console.log("  ❌ Error checking system:", error.message);
        }
        
        console.log(""); // Empty line for readability
    }

    async updateBoth() {
        try {
            console.log("🔄 Running direct updates (oracle & funding)...");
            
            let oracleSuccess = false;
            let fundingSuccess = false;
            
            // Update oracle directly
            const oracleUpdateDue = await this.retryCall(() => this.keeperContract.isOracleUpdateDue());
            if (oracleUpdateDue) {
                console.log("  📈 Updating oracle directly...");
                const oracleTx = await this.oracleContract.takePriceSnapshot({
                    gasLimit: 500000,
                    gasPrice: 500000000
                });
                console.log("    Oracle TX:", oracleTx.hash);
                const oracleReceipt = await oracleTx.wait();
                oracleSuccess = oracleReceipt.status === 1;
                console.log(oracleSuccess ? "    ✅ Oracle updated" : "    ❌ Oracle failed");
            }
            
            // Check funding directly from perpetual contract
            const lastFundingTime = await this.retryCall(() => this.perpetualContract.lastFundingTime());
            const fundingInterval = await this.retryCall(() => this.perpetualContract.fundingInterval());
            const currentTime = Math.floor(Date.now() / 1000);
            const fundingUpdateDue = currentTime >= (Number(lastFundingTime) + Number(fundingInterval));
            
            if (fundingUpdateDue) {
                console.log("  💰 Settling funding directly...");
                const fundingTx = await this.perpetualContract.settleFunding({
                    gasLimit: 500000,
                    gasPrice: 500000000
                });
                console.log("    Funding TX:", fundingTx.hash);
                const fundingReceipt = await fundingTx.wait();
                fundingSuccess = fundingReceipt.status === 1;
                console.log(fundingSuccess ? "    ✅ Funding settled" : "    ❌ Funding failed");
            }
            
            if (!oracleUpdateDue && !fundingUpdateDue) {
                console.log("  ✅ No updates needed");
                return true;
            }
            
            // Show updated VIX
            const newVIX = await this.oracleContract.getAnnualizedVolatility();
            console.log("  Current VIX:", ethers.formatUnits(newVIX, 18));
            
            return (oracleUpdateDue ? oracleSuccess : true) && (fundingUpdateDue ? fundingSuccess : true);
            
        } catch (error) {
            console.log("  ⚠️ Update failed:", error.message);
            return false;
        }
    }

    async start() {
        if (this.isRunning) {
            console.log("⚠️ Keeper is already running!");
            return;
        }
        
        await this.initialize();
        
        this.isRunning = true;
        console.log("🔄 Starting keeper bot...");
        console.log("Press Ctrl+C to stop\n");
        
        // Initial check
        await this.checkAndUpdate();
        
        // Set up periodic checks
        this.interval = setInterval(async () => {
            if (this.isRunning) {
                await this.checkAndUpdate();
            }
        }, this.UPDATE_INTERVAL);
    }

    stop() {
        console.log("\n🛑 Stopping keeper bot...");
        this.isRunning = false;
        if (this.interval) {
            clearInterval(this.interval);
        }
        console.log("✅ Keeper stopped");
        process.exit(0);
    }
}

// Handle graceful shutdown
process.on('SIGINT', () => {
    if (keeper) {
        keeper.stop();
    } else {
        process.exit(0);
    }
});

process.on('SIGTERM', () => {
    if (keeper) {
        keeper.stop();
    } else {
        process.exit(0);
    }
});

// Main execution
let keeper;

async function main() {
    try {
        keeper = new HyperVIXKeeper();
        await keeper.start();
    } catch (error) {
        console.error("💥 Failed to start keeper:", error.message);
        process.exit(1);
    }
}

// Run if called directly
if (require.main === module) {
    main();
}

module.exports = HyperVIXKeeper;