import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from simulator.risk_sim import run_risk_simulation
from simulator.waterfall_sim import run_waterfall_simulation
from simulator.benchmark import run_benchmarks

def run_all_stress_tests():
    print("Executing comprehensive Aegis stress tests...\n")
    run_risk_simulation()
    print("\n" + "="*70 + "\n")
    run_waterfall_simulation()
    print("\n" + "="*70 + "\n")
    run_benchmarks()
    print("\nAll stress tests and gas benchmarks completed successfully.")

if __name__ == "__main__":
    run_all_stress_tests()
