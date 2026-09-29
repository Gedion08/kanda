import { explorerReadUrl, type KandaNetwork } from '@kanda/chain';
import { useTranslation } from 'react-i18next';
import type { Snapshot } from '../data/snapshot.js';
import { Evidence, Pill } from './ui.js';

export function Status({ snapshot, network }: { snapshot: Snapshot; network: KandaNetwork }) {
  const { t } = useTranslation();
  const token = explorerReadUrl(network, network.contracts.kandaToken, true);
  const vault = explorerReadUrl(network, network.contracts.basketVault, true);
  const rows = [
    {
      label: t('status.transfers'),
      paused: snapshot.token.paused,
      on: t('status.active'),
      href: token,
      call: 'KandaToken.paused()',
    },
    {
      label: t('status.vault'),
      paused: snapshot.vault.paused,
      on: t('status.active'),
      href: vault,
      call: 'BasketVault.paused()',
    },
    {
      label: t('status.creation'),
      paused: snapshot.vault.createPaused,
      on: t('status.open'),
      href: vault,
      call: 'BasketVault.createPaused()',
    },
  ];

  return (
    <section aria-labelledby="status" className="flex flex-col gap-4">
      <h2 id="status" className="text-lg font-bold tracking-tight">
        {t('status.heading')}
      </h2>
      <ul className="grid gap-3 sm:grid-cols-3">
        {rows.map((row) => (
          <li
            key={row.label}
            className="flex items-center justify-between gap-3 rounded-lg border border-line bg-surface-raised px-4 py-3"
          >
            <span className="text-sm font-bold">{row.label}</span>
            <Evidence href={row.href} call={row.call}>
              <Pill tone={row.paused ? 'caution' : 'settled'}>
                {row.paused ? t('status.paused') : row.on}
              </Pill>
            </Evidence>
          </li>
        ))}
      </ul>
    </section>
  );
}
