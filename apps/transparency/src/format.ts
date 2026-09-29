import { formatUnits } from '@kanda/shared';

/** Number-format locales offered on the page (L5 acceptance: a locale switch changes number formatting). */
export const LOCALES = [
  { id: 'en-US', label: 'English (US)' },
  { id: 'en-KE', label: 'English (Kenya)' },
  { id: 'en-NG', label: 'English (Nigeria)' },
  { id: 'sw-KE', label: 'Kiswahili (Kenya)' },
  { id: 'fr-FR', label: 'Français' },
] as const;

export type LocaleId = (typeof LOCALES)[number]['id'];

const STORAGE_KEY = 'kanda.transparency.locale';

export function loadLocale(): LocaleId {
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    const match = LOCALES.find((l) => l.id === saved);
    if (match) return match.id;
  } catch {
    // Storage can be blocked; the default is fine.
  }
  return 'en-US';
}

export function saveLocale(locale: LocaleId): void {
  try {
    localStorage.setItem(STORAGE_KEY, locale);
  } catch {
    // A per-viewer convenience only.
  }
}

/** A token quantity at full precision with at least 2 decimals: 0.70, 0.00007. */
export function formatQuantity(value: bigint, decimals: number, locale: string): string {
  return new Intl.NumberFormat(locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: decimals,
  }).format(formatUnits(value, decimals) as `${number}`);
}

/** A block number with grouping: 47,426,610. */
export function formatInteger(value: bigint, locale: string): string {
  return new Intl.NumberFormat(locale).format(value);
}

/** A duration in seconds as the largest whole unit: 300 → "5 minutes". */
export function formatDuration(seconds: bigint, locale: string): string {
  const units = [
    ['day', 86_400n],
    ['hour', 3_600n],
    ['minute', 60n],
  ] as const;
  for (const [unit, size] of units) {
    if (seconds >= size && seconds % size === 0n) {
      return new Intl.NumberFormat(locale, { style: 'unit', unit, unitDisplay: 'long' }).format(
        seconds / size,
      );
    }
  }
  return new Intl.NumberFormat(locale, { style: 'unit', unit: 'second', unitDisplay: 'long' }).format(
    seconds,
  );
}

/** A block timestamp in UTC. */
export function formatUtc(timestamp: bigint, locale: string): string {
  return new Intl.DateTimeFormat(locale, {
    dateStyle: 'medium',
    timeStyle: 'medium',
    timeZone: 'UTC',
  }).format(new Date(Number(timestamp) * 1000));
}
