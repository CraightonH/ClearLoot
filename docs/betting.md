# Side bets

**Click an amount beside a player in the loot table.** That single click selects both your stake and prediction, and places the bet immediately. The prediction is recorded locally immediately, friends' bets appear as notifications arrive, and the pool total updates automatically.

There is no host button, invitation, acceptance/retry step, matching-settings checklist, or hosted five-second window. Loot choices are never delayed. Only bettors need LootGoblin; a prediction target can use the default loot UI.

## In the client

1. Find any player you want to back in the loot table.
2. Click **1c**, **1s**, or **1g** to add one copper, one silver, or one gold to your stake on that player.
3. Keep clicking to add more, and back other players too. There is no single-prediction lockout or personal pledge cap.
4. Each backed row shows your running stake. Your total and the live pool stay on the item panel. Normal loot controls keep working.
5. At the time/selection cutoff, additions stop and existing stakes stay in the pool. The window cannot reopen. `/lg bets` holds the ledger, payment notes, and time/percentage preferences.

`/lg demo` supports repeated sample bets on multiple players without network messages or ledger entries. Its illustrative party choices are independent of real-roll placement gates; its controls close when the sample result resolves or the timer expires.

No prior peer discovery or manual hosting is required. Late bettors can join while the normal gates remain open.

The rules apply when each bettor places their own prediction:

- No more than **20% of eligible rollers** have chosen, inclusively: 1/5, 2/10, 4/20, or 8/40. Need, Greed, Transmog, and Pass all count.
- **More than 10 seconds** remain according to the native loot timer.
- The item and its eligible participants can be identified reliably, and no result is already known locally.
- Each increment is a positive, exact copper amount.

You can use stricter personal time/percentage limits. Friends do not need to match those settings. The shared rules remain 20% and 10 seconds.

Either cutoff closes new submissions without cancelling accepted stakes. A valid cumulative update can arrive after the cutoff; its originating submission facts are checked instead of arrival-time loot choices. Closed clients do not reopen their own placement controls.

## Payouts and persistence

Everything is an honor-system ledger. LootGoblin never collects gold, checks balances, opens trades, sends payments, or changes your loot choice.

Correct bettors split the pledged pool in proportion to their combined stakes on the winner. Every stake, including their bets on losing players, is deducted when calculating net balances. Copper rounding is deterministic and conserves the pool. The ledger lists net amounts owed. No correct predictions or everyone passing cancels pledges; a lone bettor has no payable pool.

**Mark paid locally** is a local note, not proof of a transfer. A late valid notification can revise a calculated pool; prior paid notes are retained separately for manual reconciliation and do not mark newly calculated payments as paid.

The newest 1,000 round records are retained in account-level `LootGoblinDB.betLedger`, protecting active records when pruning. Interrupted active pools are retained as **Waiting to reconcile**, including the predictions already recorded. Unavailable results or a pool that cannot be agreed never produce invented payments. Switching friend notifications off does not withdraw your existing pledge.

## How coordination works

This is protocol version 3 under the `LootGoblinBets` prefix. All bettors need this version; earlier protocols do not participate in these pools.

- Each click is validated locally, then added to the client's cumulative stake for that player and session. `BET` carries that cumulative total, a monotonically increasing revision, and the selection-count/timer facts. Recipients authenticate the group sender and ignore duplicate or older revisions. Higher revisions can only increase the stake. Rapid queued updates for the same position are coalesced without losing money.
- Pools are matched to an unambiguous local loot item, eligible roster, and expected server deadline. Client-local roll IDs and manually created round IDs are not shared identities.
- The bet set is sorted canonically, so simultaneous first bets and out-of-order notifications produce the same pool. `BOOK` notifications automatically establish that participating clients have the same set. There are no user-facing confirmation controls.
- Missing data is requested through `SYNC`; authors replay their own bets. Brief, bounded background replay handles dropped or late notifications without a manual retry button.
- The connected bettor with the lowest GUID resolves the agreed pool automatically. If that bettor leaves, the next connected bettor can resolve it. Passive viewers are not elected.
- `RESULT` identifies the shared bet set and loot winner. Recipients verify it against their own loot history before showing calculated payments. Late notifications trigger reconciliation, not duplicated pledges.

This is a cooperative design for friends. Remote submission facts are notifications from those clients, not server-issued receipts or escrow guarantees. A deliberately modified addon can lie about its own submission. Ordinary message latency is handled by resynchronization rather than repeated host approval or cancellation ceremonies.

## Validation still needed

Simulated checks cover local validation, immediate placement, asynchronous joining, simultaneous first bets, late notifications, automatic agreement/election, resolver failover, missing/reordered notifications, exact pool arithmetic including independently calculated large-value reference cases, rapid-click coalescing, interrupted records, and 40 clients with 80 stake positions. Game-binding tests exercise per-player denomination buttons, repeated clicks, multiple targets, live pool, cutoff and stale-message rejection, and normal loot buttons without a hold.

Live two-client and raid testing in Forever remains necessary. Start with small honorary amounts and compare the friends list, pool total, item winner, prediction outcomes, and ledger on both clients. The browser previews currently show loot/history only; they are not an in-game render or a networked betting simulation.
