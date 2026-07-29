# Customer Loyalty: Punch Card → Points (Future Plan)

**Status: not scheduled.** The customer-facing card stays a simple punch
card for initial launch — this doc exists so a future switch to points
(to support variable rewards and sellable/giveaway swag) doesn't start from
scratch. Nothing here should be built until the punch card has real launch
feedback.

## Why points, eventually

The punch card today is one rule: 1 punch per sushi order, 10 punches = a
free roll. That's easy to explain but can't express "a dine-in visit is
worth more than a to-go order" or "redeem for a hat instead of food." Staff
Rewards (`/staff-rewards-admin.html`) already solved this exact problem for
employees — variable point values per action category, plus an editable
redemption catalog (`RewardCatalogItem`: name + point cost, unpriced items
allowed as placeholders) that already lists an **Ohana Hat** and **Ohana
T-Shirt**. The plan below is to give customers the same shape of system,
not invent a new one.

## Current state (for reference)

`LoyaltyCustomer` (`server/Sources/App/Loyalty.swift`):
- `punches: Int` — real, redeemable punches
- `bonusPoints: Int` — **tenths of a punch**, 0–9, from approved photo/social
  bonus claims; rolls over into a real punch at 10
- `totalRedeemed: Int` — lifetime free-roll count

`LoyaltyStore.punchesNeeded = 10` is the only redemption rule that exists.

## A clean conversion falls out of the current data

`bonusPoints` is already "tenths of a punch," i.e. already points at a
10-points-per-punch scale. That means:

```
totalPoints = punches * 10 + bonusPoints
```

...requires no guessing at a conversion ratio — it's already implicit in
the existing schema. A free roll costing 100 points reproduces today's
"10 punches" exactly. This is worth preserving as the anchor number even if
other point values change later.

## Proposed data model

Mirror `StaffRewardsData`/`RewardCatalogItem` almost exactly:

```swift
struct LoyaltyCustomer {
  // ...existing fields...
  var points: Int          // replaces punches+bonusPoints as the source of truth
  // keep `punches`/`bonusPoints` decodable (decodeIfPresent) for one release,
  // computed as points/10 and points%10, so old clients/reports don't break
  // mid-rollout — drop once nothing reads them anymore.
}

struct CustomerRewardCatalogItem {
  var id: String
  var name: String          // "Free Roll", "Ohana Hat", "Ohana T-Shirt", ...
  var pointCost: Int?        // nil = placeholder, not yet redeemable (swag pricing pending)
}
```

A migration function converts every existing customer once, on first load
under the new schema:
`points = punches * 10 + bonusPoints`, then the old fields become
write-once-derived (or dropped after a release or two, same pattern already
used for `bonusPoints`/`totalRedeemed` being added after the fact).

## Proposed point values (draft, needs a real decision before shipping)

Same idea as `StaffRewardsStore.defaultPointValues` — a `[String: Int]`
admin can edit from a new `/loyalty-admin.html` panel, not hardcoded:

| Action | Draft points | Note |
|---|---|---|
| Sushi order (today's 1 punch) | 10 | anchor value, keeps the 100-point free roll identical to today |
| Approved photo/social share | 1 | unchanged from today's bonusPoints |
| Dine-in vs. to-go | +? | not tracked today — would need a new field on the order/visit if this distinction matters |
| Referral / first visit bonus | ? | doesn't exist today |
| Birthday Club month bonus | ? | `my-account.html` already has the birthday field; currently unused for rewards |

## Redemption catalog

Reuse the exact `GET`/`PUT /api/.../catalog` pattern already built for staff
rewards: an admin-editable list, unpriced entries shown-but-not-redeemable.
Seed it with:
- Free Roll / Happy Hour appetizer — 100 points (today's equivalent)
- Ohana Hat — placeholder, no cost until real swag pricing exists
- Ohana T-Shirt — placeholder, same

This answers the "sell or give customers swag" goal directly: once an item
has a real cost, it's redeemable exactly like the free roll is today, no
new mechanism needed. If Ohana wants to *sell* swag (not just give it as a
reward) rather than only offer it as a point-catalog redemption, that's a
distinct feature (real checkout/payment) and out of scope for this doc.

## What has to change on the surface, not just the backend

- `/rewards` (public lookup + bonus-claim form) — currently shows
  "X / 10 punches." Needs a points balance + a browsable catalog instead of
  one fixed target. This is a real UI redesign, not a copy change.
- `/loyalty-admin.html` — staff currently see a punch count per customer;
  needs a points column and (if variable action values ship) a way to award
  points for things beyond a sushi order.
- `/my-account.html` (customer profile linking) — shows live punch/redemption
  status; same redesign as `/rewards`.
- Anywhere "10 punches" or "free roll" is mentioned in copy (FAQ, `/rewards`
  hero text, etc.) needs a pass once the catalog can hold more than one
  reward.

## Rollout plan

1. Ship as-is for initial launch (already done) — gather real usage/feedback
   on the punch-card metaphor first, per your call.
2. When ready: land the backend (`points` field + migration + catalog +
   admin point-values panel) behind the existing data, without changing the
   public UI yet — verify the migrated numbers match today's punch counts
   exactly (this is why the `punches * 10 + bonusPoints` identity matters:
   it's a testable invariant, not just a design note).
3. Redesign `/rewards`/`/my-account.html` for a points balance + catalog.
4.  Cut over, keeping "Free Roll = 100 points" so a customer mid-way to
   their next punch doesn't feel like they lost progress.

## Open questions to resolve before building

- Does existing progress (current punches/bonusPoints) get honored 1:1 via
  the conversion above (recommended), or reset with an announcement?
- Do dine-in vs. to-go, referrals, or birthday-month bonuses actually need
  new point categories, or is "1 order = 10 points" still the whole rule?
- Swag: real point cost, and how staff mark one redeemed/out of stock (the
  current staff-rewards catalog has no inventory concept at all — redeeming
  a T-shirt 50 times doesn't run out of T-shirts today, which may not be
  fine for real swag with finite stock).
- Does a points balance ever expire (todays punches don't)?
