import { explorerAddressUrl, explorerReadUrl, type KandaNetwork } from '@kanda/chain';
import { AddressLink } from '@kanda/ui';
import { useTranslation } from 'react-i18next';
import { safeIsSingleSigner } from '../data/derive.js';
import type { Snapshot } from '../data/snapshot.js';
import { formatDuration } from '../format.js';
import { Evidence, Pill, Section, TableFrame, td, th } from './ui.js';

export function Governance({
  snapshot,
  network,
  locale,
}: {
  snapshot: Snapshot;
  network: KandaNetwork;
  locale: string;
}) {
  const { t } = useTranslation();
  const timelock = network.contracts.timelock;

  return (
    <Section id="governance" title={t('governance.heading')}>
      <p className="max-w-[65ch]">
        <Evidence href={explorerReadUrl(network, timelock, false)} call="TimelockController.getMinDelay()">
          {t('governance.timelock', { delay: formatDuration(snapshot.timelockMinDelay, locale) })}
        </Evidence>
      </p>

      <h3 className="text-base font-bold">{t('governance.safes')}</h3>
      <TableFrame>
        <thead>
          <tr>
            <th scope="col" className={th}>
              {t('governance.safe')}
            </th>
            <th scope="col" className={th}>
              {t('governance.address')}
            </th>
            <th scope="col" className={th}>
              {t('governance.signers')}
            </th>
          </tr>
        </thead>
        <tbody>
          {snapshot.safes.map((safe) => (
            <tr key={safe.address}>
              <th scope="row" className={`${td} text-left font-bold`}>
                {safe.name}
              </th>
              <td className={td}>
                <AddressLink address={safe.address} href={explorerAddressUrl(network, safe.address)} />
              </td>
              <td className={td}>
                <div className="flex flex-col items-start gap-1.5">
                  <span className="font-mono tabular-nums">
                    {t('governance.signersValue', {
                      threshold: safe.threshold.toString(),
                      owners: safe.owners.length.toString(),
                    })}
                  </span>
                  {safeIsSingleSigner(safe.threshold, safe.owners.length) ? (
                    <Pill tone="caution">{t('governance.singleSigner')}</Pill>
                  ) : null}
                </div>
              </td>
            </tr>
          ))}
        </tbody>
      </TableFrame>

      <h3 className="text-base font-bold">{t('governance.roles')}</h3>
      <TableFrame>
        <caption className="px-4 pt-3 text-left text-sm text-ink-muted">
          {t('governance.rolesCaption')}
        </caption>
        <thead>
          <tr>
            <th scope="col" className={th}>
              {t('governance.contract')}
            </th>
            <th scope="col" className={th}>
              {t('governance.role')}
            </th>
            <th scope="col" className={th}>
              {t('governance.holder')}
            </th>
            <th scope="col" className={th}>
              {t('governance.check')}
            </th>
          </tr>
        </thead>
        <tbody>
          {snapshot.roles.map((row) => (
            <tr key={`${row.target}-${row.role}-${row.holderAddress}`}>
              <td className={td}>{row.contract}</td>
              <td className={`${td} font-mono text-xs`}>{row.role}</td>
              <td className={td}>
                <AddressLink
                  address={row.holderAddress}
                  href={explorerAddressUrl(network, row.holderAddress)}
                  label={row.holder}
                />
              </td>
              <td className={td}>
                <Evidence
                  href={explorerReadUrl(network, row.target, true)}
                  call={`${row.contract}.hasRole(${row.role}, ${row.holder})`}
                >
                  <Pill tone={row.held ? 'settled' : 'danger'}>
                    {row.held ? t('governance.held') : t('governance.missing')}
                  </Pill>
                </Evidence>
              </td>
            </tr>
          ))}
        </tbody>
      </TableFrame>
    </Section>
  );
}
