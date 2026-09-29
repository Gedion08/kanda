import { mulDivCeil } from '@kanda/shared';

export const MAX_UINT256 = 2n ** 256n - 1n;
const UNIT = 10n ** 18n;

/** INV-1 required backing for one leg: ceil(totalSupply * qtyPerUnit / 1e18), as the vault computes it. */
export function requiredBacking(totalSupply: bigint, qtyPerUnit: bigint): bigint {
  return mulDivCeil(totalSupply, qtyPerUnit, UNIT);
}

/** The lowest per-leg coverage in bps, or null while supply is zero (coverage() returns max per leg then). */
export function lowestCoverageBps(ratiosBps: readonly bigint[]): bigint | null {
  const real = ratiosBps.filter((r) => r !== MAX_UINT256);
  if (real.length === 0) return null;
  return real.reduce((min, r) => (r < min ? r : min));
}

/** A Safe that one key controls: fine on testnet until signers are added, never on mainnet. */
export function safeIsSingleSigner(threshold: bigint, ownerCount: number): boolean {
  return threshold === 1n && ownerCount === 1;
}
