import { explorerAddressUrl, explorerReadUrl, type KandaNetwork } from '@kanda/chain';
import { formatBps } from '@kanda/shared';
import { AddressLink, MoneyText } from '@kanda/ui';
import { useTranslation } from 'react-i18next';
import { MAX_UINT256 } from '../data/derive.js';
import type { LegSnapshot, Snapshot } from '../data/snapshot.js';
import { formatInteger, formatQuantity } from '../format.js';
import { Evidence, Pill, Section, TableFrame, td, th } from './ui.js';

export function Reserves({
  snapshot,
  network,
  locale,
}: {
  snapshot: Snapshot;
  network: KandaNetwork;
  locale: string;
}) {
  const { t } = useTranslation();
  const vault = network.contracts.basketVault;
  const vaultRead = explorerReadUrl(network, vault, true);
  const holdings = `${explorerAddressUrl(network, vault)}?tab=tokens`;

  return (
    <Section id="reserves" title={t('reserves.heading')}>
      <TableFrame>
        <caption className="px-4 pt-3 text-left text-sm text-ink-muted">
          {t('reserves.caption', {
            version: snapshot.vault.basketVersion,
            block: formatInteger(snapshot.blockNumber, locale),
          })}
        </caption>
        <thead>
          <tr>
            <th scope="col" className={th}>
              {t('reserves.asset')}
            </th>
            <th scope="col" className={`${th} text-right`}>
              {t('reserves.perKnd')}
            </th>
            <th scope="col" className={`${th} text-right`}>
              {t('reserves.inVault')}
            </th>
            <th scope="col" className={`${th} text-right`}>
              {t('reserves.required')}
            </th>
            <th scope="col" className={th}>
              {t('reserves.coverage')}
            </th>
          </tr>
        </thead>
        <tbody>
          {snapshot.legs.map((leg, i) => (
            <tr key={leg.asset}>
              <th scope="row" className={`${td} text-left font-bold`}>
                <AddressLink
                  address={leg.asset}
                  href={explorerAddressUrl(network, leg.asset)}
                  label={leg.symbol}
                />
              </th>
              <td className={`${td} text-right font-mono tabular-nums`}>
                <Evidence href={vaultRead} call="BasketVault.legs()">
                  {formatQuantity(leg.qtyPerUnit, leg.decimals, locale)}
                </Evidence>
              </td>
              <td className={`${td} text-right`}>
                <Evidence href={holdings} call={`${leg.symbol}.balanceOf(BasketVault)`}>
                  <MoneyText
                    amount={leg.vaultBalance}
                    decimals={leg.decimals}
                    currency={leg.symbol}
                    locale={locale}
                  />
                </Evidence>
              </td>
              <td className={`${td} text-right`}>
                <MoneyText
                  amount={leg.requiredBalance}
                  decimals={leg.decimals}
                  currency={leg.symbol}
                  locale={locale}
                />
              </td>
              <td className={td}>
                <Coverage leg={leg} gold={i > 0} href={vaultRead} locale={locale} />
              </td>
            </tr>
          ))}
        </tbody>
      </TableFrame>
      <p className="max-w-[65ch] text-sm text-ink-muted">{t('reserves.note')}</p>
    </Section>
  );
}

function Coverage({
  leg,
  gold,
  href,
  locale,
}: {
  leg: LegSnapshot;
  gold: boolean;
  href: string;
  locale: string;
}) {
  const { t } = useTranslation();
  const backed = leg.vaultBalance >= leg.requiredBalance;
  const noSupply = leg.coverageBps === MAX_UINT256;
  const fill = noSupply ? 100 : Number(leg.coverageBps > 10_000n ? 10_000n : leg.coverageBps) / 100;

  return (
    <div className="flex min-w-40 flex-col gap-1.5">
      <div className="flex items-center justify-between gap-3">
        <Evidence href={href} call="BasketVault.coverage()">
          <span className="font-mono tabular-nums">
            {noSupply ? '—' : formatBps(leg.coverageBps, locale)}
          </span>
        </Evidence>
        <Pill tone={backed ? 'settled' : 'danger'}>
          {backed ? t('reserves.backed') : t('reserves.short')}
        </Pill>
      </div>
      <div aria-hidden="true" className="h-2 overflow-hidden rounded-full bg-reserve-soft">
        <div
          className={`h-full ${gold ? 'bg-bullion' : 'bg-reserve'}`}
          style={{ width: `${fill.toString()}%` }}
        />
      </div>
    </div>
  );
}
