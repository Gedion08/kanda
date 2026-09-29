import { describe, expect, it } from 'vitest';
import { lowestCoverageBps, requiredBacking, safeIsSingleSigner, MAX_UINT256 } from '../src/data/derive.js';

describe('requiredBacking (INV-1: ceil(totalSupply * qtyPerUnit / 1e18))', () => {
  it('matches the vault for the live testnet basket', () => {
    expect(requiredBacking(1_000n * 10n ** 18n, 700_000n)).toBe(700_000_000n); // 700 USDC
    expect(requiredBacking(1_000n * 10n ** 18n, 70_000_000_000_000n)).toBe(70_000_000_000_000_000n); // 0.07 oz
  });

  it('rounds up, like the contract', () => {
    expect(requiredBacking(1n, 700_000n)).toBe(1n);
  });

  it('is zero with no supply', () => {
    expect(requiredBacking(0n, 700_000n)).toBe(0n);
  });
});

describe('lowestCoverageBps', () => {
  it('returns the scarcest leg', () => {
    expect(lowestCoverageBps([10_101n, 10_000n])).toBe(10_000n);
  });

  it('returns null while supply is zero (coverage() is type(uint256).max per leg)', () => {
    expect(lowestCoverageBps([MAX_UINT256, MAX_UINT256])).toBeNull();
  });
});

describe('safeIsSingleSigner', () => {
  it('flags a 1-of-1 Safe', () => {
    expect(safeIsSingleSigner(1n, 1)).toBe(true);
    expect(safeIsSingleSigner(2n, 3)).toBe(false);
  });
});
