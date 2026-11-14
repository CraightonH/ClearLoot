# Side bets

**Click an amount beside a player in the loot table.** That single click selects both your stake and prediction, and places the bet immediately. The prediction is recorded locally immediately, friends' bets appear as notifications arrive, and the pool total updates automatically.

There is no host button, invitation, acceptance/retry step, matching-settings checklist, or hosted five-second window. Loot choices are never delayed. Only bettors need LootGoblin; a prediction target can use the default loot UI.

## In the client

1. Find the player you predict will win in the attached loot table.
2. Click **1g**, **5g**, or **10g** on that row. There is no picker, confirmation step, or dedicated placement menu.
3. To change the middle amount, edit **Middle bet** on the item panel and press Enter. This amount is saved for future drops. Each character can make one prediction per item.
4. Your prediction and the live pool stay on the panel. Buttons close after your bet or when the eligibility/time limits are reached. Normal loot controls keep working.
5. Once the result is confirmed, the panel shows the loot winner and your prediction outcome. `/lg bets` opens the optional ledger and rules, including the honor-payment details.

`/lg demo` includes clickable sample bets for checking this layout without a party. They use no network messages or persistent ledger entries. Demo sample buttons demonstrate placement independently of the real-roll betting gates.

Bet placement does not require an enabled peer to have been discovered. A second or third bettor can place their prediction later without anyone reopening a round. One character gets one immutable prediction per item.

The rules apply when each bettor places their own prediction:

- No more than **20% of eligible rollers** have chosen, inclusively: 1/5, 2/10, 4/20, or 8/40. Need, Greed, Transmog, and Pass all count.
- **More than 10 seconds** remain according to the native loot timer.
- The item and its eligible participants can be identified reliably, and no result is already known locally.
- The pledge is positive and within that character's personal limit.

You can use stricter personal time/percentage limits and a personal pledge cap. Friends do not need to match those settings. The shared rules remain 20% and 10 seconds.

The earlier threshold-void policy is retained: if an unagreed pool is still open when the client observes more than 20% selected, it is voided. Once the existing pool has been shared and agreed, later normal loot choices do not void it. Reaching the time cutoff closes new submissions without cancelling earlier valid bets. Valid notifications may still arrive asynchronously after either limit; the original submission facts are used instead of their arrival time.

## Payouts and persistence

Everything is an honor-system ledger. LootGoblin never collects gold, checks balances, opens trades, sends payments, or changes your loot choice.

Correct bettors split the pledged pool in proportion to stakes, including their own stakes. Copper rounding is deterministic and conserves the pool. The ledger lists net amounts owed. No correct predictions or everyone passing cancels pledges; a lone bettor has no payable pool.

**Mark paid locally** is a local note, not proof of a transfer. A late valid notification can revise a calculated pool; prior paid notes are retained separately for manual reconciliation and do not mark newly calculated payments as paid.

The newest 1,000 round records are retained in account-level `LootGoblinDB.betLedger`, protecting active records when pruning. Interrupted active pools are retained as **Waiting to reconcile**, including the predictions already recorded. Unavailable results or a pool that cannot be agreed never produce invented payments. Switching friend notifications off does not withdraw your existing pledge.

## How coordination works

This is protocol version 2 under the `LootGoblinBets` prefix. Version 1 clients must be updated; they cannot participate in the same pool.

- Each client validates its own placement, then broadcasts its own immutable `BET` notification. The message contains the prediction, stake, and selection-count/timer facts from submission. A recipient attributes it to the actual group-channel sender, not to an identity claimed in the payload.
- Pools are matched to an unambiguous local loot item, eligible roster, and expected server deadline. Client-local roll IDs and manually created round IDs are not shared identities.
- The bet set is sorted canonically, so simultaneous first bets and out-of-order notifications produce the same pool. `BOOK` notifications automatically establish that participating clients have the same set. There are no user-facing confirmation controls.
- Missing data is requested through `SYNC`; authors replay their own bets. Brief, bounded background replay handles dropped or late notifications without a manual retry button.
- The connected bettor with the lowest GUID resolves the agreed pool automatically. If that bettor leaves, the next connected bettor can resolve it. Passive viewers are not elected.
- `RESULT` identifies the shared bet set and loot winner. Recipients verify it against their own loot history before showing calculated payments. Late notifications trigger reconciliation, not duplicated pledges.

This is a cooperative design for friends. Remote submission facts are notifications from those clients, not server-issued receipts or escrow guarantees. A deliberately modified addon can lie about its own submission. Ordinary message latency is handled by resynchronization rather than repeated host approval or cancellation ceremonies.

## Validation still needed

Simulated checks cover local validation, immediate placement, asynchronous joining, simultaneous first bets, late notifications, automatic agreement/election, resolver failover, missing/reordered notifications, exact pool arithmetic, interrupted records, and 40 participating clients. Game-binding tests exercise per-player quick-bet buttons, inline custom stakes, live pool, cutoff and duplicate-click rejection, and normal loot buttons without a hold.

Live two-client and raid testing in Forever remains necessary. Start with small honorary amounts and compare the friends list, pool total, item winner, prediction outcomes, and ledger on both clients. The browser previews currently show loot/history only; they are not an in-game render or a networked betting simulation.
