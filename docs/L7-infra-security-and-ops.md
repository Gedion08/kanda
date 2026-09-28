# L7 Infra, security and ops

The operating model assumes something will break: every key is split, every change is reviewed, every alert has a runbook, and the pause is always one guardian signature away. Vercel and Render are fine for dev and demos; production runs in a cloud account you control, in a region that meets each country's data rules.

## 1. Hosting

| Piece | Dev | Staging and prod |
| --- | --- | --- |
| API and workers | Local Docker, Render | Containers on a managed service (ECS Fargate or Cloud Run) in private subnets |
| Postgres | Docker | Managed Postgres with point-in-time recovery, encrypted, private |
| Redis | Docker | Managed Redis, private |
| Indexer | Local | Container plus its own Postgres schema |
| Frontends | Vercel previews | Static hosting behind a CDN with WAF |
| Secrets | .env (never committed) | Cloud secrets manager; KMS for PII keys |
| RPC | Public | Two paid providers with failover |

Everything provisioned with Terraform modules in infra/: network, database, cache, services, cdn, secrets, monitoring.

## 2. Keys and signers

| Key | Purpose | Custody | Threshold | Rotation |
| --- | --- | --- | --- | --- |
| Admin Safe | Timelock proposer: upgrades, roles, parameters | Hardware wallets, signers in at least 2 countries, 2 external trusted signers | 3 of 5 | On signer change |
| Guardian Safe | Pause | Hardware wallets | 2 of 4 | Yearly review |
| Pause bot | Automatic pause on invariant alert | MPC or KMS key, pause-only role | 1 | Quarterly |
| Compliance Safe | Block and unblock | Hardware wallets | 2 of 3 | On staff change |
| Ops Safe | Participants, limits within caps, arbiter | Hardware wallets | 2 of 3 | On staff change |
| Treasury Safe | Fee sweeps, P2 cash desk approvals | Hardware wallets | 2 of 3 | On staff change |
| Releaser | Escrow release for PAID\_OUT intents | MPC with policy engine | Policy-enforced | Quarterly |
| Deployer | Deploy scripts | Fresh hardware wallet per deployment | 1, renounced after wiring | Per deployment |
| Oracle reporters (P2) | FX reports | MPC | 1 each | Quarterly |

MPC policy for the releaser: only calls PaymentEscrow.release; only for intent ids the API confirms as PAID\_OUT; per-transaction and daily value caps; two-person approval above a threshold.

Key ceremony (before mainnet): generate Safes with signers present or verified by video; test each signer with a testnet transaction; record addresses in config/base.json; deploy with a fresh deployer; run WireRoles and VerifyRoles; publish the role report.

## 3. CI/CD

| Pipeline | Steps | Gate |
| --- | --- | --- |
| Contracts | forge fmt check, build, unit and fuzz tests, invariants (256 runs on PR, 10,000 nightly), slither, aderyn, gas snapshot diff, storage layout diff | All green, no new high findings |
| Backend | lint, typecheck, unit tests, integration tests with testcontainers, migration dry run | All green |
| Frontend | lint, typecheck, build, Playwright against staging | All green |
| API | OpenAPI lint and route drift check | No drift |
| Supply chain | Dependency audit, SBOM, container signing | No critical CVEs |

Deploys: staging on merge to main; production by manual approval from two reviewers. Contract deployments only through scripts; mainnet changes only through Safe proposals and the timelock.

Repository rules: branch protection, required reviews, CODEOWNERS for contracts and infra, signed commits, no secrets in code (secret scanning on).

## 4. Security programme

- Audits: two independent firms before P1 mainnet; one before P2 contracts; one per contract upgrade.
- Bug bounty from P1 launch covering all contracts and the Partner API; payouts scaled to funds at risk.
- Yearly penetration test of API and apps; threat model reviewed at every phase gate.
- Access: SSO with hardware keys for all staff tools; quarterly access review; least privilege in cloud IAM.

## 5. Alerts

| Alert | Condition | Severity | Runbook |
| --- | --- | --- | --- |
| Coverage breach | Any leg under 100% of required backing | Critical, auto-pause | R1 |
| Escrow mismatch | Escrow balance differs from ledger or ghost sum | Critical | R1 |
| Unexpected role change or timelock queue item | Event not matching an approved change ticket | Critical | R2 |
| Large mint or redeem | Over 10% of supply in one hour | High | R1 |
| Oracle down or degraded | NAVOracle health not Ok for 10 min | High | R3 |
| Partner SLA breach | Intents past payout SLA | High | R4 |
| Reserve asset depeg, freeze or seizure | USDC or DGLD off peg by 1%; Paused or Upgraded on USDC or DGLD; Blacklisted or RecoveryFromBlacklistedAddress naming the vault | Critical | R5 |
| Sequencer down | Uptime feed down | High | R6 |
| PII access anomaly | Unusual reads of compliance schema | Critical | R7 |
| API error rate | Over 2% 5xx for 5 min | Medium | R8 |

## 6. Incident response

Severity: Critical (funds or data at risk), High (service impaired), Medium (degraded). Roles: incident commander, technical lead, communications, scribe. Post-incident review within 5 business days, published for Critical incidents.

Runbooks:

- R1 Invariant or coverage breach: confirm pause executed (bot or guardian); freeze quoting; snapshot state; identify the transaction; engage auditors; communicate on the transparency page within 1 hour; unpause only by Admin Safe after root cause and fix.
- R2 Suspected key compromise: guardian pauses; cancel queued timelock operations from Admin Safe; rotate affected signer out; review all transactions from that key.
- R3 Oracle failure: confirm zap disabled; widen or block quotes per L2; switch secondary feed through timelock if prolonged.
- R4 Partner failure: stop routing to the partner; let intents expire and refund; contact backup partner; invoke partner collateral per agreement.
- R5 Reserve asset depeg, freeze or seizure: call pauseCreate on BasketVault. Do not pause KandaToken, which would also stop redeem. Keep redeem open unless unsafe. If DGLD is paused or the vault is blacklisted, every create and redeem reverts until the issuer acts: pause BasketVault and escalate. Legal escalation with the issuer (Circle for USDC, Gold Token SA for DGLD); public notice.
- R6 Sequencer outage: stop quotes; queue intents; resume after grace period.
- R7 Data breach: contain, preserve evidence, notify regulators and data subjects within legal deadlines.
- R8 API degradation: scale, roll back last deploy, fail over RPC.

## 7. Upgrade procedure

1. Change approved in an ADR; audit of the diff.
2. New implementation deployed and verified; storage layout diff attached.
3. Admin Safe queues upgradeToAndCall in the timelock; public announcement with the diff.
4. 48-hour wait; monitoring watches the queue.
5. Execute; run VerifyRoles and the post-upgrade test suite on a fork before and on mainnet after.

## 8. Continuity

- Postgres point-in-time recovery, daily snapshots copied to a second region; RPO 5 minutes, RTO 1 hour.
- Restore drill every quarter; game day for R1 and R4 before P1 launch and every 6 months.
- On-chain state is the recovery source for balances and intents; the ledger can be rebuilt from onchain\_events plus intent\_events.

## 9. Agent tasks

1. Write infra/ Terraform modules for staging with the same shape as prod.
2. Write the GitHub Actions workflows in section 3.
3. Build the invariant watcher service that recomputes coverage and escrow every block and triggers the pause bot.
4. Write alert rules and link each to its runbook.
5. Write WireRoles.s.sol and VerifyRoles.s.sol (L1 section 7).
