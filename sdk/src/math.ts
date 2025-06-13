/**
 * Fixed-point BigInt math utilities matching on-chain Vyper MathLib.
 */

export const WAD = 1_000_000_000_000_000_000n; // 10^18
export const HALF_WAD = 500_000_000_000_000_000n;
export const RAY = 1_000_000_000_000_000_000_000_000_000n; // 10^27
export const HALF_RAY = 500_000_000_000_000_000_000_000_000n;

export function wadMul(a: bigint, b: bigint): bigint {
  if (a === 0n || b === 0n) return 0n;
  return (a * b + HALF_WAD) / WAD;
}

export function wadDiv(a: bigint, b: bigint): bigint {
  if (b === 0n) throw new Error("Math: division by zero");
  return (a * WAD + b / 2n) / b;
}

export function rayMul(a: bigint, b: bigint): bigint {
  if (a === 0n || b === 0n) return 0n;
  return (a * b + HALF_RAY) / RAY;
}

export function rayDiv(a: bigint, b: bigint): bigint {
  if (b === 0n) throw new Error("Math: division by zero");
  return (a * RAY + b / 2n) / b;
}

export function formatWad(val: bigint, decimals: number = 4): string {
  const isNegative = val < 0n;
  const absVal = isNegative ? -val : val;
  const integerPart = absVal / WAD;
  const fracPart = absVal % WAD;
  const fracStr = fracPart.toString().padStart(18, "0").slice(0, decimals);
  return `${isNegative ? "-" : ""}${integerPart}.${fracStr}`;
}
