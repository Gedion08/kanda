/**
 * @kanda/chain: ABIs, deployment addresses, viem clients. L3 s11, L5 s2.
 */
import { createPublicClient, http } from 'viem';
import { baseSepolia as viemBaseSepolia } from 'viem/chains';
import type { KandaNetwork } from './networks.js';

export * from './abis.js';
export * from './networks.js';
export * from './roles.js';
export * from './safe.js';

/** A read-only client for `network`. Multicall3 batches the reads into one RPC call per block. */
export function createKandaClient(network: KandaNetwork, rpcUrl?: string) {
  return createPublicClient({
    chain: viemBaseSepolia,
    transport: http(rpcUrl ?? network.defaultRpcUrl),
    batch: { multicall: true },
  });
}

/** The client type createKandaClient returns. */
export type KandaClient = ReturnType<typeof createKandaClient>;
