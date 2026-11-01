#!/bin/bash
set -euo pipefail

# Claude Watch - Mac OFF
# Removes Claude Watch hooks from ~/.claude/settings.json.
# Other hooks and user configurations remain untouched.

SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
    echo "No ~/.claude/settings.json found - nothing to remove."
    exit 0
fi

python3 - << 'EOF'
import json
import os

settings_path = os.path.expanduser("~/.claude/settings.json")

try:
    with open(settings_path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
except Exception as e:
    print(f"Error reading settings: {e}")
    exit(0)

if not isinstance(cfg, dict) or "hooks" not in cfg or not isinstance(cfg["hooks"], dict):
    print("No hooks found in settings.json.")
    exit(0)

hooks = cfg["hooks"]

def is_clawd_entry(entry):
    if not isinstance(entry, dict) or "hooks" not in entry:
        return False
    for h in entry.get("hooks", []):
        if isinstance(h, dict) and "clawd-status.txt" in h.get("command", ""):
            return True
    return False

removed_count = 0
for ev in list(hooks.keys()):
    if isinstance(hooks[ev], list):
        initial_len = len(hooks[ev])
        hooks[ev] = [entry for entry in hooks[ev] if not is_clawd_entry(entry)]
        removed_count += (initial_len - len(hooks[ev]))
        if len(hooks[ev]) == 0:
            del hooks[ev]

if len(hooks) == 0:
    del cfg["hooks"]

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"\n  \033[32mClaude Watch DISABLED.\033[0m")
print(f"  Removed {removed_count} hook(s) from {settings_path}\n")
EOF

chmod +x "$0"
