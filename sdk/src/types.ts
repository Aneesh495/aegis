/**
 * Core type definitions for Aegis protocol contracts and SDK operations.
 */

export interface PositionSnapshot {
  account: string;
  equityUsd: bigint;
  totalCollateralUsd: bigint;
  totalDebtUsd: bigint;
  healthFactorWad: bigint;
  isLiquidatable: boolean;
}

export interface AuctionData {
  auctionId: bigint;
  account: string;
  debtAsset: string;
  collateralAsset: string;
  debtAmount: bigint;
  collateralAmount: bigint;
  startTime: bigint;
  duration: bigint;
  currentPenaltyWad: bigint;
  settled: boolean;
}

export interface BatchOrder {
  orderId: bigint;
  trader: string;
  baseAsset: string;
  quoteAsset: string;
  isBuy: boolean;
  limitPriceWad: bigint;
  amount: bigint;
  filled: bigint;
  epochId: bigint;
  cancelled: boolean;
}

export enum TrancheTier {
  Senior = 0,
  Mezzanine = 1,
  Junior = 2,
}
