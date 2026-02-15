Load decision principles and goals from the TELOS identity system, analyze a decision scenario, and provide structured recommendations.

When the user invokes /decision-helper, do the following:

## Step 1: Gather context

If the user provided a question after the command (e.g., `/decision-helper should I prioritize MCP integration`), use that as the decision topic.

If no content was provided, ask: What decision are you weighing?

## Step 2: Load TELOS context

Read the relevant identity documents:

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)

echo "===BELIEFS==="
obsidian read file=beliefs 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===GOALS==="
obsidian read file=goals 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===MODELS==="
obsidian read file=models 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

echo "===STRATEGIES==="
obsidian read file=strategies 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null

# macOS-only
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

## Step 3: Analyze the decision

Based on the loaded beliefs, goals, models, and strategies, produce a structured analysis:

1. **Decision question** — restate the question clearly
2. **Options analysis** — list each option with pros/cons, evaluated against:
   - Does it align with decision principles (closed-loop first, evidence-driven, subtraction, etc.)
   - Does it advance current OKR
   - Is it on the "don't do" list
3. **Recommendation** — a clear recommendation with reasoning
4. **Risks** — what could go wrong with the recommended option

## Step 4: Search for related context

If the decision relates to a specific project or topic, search the vault for additional context:

```bash
# macOS-only
PREV_APP=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
obsidian search query="<relevant keyword>" limit=5 matches 2>&1 &
PID=$!; sleep 6; kill $PID 2>/dev/null; wait $PID 2>/dev/null
osascript -e "tell application \"$PREV_APP\" to activate" 2>/dev/null
```

Incorporate any relevant findings into the analysis.

## Output

Present the analysis directly. Do NOT create a new note — this is a conversational tool, not a note-creation tool.

If the user wants to save the decision record, they can use `/knowledge-capture` separately.

## Notes

- Always ground recommendations in the actual beliefs and goals loaded from the vault, not generic advice.
- Quote specific principles when they apply.
- Be opinionated — the user wants a clear recommendation, not a balanced "it depends".
- If the decision falls outside current goals, say so directly.
