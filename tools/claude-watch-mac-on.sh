#!/bin/bash
set -euo pipefail

# Claude Watch - Mac ON
# Installs Claude Code hooks that write Claude's current activity to /tmp/clawd-status.txt.
# Clawd Pet reads this file and shows animated speech bubbles above its head.

SETTINGS="$HOME/.claude/settings.json"
BACKUP="$SETTINGS.clawd-backup"

mkdir -p "$HOME/.claude"

python3 - << 'EOF'
import json
import os
import shutil

settings_path = os.path.expanduser("~/.claude/settings.json")
backup_path = settings_path + ".clawd-backup"

cfg = {}
if os.path.exists(settings_path):
    try:
        shutil.copy2(settings_path, backup_path)
        with open(settings_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except Exception as e:
        print(f"Warning: Failed to load existing settings ({e}), initializing empty config.")
        cfg = {}

if not isinstance(cfg, dict):
    cfg = {}

if "hooks" not in cfg or not isinstance(cfg["hooks"], dict):
    cfg["hooks"] = {}

hooks = cfg["hooks"]

# Our hook definitions
hook_definitions = [
    {"event": "UserPromptSubmit", "matcher": "",                                "token": "think"},
    {"event": "PreToolUse",       "matcher": "Bash",                            "token": "bash"},
    {"event": "PreToolUse",       "matcher": "Edit|Write|MultiEdit|NotebookEdit", "token": "edit"},
    {"event": "PreToolUse",       "matcher": "Read|Grep|Glob",                  "token": "read"},
    {"event": "PreToolUse",       "matcher": "WebFetch|WebSearch",              "token": "web"},
    {"event": "PreToolUse",       "matcher": "Task",                            "token": "task"},
    {"event": "Notification",     "matcher": "",                                "token": "notify"},
    {"event": "Stop",             "matcher": "",                                "token": "done"}
]

# Helper to check if an entry belongs to clawd
def is_clawd_entry(entry):
    if not isinstance(entry, dict) or "hooks" not in entry:
        return False
    for h in entry.get("hooks", []):
        if isinstance(h, dict) and "clawd-status.txt" in h.get("command", ""):
            return True
    return False

# Clean out old clawd hooks
events = list({d["event"] for d in hook_definitions})
for ev in events:
    if ev in hooks and isinstance(hooks[ev], list):
        hooks[ev] = [entry for entry in hooks[ev] if not is_clawd_entry(entry)]
    elif ev not in hooks:
        hooks[ev] = []

# Add current hooks
for d in hook_definitions:
    ev = d["event"]
    token = d["token"]
    cmd = f'printf "%s" "{token}" > /tmp/clawd-status.txt'
    entry = {
        "hooks": [
            {
                "type": "command",
                "command": cmd
            }
        ]
    }
    if d["matcher"]:
        entry["matcher"] = d["matcher"]
    hooks[ev].append(entry)

with open(settings_path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")

print("\n  \033[32mClaude Watch for macOS ENABLED.\033[0m")
print(f"  Hooks installed into: {settings_path}")
if os.path.exists(backup_path):
    print(f"  Backup saved to: {backup_path}")
print("\n  \033[33mNext steps:\033[0m")
print("  1. Restart your Claude Code session so the hooks are reloaded.")
print("  2. Run start-clawd-mac.sh to see Clawd Pet follow Claude's activity!\n")
EOF

chmod +x "$0"
