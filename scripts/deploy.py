"""
Deterministic protocol deployment script orchestrating all Aegis contract deployments and linkages.
"""

from dataclasses import dataclass
import boa

WAD = 10**18

@dataclass
class DeployedSystem:
    weth: any
    usdc: any
    wbtc: any
    twap_oracle: any
    price_router: any
    vault: any
    risk_engine: any
    credit_manager: any
    debt_engine: any
    liquidation_auction: any
    batch_clearinghouse: any
    dex_adapter: any
    emergency_council: any
    protocol_parameters: any

def deploy_aegis_protocol() -> DeployedSystem:
    print("[1/6] Deploying test assets...")
    weth = boa.load("contracts/core/MockERC20.vy", "Wrapped Ether", "WETH", 18)
    usdc = boa.load("contracts/core/MockERC20.vy", "USD Coin", "USDC", 6)
    wbtc = boa.load("contracts/core/MockERC20.vy", "Wrapped Bitcoin", "WBTC", 8)

    print("[2/6] Deploying oracle subsystem...")
    twap = boa.load("contracts/oracles/TWAPOracle.vy", 64)
    router = boa.load("contracts/oracles/PriceFeedRouter.vy", twap.address)

    # Aggregators: WETH $3,000, USDC $1.00, WBTC $60,000
    empty_addr = "0x0000000000000000000000000000000000000000"
    agg_weth = boa.load("contracts/oracles/MockAggregator.vy", 8, 300_000_000_000)
    ad_weth = boa.load("contracts/oracles/ChainlinkAdapter.vy", agg_weth.address, 3600, 10_000_000_000, 5_000_000_000_000)
    router.set_asset_feeds(weth.address, ad_weth.address, empty_addr, int(0.05 * WAD), 1800)

    agg_usdc = boa.load("contracts/oracles/MockAggregator.vy", 8, 100_000_000)
    ad_usdc = boa.load("contracts/oracles/ChainlinkAdapter.vy", agg_usdc.address, 3600, 50_000_000, 200_000_000)
    router.set_asset_feeds(usdc.address, ad_usdc.address, empty_addr, int(0.05 * WAD), 1800)

    agg_wbtc = boa.load("contracts/oracles/MockAggregator.vy", 8, 6_000_000_000_000)
    ad_wbtc = boa.load("contracts/oracles/ChainlinkAdapter.vy", agg_wbtc.address, 3600, 100_000_000_000, 20_000_000_000_000)
    router.set_asset_feeds(wbtc.address, ad_wbtc.address, empty_addr, int(0.05 * WAD), 1800)

    print("[3/6] Deploying core risk and prime brokerage contracts...")
    vault = boa.load("contracts/core/AegisVault.vy", 10) # 10 bps flash fee
    risk_engine = boa.load("contracts/core/RiskEngine.vy", router.address)
    credit_manager = boa.load("contracts/core/CreditManager.vy", vault.address)
    debt_engine = boa.load("contracts/core/DebtEngine.vy", vault.address)
    liquidation_auction = boa.load("contracts/core/LiquidationAuction.vy", router.address)
    clearinghouse = boa.load("contracts/core/BatchClearinghouse.vy", 60)

    print("[4/6] Deploying DEX adapters...")
    dex = boa.load("contracts/adapters/MockDEXAdapter.vy")
    dex.set_rate(weth.address, usdc.address, 3000 * WAD)
    dex.set_rate(usdc.address, weth.address, WAD // 3000)

    print("[5/6] Deploying governance and emergency council...")
    council = boa.load("contracts/governance/EmergencyCouncil.vy", 172_800)
    params = boa.load("contracts/governance/ProtocolParameters.vy", council.address)

    print("[6/6] Linking system authorizations...")
    vault.set_credit_manager(credit_manager.address)
    vault.set_debt_engine(debt_engine.address)
    risk_engine.set_credit_manager(credit_manager.address)
    credit_manager.set_protocol_contracts(risk_engine.address, debt_engine.address, liquidation_auction.address)
    credit_manager.set_adapter_status(dex.address, True)
    liquidation_auction.set_credit_manager(credit_manager.address)

    # Risk parameters: WETH 85%, USDC 95%, WBTC 85%
    risk_engine.set_asset_risk_parameters(weth.address, int(0.15 * WAD), int(0.85 * WAD), WAD)
    risk_engine.set_asset_risk_parameters(usdc.address, int(0.05 * WAD), int(0.95 * WAD), WAD)
    risk_engine.set_asset_risk_parameters(wbtc.address, int(0.15 * WAD), int(0.85 * WAD), WAD)

    vault.set_asset_status(weth.address, True, 0)
    vault.set_asset_status(usdc.address, True, 0)
    vault.set_asset_status(wbtc.address, True, 0)

    print("All Aegis contracts successfully deployed and linked.")
    return DeployedSystem(
        weth=weth,
        usdc=usdc,
        wbtc=wbtc,
        twap_oracle=twap,
        price_router=router,
        vault=vault,
        risk_engine=risk_engine,
        credit_manager=credit_manager,
        debt_engine=debt_engine,
        liquidation_auction=liquidation_auction,
        batch_clearinghouse=clearinghouse,
        dex_adapter=dex,
        emergency_council=council,
        protocol_parameters=params
    )

if __name__ == "__main__":
    deploy_aegis_protocol()
