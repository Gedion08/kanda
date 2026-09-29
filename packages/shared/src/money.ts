/**
 * Money helpers. Amounts are bigint base units end to end; decimal strings only at the edges (AGENTS.md: never
 * floats for money). Display goes through Intl.NumberFormat with decimal-string input, which is exact.
 */

const DECIMAL = /^(-)?(\d+)(?:\.(\d+))?$/u;

/** Exact decimal string of `value` base units with `decimals` places, trailing zeros trimmed. */
export function formatUnits(value: bigint, decimals: number): string {
  const negative = value < 0n;
  const abs = negative ? -value : value;
  const base = 10n ** BigInt(decimals);
  const whole = (abs / base).toString();
  const fraction = (abs % base).toString().padStart(decimals, '0').replace(/0+$/u, '');
  return `${negative ? '-' : ''}${whole}${fraction ? `.${fraction}` : ''}`;
}

/** Parse a plain decimal string into base units. Throws RangeError on more places than `decimals` allows. */
export function parseUnits(text: string, decimals: number): bigint {
  const match = DECIMAL.exec(text);
  if (!match) throw new RangeError(`Not a decimal number: "${text}"`);
  const [, sign, whole = '0', fraction = ''] = match;
  if (fraction.length > decimals) {
    throw new RangeError(`More than ${decimals.toString()} decimal places: "${text}"`);
  }
  const units = BigInt(whole) * 10n ** BigInt(decimals) + BigInt(fraction.padEnd(decimals, '0') || '0');
  return sign ? -units : units;
}

function checkMulDiv(a: bigint, b: bigint, d: bigint): void {
  if (d <= 0n) throw new RangeError('Denominator must be positive');
  if (a < 0n || b < 0n) throw new RangeError('mulDiv inputs must be non-negative');
}

/** floor(a * b / d), as Math.mulDiv(..., Floor) in the contracts. */
export function mulDivFloor(a: bigint, b: bigint, d: bigint): bigint {
  checkMulDiv(a, b, d);
  return (a * b) / d;
}

/** ceil(a * b / d), as Math.mulDiv(..., Ceil) in the contracts. */
export function mulDivCeil(a: bigint, b: bigint, d: bigint): bigint {
  checkMulDiv(a, b, d);
  const product = a * b;
  return product / d + (product % d === 0n ? 0n : 1n);
}

export interface FormatMoneyOptions {
  /** Show every base unit instead of 2 decimals (tooltips). */
  fullPrecision?: boolean;
}

let isoCurrencies: ReadonlySet<string> | undefined;

/** Whether `code` is an ISO 4217 currency the runtime knows. KND and token symbols are not. */
export function isIsoCurrency(code: string): boolean {
  isoCurrencies ??= new Set(Intl.supportedValuesOf('currency'));
  return isoCurrencies.has(code);
}

/**
 * Format an amount for display. KND and token symbols are written after the amount ("1,250.00 KND", brand book);
 * ISO 4217 currencies use the locale's currency style. The UI shows 2 decimals, truncated so a balance is never overstated.
 */
export function formatMoney(
  amount: bigint,
  decimals: number,
  currency: string,
  locale: string,
  options: FormatMoneyOptions = {},
): string {
  const decimal = formatUnits(amount, decimals);
  const digits = options.fullPrecision
    ? { minimumFractionDigits: 2, maximumFractionDigits: Math.max(2, decimals) }
    : { minimumFractionDigits: 2, maximumFractionDigits: 2 };
  const common = { ...digits, roundingMode: 'trunc' } as const;

  if (!isIsoCurrency(currency)) {
    const number = new Intl.NumberFormat(locale, common).format(decimal as `${number}`);
    return `${number} ${currency}`;
  }
  return new Intl.NumberFormat(locale, { ...common, style: 'currency', currency }).format(
    decimal as `${number}`,
  );
}

/** Format basis points (10000 = 100%) as a percentage with 2 decimals, truncated. */
export function formatBps(bps: bigint, locale: string): string {
  return new Intl.NumberFormat(locale, {
    style: 'percent',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
    roundingMode: 'trunc',
  }).format(formatUnits(bps, 4) as `${number}`);
}
