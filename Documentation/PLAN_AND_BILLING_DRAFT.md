# RepRoot Studio Plan and Billing Draft

**Status:** Approved plan policy — implementation intentionally pending  
**Updated:** 10 August 2026

This document records the intended public plan structure. It does not change
backend limits, frontend behavior, billing, existing subscriptions, or hosted
environment configuration.

## Public plan structure

RepRoot Studio has exactly three public professional plan tiers:

1. Free
2. Pro
3. Premium

Do not display Starter, Starter Free, Premium Unlimited, Legacy, trial, or any
other plan as a separate public tier. Any obsolete or greyed-out plan option
must be removed from the visible plan cards, selectors, comparisons, checkout
choices, marketing copy, and user-facing labels during implementation.

Internal compatibility identifiers for existing database records are an
implementation concern and must never appear as additional customer plans.

## Plan limits

| Feature | Free | Pro | Premium |
|---|---:|---:|---:|
| Lead forms | 1 | 2 | 3 |
| Clients | 50 | Unlimited | Unlimited |
| Storage | 100 MB | 1 GB | 10 GB |
| Groups | 3 | 10 | 25 |
| Templates | 5 | 15 | 50 |
| Resources | 30 | 100 | 250 |
| Categories | 5 | 20 | 50 |
| Subcategories per category | 3 | 10 | 20 |
| Client history | 60 days | 90 days | 180 days |

## Monthly pricing

| Market | Free | Pro | Premium |
|---|---:|---:|---:|
| India | ₹0 | ₹499 | ₹999 |
| International | $0 | $7.49 | $14.99 |

The international Pro amount is confirmed as **$7.49 per month**.

## Longer billing periods

The existing commercial rule is retained in this draft until final approval:

- Six months: monthly price multiplied by 5.
- Yearly: monthly price multiplied by 10.

| Market | Plan | Monthly | 6 months | Yearly |
|---|---|---:|---:|---:|
| India | Pro | ₹499 | ₹2,495 | ₹4,990 |
| India | Premium | ₹999 | ₹4,995 | ₹9,990 |
| International | Pro | $7.49 | $37.45 | $74.90 |
| International | Premium | $14.99 | $74.95 | $149.90 |

The calculated six-month and yearly Pro amounts must be confirmed before
implementation or payment-provider configuration.

## Future custom capacity

A future optional purchase may allow a professional to add capacity such as:

- Additional templates
- Additional storage
- Other selected limits

This is not a fourth plan, not a trial tier, and is not part of the current
implementation. Its pricing, eligibility, renewal behavior, downgrade rules,
and limit enforcement will be planned separately.

## Implementation rules for the later phase

- Keep the backend as the single source of truth for plan limits and prices.
- Website and mobile must consume the same backend plan catalogue.
- Show only Free, Pro, and Premium to users.
- Remove obsolete or greyed-out public plan choices.
- Preserve existing account data while converting old internal plan codes.
- Do not enable checkout until payment configuration is approved.
- Do not implement custom capacity purchases during the current phase.

## Items awaiting confirmation

1. Confirm the calculated Pro six-month and yearly prices.
2. Decide separately whether the client ad-free add-on remains part of the
   product; it must not appear as a professional plan tier.
