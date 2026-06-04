# LootBox Game — On-chain NFT System

**Fully on-chain loot box mechanics on Sui blockchain. Provably fair randomness. No oracle dependency.**

[![Sui Move](https://img.shields.io/badge/Sui_Move-4DA2FF?style=flat-square&logo=sui&logoColor=white)](https://github.com/amith-m-s/lootbox-game)
[![On-chain](https://img.shields.io/badge/testnet-4DA2FF?style=flat-square)](https://github.com/amith-m-s/lootbox-game)

---

## What This Is

A loot box system where every mechanic — randomness, rarity distribution, pity tracking, NFT lifecycle, treasury management — lives entirely on-chain in Sui Move. No backend. No trusted randomness oracle. No off-chain state.

The implementation prioritizes security correctness over simplicity. The interesting engineering is in the randomness architecture.

---

## The Randomness Problem (and Why Most Contracts Get It Wrong)

```
❌ VULNERABLE:
   public fun open_loot_box(r: &Random, game: &mut GameConfig, coin: Coin<SUI>, ctx: &mut TxContext)

   A public function lets any caller:
   1. Simulate the randomness outcome before committing
   2. Abort the transaction if the result is undesirable
   3. Retry until they get Legendary
   This is front-running. The entire fairness guarantee collapses.

✅ CORRECT:
   entry fun open_loot_box(r: &Random, game: &mut GameConfig, coin: Coin<SUI>, ctx: &mut TxContext)

   entry functions cannot be called from other Move modules.
   The RandomGenerator is consumed inside the entry fn.
   Simulation → abort loops are impossible at the protocol level.
```

`sui::random` enforces this constraint by design — the compiler rejects `&mut RandomGenerator` in public functions. Most Move tutorials don't explain why. This contract is built around that constraint.

---

## Contract Architecture

```
GameConfig (Shared Object)
├── price: u64                          — exact SUI cost per open
├── rarity_weights: vector<u64>         — [6000, 2500, 1200, 300] (basis points)
├── admin_cap_id: ID                    — reference to AdminCap holder
└── treasury: Balance<SUI>             — accumulated fees

AdminCap (Owned Object)
├── update_rarity_weights(...)         — admin-gated weight adjustment
└── withdraw_treasury(...)             — admin-gated fund withdrawal

PityTracker: Table<address, u8>        — per-wallet consecutive non-Legendary count
NFTItem (Owned Object)
├── name: String
├── rarity: u8                         — 0=Common 1=Rare 2=Epic 3=Legendary
└── item_id: u64
```

**Key design decisions:**

| Decision | Why |
|---|---|
| `entry` function for randomness | Prevents front-running — protocol-level guarantee, not convention |
| Exact `Coin<SUI>` enforcement | Partial payments abort at the type system level, not runtime check |
| AdminCap ownership pattern | Treasury ops require capability object possession, not just caller address |
| `Table<address, u8>` for pity | Per-wallet pity counter lives on-chain — no off-chain state drift possible |
| Event emission on every open | Full auditability — every drop outcome is queryable from chain history |

---

## Rarity System

```
Rarity       Weight    Probability
─────────────────────────────────
Common        6000      60.00%
Rare          2500      25.00%
Epic          1200      12.00%
Legendary      300       3.00%
─────────────────────────────────
Total        10000     100.00%
```

**Pity guarantee:** After 30 consecutive non-Legendary opens, the next open forces a Legendary drop regardless of RNG output. The counter resets on any Legendary. Tracked per wallet address via `Table<address, u8>` dynamic fields — fully on-chain, no trusted third party.

---

## NFT Lifecycle

```
mint()     → creates NFTItem, transfers to caller
transfer() → moves NFTItem between wallets
burn()     → destroys NFTItem, emits burn event
```

All three operations emit indexed events. Every item's full history is queryable from chain state.

---

## Test Coverage

```bash
sui move test
```

Test suite covers:

| Test | What it validates |
|---|---|
| `test_init` | GameConfig shared object initialized correctly |
| `test_invalid_payment` | Under/over payment aborts with correct error |
| `test_rarity_boundaries` | Weight boundary conditions produce correct rarity |
| `test_pity_threshold` | Counter increments correctly, forces Legendary at 30 |
| `test_transfer` | NFT ownership changes correctly |
| `test_burn` | NFT destroyed, event emitted, object no longer exists |
| `test_admin_withdrawal` | Treasury withdrawal requires AdminCap |
| `test_unauthorized_withdrawal` | Withdrawal without AdminCap aborts |

---

## Running Locally

```bash
# Prerequisites: Sui CLI installed, testnet configured
git clone https://github.com/amith-m-s/lootbox-game
cd lootbox-game

# Run test suite
sui move test

# Build
sui move build

# Deploy to testnet
sui client publish --gas-budget 100000000
```

---

## Honest Limitations

- Frontend UI is incomplete. The contract is fully deployed and tested; the wallet interaction layer is not finished.
- Single-item-type loot box. Multi-item pools with weighted drops by item ID are not implemented.
- No upgrade path. Sui Move objects are immutable once deployed — a v2 would require migrating state.

**What's production-ready:** the contract logic, randomness architecture, pity system, test suite, and deployment config.
