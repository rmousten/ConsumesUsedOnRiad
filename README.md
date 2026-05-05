# Gold Used In Raid Loser

World of Warcraft addon to track your consumable costs from Auction House prices.

## Files

- `GUIRL.toc` loads the addon metadata.
- `GUIRL_Database.lua` contains your consumables list and settings template.
- `Log/GUIRL_Log.lua` contains log snapshot storage helpers.
- `Media/` holds optional custom UI images.
- `GUIRL_UI.lua` contains the movable UI, slash command, and total cost logic.

## How to use

1. Put this folder in your WoW addons directory as `GUIRL`.
2. Install and enable Auctionator.
3. Launch the game and type `/guirl` to show/hide the window.
4. Drag the window with left click to move it.
5. Click `Reset/Log` and choose `Yes` or `No` in the popup prompt.

## Refresh logging

- On `Reset/Refresh`, a popup asks if you want to log the current addon data before reset.
- Press `Yes` to save the currently displayed rows and total cost, then reset tracked usage.
- Press `No` to reset tracked usage without saving a log entry.
- Log entries are stored in `GUIRL_DB.log.entries` and are ready for future statistics/graph features.
- Logged prices are static snapshots (`snapshotUnitPriceCopper`, `snapshotLineTotalCopper`, `snapshotTotalCopper`) so historical data does not change when market prices change later.

## Graph view

- Click `Graph` in the main window to switch to total gold spent history.
- The top graph is `Total Gold Spend Per Raid` and plots one point per saved log entry.
- The second graph shows cumulative gold spend over time so you can see total growth.
- Hover a point to see that entry's total gold spent.
- The graph uses only snapshot total values from the log (not live market prices).
- Bottom counters show `Gold Used Last Raid` and `Gold Used Lifetime`.

## Top-right window image

- The `/guirl` frame supports a custom image in the top-right corner.
- Current default filename is `Media/Haste_AI.png`.
- In-game texture path used by the addon is built from the live addon folder name: `Interface\\AddOns\\<AddonFolder>\\Media\\Haste_AI.png`.
- If your client does not render `.png`, convert the same image to `.tga` and I can switch the loader to that file name.

## Real value conversion

- At the top-right of the UI, set `Price of 1000 gold` and click `Set Price`.
- The addon converts tracked gold totals into real value (`$/EUR`) using that rate.
- Converted values are shown in list totals, graph tooltips, and last raid/lifetime summary.


## Live tracking behavior

- The addon tracks consumed quantity from successful player cast events tied to enabled consumables.
- Tracking is active everywhere by default.
- Enable `Track Raids Only` in the UI to count consumables only while you are in a raid group.

## Price source
- Primary source: Auctionator API.
