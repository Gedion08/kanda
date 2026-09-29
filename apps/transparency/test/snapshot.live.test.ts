import { baseSepolia, createKandaClient } from '@kanda/chain';
import { describe, expect, it } from 'vitest';
import { readSnapshot } from '../src/data/snapshot.js';

// Reads the real Base Sepolia deployment. Opt-in, so CI never depends on a public RPC:
//   KANDA_LIVE=1 pnpm --filter @kanda/transparency test
describe.runIf(process.env.KANDA_LIVE === '1')('readSnapshot against Base Sepolia', () => {
  it('reads a fully backed, correctly wired deployment', { timeout: 60_000 }, async () => {
    const s = await readSnapshot(createKandaClient(baseSepolia), baseSepolia);

    expect(s.token.symbol).toBe('KND');
    expect(s.token.totalSupply).toBeGreaterThan(0n);
    expect(s.legs).toHaveLength(2);
    for (const leg of s.legs) {
      expect(leg.vaultBalance).toBeGreaterThanOrEqual(leg.requiredBalance); // INV-1, recomputed off-chain
      expect(leg.coverageBps).toBeGreaterThanOrEqual(10_000n);
    }
    expect(s.roles.every((r) => r.held)).toBe(true);
    expect(s.timelockMinDelay).toBe(300n);
    expect(s.safes).toHaveLength(5);
    expect(s.implementations.basketVault).not.toBe('0x0000000000000000000000000000000000000000');
  });
});
