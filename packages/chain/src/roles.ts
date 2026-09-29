import { keccak256, toHex, zeroHash, type Address, type Hex } from 'viem';
import type { KandaNetwork } from './networks.js';

/** Role IDs, as in contracts/src/governance/Roles.sol. */
export const ROLES = {
  DEFAULT_ADMIN_ROLE: zeroHash,
  UPGRADER_ROLE: keccak256(toHex('UPGRADER_ROLE')),
  LIMITS_ADMIN_ROLE: keccak256(toHex('LIMITS_ADMIN_ROLE')),
  MINTER_ROLE: keccak256(toHex('MINTER_ROLE')),
  PAUSER_ROLE: keccak256(toHex('PAUSER_ROLE')),
  UNPAUSER_ROLE: keccak256(toHex('UNPAUSER_ROLE')),
  COMPLIANCE_ROLE: keccak256(toHex('COMPLIANCE_ROLE')),
  PARTICIPANT_MANAGER_ROLE: keccak256(toHex('PARTICIPANT_MANAGER_ROLE')),
  LIMITS_CONSUMER_ROLE: keccak256(toHex('LIMITS_CONSUMER_ROLE')),
} as const satisfies Record<string, Hex>;

export type RoleName = keyof typeof ROLES;
export type ContractName = 'KandaToken' | 'ParticipantRegistry' | 'BasketVault';
export type HolderName =
  'Timelock' | 'BasketVault' | 'Admin Safe' | 'Ops Safe' | 'Compliance Safe' | 'Guardian Safe' | 'Pause bot';

export interface RoleRow {
  contract: ContractName;
  target: Address;
  role: RoleName;
  holder: HolderName;
  holderAddress: Address;
}

/**
 * The ADD section 4 role map for the P0 contracts, for display. The authority is contracts/script/lib/RoleMap.sol,
 * which VerifyRoles checks on-chain; the page shows the same rows and checks each one with hasRole.
 */
export function roleMap(network: KandaNetwork): RoleRow[] {
  const { kandaToken, participantRegistry, basketVault, timelock } = network.contracts;
  const { admin, ops, compliance, guardian } = network.safes;
  const row = (
    contract: ContractName,
    target: Address,
    role: RoleName,
    holder: HolderName,
    holderAddress: Address,
  ): RoleRow => ({ contract, target, role, holder, holderAddress });

  return [
    row('KandaToken', kandaToken, 'DEFAULT_ADMIN_ROLE', 'Timelock', timelock),
    row('KandaToken', kandaToken, 'UPGRADER_ROLE', 'Timelock', timelock),
    row('KandaToken', kandaToken, 'MINTER_ROLE', 'BasketVault', basketVault),
    row('KandaToken', kandaToken, 'PAUSER_ROLE', 'Guardian Safe', guardian),
    row('KandaToken', kandaToken, 'PAUSER_ROLE', 'Pause bot', network.pauseBot),
    row('KandaToken', kandaToken, 'UNPAUSER_ROLE', 'Admin Safe', admin),
    row('KandaToken', kandaToken, 'COMPLIANCE_ROLE', 'Compliance Safe', compliance),
    row('ParticipantRegistry', participantRegistry, 'DEFAULT_ADMIN_ROLE', 'Timelock', timelock),
    row('ParticipantRegistry', participantRegistry, 'UPGRADER_ROLE', 'Timelock', timelock),
    row('ParticipantRegistry', participantRegistry, 'LIMITS_ADMIN_ROLE', 'Timelock', timelock),
    row('ParticipantRegistry', participantRegistry, 'PARTICIPANT_MANAGER_ROLE', 'Ops Safe', ops),
    row('ParticipantRegistry', participantRegistry, 'LIMITS_CONSUMER_ROLE', 'BasketVault', basketVault),
    row('BasketVault', basketVault, 'DEFAULT_ADMIN_ROLE', 'Timelock', timelock),
    row('BasketVault', basketVault, 'UPGRADER_ROLE', 'Timelock', timelock),
    row('BasketVault', basketVault, 'LIMITS_ADMIN_ROLE', 'Timelock', timelock),
    row('BasketVault', basketVault, 'PAUSER_ROLE', 'Guardian Safe', guardian),
    row('BasketVault', basketVault, 'PAUSER_ROLE', 'Pause bot', network.pauseBot),
    row('BasketVault', basketVault, 'UNPAUSER_ROLE', 'Admin Safe', admin),
  ];
}
