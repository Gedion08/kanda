import { describe, expect, it } from 'vitest';
import {
  formatBps,
  formatMoney,
  formatUnits,
  isIsoCurrency,
  mulDivCeil,
  mulDivFloor,
  parseUnits,
} from '../src/money.js';

/** Intl uses non-breaking spaces; compare with plain spaces. */
const plain = (text: string): string => text.replace(/\s/gu, ' ');

describe('formatUnits', () => {
  it('is exact for 18 decimals, with no float rounding', () => {
    expect(formatUnits(1_000_000_000_000_000_000_001n, 18)).toBe('1000.000000000000000001');
    expect(formatUnits(999_000_000_000_000_000_000n, 18)).toBe('999');
    expect(formatUnits(700_000n, 6)).toBe('0.7');
    expect(formatUnits(0n, 18)).toBe('0');
    expect(formatUnits(1n, 18)).toBe('0.000000000000000001');
  });

  it('keeps the sign of negative values', () => {
    expect(formatUnits(-1_500_000n, 6)).toBe('-1.5');
  });

  it('handles values beyond 2^53 exactly', () => {
    expect(formatUnits(2n ** 255n, 18)).toBe(
      '57896044618658097711785492504343953926634992332820282019728.792003956564819968',
    );
  });
});

describe('parseUnits', () => {
  it('round-trips with formatUnits', () => {
    expect(parseUnits('1000.000000000000000001', 18)).toBe(1_000_000_000_000_000_000_001n);
    expect(parseUnits('0.7', 6)).toBe(700_000n);
    expect(parseUnits('-1.5', 6)).toBe(-1_500_000n);
  });

  it('rejects more decimals than the unit has, and malformed input', () => {
    expect(() => parseUnits('0.0000001', 6)).toThrow(RangeError);
    expect(() => parseUnits('1e18', 18)).toThrow(RangeError);
    expect(() => parseUnits('', 18)).toThrow(RangeError);
  });
});

describe('mulDiv (matches Math.mulDiv in the contracts)', () => {
  it('floor and ceil agree on exact divisions', () => {
    expect(mulDivFloor(1000n * 10n ** 18n, 700_000n, 10n ** 18n)).toBe(700_000_000n);
    expect(mulDivCeil(1000n * 10n ** 18n, 700_000n, 10n ** 18n)).toBe(700_000_000n);
  });

  it('ceil rounds up any remainder, floor drops it', () => {
    // 1 base unit of KND needs 0.0000007 USDC base units.
    expect(mulDivFloor(1n, 700_000n, 10n ** 18n)).toBe(0n);
    expect(mulDivCeil(1n, 700_000n, 10n ** 18n)).toBe(1n);
  });

  it('rejects a zero denominator and negative inputs', () => {
    expect(() => mulDivCeil(1n, 1n, 0n)).toThrow(RangeError);
    expect(() => mulDivFloor(-1n, 1n, 1n)).toThrow(RangeError);
  });
});

describe('formatMoney', () => {
  it('shows KND after the amount with 2 decimals, truncated so it never overstates', () => {
    expect(formatMoney(1_250_999_000_000_000_000_000n, 18, 'KND', 'en-US')).toBe('1,250.99 KND');
    expect(formatMoney(999_000_000_000_000_000_000n, 18, 'KND', 'en-US')).toBe('999.00 KND');
  });

  it('formats ISO currencies with Intl, following the locale', () => {
    expect(plain(formatMoney(161_240_00n, 2, 'KES', 'en-KE'))).toBe('Ksh 161,240.00');
    expect(formatMoney(700_000n, 6, 'USD', 'en-US')).toBe('$0.70');
  });

  it('changes grouping and decimal marks with the locale', () => {
    const fr = formatMoney(1_250_500_000_000_000_000_000n, 18, 'KND', 'fr-FR');
    expect(fr).toMatch(/^1\s250,50 KND$/u);
  });

  it('writes token symbols after the amount instead of treating them as currencies', () => {
    expect(formatMoney(700_000_000n, 6, 'tUSDC', 'en-US')).toBe('700.00 tUSDC');
    expect(isIsoCurrency('KND')).toBe(false);
    expect(isIsoCurrency('NGN')).toBe(true);
  });

  it('shows full precision when asked', () => {
    expect(formatMoney(1n, 18, 'KND', 'en-US', { fullPrecision: true })).toBe('0.000000000000000001 KND');
  });
});

describe('formatBps', () => {
  it('formats basis points as a percentage', () => {
    expect(formatBps(10_000n, 'en-US')).toBe('100.00%');
    expect(formatBps(10_101n, 'en-US')).toBe('101.01%');
    expect(formatBps(9_999n, 'en-US')).toBe('99.99%');
  });
});
