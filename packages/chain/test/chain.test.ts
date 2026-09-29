import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isAddress, keccak256, toHex } from 'viem';
import { describe, expect, it } from 'vitest';
import {
  basketVaultAbi,
  baseSepolia,
  ERC1967_IMPLEMENTATION_SLOT,
  explorerReadUrl,
  kandaTokenAbi,
  participantRegistryAbi,
  ROLES,
  roleMap,
  timelockControllerAbi,
} from '../src/index.js';
import { readAbi, SOURCES } from '../scripts/gen-abis.mjs';

const here = dirname(fileURLToPath(import.meta.url));

describe('baseSepolia network', () => {
  it('reads every address from the deployment and config files', () => {
    expect(baseSepolia.chainId).toBe(84532);
    const all = [
      ...Object.values(baseSepolia.contracts),
      ...Object.values(baseSepolia.safes),
      baseSepolia.pauseBot,
      baseSepolia.releaser,
      baseSepolia.feeRecipient,
    ];
    for (const address of all) expect(isAddress(address, { strict: true })).toBe(true);
    expect(baseSepolia.feeRecipient).toBe(baseSepolia.safes.treasury);
  });

  it('links numbers to the contract read tab', () => {
    expect(explorerReadUrl(baseSepolia, baseSepolia.contracts.basketVault, true)).toBe(
      `https://base-sepolia.blockscout.com/address/${baseSepolia.contracts.basketVault}?tab=read_proxy`,
    );
  });
});

describe('ABIs', () => {
  it('expose the reads the transparency page uses', () => {
    const names = (abi: readonly { type: string; name?: string }[]) =>
      abi.filter((item) => item.type === 'function').map((item) => item.name);
    expect(names(kandaTokenAbi)).toEqual(expect.arrayContaining(['totalSupply', 'paused', 'hasRole']));
    expect(names(basketVaultAbi)).toEqual(
      expect.arrayContaining(['legs', 'coverage', 'paused', 'createPaused']),
    );
    expect(names(participantRegistryAbi)).toEqual(expect.arrayContaining(['hasRole']));
    expect(names(timelockControllerAbi)).toEqual(expect.arrayContaining(['getMinDelay']));
  });

  const out = join(here, '../../../contracts/out');
  it.runIf(existsSync(out))('match the current Foundry build (re-run gen:abis if this fails)', async () => {
    const generated = (await import('../src/abis.js')) as Record<string, unknown>;
    for (const [name, [file, contract]] of Object.entries(SOURCES)) {
      expect(generated[name], name).toEqual(readAbi(file, contract));
    }
  });
});

describe('roles', () => {
  it('match Roles.sol', () => {
    expect(ROLES.MINTER_ROLE).toBe(keccak256(toHex('MINTER_ROLE')));
    expect(ROLES.DEFAULT_ADMIN_ROLE).toBe(`0x${'0'.repeat(64)}`);
  });

  it('list the 18 P0 rows of the ADD section 4 map', () => {
    const rows = roleMap(baseSepolia);
    expect(rows).toHaveLength(18);
    expect(rows.filter((r) => r.role === 'MINTER_ROLE')).toEqual([
      expect.objectContaining({ contract: 'KandaToken', holder: 'BasketVault' }),
    ]);
  });

  it('use the ERC-1967 implementation slot', () => {
    const slot = BigInt(keccak256(toHex('eip1967.proxy.implementation'))) - 1n;
    expect(ERC1967_IMPLEMENTATION_SLOT).toBe(`0x${slot.toString(16)}`);
  });
});
