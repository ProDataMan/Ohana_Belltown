# Credit Card Processing Plan for Web Purchases (Shop + Gift Cards)

Written 2026-08-02. Context for a fresh conversation — read alongside
`README.md`'s [Payment Processing (Square)](../README.md#payment-processing-square)
section, which covers how the current Square integration actually works
under the hood. This doc is about the *business* question — Square vs.
Echelon — not the code.

## The question

Ohana's bookkeeper said the restaurant's card processor is "Echelon" —
resolving an earlier mystery from this session where it was misheard as
"spaced" over the phone. The ask: is Echelon cheaper than Square for the
**web purchases** this site handles (Shop merch + Gift Cards, both built
2026-08-01/02), and should the integration switch?

**Short answer: can't be determined yet — Echelon doesn't publish pricing.**
A real quote is needed before this is a real decision. What follows is
everything that could be verified plus exactly what to ask Echelon for.

## What's already true today

- The site's Shop (`/shop`) and Gift Cards (`/gift-cards`) checkout is fully
  built and tested end-to-end against **Square** (sandbox — see README for
  exact production-cutover steps). This was a real, non-trivial build:
  `SquareCheckout.swift` calls Square's Payment Links API + verifies
  webhook signatures, `SwagOrdersStore`/`GiftCardOrdersStore` track order
  state, and both `/shop`/`/gift-cards` pages were built around it.
- Square was chosen specifically because the restaurant was confirmed (by
  logging into `app.squareup.com/dashboard`) to already have an active
  Square account — no new merchant signup needed, unlike the originally-built
  Stripe integration that was fully removed and replaced with Square the
  same day.
- **If Echelon turns out to be the restaurant's actual in-person card
  processor**, that's a *separate* merchant relationship from the Square
  account used above — having both isn't unusual (many restaurants keep a
  legacy in-person processor while using something else, e.g. Square, for a
  newer online-only feature), but it's worth confirming which is really
  "the" processor before assuming either one.

## Square — verified, current, publicly published (2026-08-02)

Square publishes its rates directly at squareup.com/us/en/payments/our-fees.
For **online / card-not-present** payments — what Payment Links (what this
site uses) falls under, per Square's own wording "card payments made online
or through an invoice":

| Square plan | Online rate | In-person rate | Keyed-in rate | Monthly fee |
|---|---|---|---|---|
| Free | 3.3% + $0.30 | 2.6% + $0.15 | 3.5% + $0.15 | $0 |
| Plus | 2.9% + $0.30 | 2.5% + $0.15 | 3.5% + $0.15 | paid (amount not published on the fees page — confirm in-account) |
| Premium | 2.9% + $0.30 | 2.4% + $0.15 | 3.5% + $0.15 | paid, higher than Plus (amount not published on the fees page — confirm in-account) |

**Open question:** which Square plan is the restaurant actually on? If the
existing in-person Square account is already Plus or Premium (for the
lower in-person rate), the *online* rate for Shop/Gift Cards is already
2.9%+$0.30, not the Free plan's 3.3%+$0.30 — matters for an apples-to-apples
comparison. Check the Square Dashboard (Account & Settings → Subscriptions
& Services) or ask whoever manages the account.

No setup fee, no contract, no early termination fee — Square is
month-to-month by design.

## Echelon — real company, but no public pricing

**echelonpayments.com** is a real payment processor (not a scam/mismatch —
confirmed via their site) with products that do cover web purchases:

- **Hosted Payment Pages** — a Square-Payment-Links equivalent: "process
  credit cards, debit cards, and in-app payments directly on your site."
- **Ecommerce** — "easy API and shopping cart integrations."
- **Payment Links** — send via email/text/QR, same concept as Square's.
- Also: Virtual Terminal, Smart Terminal (in-person), Subscription/Recurring
  Billing, Invoicing (QuickBooks/Dynamics integrations), ACH/eCheck.

So *technically*, Echelon could replace Square here — the product exists.

**But: Echelon's pricing is entirely quote-based.** Their site explicitly
advertises "Pay a Fixed Rate, Guaranteed" and fee-reduction programs
(surcharging, cash discounting, dual pricing) but discloses **zero specific
numbers** anywhere public. This is normal for their business model —
traditional payment-processing ISOs (independent sales organizations) sell
through a dedicated rep with a custom quote per merchant, unlike Square's
transparent published-rate model. It means:

- There is no way to answer "is Echelon cheaper" without an actual quote.
- Any number short of a written quote (a sales rep saying "rates as low as
  X%" on a call) should be treated as a marketing floor, not the real
  effective rate — ask for it in writing.

## What to actually ask Echelon for (get this before deciding anything)

Request a **written quote**, specifically covering:

1. **Effective/blended rate for card-not-present (online) transactions** —
   not "as low as," the real all-in percentage + fixed fee per transaction,
   comparable to Square's "2.9% + $0.30" format above.
2. **Pricing model** — interchange-plus (transparent, markup over the real
   card-network cost) vs. flat-rate vs. tiered (their own site calls tiered
   "less transparent and potentially costlier" — worth taking that
   seriously even coming from them).
3. **Monthly/platform/gateway fees** — separate from the per-transaction
   rate. Many traditional processors charge a merchant-account fee *and* a
   separate payment-gateway fee (two line items where Square has one).
4. **PCI compliance fee**, **statement fee**, **chargeback fee** — Square
   effectively bundles these into its published rate; Echelon's site lists
   these as separate line items, so get real numbers for each.
5. **Contract length and early termination fee** — traditional processors
   often lock in a 1–3 year term with a real cancellation penalty; Square is
   month-to-month with none. This matters a lot if the numbers are close,
   since Square's flexibility has real value on its own.
6. **Whether the existing in-person Echelon relationship (if confirmed)
   gets a bundled/discounted rate for adding online payments** — this is
   the main scenario where switching could actually make sense: one
   consolidated statement/relationship instead of two, at a rate at or
   below Square's.

## Decision framework once a real quote exists

- **If Echelon's all-in online rate is clearly lower than Square's 2.9–3.3%
  + $0.30 and has no meaningful lock-in**, switching is worth scoping —
  budget it as a comparable engineering effort to the original
  Stripe→Square swap this session (new `EchelonCheckout.swift`-equivalent,
  new webhook handling, re-test Shop + Gift Cards end-to-end). Not a
  config change.
- **If the numbers are close (within a few tenths of a percent)**, the
  switch is probably not worth the engineering time plus losing Square's
  no-lock-in flexibility, unless consolidating onto one processor
  (bookkeeping simplicity) has its own value to the business.
- **If Echelon requires a contract term/early termination fee** and Square
  doesn't, that's a real cost even if the rate is nominally lower — factor
  it in, don't compare rate-only.
- Given current web-purchase volume is low (Shop/Gift Cards just launched,
  sandbox-only as of this doc), the actual dollar difference either way is
  probably small right now. The bigger reason to get the Echelon quote
  isn't urgency — it's having a real number on file before volume grows
  enough that the percentage difference starts to matter in real dollars.

## Sources checked (2026-08-02)

- https://echelonpayments.com/ , `/payments/`, `/reduce-payment-processing-fees/`, `/restaurant-solutions/` — product descriptions, no pricing
- https://squareup.com/us/en/payments/our-fees — current published Square rates (table above)

## Next steps

1. Get a written Echelon quote using the question list above.
2. Confirm which Square plan (Free/Plus/Premium) the existing account is on.
3. ~~Confirm whether Echelon is actually the in-person processor~~ —
   confirmed 2026-08-15: Echelon is the restaurant's real card processor.
4. Bring the numbers back and decide — this doc intentionally stops short
   of a recommendation because the one number that actually matters
   (Echelon's real rate) isn't available yet.

**Re-checked 2026-08-15:** echelonpayments.com/payments still discloses no
pricing — same "Hosted Payment Pages"/"Ecommerce" products, same "easy API
and shopping cart integrations" language with no actual docs/SDK linked, same
generic "no hidden fees" marketing with zero numbers. Nothing has changed
since the 2026-08-02 research above; step 1 is still the blocker.
