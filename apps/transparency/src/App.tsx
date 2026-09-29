import type { KandaNetwork } from '@kanda/chain';
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Contracts } from './components/Contracts.js';
import { Figures } from './components/Figures.js';
import { Governance } from './components/Governance.js';
import { Reserves } from './components/Reserves.js';
import { Status } from './components/Status.js';
import { Section } from './components/ui.js';
import type { Snapshot } from './data/snapshot.js';
import { formatInteger, formatUtc, loadLocale, LOCALES, saveLocale, type LocaleId } from './format.js';

export interface AppProps {
  network: KandaNetwork;
  /** Shown in the footer so readers know where the numbers came from. */
  rpcLabel: string;
  loadSnapshot: () => Promise<Snapshot>;
}

const REFRESH_MS = 30_000;

export function App({ network, rpcLabel, loadSnapshot }: AppProps) {
  const { t } = useTranslation();
  const [locale, setLocale] = useState<LocaleId>(loadLocale);
  const query = useQuery({
    queryKey: ['snapshot', network.chainId],
    queryFn: loadSnapshot,
    refetchInterval: REFRESH_MS,
  });
  const snapshot = query.data;

  return (
    <div className="min-h-screen bg-surface text-ink">
      <header className="border-b border-line bg-surface-raised">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-4 px-4 py-4 sm:px-6">
          <div className="flex items-center gap-3">
            <picture>
              <source srcSet="/kanda-lockup-on-dark.svg" media="(prefers-color-scheme: dark)" />
              <img src="/kanda-lockup.svg" alt="Kanda" width={135} height={30} />
            </picture>
            <span className="text-ink-muted" aria-hidden="true">
              /
            </span>
            <span className="font-bold">{t('title')}</span>
          </div>
          <div className="flex flex-wrap items-center gap-3 text-sm">
            <span className="rounded border border-caution px-2 py-0.5 font-bold text-caution">
              {t('network', { network: network.name })}
            </span>
            <label className="flex items-center gap-2">
              <span className="text-ink-muted">{t('numberFormat')}</span>
              <select
                value={locale}
                onChange={(e) => {
                  const next = e.target.value as LocaleId;
                  setLocale(next);
                  saveLocale(next);
                }}
                className="rounded-lg border border-line-strong bg-surface-raised px-2 py-1"
              >
                {LOCALES.map((l) => (
                  <option key={l.id} value={l.id}>
                    {l.label}
                  </option>
                ))}
              </select>
            </label>
          </div>
        </div>
      </header>

      {network.testnet ? (
        <div className="border-b border-line bg-bullion-soft">
          <p className="mx-auto max-w-5xl px-4 py-2 text-sm text-bullion-ink sm:px-6">
            {t('testnetBanner', { network: network.name })}
          </p>
        </div>
      ) : null}

      <main className="mx-auto flex max-w-5xl flex-col gap-12 px-4 py-10 sm:px-6">
        <div className="flex flex-col gap-3">
          <h1 className="max-w-[22ch] text-3xl leading-tight font-extrabold tracking-tight sm:text-5xl">
            {t('thesis')}
          </h1>
          <p className="max-w-[65ch] text-ink-muted">{t('intro', { network: network.name })}</p>
        </div>

        {query.isError && snapshot ? (
          <p role="status" className="rounded-lg border border-caution px-4 py-3 text-sm text-caution">
            {t('staleWarning', { block: formatInteger(snapshot.blockNumber, locale) })}
          </p>
        ) : null}

        {snapshot ? (
          <>
            <Figures snapshot={snapshot} network={network} locale={locale} />
            <Reserves snapshot={snapshot} network={network} locale={locale} />
            <Status snapshot={snapshot} network={network} />
            <Governance snapshot={snapshot} network={network} locale={locale} />
            <Contracts snapshot={snapshot} network={network} />
            <Section id="next" title={t('next.heading')}>
              <ul className="flex max-w-[65ch] list-disc flex-col gap-1 pl-5 text-ink-muted">
                <li>{t('next.nav')}</li>
                <li>{t('next.history')}</li>
                <li>{t('next.queue')}</li>
              </ul>
            </Section>
          </>
        ) : query.isError ? (
          <div
            role="alert"
            className="flex flex-col items-start gap-3 rounded-lg border border-danger bg-surface-raised p-5"
          >
            <h2 className="text-lg font-bold text-danger">{t('errorTitle', { network: network.name })}</h2>
            <p className="text-ink-muted">{t('errorBody')}</p>
            <button
              type="button"
              onClick={() => void query.refetch()}
              className="rounded-lg bg-reserve px-4 py-2 font-bold text-on-reserve"
            >
              {t('retry')}
            </button>
          </div>
        ) : (
          <div aria-busy="true" aria-live="polite" className="flex flex-col gap-3">
            <span className="text-ink-muted">{t('loading')}</span>
            <div className="grid gap-3 sm:grid-cols-3">
              {[0, 1, 2].map((i) => (
                <div key={i} className="h-28 animate-pulse rounded-lg bg-reserve-soft" />
              ))}
            </div>
          </div>
        )}
      </main>

      <footer className="border-t border-line">
        <p className="mx-auto max-w-5xl px-4 py-6 text-sm text-ink-muted sm:px-6">
          {snapshot
            ? t('footer', {
                rpc: rpcLabel,
                block: formatInteger(snapshot.blockNumber, locale),
                time: formatUtc(snapshot.blockTimestamp, locale),
              })
            : null}
        </p>
      </footer>
    </div>
  );
}
