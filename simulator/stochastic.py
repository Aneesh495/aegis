"""
Stochastic price path generators: Geometric Brownian Motion (GBM) and Merton Jump Diffusion.
"""

import numpy as np
from typing import Tuple

class StochasticProcess:
    """
    Simulates asset price dynamics under ordinary volatility and discrete jump shocks.
    """
    @staticmethod
    def geometric_brownian_motion(
        s0: float,
        mu: float,
        sigma: float,
        t: float,
        steps: int,
        paths: int = 1,
        seed: int = 42
    ) -> np.ndarray:
        np.random.seed(seed)
        dt = t / steps
        nudt = (mu - 0.5 * sigma**2) * dt
        sidt = sigma * np.sqrt(dt)

        delta_w = np.random.normal(0, 1, size=(steps, paths))
        delta_s = nudt + sidt * delta_w
        delta_s = np.vstack([np.zeros((1, paths)), delta_s])

        return s0 * np.exp(np.cumsum(delta_s, axis=0))

    @staticmethod
    def merton_jump_diffusion(
        s0: float,
        mu: float,
        sigma: float,
        jump_intensity: float,
        jump_mean: float,
        jump_std: float,
        t: float,
        steps: int,
        paths: int = 1,
        seed: int = 42
    ) -> np.ndarray:
        np.random.seed(seed)
        dt = t / steps
        k = np.exp(jump_mean + 0.5 * jump_std**2) - 1.0

        drift = (mu - 0.5 * sigma**2 - jump_intensity * k) * dt
        vol = sigma * np.sqrt(dt)

        prices = np.zeros((steps + 1, paths))
        prices[0] = s0

        for i in range(1, steps + 1):
            z = np.random.normal(0, 1, size=paths)
            n_jumps = np.random.poisson(jump_intensity * dt, size=paths)
            jump_factor = np.zeros(paths)

            for p in range(paths):
                if n_jumps[p] > 0:
                    j_samples = np.random.normal(jump_mean, jump_std, size=n_jumps[p])
                    jump_factor[p] = np.sum(j_samples)

            log_return = drift + vol * z + jump_factor
            prices[i] = prices[i - 1] * np.exp(log_return)

        return prices
