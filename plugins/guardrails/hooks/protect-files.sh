#!/usr/bin/env bash
set -euo pipefail
file=$(jq -r '.tool_input.file_path // .tool_input.path // ""')
basename=$(basename "$file")

# Basename patterns (match anywhere in the tree)
# Quoted so the shell does not expand them against files in the current directory.
basename_protected=( '.env' '.env.*' 'package-lock.json' 'yarn.lock' 'pnpm-lock.yaml'
                     '*.pem' '*.key' '*.p12' '*.pfx' 'terraform.tfstate' 'terraform.tfstate.*' )

# Exact path patterns (resolved via suffix match)
path_protected=( .claude/settings.json .claude/settings.local.json )

# Directory patterns (match path components)
dir_protected=( .git secrets )

for pattern in "${basename_protected[@]}"; do
  # shellcheck disable=SC2053  # unquoted on purpose: $pattern is a glob
  if [[ "$basename" == $pattern ]]; then
    echo "Blocked: '$file' is protected (matched '$pattern'). Explain why this edit is necessary." >&2
    exit 2
  fi
done

for suffix in "${path_protected[@]}"; do
  if [[ "$file" == *"/$suffix" || "$file" == "$suffix" ]]; then
    echo "Blocked: '$file' is a protected config file. Ask the user to edit it manually." >&2
    exit 2
  fi
done

for dir in "${dir_protected[@]}"; do
  if [[ "$file" == *"/$dir/"* || "$file" == "$dir/"* ]]; then
    echo "Blocked: '$file' is inside protected directory '$dir'. Explain why this edit is necessary." >&2
    exit 2
  fi
done

exit 0
