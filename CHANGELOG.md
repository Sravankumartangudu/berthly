# Changelog

## 1.1.0 — 2026-10-24

🧰 Rail tools: everything else you need around an IRCTC booking, worked out on your Mac.

- **Festival planner**: festivals and holidays through 2027 (Diwali, Chhath, Holi, Eid, Pongal,
  Onam, Durga Puja, summer holidays and more). Shows the morning general booking opens for the
  day you'd travel, with a countdown, and the Tatkal day. **Plan** makes it a trip.
- **Refund calculator**: what a cancellation gives back by class, quota, status, fare and time,
  under the 2015 refund rules with the April 2026 slabs (72/24/8 h). Booked trips get a fare field
  and an "If you cancel now" line.
- **Tatkal charges**: the charge per class and a calculator.
- **Station codes**: 8,953 stations searchable offline (datameet, CC0), with renamed stations
  (ALD → PRYJ, MGS → DDU, HBJ → RKMP and more). Station names appear as you type From and To,
  and an old code offers the new one.
- **On the journey**: Rail Madad, e-Catering, retiring rooms, NTES, PNR status, 139, and a TDR
  guide.
- **Good to know**: VIKALP, auto-upgrade, lower berths, the senior concession, passengers per
  ticket, Aadhaar for Tatkal, ID on board.
- **Add to Calendar**: opening, journey and chart events with alerts. The PNR is never included.
- 1A added as a class, with a warning that it has no Tatkal quota. The passengers stepper follows
  the 4 (Tatkal) and 6 (general) limits.
- Menu → **Rail tools** opens any tool.

## 1.0.0 — 2026-10-24

First release.

- 🚆 Menu-bar app that works out when IRCTC booking opens for each trip: Tatkal and Premium
  Tatkal (10:00 IST AC, 11:00 IST SL/2S, the day before the train's start date) and general
  (08:00 IST, 60 days ahead). Handles boarding mid-route after the train started a day or more
  earlier.
- Countdown in the menu bar for the last 3 hours, on a clock checked against internet time
  servers (time.google.com, time.apple.com, pool.ntp.org).
- Alert card the evening before, 30, 10 and 2 minutes before, and at opening. The 10-minute
  alert opens IRCTC. Soft ticks through the last 10 seconds. Sound and voice options.
- Readiness checklist on every trip and alert card.
- After booking: PNR and status, chart time (December 2025 rules) with an alert 15 minutes
  before, and quick links to the official PNR enquiry and NTES pages.
- ✨ Trip coach: a short booking plan and fallbacks from Claude, using your own `claude` tool.
- System, Light or Dark appearance, launch at login.
- Never books, fills forms or solves CAPTCHAs for you. Not affiliated with IRCTC or Indian Railways.
- Privacy and security: trips readable only by your user account; the coach never receives the
  PNR; its sign-in copy is private and deleted after each answer; nonce-checked time-server
  replies; hardened-runtime signing; no third-party code. See "Rules Berthly follows" in the README.
