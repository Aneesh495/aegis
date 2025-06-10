"""
Tranche default waterfall simulator evaluating capital preservation under credit shocks.
"""

from rich.console import Console
from rich.table import Table
from rich.panel import Panel

console = Console()

def run_waterfall_simulation():
    console.print(Panel.fit("[bold cyan]Aegis DebtEngine - Tranche Waterfall Stress Simulation[/bold cyan]"))

    # Initial Pool Capital Structure: $10,000,000 total pool
    # Senior (AAA): 60% = $6,000,000
    # Mezzanine (BBB): 25% = $2,500,000
    # Junior (Equity): 15% = $1,500,000
    senior_initial = 6_000_000.0
    mezz_initial = 2_500_000.0
    junior_initial = 1_500_000.0
    total_pool = senior_initial + mezz_initial + junior_initial

    stress_scenarios = [
        ("Mild Drawdown", 0.05),       # $500k loss (5%)
        ("Moderate Volatility", 0.12), # $1.2M loss (12%)
        ("Severe Credit Event", 0.25), # $2.5M loss (25%)
        ("Catastrophic Shock", 0.45),  # $4.5M loss (45%)
    ]

    table = Table(title="Tranche Recovery Rates under Systemic Default Cascades")
    table.add_column("Scenario", style="cyan")
    table.add_column("Default Loss ($)", style="yellow")
    table.add_column("Junior Recovery", style="magenta")
    table.add_column("Mezzanine Recovery", style="blue")
    table.add_column("Senior (AAA) Recovery", style="green")

    for name, loss_pct in stress_scenarios:
        loss_usd = total_pool * loss_pct

        # Waterfall absorption: Junior first
        j_rem = max(0.0, junior_initial - loss_usd)
        j_loss = junior_initial - j_rem
        excess_loss_1 = loss_usd - j_loss

        # Mezzanine second
        m_rem = max(0.0, mezz_initial - excess_loss_1)
        m_loss = mezz_initial - m_rem
        excess_loss_2 = excess_loss_1 - m_loss

        # Senior last
        s_rem = max(0.0, senior_initial - excess_loss_2)

        j_rec = (j_rem / junior_initial) * 100.0
        m_rec = (m_rem / mezz_initial) * 100.0
        s_rec = (s_rem / senior_initial) * 100.0

        table.add_row(
            name,
            f"${loss_usd:,.0f} ({loss_pct*100:.0f}%)",
            f"{j_rec:.1f}%",
            f"{m_rec:.1f}%",
            f"[bold green]{s_rec:.1f}%[/bold green]"
        )

    console.print(table)

if __name__ == "__main__":
    run_waterfall_simulation()
