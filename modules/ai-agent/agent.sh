#!/usr/bin/env bash
set -euo pipefail

MODEL="gemma4:e4b"
URL="http://localhost:11434/api/chat"
HISTORY_FILE=".agent_history.json"
VENV_PYTHON="$HOME/.local/share/sys-env/ai-venv/bin/python3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APPLY_PATCH=false
QUERY_ONLY=false
TARGET_FILE=""
USER_PROMPT=""

show_help() {
    cat << 'EOF'
AI AGENT MODULE - SYSTEM OPERATIONAL MATRIX

USAGE:
    agent "instruction" [FLAGS] [path/to/file]
    git diff | agent "instruction" [FLAGS]

FLAGS:
    -h, --help    Display this structural layout and operational matrix.
    -q, --query   Engage Plaintext Query Mode for analysis (prose output).
    --apply       Engage Patch Generation Mode with interactive gating.
    --clear       Wipe the sequential conversation memory cache (.agent_history.json).
EOF
    exit 0
}

# Parse operational flags and path arguments
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            ;;
        --clear)
            rm -f "$HISTORY_FILE"
            echo "History cleared."
            exit 0
            ;;
        --apply)
            APPLY_PATCH=true
            ;;
        -q|--query)
            QUERY_ONLY=true
            ;;
        *)
            if [ -z "$USER_PROMPT" ]; then
                USER_PROMPT="$arg"
            elif [ -z "$TARGET_FILE" ] && [ -f "$arg" ]; then
                TARGET_FILE="$arg"
            fi
            ;;
    esac
done

# Provenance Log Append Subroutine
log_provenance() {
    local status="$1"
    local commit_hash
    commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "non-git")
    
    # Generate structured entry via jq to guarantee valid JSON formatting
    jq -n \
      --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --arg commit "$commit_hash" \
      --arg target "$TARGET_FILE" \
      --arg prompt "$USER_PROMPT" \
      --arg status "$status" \
      --arg sys "$SYSTEM_ROLE" \
      --arg vectors "$SEMANTIC_CONTEXT" \
      --arg patch "$ASSISTANT_OUT" \
      '{timestamp: $ts, commit_before: $commit, target_file: $target, user_prompt: $prompt, system_role: $sys, vector_context: ($vectors | fromjson? // $vectors), status: $status, patch_output: $patch}' \
      >> ".agent_provenance.jsonl"
}

# Pre-flight staging audit check for uncommitted changes
if [ "$APPLY_PATCH" = true ]; then
    if ! git diff-index --quiet HEAD -- > /dev/null 2>&1; then
        echo ""
        echo "=================================================="
        echo "WARNING: Uncommitted modifications detected in working directory."
        read -r -p "Do you wish to proceed despite uncommitted changes? (y/N): " preflight_confirm < /dev/tty
        if [[ ! "$preflight_confirm" =~ ^[Yy]$ ]]; then
            echo "Operation aborted by user due to uncommitted changes."
            SYSTEM_ROLE="disabled"
            SEMANTIC_CONTEXT="[]"
            ASSISTANT_OUT=""
            log_provenance "aborted_preflight"
            exit 1
        fi
    fi
fi

INPUT_CONTEXT=""
if [ ! -t 0 ]; then
    INPUT_CONTEXT=$(cat)
fi

if [ -n "$TARGET_FILE" ] && [ -z "$INPUT_CONTEXT" ]; then
    INPUT_CONTEXT=$(cat "$TARGET_FILE")
fi

if [ -z "$USER_PROMPT" ] && [ -z "$INPUT_CONTEXT" ]; then
    show_help
fi

# Semantic Retrieval Hook
SEMANTIC_CONTEXT="[]"
if [ -f ".repo_vectors.hnsw" ] && [ -n "$USER_PROMPT" ]; then
    if [ -x "$SCRIPT_DIR/vector_store.py" ]; then
        SEMANTIC_CONTEXT=$("$VENV_PYTHON" "$SCRIPT_DIR/vector_store.py" --search "$USER_PROMPT" 2>/dev/null || echo "[]")
    fi
fi

# Construct payload layers with explicit path anchoring
FULL_CONTENT=""
if [ -n "$SEMANTIC_CONTEXT" ] && [ "$SEMANTIC_CONTEXT" != "[]" ]; then
    FULL_CONTENT="Semantic Context:\n${SEMANTIC_CONTEXT}\n\n"
fi
if [ -n "$INPUT_CONTEXT" ]; then
    if [ -n "$TARGET_FILE" ]; then
        FULL_CONTENT="${FULL_CONTENT}File: ${TARGET_FILE}\n"
    fi
    FULL_CONTENT="${FULL_CONTENT}Input Context:\n${INPUT_CONTEXT}\n\n"
fi
FULL_CONTENT="${FULL_CONTENT}${USER_PROMPT}"

# System Prompt Assignment based on operational mode
if [ "$QUERY_ONLY" = true ]; then
    SYSTEM_ROLE="You are a precise terminal-native systems developer. Provide direct, technical plaintext explanations or analyses using standard engineering nomenclature. Avoid conversational filler, marketing hyperbole, or formatting descriptions."
else
    SYSTEM_ROLE="You are a precise terminal-native systems developer. When modifications are requested, output your answer EXCLUSIVELY as a valid unified diff patch file that can be read by 'git apply'. You MUST use the exact file path provided in the 'File: ' context line for the '--- a/' and '+++ b/' diff header lines. Do not introduce generic names like 'script.sh' or 'file.py'. Do not include markdown code block backticks (\`\`\`) or any introductory or summary prose."
fi

if [ ! -f "$HISTORY_FILE" ]; then
    echo "[]" > "$HISTORY_FILE"
    UPDATED_HIST=$(jq --arg sys "$SYSTEM_ROLE" '. += [{"role": "system", "content": $sys}]' "$HISTORY_FILE")
    echo "$UPDATED_HIST" > "$HISTORY_FILE"
fi

UPDATED_HIST=$(jq --arg msg "$FULL_CONTENT" '. += [{"role": "user", "content": $msg}]' "$HISTORY_FILE")
echo "$UPDATED_HIST" > "$HISTORY_FILE"

PAYLOAD=$(jq -n \
  --arg model "$MODEL" \
  --slurpfile history "$HISTORY_FILE" \
  '{model: $model, messages: $history[0], stream: false, options: {temperature: 0.0}}')

RESPONSE=$(curl -s -X POST "$URL" -H "Content-Type: application/json" -d "$PAYLOAD")
ASSISTANT_OUT=$(echo "$RESPONSE" | jq -r '.message.content')

UPDATED_HIST=$(jq --arg out "$ASSISTANT_OUT" '. += [{"role": "assistant", "content": $out}]' "$HISTORY_FILE")
echo "$UPDATED_HIST" > "$HISTORY_FILE"

if [ "$APPLY_PATCH" = true ]; then
    echo ""
    echo "=================================================="
    echo "Proposed Patch (Unified Diff Format):"
    echo "--------------------------------------------------"
    echo "$ASSISTANT_OUT"
    echo "--------------------------------------------------"
    read -r -p "Apply this patch to your working tree? (y/N): " confirmation < /dev/tty
    if [[ "$confirmation" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Applying patch via git..."
        echo "$ASSISTANT_OUT" | git apply --recount --reject -
        echo "Patch application step completed."
        log_provenance "applied"
    else
        echo ""
        echo "Patch application cancelled by user."
        log_provenance "rejected"
    fi
else
    echo "$ASSISTANT_OUT"
    log_provenance "query_viewed"
fi
