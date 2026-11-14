ClearLoot 0.5.0-alpha

A standalone group-loot addon targeting WoW Forever 1.60.1 (Interface 16001).
The exact client build has not been confirmed. This is an alpha, checked with
simulated WoW APIs, not tested inside a running game client.

INSTALL

1. Close WoW, or return to the character selection screen.
2. Extract the ClearLoot folder into your Forever client's Interface/AddOns/.
   The final path should be Interface/AddOns/ClearLoot/ClearLoot.toc.
3. Enable ClearLoot in the AddOns list. Disable other group-loot frame replacements
   such as BetterGroupLoot while evaluating this alpha.
4. Enter the game and run /cloot demo. No party is required.
5. Run /cloot for settings. If you want the default popups back, /cloot native
   restores them immediately and saves that preference.

USE

Each item has its own Need/Greed/Pass controls, a player list, labeled choices,
roll numbers, and a result. Need (including off spec), Greed, Pass, and Transmog
have explicit labels. Additional roll buttons only appear if the API offers them.
Compact panels are now the default: a short loot header with controls at the
right, a small player table immediately below, and a single-line result footer.
Turn off Compact panels in Common settings to use larger headers and spacing.
Row height, font size, width, and scale remain independently configurable.

The bar measures how many players have chosen, not elapsed time. It fills yellow
while anyone is undecided and turns green once every recorded player has chosen.
Pass counts as a choice even when passed players are hidden. Missing history
never produces a full green bar. The countdown remains a separate text label.
A green bar can precede the server's winner; the footer then says awaiting server.

Default player sorting groups Need above Greed, then Pass, with undecided players
last. Transmog, when applicable, sits between Need and Greed. Roll numbers sort
descending within each roll type. Group boundaries have horizontal separators
and a small gap. Winners are marked without moving them above higher-priority
choice groups. Advanced settings can disable separators or sort by name.
Blizzard still handles binding confirmations; the addon never confirms them
automatically. A choice is considered confirmed after history or confirmation
reports it. The addon never rolls automatically on real items.

The default layout stacks item panels in a scrollable window. Choose Tabbed
window or Separate windows in the main settings. Tabbed mode has previous/next
controls for overflow. Separate windows can be dragged individually; their
positions last for their displayed item. The main window's position is saved.

The result distinguishes You won, You lost, You passed, and Everyone passed.
You lost requires an authoritative winner from loot history. A visible leader,
highest numeric roll, missing win toast, or expired timer is never treated as
proof of losing. A Greed 99 can lose to a Need 2.

Panels stay through the roll and for 20 seconds after a confirmed result.
Hovering postpones closing; Pin keeps an item open indefinitely. Set the result
timeout to 0 to keep all results until dismissed. The live-panel session view
resets on reload. Persistent drop history is separate and survives normal
logout/reload through account-level ClearLootDB SavedVariables.
Pinned and live panels are not evicted by the session panel limit.

PERSISTENT HISTORY AND STATISTICS

History opens a persistent drop ledger; Players shows character statistics.
Records retain the item, UTC timestamp, source instance/difficulty when available,
each player's character identity, choice, roll, and confirmed winner. Click a
drop for the full recorded party list. Search finds drops containing an item,
player/alias, or source; player statistics then describe that matching drop set.
Date filters support the last 7 days, 30 days, and all retained history.

Win rate = wins / eligible contested rolls, not wins / every item that appeared.
Only the highest chosen priority tier can compete. A Greed 99 losing to a Need 1
does not count as an eligible loss. Main-spec Need, off-spec Need, Transmog, and
Greed are distinct priority tiers. Need/Greed filters apply to these eligibility
statistics. Uncontested wins and total items won are shown separately. Items won
is an all-choice total in the selected date/search period. Passes, all-pass drops,
unknown outcomes, and inconsistent/incomplete recorded pools do not become
eligible losses. Win/loss streaks span successive eligible contested outcomes;
passes and ineligible items neither advance nor reset them.

Expected wins sums 1 / eligible contenders for each contested opportunity.
It assumes independent fair rolls and equal chances within the winning tier.
Grouped aliases sum their characters' eligible shares. This is a comparison
baseline, not a significance test or proof that someone is favored. Coverage
counts show unknown and incomplete/inconsistent drops separately.

Characters use player GUIDs when supplied by the API, with name-realm fallbacks.
Select a character row, enter a shared label, and Save alias to group alts.
Switch Characters to Manual aliases to aggregate those identities. Real account
names and BattleTags of other players are not exposed by this loot API. A manual
alias is a user-provided label, not verified ownership of those characters.

The default retention is the newest 5,000 observed group-loot drops. Change the
record limit (100 to 50,000) in Advanced; reducing it prunes the oldest records.
There is no cloud sync or cross-account collection. The account-level file is
shared by your characters using this installation and WoW account. The game
writes SavedVariables during normal logout/reload; a crash can lose unsaved data.
Back up WTF/Account/<your account>/SavedVariables/ClearLoot.lua if desired.
No retrospective or unobserved drops are fabricated, and demo rolls are excluded.
If an identical drop invalidates an earlier association, its archived record is
marked uncertain and removed from rate calculations. Late confirmed results
update the original record instead of creating a second statistical event.

Copy CSV opens selectable text for manual copying into a spreadsheet. It exports
raw participant rows in the selected date/search scope, including unknown records
for auditing. It does not export only the chosen win-rate tier. No chat messages
are sent and no files are written directly by the addon.

Common settings: multi-item layout, compact/larger panels, result timeout, scale,
hover behavior, position locking, default-popup replacement, preview, and history.
Advanced: width, row height, font size, opacity, maximum stack height, completed
history limit, passed-player visibility, class colors, optional result sound,
sorting by priority/roll or by name, choice-group separators, and position reset.
These defaults are recommendations, not measured popularity rankings.

COMMANDS

/cloot              Open settings
/cloot demo         Three simulated rolls, including win/loss examples
/cloot history      Open persistent drop history
/cloot stats        Open player statistics and manual alt aliases
/cloot export       Copy retained raw drop/participant history as CSV
/cloot bets         Optional side-bet rules, predictions, and honor ledger
/cloot session      Toggle the current live-panel session view
/cloot clear        Dismiss completed results; leave live items alone
/cloot native       Restore default loot popups
/clearloot          Same commands as /cloot

SIDE BETS: PLACE A PREDICTION AND WATCH THE POOL

Click Bet on an item, choose the predicted loot winner, enter a stake, and Place
bet. That click records the bet immediately and joins the pool. Friends' bets and
the pool update as their notifications arrive. No manual host, invitation,
confirmation/retry step, matched settings, or five-second hosted window is needed.
Loot choices are never delayed. A bettor resolves the shared pool automatically.

Each client validates its own placement: <=20% of eligible rollers selected,
more than 10 seconds remaining, reliable item/roster data, and a positive pledge
within its personal cap. Stricter personal limits do not require friends to
change settings. Valid notifications may arrive after the cutoff; their original
placement facts are used rather than arrival-time choices or a host approval.

The earlier threshold-void rule remains for open pools that have not yet agreed.
Once a pool is shared and agreed, later normal choices do not void it. The timer
cutoff stops new submissions without discarding valid earlier bets.

Correct bettors share the pledged pool proportionally; the ledger records net
amounts owed. No gold is collected or moved, no balances are checked, and no
trades are opened. Local paid marks are only notes. Late valid notifications can
revise a pool, retaining prior paid notes separately for manual reconciliation.

Protocol version 2 automatically merges author-attributed bet notifications,
shares book checksums, requests replays, and elects a connected bettor to resolve.
Interrupted pools retain their predictions as Waiting to reconcile. Turning
friend notifications off does not withdraw a placed bet. Version 1 clients need
to be updated. Remote submission facts are honor-system statements, not server
receipts; this module is intended for cooperating friends.

See docs/betting.md in the repository for the full workflow and protocol.

KNOWN LIMITS AND VERIFICATION

Forever uses encounter loot history instead of the old Classic GetItem /
GetPlayerInfo API. Its history states differ from RollOnLoot button numbers.
ClearLoot uses the modern history API and explicit mappings.

No documented API maps a rollID directly to its encounter/drop identity.
ClearLoot accepts only unique item-link matches with start times within four
seconds. It never guesses duplicate-item order. Identical items arriving within
eight seconds invalidate an earlier speculative association; player details
then show as uncertain. This favors accurate attribution over complete data.
If you encounter frequent identical drops, this limitation is substantial.

Some trash/chest rolls may lack encounter history. Their controls still work,
but player rows/results may be unavailable. Ten seconds after the roll deadline,
the panel says Outcome unconfirmed and starts the result timeout. A late server
winner reopens the panel and starts a fresh result timeout.

Unknown APIs leave the native loot interface intact. Gamepad mode also keeps
its native presentation; this alpha targets mouse/keyboard. During reloads,
native rolls without a ClearLoot record remain visible. Live-roll reconstruction
is not implemented. Completed persistent drop history is retained across reloads.

Before treating this as ready for regular play, validate on your actual client:
* /run print(GetBuildInfo()) -- expected Interface number 16001.
* /cloot demo, then switch all three layouts and resize/reposition.
* A real party drop: one Need, one Greed, one Pass, and one delayed choice.
* Bind-on-pickup confirmation acceptance AND cancellation.
* A win, a loss, all pass, a tie, simultaneous different items, identical drops.
* Reload during an active roll; confirm native controls remain available.
* /cloot native restores native popups and mouse input.

Validation delivered with this alpha: 14 model scenarios, 12 persistent-history
scenarios, 28 asynchronous betting scenarios, and a mocked runtime
integration check exercising UI loading, controls, all layouts, native restore,
duplicates, unknown outcomes, demo isolation, compact height, group separators,
and the completion bar's yellow/green behavior. History scenarios cover persistent
initialization, identity, alias grouping, eligible denominators, expected wins,
streaks, date/tier filters, unknown exclusion, upserts, invalidation, retention,
CSV quoting/formula neutralization, and demo exclusion. These checks run using a
system Lua 5.4 shared library. Production code uses Lua 5.1-compatible syntax.
Mock checks cannot establish in-game API behavior, protected/taint behavior,
actual font rendering, or compatibility with other addons.
Side bets also require real two-client and raid testing of placement, live
pool notifications, history/timer gates, automatic agreement/resolution, message
latency, normal loot controls, resolver failover, and persistence. Browser previews do not validate the side-bet protocol.

SOURCE REFERENCES

https://www.curseforge.com/wow/addons/bettergrouploot
https://github.com/Karl-HeinzSchneider/WoW-BetterGroupLoot/blob/main/REWORK_NOTES.md
https://github.com/Karl-HeinzSchneider/WoW-BetterGroupLoot/blob/main/BetterGroupLoot/BetterGroupLoot.toc
https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/LootHistoryDocumentation.lua
https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua

ClearLoot is a separate implementation, not a modified BetterGroupLoot release.
