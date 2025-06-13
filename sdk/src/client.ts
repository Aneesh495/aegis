/**
 * High-level Aegis Protocol Client for querying risk, managing credit accounts,
 * submitting batch orders, and participating in Dutch liquidations.
 */

import { PositionSnapshot, AuctionData, BatchOrder, TrancheTier } from "./types";
import { WAD, wadMul, wadDiv } from "./math";

export interface ProtocolAddresses {
  vault: string;
  creditManager: string;
  debtEngine: string;
  riskEngine: string;
  liquidationAuction: string;
  batchClearinghouse: string;
  priceRouter: string;
}

export class AegisProtocolClient {
  public readonly addresses: ProtocolAddresses;

  constructor(addresses: ProtocolAddresses) {
    this.addresses = addresses;
  }

  /**
   * Calculates health factor given adjusted collateral and adjusted debt.
   */
  public calculateHealthFactor(adjCollateralWad: bigint, adjDebtWad: bigint): bigint {
    if (adjDebtWad === 0n) return ~0n;
    return wadDiv(adjCollateralWad, adjDebtWad);
  }

  /**
   * Calculates Dutch auction linear decaying penalty at elapsed seconds.
   */
  public calculateDecayingPenalty(
    startPenaltyWad: bigint,
    minPenaltyWad: bigint,
    durationSeconds: bigint,
    elapsedSeconds: bigint
  ): bigint {
    if (elapsedSeconds >= durationSeconds) return minPenaltyWad;
    const spread = startPenaltyWad - minPenaltyWad;
    const decay = (elapsedSeconds * spread) / durationSeconds;
    return startPenaltyWad - decay;
  }
}
