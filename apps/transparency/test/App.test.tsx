// @vitest-environment jsdom
import { baseSepolia, roleMap } from '@kanda/chain';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';
import { App } from '../src/App.js';
import type { Snapshot } from '../src/data/snapshot.js';
import '../src/i18n.js';

const E18 = 10n ** 18n;

/** Shaped like the live Base Sepolia deployment after SeedTestnet. */
function fixture(overrides: Partial<Snapshot> = {}): Snapshot {
  return {
    blockNumber: 47_426_700n,
    blockTimestamp: 1_790_622_400n,
    token: { name: 'Kanda', symbol: 'KND', decimals: 18, totalSupply: 1_000n * E18, paused: false },
    vault: { paused: false, createPaused: false, basketVersion: 1 },
    legs: [
      {
        asset: '0xCb0586c74234fa79f8a71f926841B3d1ae9E6c98',
        symbol: 'tUSDC',
        decimals: 6,
        qtyPerUnit: 700_000n,
        vaultBalance: 700_000_000n,
        requiredBalance: 700_000_000n,
        coverageBps: 10_000n,
      },
      {
        asset: '0x2BF116ed7190147A90219271361dE9477Fb7B4E8',
        symbol: 'tDGLD',
        decimals: 18,
        qtyPerUnit: 70_000_000_000_000n,
        vaultBalance: 70_000_000_000_000_000n,
        requiredBalance: 70_000_000_000_000_000n,
        coverageBps: 10_000n,
      },
    ],
    timelockMinDelay: 300n,
    implementations: {
      kandaToken: '0x7a54dE17441455Dc2c515B929871EDF8d016EbB3',
      participantRegistry: '0xeFe87b54Fc6D2C9484fD00f21BeB8714ea3a51d6',
      basketVault: '0xBffBA024C36680a827125a90a6a90B5f19a18B8E',
    },
    safes: (['Admin', 'Ops', 'Compliance', 'Guardian', 'Treasury'] as const).map((name) => ({
      name,
      address: baseSepolia.safes[name.toLowerCase() as keyof typeof baseSepolia.safes],
      owners: ['0x164e31F960ab37369e5b17Ed0faDA994E71AEE5c'],
      threshold: 1n,
    })),
    roles: roleMap(baseSepolia).map((row) => ({ ...row, held: true })),
    ...overrides,
  };
}

function renderApp(load: () => Promise<Snapshot>) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <App network={baseSepolia} rpcLabel="sepolia.base.org" loadSnapshot={load} />
    </QueryClientProvider>,
  );
}

afterEach(cleanup);

describe('App', () => {
  it('renders supply, coverage and the basket from chain data alone', async () => {
    renderApp(() => Promise.resolve(fixture()));

    const figures = await screen.findByRole('region', { name: 'Key figures' });
    expect(within(figures).getByText('1,000.00 KND')).toBeTruthy();
    expect(within(figures).getByText('100.00%')).toBeTruthy();
    expect(within(figures).getByText('Fully backed')).toBeTruthy();
    // Non-breaking spaces keep each amount with its symbol.
    expect(within(figures).getByText(/^0\.70\stUSDC \+ 0\.00007\stDGLD$/u)).toBeTruthy();
  });

  it('shows each reserve leg against its required backing', async () => {
    renderApp(() => Promise.resolve(fixture()));
    const table = await screen.findByRole('table', { name: /Basket version 1/u });
    const rows = within(table).getAllByRole('row');
    expect(rows).toHaveLength(3); // header + 2 legs
    const usdcRow = rows[1];
    if (!usdcRow) throw new Error('missing USDC row');
    // Fully backed: in vault and required are both exactly 700 tUSDC.
    expect(within(usdcRow).getAllByText('700.00 tUSDC')).toHaveLength(2);
    expect(within(table).getAllByText('Backed')).toHaveLength(2);
  });

  it('flags an under-backed leg in words, not colour alone', async () => {
    const s = fixture();
    const legs = s.legs.map((leg, i) => (i === 1 ? { ...leg, vaultBalance: 1n, coverageBps: 0n } : leg));
    renderApp(() => Promise.resolve({ ...s, legs }));
    expect(await screen.findByText('Under-backed')).toBeTruthy();
    expect(screen.getByText('Short')).toBeTruthy();
  });

  it('checks every role row on-chain and warns about single-signer Safes', async () => {
    renderApp(() => Promise.resolve(fixture()));
    const roles = await screen.findByRole('table', { name: /role map/u });
    expect(within(roles).getAllByText('Held')).toHaveLength(18);
    expect(screen.getAllByText('One signer. Signers are added before mainnet.')).toHaveLength(5);
    expect(screen.getByText(/public timelock for 5 minutes/u)).toBeTruthy();
  });

  it('reformats numbers when the locale changes', async () => {
    renderApp(() => Promise.resolve(fixture()));
    const select = await screen.findByLabelText('Number format');
    fireEvent.change(select, { target: { value: 'fr-FR' } });
    const figures = screen.getByRole('region', { name: 'Key figures' });
    expect(within(figures).getByText(/^1\s000,00 KND$/u)).toBeTruthy();
  });

  it('shows pause states in words', async () => {
    renderApp(() =>
      Promise.resolve(fixture({ vault: { paused: false, createPaused: true, basketVersion: 1 } })),
    );
    const status = await screen.findByRole('region', { name: 'Status' });
    expect(within(status).getByText('New creation').parentElement?.textContent).toContain('Paused');
  });

  it('explains an RPC failure and offers a retry instead of a blank page', async () => {
    renderApp(() => Promise.reject(new Error('fetch failed')));
    expect(await screen.findByText('Could not read Base Sepolia')).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Try again' })).toBeTruthy();
  });
});
