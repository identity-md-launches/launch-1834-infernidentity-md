# INFERN tests

The suite tests the deployed `src/InfernToken.sol` through its public interface. It uses the
repository's existing OpenZeppelin and forge-std dependencies; no fork, RPC, external service,
environment-reading cheatcode, or extra dependency is needed.

- `InfernToken.t.sol` retains the existing checks for exact metadata and constructor minting,
  factory deployment, transfer events, transfer accounting, invalid calls, and absent mint/admin
  entry points.
- `InfernToken.adversarial.t.sol` adds one-wei and uint256 boundary cases, repeated spending,
  allowance exhaustion and revocation, failed-call rollback and retry, and authorization isolation
  between holders, spenders, and a contract caller. Its four fuzz properties run 1,000 cases each.
- `InfernToken.invariant.t.sol` drives four actors through 11 operations, including successful
  transfers/approvals, full-balance transfers, revocations, and expected failures. The campaign
  runs 256 sequences of 128 calls. Expected balances and allowances are tracked independently
  from the token's getters. After each call it checks fixed supply, balance conservation, exact
  authorization accounting, and unchanged metadata. After each sequence every actor transfers
  its full balance and the supply is consolidated back to the initial holder.

All successful recipients in the invariant campaign are tracked actors, so their balances must
sum to exactly `1_000_000_000 * 10 ** 18`. Expected reverts leave the model unchanged, requiring
both balances and allowances to roll back. Unexpected handler reverts fail the campaign. A
deterministic handler sequence also pins nonzero delegated spending and rollback/revocation cases.

Run from the repository root with the verification seed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x0efb9537bbb913b91d05caf334467f01f4d86f2697257b244829fb0e06a61ae7 forge test
```

To keep generated build artifacts inside the disposable workspace, prefix either command with
`FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache`. No submitted test imports or
reads anything under `test/scratch/`.

The factory/distribution fixture tests token movements. The externally supplied protected checks
provide the full launch and Uniswap integration coverage; this repository does not contain those
integration contracts or their deployment configuration.
