# Key ceremony plan

29 Sep 2026 · Source: L7 section 2 (keys and signers), L1 section 7 (deployment), P1 "Genesis ceremony" · Status: draft for external auditor review (P0 exit gate, row 6)

The ceremony creates every key and Safe that controls Kanda on Base mainnet, then hands the contracts to them. It ends where the P1 genesis ceremony begins. Run the whole plan on Base Sepolia first (section 8). That dry run also replaces the 1-of-1 test Safes (threat T-14).

**Personal data stays out of this repo.** Signers appear here by role code only (A1 to A5, G1 to G4 and so on). Their names, devices and backup locations go in the company's restricted records.

## 1. What gets created

| Key | Threshold | Signers | Custody | Holds (ADD section 4) |
| --- | --- | --- | --- | --- |
| Admin Safe | 3 of 5 | A1 to A5: two or more countries, including two external trusted signers | Hardware wallets | Timelock proposer and canceller; UNPAUSER_ROLE |
| Guardian Safe | 2 of 4 | G1 to G4 | Hardware wallets | PAUSER_ROLE |
| Compliance Safe | 2 of 3 | C1 to C3 | Hardware wallets | COMPLIANCE_ROLE |
| Ops Safe | 2 of 3 | O1 to O3 | Hardware wallets | PARTICIPANT_MANAGER_ROLE; ARBITER_ROLE (P1) |
| Treasury Safe | 2 of 3 | T1 to T3 | Hardware wallets | Fee recipient |
| Pause bot | 1 | Service | KMS or MPC, pause-only | PAUSER_ROLE |
| Releaser | Policy | Service | MPC with policy engine | RELEASER_ROLE (P1) |
| Deployer | 1 | Ceremony lead | New hardware wallet, used once | Nothing after WireRoles |

No person signs for two Safes whose powers check each other: Admin and Guardian, or Compliance and Ops.

## 2. People

- **Ceremony lead**: runs the script, holds the deployer device, never signs for a Safe.
- **Scribe**: keeps the ceremony log (section 7) with times, transaction hashes and every check result.
- **Verifier**: a second engineer who repeats each on-chain check independently.
- **Signers**: present in person, or verified live by video with a pre-agreed challenge.
- **Observer**: an audit firm representative, if the firm agrees.

## 3. Before the day (T-14 to T-1)

1. Buy every hardware wallet new, directly from the manufacturer. Check the seals and firmware on arrival.
2. Each signer sets up their device offline and writes the recovery phrase on metal, stored in two places they control. Never photograph it or type it anywhere.
3. Each signer sends their address together with a signed message: "Kanda <Safe> signer <role code> <date>". The verifier checks every signature (`cast wallet verify`) and records the address against the role code.
4. Set up the pause bot and the releaser in KMS or MPC. Configure the releaser policy from L7 section 2 and record its ID.
5. Confirm with the DGLD issuer that 1 DGLD = 1 troy ounce (G-02), and request the written acknowledgement of the vault address (G-01).
6. Agree the genesis reference block for G (P1 genesis ceremony, step 1).
7. Prepare the ceremony log template and a clean machine with Foundry 1.8.3 and a fresh checkout of the tagged release.

**Stop if** any signature fails to verify, any device arrives tampered, or the releaser policy can't be shown working on testnet.

## 4. Create the Safes (day 1)

For each Safe in section 1:

1. Create it in the Safe app (app.safe.global, Base) with its owners and threshold.
2. The verifier checks on-chain, independently:
   ```sh
   cast call <safe> "getOwners()(address[])" --rpc-url $BASE_RPC
   cast call <safe> "getThreshold()(uint256)" --rpc-url $BASE_RPC
   ```
3. Each signer confirms by signing a message from the Safe (Safe's "sign message"). This proves every owner can sign, with no funds moved.
4. The scribe records the Safe address, owners and threshold.

**Stop if** the owners or threshold differ from the roster in any way. Create a new Safe; never repair one.

## 5. Configure and rehearse (day 1)

1. Open a pull request that fills `contracts/config/base.json`: Safes, pause bot, releaser, fee recipient (the Treasury Safe), `goldQtyPerUnit` (G from the genesis reference block), and the P1 values already in the file. Two reviewers check each address against the ceremony log.
2. Fork mainnet and run the full deployment against the fork with the real config:
   ```sh
   anvil --fork-url $BASE_RPC --port 8546
   cast rpc anvil_impersonateAccount <deployer> --rpc-url http://127.0.0.1:8546
   cast rpc anvil_setBalance <deployer> 0xDE0B6B3A7640000 --rpc-url http://127.0.0.1:8546   # 1 ETH on the fork
   forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8546 --sender <deployer> --unlocked --broadcast
   forge script script/VerifyRoles.s.sol --rpc-url http://127.0.0.1:8546
   ```
   Deploy refuses to run on a wrong chain ID, zero-address placeholders, a gold decimals mismatch, or an unset G (T0.6).
3. Merge the config pull request only after the fork run passes.

**Stop if** the fork run or VerifyRoles fails.

## 6. Deploy and hand over (day 2)

1. Fund the new deployer with only the gas the deployment needs.
2. Deploy from the hardware wallet:
   ```sh
   forge script script/Deploy.s.sol --rpc-url $BASE_RPC --ledger --sender <deployer> --broadcast --slow
   ```
3. Verify every source on Basescan and Sourcify.
4. The verifier runs VerifyRoles independently, from their own machine and RPC:
   ```sh
   forge script script/VerifyRoles.s.sol --rpc-url $BASE_RPC
   ```
5. Confirm the deployer holds no role on any contract. VerifyRoles covers this. Then retire the deployer device.
6. Publish the role report: the VerifyRoles output, every address, and the Safe thresholds.
7. Hand over to the P1 genesis ceremony: the first participant creates KND, and the transparency page shows supply and coverage.

**Stop if** VerifyRoles fails. Nothing else continues until the role map matches. The guardian can pause while it's investigated.

## 7. Records

The scribe's log is signed by the lead and the verifier, and stored with the restricted records. It includes:

- the roster by role code, with each address and signed-message hash
- each Safe's address, owners and threshold, as read on-chain
- the config pull request, the fork-run output, and the deployment and verification transaction hashes
- the VerifyRoles output, and the deployer's retirement
- every stop or deviation, and how it was resolved

## 8. Testnet dry run (before mainnet)

Run sections 3 to 6 on Base Sepolia with the real signers and their real devices:

1. Add the real signers to the existing test Safes in the Safe app (Settings, then Setup) and raise each threshold to the section 1 value. The Safe addresses stay the same.
2. Remove the testnet deployer as an owner of every Safe (T-13, T-14).
3. Each signer approves one real testnet transaction per Safe. For example, the Ops Safe registers a test participant, and the Guardian Safe pauses and the Admin Safe unpauses the vault.
4. Rehearse one timelock change end to end: the Admin Safe schedules, you wait out the delay, anyone executes.
5. Record timings and problems, then fix the plan before the mainnet date.

## 9. After the ceremony

- Test every signer's device and backup every six months, by signing a message.
- Rotate on staff change (Compliance, Ops, Treasury) and review yearly (Guardian), per L7 section 2.
- If a key is lost or compromised, follow R2: the guardian pauses, the Admin Safe cancels queued operations and replaces the signer.
