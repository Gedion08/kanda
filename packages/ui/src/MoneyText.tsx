import { formatMoney } from '@kanda/shared';

export interface MoneyTextProps {
  /** Amount in base units. */
  amount: bigint;
  decimals: number;
  /** "KND" or an ISO 4217 code. */
  currency: string;
  locale: string;
  className?: string;
}

/** An amount with 2 decimals (truncated) and the full-precision value in its tooltip (L5 section 2). */
export function MoneyText({ amount, decimals, currency, locale, className }: MoneyTextProps) {
  const full = formatMoney(amount, decimals, currency, locale, { fullPrecision: true });
  return (
    <span className={`font-mono tabular-nums ${className ?? ''}`} title={full}>
      {formatMoney(amount, decimals, currency, locale)}
    </span>
  );
}
