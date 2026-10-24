# Security policy

## Reporting a problem

Please report security problems privately through GitHub:
**Security → Report a vulnerability** on this repository. Don't open a public issue for them.

Include what you found, how to reproduce it, and the Berthly version (menu → ⚙ Settings →
the version line). You'll get a reply within a week.

## Supported versions

Only the latest release gets fixes. Update from the
[latest release](https://github.com/Sravankumartangudu/berthly/releases/latest).

## What Berthly handles

- **Stored on your Mac:** trips in `~/Library/Application Support/Berthly/trips.json`, in a folder
  only your user account can read.
- **Sent over the network:** time-server queries (no personal data), and, only when you click the
  ✨ coach, the trip details without the PNR, through your own `claude` command-line tool.
- **Never handled:** IRCTC passwords, OTPs, Aadhaar numbers, passenger identity details or payment
  details.
