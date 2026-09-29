import i18next from 'i18next';
import { initReactI18next } from 'react-i18next';

/** English copy. Swahili and French follow (L5 section 2); number formats already follow the chosen locale. */
export const en = {
  title: 'Transparency',
  network: '{{network}} · testnet',
  testnetBanner: 'Testnet deployment. The tokens on {{network}} are test tokens with no value.',
  numberFormat: 'Number format',
  thesis: 'Every KND is backed in the vault, and anyone can check.',
  intro:
    'This page reads the contracts on {{network}} directly, at a single block. No Kanda server is involved, so it keeps working if ours are down.',
  loading: 'Reading the chain…',
  errorTitle: 'Could not read {{network}}',
  errorBody: 'The RPC endpoint did not answer. The page retries every 30 seconds.',
  staleWarning: 'The latest read failed. Showing data from block {{block}}.',
  retry: 'Try again',
  figures: {
    supply: 'Total supply',
    coverage: 'Lowest leg coverage',
    basket: 'Basket per KND',
    noSupply: 'No supply yet',
    fullyBacked: 'Fully backed',
    underBacked: 'Under-backed',
  },
  reserves: {
    heading: 'Reserves',
    caption: 'Basket version {{version}}, read at block {{block}}',
    asset: 'Asset',
    perKnd: 'Per KND',
    inVault: 'In vault',
    required: 'Required',
    coverage: 'Coverage',
    backed: 'Backed',
    short: 'Short',
    note: 'Required backing is recomputed here from total supply and the basket quantities, rounded up the way the vault rounds: ceil(totalSupply × quantity ÷ 10¹⁸). Coverage is the vault’s own coverage() reading.',
  },
  status: {
    heading: 'Status',
    transfers: 'KND transfers',
    vault: 'Create and redeem',
    creation: 'New creation',
    active: 'Active',
    paused: 'Paused',
    open: 'Open',
  },
  governance: {
    heading: 'Governance',
    timelock: 'Upgrades and limit changes wait in a public timelock for {{delay}}.',
    safes: 'Safes',
    safe: 'Safe',
    address: 'Address',
    signers: 'Signers',
    signersValue: '{{threshold}} of {{owners}}',
    singleSigner: 'One signer. Signers are added before mainnet.',
    roles: 'Roles',
    rolesCaption: 'The ADD section 4 role map, each row checked on-chain with hasRole',
    contract: 'Contract',
    role: 'Role',
    holder: 'Holder',
    check: 'On-chain check',
    held: 'Held',
    missing: 'Missing',
  },
  contracts: {
    heading: 'Contracts',
    contract: 'Contract',
    proxy: 'Address',
    implementation: 'Implementation',
    source: 'Source',
    verified: 'Verified source',
  },
  next: {
    heading: 'Coming in P1',
    nav: 'NAV in USD with the gold price feeds and their update times (NAVOracle).',
    history: 'Supply and coverage over time (indexer).',
    queue: 'The timelock queue, with a countdown on each pending change (indexer).',
  },
  footer:
    'Read from {{rpc}} at block {{block}} ({{time}} UTC). Refreshes every 30 seconds. Each number links to the call that produced it on Blockscout.',
} as const;

void i18next.use(initReactI18next).init({
  lng: 'en',
  fallbackLng: 'en',
  resources: { en: { translation: en } },
  interpolation: { escapeValue: false }, // React escapes
});

export default i18next;
