# T085 - Managed-EDR Decision: Huntress vs Microsoft Defender for Business

> **Type:** [DECISION] - no code to ship. Deliverable = this analysis + a clear
> recommendation + the exact questions Helder must close before buying.
> **Context:** This applies to the **clean rebuild** (Phase 1), NOT the current
> compromised host. On the live box, EDR findings are leads, not proof
> (assume-breach). See `THREAT_MODEL.md` and `Tasks/tools-enhacements/Protecao_Win11.md`.
> **Pricing refreshed:** 2026-06-29 (web). All prices US list; Brazil/Brasilia
> expect FX + reseller markup. Verify locally before purchase.

---

## 1. The decision in one line

For a **solo individual** (one laptop, no IT team, Brasilia), the realistic,
buy-today choice is **Microsoft Defender for Business (standalone, ~$3/user/mo,
no device minimum)**. **Huntress Managed EDR** is the better *managed-SOC* layer
but is gated behind a **50-agent minimum** that only makes sense **through a
local MSP** - pursue it only if a Brazilian MSP can onboard a single endpoint at
sane cost. **Do not stack two kernel-level EDRs as peers**; the only supported
stack here is **Huntress layered on Microsoft Defender AV**.

**Recommended path:** Rebuild on **Defender for Business** now; **add Huntress
on top later** if/when an MSP path exists. This is additive (Huntress is built to
ride on Defender AV), so starting with Defender does not waste effort.

---

## 2. Side-by-side

| Factor | Microsoft Defender for Business | Huntress Managed EDR |
|---|---|---|
| What it is | Microsoft's SMB EDR (EDR + ASR rules + auto-investigation + Defender APIs) | A 24/7 human+AI **managed SOC** that rides **on top of** Defender AV |
| Who operates it | **You** (self-managed; you triage alerts) | **Huntress SOC** triages, contains, remediates, sends plain-language reports |
| Min. devices | **None** - start with 1 | **50-agent minimum** (12-mo term); solo only viable **via an MSP** that pools volume |
| List price | ~**$3 / user / month** standalone; also bundled in M365 Business Premium | ~**$8.99 / endpoint / month** direct (50-99 tier); ~$2.50-3.50/endpoint via MSP partner rates. Public list not published - demo for quote |
| Annual (1 endpoint) | ~**$36 / yr** | ~**$108 / yr** direct-tier rate (but 50-min blocks direct solo buy) |
| Kernel-level | Yes (Defender) | Rides on Defender AV (no second kernel EDR) - **supported** combo |
| Coverage | Up to 300 users, up to 5 devices/user | Per-endpoint |
| Best fit | Already use / willing to use Microsoft 365; want self-serve, no minimum | Want a managed SOC watching 24/7 and can reach an MSP |
| Trust caveat | On-host agent - blindable under kernel compromise; value is on the **clean rebuild** + feeding signals off-box | Same on-host caveat, but adds **external human review** which is harder for a local attacker to silence |

Other commercial options (from the research doc, **not** recommended for solo):
- **CrowdStrike Falcon Go** $59.99/device/yr (NGAV tier; lacks full EDR/XDR).
- **SentinelOne** ~$70-80/endpoint/yr (Control); strong autonomous AI + rollback
  but **really needs someone to watch it** - so no real advantage over Defender
  for a solo user without a SOC.
- **Defender for Endpoint Plan 2** - enterprise/standalone, also in M365 E5;
  overkill/over-priced for one laptop.

---

## 3. Why this recommendation

1. **No device minimum = no MSP dependency.** Defender for Business can protect
   one laptop today. Huntress's 50-agent floor means a solo user must find an MSP
   willing to add a single endpoint to their pool - an external relationship and
   contract Helder does not currently have.
2. **Cost.** ~$36/yr (Defender) vs ~$108/yr (Huntress direct rate, if it were
   even buyable solo). For one endpoint the managed-SOC premium is hard to justify
   unless the MSP rate (~$2.50-3.50/endpoint/mo) is reachable AND the MSP onboards
   a single device.
3. **No EDR conflict.** Starting with Defender keeps the door open: Huntress is
   explicitly designed to **layer on Defender AV**, so adding it later is additive,
   not a rip-and-replace. Choosing SentinelOne/CrowdStrike instead would later
   conflict with a Defender-based Huntress stack.
4. **Managed SOC value is real but situational.** Huntress's pitch (human eyes,
   ~8-min MTTR, low false positives - **vendor-published, not independently
   audited**) matters most when nobody is watching alerts. Helder is actively
   running this ecosystem and reading logs daily, partially substituting for that
   - so the managed layer is a "nice upgrade," not a blocker for the rebuild.

**When to upgrade to Huntress (decision triggers):**
- A Brasilia/BR MSP can onboard **one** endpoint at the ~$2.50-3.50/endpoint/mo
  partner rate (or a flat solo-friendly price), AND
- The offline scans (T082) / N100 sensor (T083) reveal **active, persistent
  compromise** that justifies a 24/7 external SOC, OR
- Helder's time-to-triage on alerts becomes the bottleneck.

---

## 4. Open questions for Helder (close these before buying)

These require Helder (signup / phone / local market) and cannot be automated:

1. **Microsoft 365 status** - Do you already pay for M365 (Business Premium
   includes Defender for Business at no extra EDR cost)? If yes, **it may already
   be available** - just turn it on during rebuild. If no, buy the ~$3/user/mo
   standalone add-on.
2. **Brazil availability + real price** - Confirm Defender for Business standalone
   pricing in BRL via the Microsoft BR store / a CSP reseller (expect FX + markup
   over the $3 US figure).
3. **MSP path for Huntress** - Contact 1-2 Brasilia/regional MSPs: will they
   onboard a **single** endpoint, and at what monthly price? If no reasonable
   single-seat option exists, Huntress stays parked.
4. **Timing** - This is a **clean-rebuild (Phase 1)** purchase. Do not subscribe
   while the current host is compromised; the agent would just run on a
   distrusted OS. Buy at rebuild time.

---

## 5. Final verdict (Pending Helder's purchase decision)

- **Default / buy at rebuild:** Microsoft Defender for Business (standalone or via
  existing M365 Business Premium). No minimum, ~$3/user/mo, self-serve.
- **Upgrade if MSP path opens:** Huntress Managed EDR layered on Defender AV.
- **Reject for solo use:** stacking CrowdStrike or SentinelOne as a second
  kernel-level EDR; consumer-AV-only rebuild.

This task is **Pending-Decision**: the analysis is complete; the actual purchase
is Helder's call and depends on the four open questions above (M365 status, BR
pricing, MSP availability, rebuild timing).

---

## Sources (verified 2026-06-29)
- Huntress Managed EDR pricing / 50-agent minimum: huntress.com/pricing, mdrcost.com/huntress-pricing, rallied.ai/blog/huntress-pricing
- Defender for Business price / no device minimum: microsoft.com/en-us/security/business/endpoint-security/microsoft-defender-business, learn.microsoft.com/en-us/defender-business/mdb-faq
- Internal research basis: `Tasks/tools-enhacements/Protecao_Win11.md` (Layer-2 commercial-EDR section, Phase 1 step 3)
