import { getAddress, type Address } from 'viem';
import baseSepoliaDeployment from '../../../contracts/deployments/base-sepolia.json' with { type: 'json' };
import baseSepoliaConfig from '../../../contracts/config/base-sepolia.json' with { type: 'json' };

/** Addresses of one network's deployment. Read from contracts/deployments and contracts/config, never hard-coded. */
export interface KandaNetwork {
  chainId: number;
  name: string;
  testnet: boolean;
  explorerUrl: string;
  defaultRpcUrl: string;
  startBlock: bigint;
  contracts: {
    kandaToken: Address;
    participantRegistry: Address;
    basketVault: Address;
    timelock: Address;
  };
  safes: { admin: Address; ops: Address; compliance: Address; guardian: Address; treasury: Address };
  pauseBot: Address;
  releaser: Address;
  feeRecipient: Address;
}

export const baseSepolia: KandaNetwork = {
  chainId: baseSepoliaDeployment.chainId,
  name: 'Base Sepolia',
  testnet: true,
  explorerUrl: 'https://base-sepolia.blockscout.com',
  defaultRpcUrl: 'https://sepolia.base.org',
  startBlock: BigInt(baseSepoliaDeployment.startBlock),
  contracts: {
    kandaToken: getAddress(baseSepoliaDeployment.kandaToken),
    participantRegistry: getAddress(baseSepoliaDeployment.participantRegistry),
    basketVault: getAddress(baseSepoliaDeployment.basketVault),
    timelock: getAddress(baseSepoliaDeployment.timelock),
  },
  safes: {
    admin: getAddress(baseSepoliaConfig.safes.admin),
    ops: getAddress(baseSepoliaConfig.safes.ops),
    compliance: getAddress(baseSepoliaConfig.safes.compliance),
    guardian: getAddress(baseSepoliaConfig.safes.guardian),
    treasury: getAddress(baseSepoliaConfig.safes.treasury),
  },
  pauseBot: getAddress(baseSepoliaConfig.pauseBot),
  releaser: getAddress(baseSepoliaConfig.releaser),
  feeRecipient: getAddress(baseSepoliaConfig.feeRecipient),
};

/** Networks with a Kanda deployment, by chain ID. Base mainnet joins at P1 genesis. */
export const networks: Readonly<Record<number, KandaNetwork>> = { [baseSepolia.chainId]: baseSepolia };

/** Explorer link for an address. */
export function explorerAddressUrl(network: KandaNetwork, address: Address): string {
  return `${network.explorerUrl}/address/${address}`;
}

/** Explorer link to a contract's read tab, where anyone can repeat a call (L5 section 5: every number has a link). */
export function explorerReadUrl(network: KandaNetwork, address: Address, proxy: boolean): string {
  return `${network.explorerUrl}/address/${address}?tab=${proxy ? 'read_proxy' : 'read_contract'}`;
}
