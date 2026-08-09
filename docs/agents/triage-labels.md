# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the label strings this repo's issue tracker should use.

Only `wontfix` from this canonical triage set exists in the tracker today (`gh label list`) — the repo also carries unrelated default labels (`bug`, `documentation`, `enhancement`, etc.) that this table doesn't cover. Create the remaining four triage labels with `gh label create <name>` before a skill applies them for the first time.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

> Applying these labels (`gh issue edit --add-label`/`--remove-label`) requires `issues: write` on the calling token. This repo's CI workflows only grant `issues: read` — run `/triage` label mutations from a user-authenticated local `gh` session instead.
