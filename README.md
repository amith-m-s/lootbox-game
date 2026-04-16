# 🎮 Lootbox Game (Blockchain)

A blockchain-based lootbox system implementing NFT minting, randomness, and on-chain logic.

---
- shared game configuration
- exact-price box purchase
- verifiable on-chain randomness
- NFT minting for items
- transfer and burn support
- admin-controlled rarity updates
- optional pity tracking

## Core flow

1. `init_game(...)` creates the shared `GameConfig` and transfers `AdminCap` to the deployer.
2. `purchase_loot_box(...)` accepts `Coin<SUI>` and mints an unopened `LootBox`.
3. `open_loot_box(...)` consumes the box, uses `sui::random`, mints a `GameItem`, and emits an event.
4. `transfer_item(...)` moves a `GameItem` to another address.
5. `burn_item(...)` destroys an unwanted item.
6. `update_rarity_weights(...)` lets the admin re-balance drop rates.
7. `withdraw_treasury(...)` lets the admin collect the treasury.

## Sui-specific design choices

- Randomness is created inside the consuming function with `random::new_generator(r, ctx)`.
- The random-opening function is `entry` and not `public`.
- The game item is an owned object with `key, store`, so wallets can transfer it normally.
- Loot box and item lifecycle are modeled with on-chain objects, not off-chain state.

---

## 🏗️ Architecture

```text
User
 │
 ▼
Smart Contract (Sui Move)
 │
 ▼
NFT Minting + Randomness
```

---

## 🧠 Engineering Concepts

* On-chain state management
* Deterministic randomness
* Smart contract design

---

## 🚧 Challenges & Solutions

* Fair randomness
  → implemented deterministic logic

* Secure contract execution
  → validated inputs and flows

---


## Default rarity model

- Common: 60%
- Rare: 25%
- Epic: 12%
- Legendary: 3%

## Notes

- The contract requires exact payment equal to `price`.
- The pity system guarantees a Legendary after 30 non-Legendary opens by the same address.
- The pity counter is stored in a Sui `Table<address, u8>`, which is backed by dynamic fields.

## Suggested test cases

- initialize with valid weights
- reject invalid weight sums
- purchase with exact payment
- reject incorrect payment
- open a box and confirm item rarity is in range
- transfer an item
- burn an item
- update rarity weights as admin
- ensure pity becomes Legendary after the threshold
