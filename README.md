# Infernidentity.md (INFERN)

`src/InfernToken.sol:InfernToken` is a fixed-supply ERC-20. It uses the vendored,
unmodified OpenZeppelin Contracts v5.0.2 ERC-20 implementation.

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `InfernToken` |
| Token name | `Infernidentity.md` |
| Symbol | `INFERN` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Launch chain | Ethereum, chain ID `1` |

## Behavior and assumptions

The constructor mints the entire supply exactly once and emits the standard
`Transfer` event from the zero address. No function can mint or burn after
deployment. There is no owner, administrator, proxy, upgrade mechanism, pause,
blacklist, seizure, fee, tax, rebasing, vesting, permit, or external callback.
The deployer has the same transfer permissions as every other holder.

Transfers deliver the exact requested amount. Zero-value transfers and
self-transfers are supported and emit `Transfer`. Transfers to the zero address
and approvals to a zero spender revert, as do insufficient balances or allowances.
Successful `transfer`, `approve`, and `transferFrom` calls return `true`.

`approve` replaces the allowance and emits `Approval`. `transferFrom` consumes a
finite allowance; `type(uint256).max` represents unlimited approval and is not
decremented. This OpenZeppelin implementation does not emit `Approval` when
spending an allowance, so integrations should read `allowance()` for its current
value. Holders should approve only trusted spenders and amounts they intend to
spend. To change a live allowance safely, revoke it first, wait for confirmation,
then grant the new amount; an already authorized spender may spend before the
revocation confirms.

## Build and test

Foundry and Solidity `0.8.26` are required. The root `foundry.toml` pins that
compiler, the Cancun EVM target, optimizer settings (200 runs), and
`bytecode_hash = "none"`. All Solidity dependencies and their licenses are
ordinary files under `lib/`; no dependency install, submodule, RPC, environment
file, FFI, or filesystem cheatcode permissions are needed. The compiler must
already be installed for a build without network access.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x0efb9537bbb913b91d05caf334467f01f4d86f2697257b244829fb0e06a61ae7 forge test
forge fmt --check
```

The suite covers exact metadata and supply, mint events, direct and CREATE2
factory deployment, complete distribution and claim transfers, transfer events,
zero and self-transfers, allowances and revocation, unlimited approvals, invalid
addresses, insufficient funds and authorization, rollback on failure, absent
administrative entry points, and runtime size/opcodes. Four fuzz tests use 512
cases each. Stateful invariant tests use 256 sequences of 64 calls each to compare
balances and allowances against an independent model, including failed operations.
Tests use local fixtures and no shared environment or network state.

The supplied protected launch tests depend on the network's separate factory,
Uniswap v4 harness, manifest, and launch environment. They are not part of this
standalone project's runnable suite. The local distribution fixture checks token
movement and does not claim to simulate AMM pricing, liquidity seeding, or swaps.

## Deployment and operational responsibilities

Deploy the compiled creation bytecode for `InfernToken` with no arguments and no
ETH value. Its artifact is `out/InfernToken.sol/InfernToken.json`. The constructor
does not call any other contract, require external configuration, or reserve any
supply. No libraries require linking. It supports both CREATE and CREATE2.

When the launch factory deploys the token, the factory receives all `10^27` units;
the wallet that initiated the factory call receives none from the constructor.
The launch factory is responsible for subsequent allocation: 10% to the swarm
distributor, 88% to pool allocation, and 2% to the remainder recipient under the
provided launch policy. Those transfers and pool configuration are external to
the token. The separate launch manifest step supplies the launch configuration;
this repository contains no launch manifest or live deployment script.

The network deployer is responsible for deployment, checking the initial supply
and recipient, publishing verified source, and completing factory distribution and
pool setup. This assignment performs no broadcast. Deploying through any other
contract requires that contract to be able to transfer its received tokens.

### After launch

There are no token settings, privileged keys, initialization calls, or maintenance
jobs. Holders control transfers and spending approvals. The code cannot recover
mistaken transfers, tokens sent to this token contract, or assets sent to other
contracts that cannot release them. Direct ETH transfers revert; there is no
asset rescue function. A separate review of the token and launch integration is
the release responsibility of the network; passing local tests is not an audit.

## Dependencies and review scope

`DEPENDENCIES.json` records the upstream tags, archive SHA-256 values, and hashes
of every vendored file. OpenZeppelin v5.0.2 is included only for ERC-20 and its
transitive imports (MIT). Forge Standard Library v1.9.7 is included for tests
(MIT/Apache-2.0). Their license texts are included beside their source.

The security review focuses on supply immutability, exact transfers, allowance
authorization, zero-address validation, arithmetic conservation, lack of external
calls, and absence of privileged or upgrade paths. Oracle, randomness, signature,
and vault risks do not apply to this token. Verification uses the compiler,
Foundry unit/fuzz/invariant tests, and an opcode check; Slither, Mythril, and a
production-chain integration test are not run here.
