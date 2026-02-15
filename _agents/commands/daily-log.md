Log an entry to today's daily note in Obsidian.

When the user invokes /daily-log, do the following:

1. If the user provided a message after the command (e.g., `/daily-log finished API integration`), use that as the log entry.
2. If no message was provided, ask the user what to log.
3. Format the entry as a bullet point with timestamp: `- HH:MM <content>`
4. Write it to today's daily note under the `## Log` section using the vault helper:

```bash
source "$HOME/.agents/hooks/lib/vault.sh"
vault_daily_append "- $(date +%H:%M) <content>"
```

This inserts the entry between `## Log` and the next `## ` header, not at the end of the file.

If the daily note doesn't exist yet, create it with the template first:

```bash
VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"
mkdir -p "$VAULT/_journal/daily"
TODAY=$(date +%Y-%m-%d)
DAILY="$VAULT/_journal/daily/${TODAY}.md"
WEEKDAY=$(date +%A)
cat > "$DAILY" << EOF
---
tags:
  - journal
  - daily
date: ${TODAY}
---

# ${TODAY} ${WEEKDAY}

## Plan
-

## Log

## Reflection
EOF
source "$HOME/.agents/hooks/lib/vault.sh"
vault_daily_append "- $(date +%H:%M) <content>"
```

5. Confirm to the user what was logged.

Do NOT read the daily note back unless the user asks. Keep it quick.
