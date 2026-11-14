# ClearLoot

Native group-loot extensions and persistent roll history for **WoW Forever 1.60.1**, provisionally targeting Interface `16001`.

**Status: 0.5.1 alpha.** The code has passed simulated model, history, betting, UI, and browser checks. It has not been tested inside a running Forever client. The browser previews show the loot/history interface using illustrative data; they are not in-game screenshots and do not demonstrate networked side bets.

## Features

- Blizzard's original loot controls, with a matching player/choice/roll table attached underneath.
- Confirmed winners highlighted across the entire row in gold; results remain available after the native popup closes.
- Settings under **Options → AddOns → ClearLoot**; `/cloot` opens the same category.
- Optional standalone panels, tabs, or separate windows in settings. Live native extensions follow the game's loot-frame layout.
- Need above Greed, then Pass, with separators between choice groups and undecided players last. Transmog appears between Need and Greed when offered by the client.
- A yellow bar showing how many players have chosen, turning green once all recorded players have chosen. The server may still be resolving the winner.
- Explicit win, loss, pass, all-pass, and unconfirmed results; configurable closing, and hover hold.
- Persistent drop history with UTC timestamps, item, source, participant choices, rolls, and confirmed winner.
- Per-character statistics: contested win rate, expected wins, win/loss streaks, solo wins, and total items won.
- Manual alt/account labels, date and choice-tier filters, a searchable drop ledger, and CSV copying.
- Optional, default-off side bets between enabled addon users, with a shared prediction book and persistent honor-payment ledger. No gold handling or trade automation.

## Install the alpha

1. Download this repository with **Code → Download ZIP**, or clone it.
2. Copy the inner `ClearLoot/` directory into the Forever client's `Interface/AddOns/` directory.
3. Confirm the resulting path is `Interface/AddOns/ClearLoot/ClearLoot.toc`.
4. Enable ClearLoot in the character selection AddOns list. Disable other group-loot replacements, including BetterGroupLoot, while evaluating it.
5. Run `/cloot` for the game's settings category. The default presentation is **Extend Blizzard loot frames**.
6. Restart the client after updating, then run `/cloot demo` to show three Forever-native loot previews with attached tables. Need, Greed, and Pass are simulated; results and winner highlights appear after about ten seconds. No party is needed.

You can also build an addon-only ZIP:

```sh
python3 scripts/package.py
```

This writes `dist/ClearLoot-0.5.1-alpha.zip`. Extract it into `Interface/AddOns/`.

Drag the native item header, item icon, or any non-button area of the player
table to move that item and its table together. Loot buttons retain their clicks. Each of the four loot slots remembers its
position for both demo and live rolls. **Lock window position** disables dragging;
**Advanced → Reset position** clears the saved locations. Pin controls are removed.
Need stays above Greed, then Pass, with waiting players last. Name sorting applies
within choice tiers and never changes that group order.

Confirmed personal wins pulse green around the item header and player table;
confirmed losses pulse red. Three pulses settle into a quieter outline until the
result closes. Passes and unconfirmed results have no win/loss glow.

## Native presentation

ClearLoot attaches a table to each visible `GroupLootFrame` using its `rollID`.
Blizzard keeps ownership of the item header, loot buttons, countdown, and binding
confirmations. Native container spacing grows to accommodate the tables and is
restored when the extensions are disabled. Spacing changes wait until combat ends.
When Blizzard hides or recycles a popup, that roll's table moves into ClearLoot's
result window and follows the configured result timeout. Winners are highlighted
only after confirmation; a visible leading roll does not count as a winner.

Settings also offer **Standalone ClearLoot panels** and **Blizzard UI only**.
`/cloot native` selects Blizzard UI only immediately. History collection continues.
`/cloot demo` creates addon-owned instances inheriting Blizzard's
`MKBGroupLootFrameTemplate`. They use Forever's nested `LootButtonContainer`, the same table attachment
function as live rolls, and Blizzard's `GroupLootContainer_AddFrame` layout
function with an independent container. Item data, choices, and server outcomes
are simulated; the addon cannot create a server-side dungeon drop. Missing
native templates report an error and stop the demo without a standalone fallback. The native layout and
textures are visible without a party; no live loot APIs or statistics are used.
Preview frames remain through the result timeout and can be dismissed.
Running the demo again resets it. Real drops still need separate validation for
server events, binding confirmations, and native frame recycling.

The standalone browser previews illustrate the earlier standalone layout; they
do not reproduce the native game textures or the attached-frame integration.

## Commands

| Command | Action |
| --- | --- |
| `/cloot` | Open settings |
| `/cloot demo` | Simulate three rolls without submitting real loot choices |
| `/cloot history` | Open persistent drop history |
| `/cloot stats` | Open character statistics and manual aliases |
| `/cloot export` | Open selectable CSV text for copying |
| `/cloot bets` | Open side-bet rules, live predictions, and the honor ledger |
| `/cloot session` | Show the current session's live-panel history |
| `/cloot clear` | Dismiss completed panels |
| `/cloot native` | Immediately restore the default loot popups |

`/clearloot` is an alias for `/cloot`.

## Interpreting the statistics

A **try** is a confirmed, contested roll in the highest chosen priority tier. A Greed 99 against a Need 1 does not count as an eligible loss. Passes, all-pass drops, unknown outcomes, and inconsistent or incomplete pools are excluded from win-rate calculations. Uncontested wins are shown separately.

Expected wins sums each character's eligible share of the contested rolls, assuming equal chances within each winning tier. It is a comparison baseline, not a test for bias. Streaks cover successive eligible contested outcomes within the selected date, search, and tier filters. Small samples can vary substantially.

Characters use GUIDs when supplied by the client and name-realm fallbacks otherwise. Other players' real account names and BattleTags are not exposed through the loot API. Shared alt/account labels are assigned manually and do not verify account ownership.

History records only group-loot rolls observed while the addon is running. The default retention is the newest **5,000 drops**, configurable from 100 to 50,000 in Advanced settings. Decreasing the limit prunes older records.

Data is kept in account-level `ClearLootDB` SavedVariables and shared by your characters using the same WoW installation/account. The game saves it during normal logout or reload; a crash can lose unsaved changes. There is no cloud sync, retrospective collection, or automatic chat posting. Demo rolls never enter persistent statistics.

## Side bets: place a prediction and watch the pool

Click **Bet** on an item, choose the player you predict will win, enter a stake, and press **Place bet**. That click records your bet immediately and joins the pool. Friends' predictions and the pool update as their notifications arrive.

There is no manual hosting, peer-discovery prerequisite, confirmation/retry step, matching-settings setup, or five-second hosted window. ClearLoot elects a bettor to resolve the agreed pool automatically, and normal loot choices are never held. Only bettors need the addon.

Each client validates its own bet at placement: **20% selected or less**, **more than 10 seconds remaining**, a reliably identified item/eligible roster, and a positive pledge within the player's personal limit. Personal limits can be stricter without requiring friends to change theirs. In-time notifications can arrive asynchronously after the cutoff; arrival time is not a second host approval gate.

The existing threshold-void policy remains for an open pool that has not yet been agreed. An agreed pool survives later normal loot choices. Reaching the timer cutoff stops new submissions while retaining valid earlier bets.

Resolution is an **honor-system ledger**. ClearLoot never handles gold or trades. Correct bettors share the pledged pool proportionally, with exact copper rounding and net amounts owed. The item winner, prediction results, and persistent ledger are shown automatically.

See [the betting guide](docs/betting.md) for the workflow, local paid notes, asynchronous reconciliation, protocol, and remaining in-game validation.

## Browser previews

Serve the repository locally:

```sh
python3 -m http.server 8000
```

Then open:

- <http://localhost:8000/previews/loot.html> — compact loot panels and layout settings.
- <http://localhost:8000/previews/history.html> — sample history, character statistics, and manual alias grouping.

The history preview's sample summaries were computed by the addon's Lua statistics code. The previews contain no real player history and run independently of WoW. They optionally load Lucide icons from a version-pinned CDN.

## Development and checks

There are no bundled addon libraries or runtime package dependencies.

Run the Lua checks with Lua 5.1 or 5.4 from the repository root:

```sh
lua tests/model.lua
lua tests/history.lua
lua tests/betting.lua
lua tests/integration.lua
```

Or use `make test LUA=lua5.1`. On Linux with Python and `liblua5.4.so.0` installed, the included runner needs no Python packages:

```sh
python3 tests/run_lua.py tests/model.lua tests/history.lua tests/betting.lua tests/integration.lua
```

The suites cover 16 model scenarios, 12 history scenarios, 28 asynchronous betting scenarios, and mocked addon integration. Betting checks include inclusive percentage boundaries, native timer validation, immediate placement, canonical bet sets, asynchronous joining, late notifications, automatic agreement and resolver failover, exact settlement, and 40-client synchronization. Mocked game bindings verify group-message routing, the player picker, one-step placement, live pool, normal loot choices without a hold, and local paid notes. GitHub Actions runs these against Lua 5.1 and 5.4 and verifies addon packaging.

Optional browser checks:

```sh
python3 -m pip install -r requirements-dev.txt
python3 -m playwright install chromium
python3 tests/previews.py
```

Set `CHROMIUM_PATH` to use an existing Chromium executable. Browser checks start their own local server and exercise the previews at 320, 520, and 736 pixels.

## Compatibility and remaining validation

The client build is still unconfirmed. Check it in game with:

```text
/run print(GetBuildInfo())
```

Forever's encounter loot history does not provide a documented direct mapping from `rollID` to encounter/drop identity. ClearLoot uses unique item-link matches within a narrow time window. Simultaneous identical items are marked uncertain instead of being attributed by guessed arrival order. Some trash/chest rolls may lack history entries. Those records cannot produce reliable per-player statistics.

Before regular use, test real Need/Greed/Pass choices, binding confirmation acceptance and cancellation, wins and losses, ties, simultaneous and identical drops, all-pass outcomes, reloads during active rolls, persistence after logout/reload, and restoration with `/cloot native`. Gamepad mode keeps its native presentation. Mock tests do not verify in-game rendering, protected/taint behavior, or compatibility with other addons.

For side bets, validate two real clients first: placing a bet without prior setup, live friend notifications and pool totals, both sides of the 20% boundary, the ten-second cutoff, automatic agreement and resolution, normal loot buttons, and persistent ledger notes. Then test a raid, latency, late joining, resolver failover, reloads, and ambiguous drops. Do not treat simulated networking as validation of the live client's addon channel behavior.

The complete usage notes and source references are in [ClearLoot/README.txt](ClearLoot/README.txt).

## Source layout

| File | Purpose |
| --- | --- |
| `ClearLoot/Model.lua` | Roll state, matching, sorting, completion, and close timing |
| `ClearLoot/History.lua` | Persistent records, identities, aliases, statistics, and CSV |
| `ClearLoot/BetModel.lua` | Betting gates, immutable books, and exact honor settlements |
| `ClearLoot/BetComms.lua` | Peer protocol, native timer/history bindings, and synchronization |
| `ClearLoot/BetUI.lua` | Opt-in rules, predictions, and the persistent honor ledger |
| `ClearLoot/UI.lua` | Loot tables, optional panels, and registered game settings |
| `ClearLoot/NativeUI.lua` | Native-frame attachment, pooling, and container spacing |
| `ClearLoot/StatsUI.lua` | History, statistics, detail, and CSV windows |
| `ClearLoot/Core.lua` | Game events and native loot UI integration |
| `tests/` | Model, history, integration, and browser checks |
| `previews/` | Standalone browser mockups with sample data |
| `scripts/package.py` | Addon ZIP builder |
