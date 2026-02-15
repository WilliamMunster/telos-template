#!/bin/bash
# telos SecurityValidator — PreToolUse hook
# Validates Bash commands and file paths against security patterns
# Exit codes: 0 = allow, 2 = block
#
# Policy: fail-closed for Bash tool (high-risk), fail-open for others
# If patterns file missing or parse error on a Bash command -> block

HOOK_DIR="$(dirname "${BASH_SOURCE[0]:-$0}")"
HOOK_DIR="$(cd "$HOOK_DIR" 2>/dev/null && pwd -P || echo "$HOOK_DIR")"
AGENTS_ROOT="$(cd "$HOOK_DIR/../../.." 2>/dev/null && pwd -P)"
PATTERNS_FILE="${TELOS_PATTERNS_FILE:-$AGENTS_ROOT/security-patterns.yaml}"

# Read JSON input from stdin (with timeout)
INPUT=""
if read -t 1 -r INPUT; then
  : # got input
else
  # No input — can't determine tool, fail-open
  exit 0
fi

# Detect if this is a Bash tool call (quick check before Python)
IS_BASH=""
case "$INPUT" in *'"Bash"'*) IS_BASH=1 ;; esac

# No patterns file — fail-closed for Bash, fail-open for others
if [ ! -f "$PATTERNS_FILE" ]; then
  if [ -n "$IS_BASH" ]; then
    echo 'BLOCKED: security-patterns.yaml missing, Bash commands denied' >&2
    exit 2
  fi
  exit 0
fi

# Python does the heavy lifting
exec python3 - "$INPUT" "$PATTERNS_FILE" << 'PYEOF'
import sys, json, re, os

def main():
    try:
        input_data = json.loads(sys.argv[1])
        patterns_file = sys.argv[2]
    except:
        return fail_closed_if_bash(sys.argv[1] if len(sys.argv) > 1 else "")

    tool = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})
    if not tool:
        return allow()

    try:
        patterns = parse_patterns(patterns_file)
    except Exception as e:
        if tool == "Bash":
            return block("security-patterns.yaml parse error, Bash denied", str(e))
        return allow()

    if tool == "Bash" and len(patterns["bash"]["blocked"]) == 0:
        return block("No blocked rules loaded — security-patterns.yaml may be corrupt", "(empty ruleset)")

    if tool == "Bash":
        return validate_bash(tool_input.get("command", ""), patterns)
    elif tool in ("Edit", "Write", "Read", "MultiEdit"):
        return validate_path(tool_input.get("file_path", ""), tool, patterns)
    else:
        return allow()
def allow():
    sys.exit(0)

def fail_closed_if_bash(raw_input):
    """When we can't parse input properly, block if it looks like a Bash call."""
    if '"Bash"' in str(raw_input):
        block("Input parse error, Bash commands denied", "(unparseable)")
    sys.exit(0)

def block(reason, target):
    sys.stderr.write(f"BLOCKED: {reason}\n  -> {target}\n")
    sys.exit(2)

def ask(reason, target):
    msg = f"{reason}\n\n  {target}\n\nProceed?"
    print(json.dumps({"decision": "ask", "message": msg}))
    sys.exit(0)

def match_cmd(command, pattern):
    try:
        return bool(re.search(pattern, command, re.IGNORECASE))
    except:
        return pattern.lower() in command.lower()

def match_path(filepath, pattern):
    expanded = pattern.replace("~", os.path.expanduser("~"))
    regex = expanded.replace(".", r"\.").replace("**", "X").replace("*", "[^/]*").replace("X", ".*")
    try:
        return bool(re.match(regex + "$", filepath))
    except:
        return filepath.startswith(expanded.rstrip("*"))

def parse_patterns(filepath):
    p = {"bash": {"blocked": [], "confirm": [], "alert": []},
         "paths": {"blocked": [], "read_only": [], "confirm_write": []}}
    lines = open(filepath).readlines()

    section = level = None
    item = {}

    for line in lines:
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s == "bash:":
            section, level = "bash", None; continue
        if s == "paths:":
            section, level = "paths", None; continue

        if section == "bash":
            if s.rstrip(":") in ("blocked", "confirm", "alert"):
                if item.get("pattern") and level:
                    p["bash"][level].append(item); item = {}
                level = s.rstrip(":"); continue
            if s.startswith("- pattern:"):
                if item.get("pattern") and level:
                    p["bash"][level].append(item)
                item = {"pattern": s.split(":", 1)[1].strip().strip("\"'")}; continue
            if s.startswith("reason:"):
                item["reason"] = s.split(":", 1)[1].strip().strip("\"'"); continue

        if section == "paths":
            if s.rstrip(":") in ("blocked", "read_only", "confirm_write"):
                level = s.rstrip(":"); continue
            if s.startswith("- "):
                val = s[2:].strip().strip("\"'")
                if level and level in p["paths"]:
                    p["paths"][level].append(val); continue

    if item.get("pattern") and section == "bash" and level:
        p["bash"][level].append(item)
    return p

def validate_bash(command, patterns):
    if not command:
        return allow()
    for r in patterns["bash"]["blocked"]:
        if match_cmd(command, r["pattern"]):
            block(r.get("reason", "Blocked"), command)
    for r in patterns["bash"]["confirm"]:
        if match_cmd(command, r["pattern"]):
            ask(r.get("reason", "Confirm"), command)
    for r in patterns["bash"]["alert"]:
        if match_cmd(command, r["pattern"]):
            sys.stderr.write(f"ALERT: {r.get('reason','')} -- {command}\n")
    return allow()

def validate_path(filepath, tool, patterns):
    if not filepath:
        return allow()
    is_write = tool in ("Edit", "Write", "MultiEdit")
    for pat in patterns["paths"]["blocked"]:
        if match_path(filepath, pat):
            block(f"Access denied", filepath)
    if is_write:
        for pat in patterns["paths"]["read_only"]:
            if match_path(filepath, pat):
                block(f"Read-only path", filepath)
        for pat in patterns["paths"]["confirm_write"]:
            if match_path(filepath, pat):
                ask("Writing to sensitive file", filepath)
    return allow()

main()
PYEOF
