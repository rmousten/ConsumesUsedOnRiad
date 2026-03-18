# ConsumesUsedOnRiad

World of Warcraft addon to track your consumable costs from Auction House prices.

## Files

- `ConsumesUsedOnRiad.toc` loads the addon.
- `CUOR_Database.lua` contains your consumables list and settings template.
- `CUOR_UI.lua` contains the movable UI, slash command, and total cost logic.

## How to use

1. Put this folder in your WoW addons directory as `ConsumesUsedOnRiad`.
2. Install and enable Auctionator.
3. Launch the game and type `/cuor` to show/hide the window.
4. Drag the window with left click to move it.
5. Click `Refresh` after Auctionator data updates.

## Edit your consumables

Open `CUOR_Database.lua` and edit `CUOR.Consumables` entries.

Template per item:

- `key`: internal unique key.
- `label`: name shown in UI.
- `itemID`: WoW item ID.
- `enabled`: set `true` to track this item, `false` to ignore it.

Example:

```
{
	key = "YOUR_ITEM_KEY",
	label = "Your Consumable",
	itemID = 12345,
	enabled = true,
},
```

`quantityUsed` is now automatic and live-updated by the addon.

The addon calculates:

- line total = `unit price * quantityUsed`
- grand total = sum of all line totals

## Live tracking behavior

- The addon tracks consumed quantity by watching bag count decreases for enabled consumables.
- Tracking is active in raid instances by default.
- On entering a raid instance, usage counters reset automatically by default.
- You can change this in `CUOR.Settings.trackInRaidOnly` and `CUOR.Settings.autoResetOnRaidEnter`.

## Price source

- Primary source: Auctionator API.
- Optional future fallback: TSM (disabled by default in `CUOR.Settings.allowTSMFallback`).
