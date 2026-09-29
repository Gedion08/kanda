import { explorerReadUrl, type KandaNetwork } from '@kanda/chain';
import { formatBps } from '@kanda/shared';
import { MoneyText } from '@kanda/ui';
import { useTranslation } from 'react-i18next';
import { lowestCoverageBps } from '../data/derive.js';
import type { Snapshot } from '../data/snapshot.js';
import { formatQuantity } from '../format.js';
import { Evidence, Pill } from './ui.js';

export function Figures({
  snapshot,
  network,
  locale,
}: {
  snapshot: Snapshot;
  network: KandaNetwork;
  locale: string;
}) {
  const { t } = useTranslation();
  const { kandaToken, basketVault } = network.contracts;
  const lowest = lowestCoverageBps(snapshot.legs.map((l) => l.coverageBps));
  const allBacked = snapshot.legs.every((l) => l.vaultBalance >= l.requiredBalance);
  const basket = snapshot.legs
    .map((l) => `${formatQuantity(l.qtyPerUnit, l.decimals, locale)}\u00a0${l.symbol}`) // keep each amount with its symbol
    .join(' + ');

  return (
    <section aria-label="Key figures" className="grid gap-3 sm:grid-cols-3">
      <Figure label={t('figures.supply')}>
        <Evidence href={explorerReadUrl(network, kandaToken, true)} call="KandaToken.totalSupply()">
          <MoneyText
            amount={snapshot.token.totalSupply}
            decimals={snapshot.token.decimals}
            currency="KND"
            locale={locale}
          />
        </Evidence>
      </Figure>
      <Figure
        label={t('figures.coverage')}
        footer={
          <Pill tone={allBacked ? 'settled' : 'danger'}>
            {allBacked ? t('figures.fullyBacked') : t('figures.underBacked')}
          </Pill>
        }
      >
        <Evidence href={explorerReadUrl(network, basketVault, true)} call="BasketVault.coverage()">
          <span className="font-mono tabular-nums">
            {lowest === null ? t('figures.noSupply') : formatBps(lowest, locale)}
          </span>
        </Evidence>
      </Figure>
      <Figure label={t('figures.basket')}>
        <Evidence href={explorerReadUrl(network, basketVault, true)} call="BasketVault.legs()">
          <span className="font-mono text-base tabular-nums sm:text-lg">{basket}</span>
        </Evidence>
      </Figure>
    </section>
  );
}

function Figure({
  label,
  children,
  footer,
}: {
  label: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-2 rounded-lg border border-line bg-surface-raised p-5">
      <span className="text-xs font-bold tracking-[0.06em] text-ink-muted uppercase">{label}</span>
      <span className="text-2xl leading-tight font-medium sm:text-[1.75rem]">{children}</span>
      {footer ? <span>{footer}</span> : null}
    </div>
  );
}
