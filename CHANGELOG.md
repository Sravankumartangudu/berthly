# Changelog

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
