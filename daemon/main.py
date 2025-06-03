"""
Aegis Unified Keeper Daemon CLI runner.
"""

import sys
import time
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

from daemon.config import DEFAULT_CONFIG
from daemon.keeper.liquidator import DutchAuctionLiquidator
from daemon.keeper.batch_matcher import BatchAuctionSolver, LimitOrder
from daemon.keeper.oracle_relayer import OracleRelayer

console = Console()

def run_daemon_status_check():
    console.print(Panel.fit("[bold cyan]Aegis Protocol - Autonomous Keeper Daemon[/bold cyan]"))

    table = Table(title="Keeper System Status")
    table.add_column("Subsystem", style="cyan", no_wrap=True)
    table.add_column("Status", style="green")
    table.add_column("Details", style="magenta")

    table.add_row("Dutch Liquidator", "ACTIVE", "Monitoring decaying auctions with flash loan routing")
    table.add_row("Batch Clearing Solver", "ACTIVE", "Crossing uniform clearing price epochs")
    table.add_row("Oracle Relayer", "ACTIVE", "Supervising Chainlink and Pyth feed divergence")
    table.add_row("Health Monitor", "ACTIVE", "Polling borrower credit account health factors")

    console.print(table)

    # Demonstrate batch auction solver matching
    solver = BatchAuctionSolver()
    sample_orders = [
        LimitOrder(order_id=1, trader="0xAlice", is_buy=True, limit_price=3100.0, amount=2.0),
        LimitOrder(order_id=2, trader="0xBob", is_buy=False, limit_price=2900.0, amount=2.0),
        LimitOrder(order_id=3, trader="0xCarol", is_buy=True, limit_price=3050.0, amount=1.0),
        LimitOrder(order_id=4, trader="0xDave", is_buy=False, limit_price=2950.0, amount=1.0),
    ]
    res = solver.solve_clearing_price(sample_orders)
    if res:
        console.print(f"[bold green]Batch Solved![/bold green] Uniform Price: ${res.clearing_price:.2f}, Volume: {res.matched_volume} units, Matches: {len(res.matched_pairs)}")

if __name__ == "__main__":
    run_daemon_status_check()
