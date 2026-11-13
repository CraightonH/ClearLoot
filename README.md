# ClearLoot

Compact group-loot panels and persistent roll history for **WoW Forever 1.60.1**, provisionally targeting Interface `16001`.

**Status: 0.3.0 alpha.** The code has passed simulated model, history, UI, and browser checks. It has not been tested inside a running Forever client. The browser previews show the intended interface using illustrative data; they are not in-game screenshots.

## Features

- Need, Greed, and Pass controls with the party's choices and roll numbers directly underneath each item.
- Compact panels by default, with larger panels, tabs, or separate windows available in settings.
- Need above Greed, then Pass, with separators between choice groups and undecided players last. Transmog appears between Need and Greed when offered by the client.
- A yellow bar showing how many players have chosen, turning green once all recorded players have chosen. The server may still be resolving the winner.
- Explicit win, loss, pass, all-pass, and unconfirmed results; configurable closing, hover hold, and pinning.
- Persistent drop history with UTC timestamps, item, source, participant choices, rolls, and confirmed winner.
- Per-character statistics: contested win rate, expected wins, win/loss streaks, solo wins, and total items won.
- Manual alt/account labels, date and choice-tier filters, a searchable drop ledger, and CSV copying.

## Install the alpha

1. Download this repository with **Code → Download ZIP**, or clone it.
2. Copy the inner `ClearLoot/` directory into the Forever client's `Interface/AddOns/` directory.
3. Confirm the resulting path is `Interface/AddOns/ClearLoot/ClearLoot.toc`.
4. Enable ClearLoot in the character selection AddOns list. Disable other group-loot replacements, including BetterGroupLoot, while evaluating it.
5. Run `/cloot demo` to preview three simulated rolls, then `/cloot` for settings.

You can also build an addon-only ZIP:

```sh
python3 scripts/package.py
```

This writes `dist/ClearLoot-0.3.0-alpha.zip`. Extract it into `Interface/AddOns/`.

## Commands

| Command | Action |
| --- | --- |
| `/cloot` | Open settings |
| `/cloot demo` | Simulate three rolls without submitting real loot choices |
| `/cloot history` | Open persistent drop history |
| `/cloot stats` | Open character statistics and manual aliases |
| `/cloot export` | Open selectable CSV text for copying |
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
lua tests/integration.lua
```

Or use `make test LUA=lua5.1`. On Linux with Python and `liblua5.4.so.0` installed, the included runner needs no Python packages:

```sh
python3 tests/run_lua.py tests/model.lua tests/history.lua tests/integration.lua
```

The suites cover 14 model scenarios, 12 history scenarios, and mocked addon integration, including choice progress, group sorting, duplicate-item ambiguity, late results, aliases, retention, and CSV escaping. GitHub Actions runs these against Lua 5.1 and 5.4 and verifies addon packaging.

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

The complete usage notes and source references are in [ClearLoot/README.txt](ClearLoot/README.txt).

## Source layout

| File | Purpose |
| --- | --- |
| `ClearLoot/Model.lua` | Roll state, matching, sorting, completion, and close timing |
| `ClearLoot/History.lua` | Persistent records, identities, aliases, statistics, and CSV |
| `ClearLoot/UI.lua` | Loot panels and settings |
| `ClearLoot/StatsUI.lua` | History, statistics, detail, and CSV windows |
| `ClearLoot/Core.lua` | Game events and native loot UI integration |
| `tests/` | Model, history, integration, and browser checks |
| `previews/` | Standalone browser mockups with sample data |
| `scripts/package.py` | Addon ZIP builder |
