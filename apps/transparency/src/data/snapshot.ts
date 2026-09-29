import { getAddress, type Address, type Hex } from 'viem';
import {
  basketVaultAbi,
  ERC1967_IMPLEMENTATION_SLOT,
  erc20MetadataAbi,
  kandaTokenAbi,
  ROLES,
  roleMap,
  safeAbi,
  timelockControllerAbi,
  type KandaClient,
  type KandaNetwork,
  type RoleRow,
} from '@kanda/chain';
import { requiredBacking } from './derive.js';

export interface LegSnapshot {
  asset: Address;
  symbol: string;
  decimals: number;
  qtyPerUnit: bigint;
  vaultBalance: bigint;
  requiredBalance: bigint;
  coverageBps: bigint;
}

export interface SafeSnapshot {
  name: 'Admin' | 'Ops' | 'Compliance' | 'Guardian' | 'Treasury';
  address: Address;
  owners: readonly Address[];
  threshold: bigint;
}

export interface Snapshot {
  blockNumber: bigint;
  blockTimestamp: bigint;
  token: { name: string; symbol: string; decimals: number; totalSupply: bigint; paused: boolean };
  vault: { paused: boolean; createPaused: boolean; basketVersion: number };
  legs: LegSnapshot[];
  timelockMinDelay: bigint;
  implementations: { kandaToken: Address; participantRegistry: Address; basketVault: Address };
  safes: SafeSnapshot[];
  roles: (RoleRow & { held: boolean })[];
}

/** What readSnapshot needs from a viem client; tests pass a stub with the same shape. */
export type SnapshotClient = Pick<KandaClient, 'getBlock' | 'multicall' | 'getStorageAt'>;

const SAFE_NAMES = ['Admin', 'Ops', 'Compliance', 'Guardian', 'Treasury'] as const;

function slotToAddress(slot: Hex | undefined): Address {
  return getAddress(`0x${(slot ?? '0x').slice(-40).padStart(40, '0')}`);
}

/**
 * Read everything the page shows at one block, so supply, balances and coverage are consistent with each other.
 * No Kanda backend is involved: public RPC and Multicall3 only (L5 section 5).
 */
export async function readSnapshot(client: SnapshotClient, network: KandaNetwork): Promise<Snapshot> {
  const block = await client.getBlock({ blockTag: 'latest' });
  const blockNumber = block.number;
  const { kandaToken, basketVault, timelock, participantRegistry } = network.contracts;

  const [
    name,
    symbol,
    decimals,
    totalSupply,
    tokenPaused,
    legsResult,
    coverage,
    vaultPaused,
    createPaused,
    minDelay,
  ] = await client.multicall({
    blockNumber,
    allowFailure: false,
    contracts: [
      { address: kandaToken, abi: kandaTokenAbi, functionName: 'name' },
      { address: kandaToken, abi: kandaTokenAbi, functionName: 'symbol' },
      { address: kandaToken, abi: kandaTokenAbi, functionName: 'decimals' },
      { address: kandaToken, abi: kandaTokenAbi, functionName: 'totalSupply' },
      { address: kandaToken, abi: kandaTokenAbi, functionName: 'paused' },
      { address: basketVault, abi: basketVaultAbi, functionName: 'legs' },
      { address: basketVault, abi: basketVaultAbi, functionName: 'coverage' },
      { address: basketVault, abi: basketVaultAbi, functionName: 'paused' },
      { address: basketVault, abi: basketVaultAbi, functionName: 'createPaused' },
      { address: timelock, abi: timelockControllerAbi, functionName: 'getMinDelay' },
    ],
  });
  const [basketVersion, legs] = legsResult;

  const legReads = await client.multicall({
    blockNumber,
    allowFailure: false,
    contracts: legs.flatMap((leg) => [
      { address: leg.asset, abi: erc20MetadataAbi, functionName: 'symbol' } as const,
      { address: leg.asset, abi: erc20MetadataAbi, functionName: 'decimals' } as const,
      { address: leg.asset, abi: erc20MetadataAbi, functionName: 'balanceOf', args: [basketVault] } as const,
    ]),
  });

  const safeEntries = SAFE_NAMES.map((name) => ({
    name,
    address: network.safes[name.toLowerCase() as keyof KandaNetwork['safes']],
  }));
  const safeReads = await client.multicall({
    blockNumber,
    allowFailure: false,
    contracts: safeEntries.flatMap(({ address }) => [
      { address, abi: safeAbi, functionName: 'getOwners' } as const,
      { address, abi: safeAbi, functionName: 'getThreshold' } as const,
    ]),
  });

  const rows = roleMap(network);
  const held = await client.multicall({
    blockNumber,
    allowFailure: false,
    contracts: rows.map(
      (row) =>
        ({
          address: row.target,
          abi: kandaTokenAbi, // hasRole has the same signature on all three contracts
          functionName: 'hasRole',
          args: [ROLES[row.role], row.holderAddress],
        }) as const,
    ),
  });

  const [tokenImpl, registryImpl, vaultImpl] = await Promise.all(
    [kandaToken, participantRegistry, basketVault].map((address) =>
      client.getStorageAt({ address, slot: ERC1967_IMPLEMENTATION_SLOT, blockNumber }),
    ),
  );

  return {
    blockNumber,
    blockTimestamp: block.timestamp,
    token: { name, symbol, decimals, totalSupply, paused: tokenPaused },
    vault: { paused: vaultPaused, createPaused, basketVersion },
    legs: legs.map((leg, i) => ({
      asset: leg.asset,
      symbol: legReads[i * 3] as string,
      decimals: legReads[i * 3 + 1] as number,
      vaultBalance: legReads[i * 3 + 2] as bigint,
      qtyPerUnit: leg.qtyPerUnit,
      requiredBalance: requiredBacking(totalSupply, leg.qtyPerUnit),
      coverageBps: coverage[i] ?? 0n,
    })),
    timelockMinDelay: minDelay,
    implementations: {
      kandaToken: slotToAddress(tokenImpl),
      participantRegistry: slotToAddress(registryImpl),
      basketVault: slotToAddress(vaultImpl),
    },
    safes: safeEntries.map(({ name, address }, i) => ({
      name,
      address,
      owners: safeReads[i * 2] as readonly Address[],
      threshold: safeReads[i * 2 + 1] as bigint,
    })),
    roles: rows.map((row, i) => ({ ...row, held: held[i] === true })),
  };
}
