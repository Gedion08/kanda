import { explorerAddressUrl, type KandaNetwork } from '@kanda/chain';
import { AddressLink } from '@kanda/ui';
import { useTranslation } from 'react-i18next';
import type { Address } from 'viem';
import type { Snapshot } from '../data/snapshot.js';
import { Section, TableFrame, td, th } from './ui.js';

export function Contracts({ snapshot, network }: { snapshot: Snapshot; network: KandaNetwork }) {
  const { t } = useTranslation();
  const { kandaToken, participantRegistry, basketVault, timelock } = network.contracts;
  const rows: { name: string; address: Address; implementation?: Address }[] = [
    { name: 'KandaToken', address: kandaToken, implementation: snapshot.implementations.kandaToken },
    {
      name: 'ParticipantRegistry',
      address: participantRegistry,
      implementation: snapshot.implementations.participantRegistry,
    },
    { name: 'BasketVault', address: basketVault, implementation: snapshot.implementations.basketVault },
    { name: 'TimelockController', address: timelock },
  ];

  return (
    <Section id="contracts" title={t('contracts.heading')}>
      <TableFrame>
        <thead>
          <tr>
            <th scope="col" className={th}>
              {t('contracts.contract')}
            </th>
            <th scope="col" className={th}>
              {t('contracts.proxy')}
            </th>
            <th scope="col" className={th}>
              {t('contracts.implementation')}
            </th>
            <th scope="col" className={th}>
              {t('contracts.source')}
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.address}>
              <th scope="row" className={`${td} text-left font-bold`}>
                {row.name}
              </th>
              <td className={td}>
                <AddressLink address={row.address} href={explorerAddressUrl(network, row.address)} />
              </td>
              <td className={td}>
                {row.implementation ? (
                  <AddressLink
                    address={row.implementation}
                    href={explorerAddressUrl(network, row.implementation)}
                  />
                ) : (
                  <span className="text-ink-muted">—</span>
                )}
              </td>
              <td className={td}>
                <a
                  className="underline decoration-line-strong underline-offset-4 hover:decoration-reserve"
                  href={`${explorerAddressUrl(network, row.implementation ?? row.address)}?tab=contract`}
                  target="_blank"
                  rel="noreferrer"
                >
                  {t('contracts.verified')}
                </a>
              </td>
            </tr>
          ))}
        </tbody>
      </TableFrame>
    </Section>
  );
}
