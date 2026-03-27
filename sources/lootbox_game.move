module lootbox_game::lootbox_game;

use sui::balance::{Self as balance, Balance};
use sui::coin::{Self as coin, Coin};
use sui::event;
use sui::object::UID;
use sui::random::{Self as random, Random};
use sui::sui::SUI;
use sui::table::{Self as table, Table};
use std::string::{Self as string, String};

const COMMON: u8 = 0;
const RARE: u8 = 1;
const EPIC: u8 = 2;
const LEGENDARY: u8 = 3;

const PITY_THRESHOLD: u8 = 30;

const EInvalidWeights: u64 = 1;
const EInvalidPayment: u64 = 2;
const EInvalidRarity: u64 = 3;
const EInsufficientTreasury: u64 = 4;

/// Admin capability for privileged configuration changes.
public struct AdminCap has key, store {
    id: UID,
}

/// Shared game configuration and treasury.
public struct GameConfig has key {
    id: UID,
    price: u64,
    common_weight: u8,
    rare_weight: u8,
    epic_weight: u8,
    legendary_weight: u8,
    treasury: Balance<SUI>,
    next_item_serial: u64,
    pity: Table<address, u8>,
}

/// Owned unopened loot box.
public struct LootBox has key, store {
    id: UID,
    serial: u64,
}

/// Owned in-game NFT item.
public struct GameItem has key, store {
    id: UID,
    name: String,
    rarity: u8,
    power: u8,
    serial: u64,
}

/// Emitted when a loot box is bought.
public struct LootBoxPurchasedEvent has copy, drop, store {
    buyer: address,
    box_serial: u64,
    price: u64,
}

/// Emitted when a loot box is opened.
public struct LootBoxOpenedEvent has copy, drop, store {
    item_id: address,
    owner: address,
    rarity: u8,
    power: u8,
    serial: u64,
}

/// Emitted when admin changes rarity weights.
public struct RarityWeightsUpdatedEvent has copy, drop, store {
    common_weight: u8,
    rare_weight: u8,
    epic_weight: u8,
    legendary_weight: u8,
}

/// Emitted when an item is burned.
public struct GameItemBurnedEvent has copy, drop, store {
    item_id: address,
    owner: address,
    serial: u64,
}

/// Initializes the game with the canonical rarity distribution.
entry fun init_game(
    price: u64,
    common_weight: u8,
    rare_weight: u8,
    epic_weight: u8,
    legendary_weight: u8,
    ctx: &mut TxContext,
) {
    assert!(
        common_weight + rare_weight + epic_weight + legendary_weight == 100,
        EInvalidWeights
    );

    let config = GameConfig {
        id: object::new(ctx),
        price,
        common_weight,
        rare_weight,
        epic_weight,
        legendary_weight,
        treasury: balance::zero<SUI>(),
        next_item_serial: 0,
        pity: table::new<address, u8>(ctx),
    };

    let admin_cap = AdminCap {
        id: object::new(ctx),
    };

    transfer::share_object(config);
    transfer::public_transfer(admin_cap, ctx.sender());
}

/// Purchases a loot box by paying the exact configured price.
entry fun purchase_loot_box(
    config: &mut GameConfig,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(coin::value(&payment) == config.price, EInvalidPayment);

    let paid_balance = coin::into_balance(payment);
    balance::join(&mut config.treasury, paid_balance);

    let serial = config.next_item_serial;
    config.next_item_serial = serial + 1;

    let buyer = ctx.sender();
    let loot_box = LootBox {
        id: object::new(ctx),
        serial,
    };

    event::emit(LootBoxPurchasedEvent {
        buyer,
        box_serial: serial,
        price: config.price,
    });

    transfer::public_transfer(loot_box, buyer);
}

/// Opens a loot box using local function-scoped on-chain randomness.
///
/// This must stay non-public so other modules cannot compose around the random outcome.
entry fun open_loot_box(
    loot_box: LootBox,
    config: &mut GameConfig,
    r: &Random,
    ctx: &mut TxContext,
) {
    let sender = ctx.sender();
    let mut generator = random::new_generator(r, ctx);

    let pity_count = if (table::contains(&config.pity, sender)) {
        *table::borrow(&config.pity, sender)
    } else {
        0
    };

    let is_forced_legendary = pity_count >= PITY_THRESHOLD;
    let rarity = if (is_forced_legendary) {
        LEGENDARY
    } else {
        let roll = random::generate_u8_in_range(&mut generator, 0, 99);
        resolve_rarity(roll, config)
    };

    let power = roll_power(rarity, &mut generator);
    let name = item_name(rarity);
    let item_serial = loot_box.serial;

    if (table::contains(&config.pity, sender)) {
        let pity_ref = table::borrow_mut(&mut config.pity, sender);
        if (rarity == LEGENDARY) {
            *pity_ref = 0;
        } else {
            let next = *pity_ref + 1;
            *pity_ref = if (next > PITY_THRESHOLD) { PITY_THRESHOLD } else { next };
        }
    } else {
        table::add(&mut config.pity, sender, if (rarity == LEGENDARY) { 0 } else { 1 });
    };

    let LootBox { id, serial: _ } = loot_box;
    object::delete(id);

    let item = GameItem {
        id: object::new(ctx),
        name,
        rarity,
        power,
        serial: item_serial,
    };

    event::emit(LootBoxOpenedEvent {
        item_id: object::uid_to_address(&item.id),
        owner: sender,
        rarity,
        power,
        serial: item_serial,
    });

    transfer::public_transfer(item, sender);
}

/// Returns the friendly item name, rarity label, and power level.
public fun get_item_stats(item: &GameItem): (String, String, u8) {
    let rarity_label = rarity_name(item.rarity);
    (item.name, rarity_label, item.power)
}

/// Transfers a GameItem to another address.
public fun transfer_item(item: GameItem, recipient: address) {
    transfer::public_transfer(item, recipient);
}

/// Burns an unwanted item.
entry fun burn_item(item: GameItem, ctx: &mut TxContext) {
    let owner = ctx.sender();
    let GameItem { id, name: _, rarity: _, power: _, serial } = item;
    let burned_id = object::uid_to_address(&id);
    object::delete(id);

    event::emit(GameItemBurnedEvent {
        item_id: burned_id,
        owner,
        serial,
    });
}

/// Admin-only rarity update.
public fun update_rarity_weights(
    _admin: &AdminCap,
    config: &mut GameConfig,
    common_weight: u8,
    rare_weight: u8,
    epic_weight: u8,
    legendary_weight: u8,
) {
    assert!(
        common_weight + rare_weight + epic_weight + legendary_weight == 100,
        EInvalidWeights
    );

    config.common_weight = common_weight;
    config.rare_weight = rare_weight;
    config.epic_weight = epic_weight;
    config.legendary_weight = legendary_weight;

    event::emit(RarityWeightsUpdatedEvent {
        common_weight,
        rare_weight,
        epic_weight,
        legendary_weight,
    });
}

/// Optional treasury withdrawal for the game admin.
public fun withdraw_treasury(
    _admin: &AdminCap,
    config: &mut GameConfig,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    assert!(balance::value(&config.treasury) >= amount, EInsufficientTreasury);
    let payout = coin::from_balance(balance::split(&mut config.treasury, amount), ctx);
    transfer::public_transfer(payout, recipient);
}

fun resolve_rarity(roll: u8, config: &GameConfig): u8 {
    let common_cutoff = config.common_weight;
    let rare_cutoff = common_cutoff + config.rare_weight;
    let epic_cutoff = rare_cutoff + config.epic_weight;

    if (roll < common_cutoff) {
        COMMON
    } else if (roll < rare_cutoff) {
        RARE
    } else if (roll < epic_cutoff) {
        EPIC
    } else {
        LEGENDARY
    }
}

fun roll_power(rarity: u8, generator: &mut random::RandomGenerator): u8 {
    if (rarity == COMMON) {
        random::generate_u8_in_range(generator, 1, 10)
    } else if (rarity == RARE) {
        random::generate_u8_in_range(generator, 11, 25)
    } else if (rarity == EPIC) {
        random::generate_u8_in_range(generator, 26, 40)
    } else if (rarity == LEGENDARY) {
        random::generate_u8_in_range(generator, 41, 50)
    } else {
        abort EInvalidRarity
    }
}

fun item_name(rarity: u8): String {
    if (rarity == COMMON) {
        string::utf8(b"Common Relic")
    } else if (rarity == RARE) {
        string::utf8(b"Rare Relic")
    } else if (rarity == EPIC) {
        string::utf8(b"Epic Relic")
    } else if (rarity == LEGENDARY) {
        string::utf8(b"Legendary Relic")
    } else {
        abort EInvalidRarity
    }
}

fun rarity_name(rarity: u8): String {
    if (rarity == COMMON) {
        string::utf8(b"Common")
    } else if (rarity == RARE) {
        string::utf8(b"Rare")
    } else if (rarity == EPIC) {
        string::utf8(b"Epic")
    } else if (rarity == LEGENDARY) {
        string::utf8(b"Legendary")
    } else {
        abort EInvalidRarity
    }
}