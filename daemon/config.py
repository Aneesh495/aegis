"""
Configuration settings for Aegis off-chain keeper daemon network.
"""

import os
from dataclasses import dataclass
from typing import Optional

@dataclass
class DaemonConfig:
    rpc_url: str = os.getenv("AEGIS_RPC_URL", "http://127.0.0.1:8545")
    private_key: str = os.getenv("AEGIS_PRIVATE_KEY", "0x" + "11" * 32)
    vault_address: str = os.getenv("AEGIS_VAULT_ADDRESS", "")
    credit_manager_address: str = os.getenv("AEGIS_CREDIT_MANAGER_ADDRESS", "")
    debt_engine_address: str = os.getenv("AEGIS_DEBT_ENGINE_ADDRESS", "")
    liquidation_auction_address: str = os.getenv("AEGIS_LIQUIDATION_AUCTION_ADDRESS", "")
    batch_clearinghouse_address: str = os.getenv("AEGIS_BATCH_CLEARINGHOUSE_ADDRESS", "")
    price_router_address: str = os.getenv("AEGIS_PRICE_ROUTER_ADDRESS", "")

    # Keeper execution thresholds
    min_profit_usd: float = float(os.getenv("AEGIS_MIN_PROFIT_USD", "25.0"))
    min_profit_margin: float = float(os.getenv("AEGIS_MIN_PROFIT_MARGIN", "0.02")) # 2%
    max_gas_price_gwei: float = float(os.getenv("AEGIS_MAX_GAS_GWEI", "150.0"))
    poll_interval_seconds: float = float(os.getenv("AEGIS_POLL_INTERVAL", "2.0"))

DEFAULT_CONFIG = DaemonConfig()
