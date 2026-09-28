# KND token profile

Ready-to-paste text for wherever KND is listed. It matches the contract (`KandaToken`, L1 section 3.1) and the product spec. Change it only when the spec changes, and update the brand system (https://claude.ai/artifact/AyDi16xpft6YtNu32Rr5L5) at the same time.

## Identity

Enter these values exactly as written, in every listing.

| Field | Value |
| --- | --- |
| Name | `Kanda` |
| Symbol | `KND` |
| Decimals | `18` |
| Chain | Base, chain ID `8453`. Testnet: Base Sepolia, chain ID `84532` |
| Contract | The KandaToken proxy address from `contracts/deployments/<network>.json`, written by Deploy.s.sol (T0.6). Always list the proxy, never the implementation. |
| Standard | ERC-20 with EIP-2612 permit and EIP-3009 transfer with authorization |
| Icon | `knd-256.png` (256 × 256 PNG, transparent corners). Use `kanda-mark.svg` where vector art is accepted. |
| Category | Reserve-backed token; payments; settlement |
| Website, support email, socials | Not set. They wait on the P0 name and domain clearance. Leave the fields empty rather than guess. |

## Which text goes where

| Length | Where to use it |
| --- | --- |
| One line (92 characters) | Token lists (as the `knd` tag description), wallet asset pickers, search results, social bios |
| Short (323 characters) | Wallet asset detail screens, the block explorer "Description" field (Basescan token info), partner portal token cards |
| Long (5 paragraphs) | Explorer and data-aggregator pages that allow long text, partner onboarding packs, the transparency page's "About KND" |

### One line

```text
Reserve-backed settlement unit for African trade: 0.70 USD plus fixed gold per KND, on Base.
```

### Short

```text
Kanda (KND) is a reserve-backed settlement unit for cross-border business payments in Africa. Each KND is backed by a fixed basket of 0.70 USDC and a fixed quantity of tokenized gold (DGLD), held in an on-chain vault on Base. KND is not pegged to 1 USD: its value follows the basket. Anyone can check the reserves on-chain.
```

### Long

```text
Kanda (KND) is a settlement unit for moving money between African currencies without a detour through correspondent banks. Licensed ramp partners in each country take local currency in and pay local currency out, and settle with each other in KND through an on-chain escrow.

Each KND is backed by a fixed basket: 0.70 US dollars held as USDC, plus a fixed quantity of gold held as DGLD, set at launch so that gold was 30% of the value on day one. The basket assets sit in the BasketVault contract on Base, and anyone can compare the vault's balances with KND's total supply at any block.

KND is created and redeemed in kind. Allowlisted participants deliver the basket assets to the vault to create KND, and they burn KND to take the basket assets back. No price oracle is used in either path, and the vault can only mint against assets it has actually received.

KND is not pegged to 1 US dollar. Its USD value moves with the gold price at roughly a 30% weight. It pays no interest or yield.

Safeguards: a compliance blocklist, a pause that stops all transfers, and upgrades and parameter changes held behind a public 48-hour timelock controlled by multisig Safes.
```

## Token-list entry

`kanda.tokenlist.template.json` in this folder is a complete list in the Uniswap token-list format, with KND on Base and Base Sepolia. It is a template: the address and logo placeholders are not valid values yet, so don't publish it as is. Once T0.6 has deployed and the icon has a permanent public URL:

1. Replace each `<…>` placeholder with the proxy address from `contracts/deployments/<network>.json` and the icon's URL.
2. Set `timestamp` to the publish time, in ISO 8601.
3. Raise `version` for every change: `major` when a token is removed or its address changes, `minor` when a token is added, `patch` for other fields.
4. Validate the file against the token-list JSON schema (the `@uniswap/token-lists` package) before you publish it.

The entry for one token, when a list other than ours asks for it:

```json
{
  "chainId": 8453,
  "address": "<KandaToken proxy address on Base>",
  "name": "Kanda",
  "symbol": "KND",
  "decimals": 18,
  "logoURI": "<public URL of knd-256.png>",
  "tags": ["knd"]
}
```

## Statements to avoid

Never describe KND as a stablecoin, as pegged, as guaranteed, or as earning yield. Never say holders can redeem KND for dollars: only authorized participants redeem, and they receive the basket assets. The *Words* table in the brand book lists the approved replacements.
