Quickly capture a knowledge item as an Obsidian knowledge card, with auto-classification, tagging, and linking.

When the user invokes /knowledge-capture, do the following:

## Step 1: Gather input

If the user provided content after the command (e.g., `/knowledge-capture LangGraph state management`), use that as the topic.

If no content was provided, ask the user:
- What knowledge to capture? (topic)
- Source? (article link, book, hands-on experience, etc. — optional)

## Step 2: Determine classification

Based on the topic, determine:

1. **type** — one of: `tech`, `domain`, `methodology`, `tool`
2. **folder** — map type to folder:
   - tech -> `knowledge/tech/`
   - domain -> `knowledge/domain/`
   - methodology -> `knowledge/tech/`
   - tool -> `knowledge/tech/`
3. **tags** — generate 2-4 relevant tags
4. **related notes** — search the vault for related content:

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
obsidian search query="<keyword>" limit=5 matches 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

## Step 3: Generate knowledge card

Based on the user's input, write a concise knowledge card with:
- **Key points** — 3-5 bullet points summarizing the key takeaways
- **Details** — expanded explanation if the user provided enough context, otherwise leave for the user to fill in
- **Related** — wikilinks `[[]]` to related notes found in Step 2

## Step 4: Create the note

```bash
VAULT="${TELOS_VAULT:-$HOME/Documents/Obsidian Vault}"
mkdir -p "$VAULT/<folder>"
cat > "$VAULT/<folder>/<title>.md" << 'EOF'
<generated content>
EOF
```

Use this frontmatter:
```yaml
---
tags:
  - knowledge
  - <type>
  - <tag1>
  - <tag2>
created: YYYY-MM-DD
source: <url or description, if provided>
---
```

## Step 5: Confirm

Show the user:
- File path
- Tags
- Related notes

Keep it brief. Do NOT read the note back unless asked.

## Notes

- If the user pastes a long article or code snippet, extract the key points rather than copying everything.
- If a note with the same name already exists, ask the user whether to append or create with a different name.
