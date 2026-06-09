#!/usr/bin/env bash
# Module Version: v1.0.0
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

INPUT_CONTEXT=""
# Read from standard input pipe if data is present
if [ ! -t 0 ]; then
    INPUT_CONTEXT=$(cat)
fi

# Read direct file target if passed as an argument instead of standard input redirect
if [ -n "$TARGET_FILE" ] && [ -z "$INPUT_CONTEXT" ]; then
    INPUT_CONTEXT=$(cat "$TARGET_FILE")
fi

if [ -z "$USER_PROMPT" ] && [ -z "$INPUT_CONTEXT" ]; then
    show_help
fi

# Semantic Retrieval Hook
SEMANTIC_CONTEXT=""
if [ -f ".repo_vectors.hnsw" ] && [ -n "$USER_PROMPT" ]; then
    if [ -x "$SCRIPT_DIR/vector_store.py" ]; then
        SEMANTIC_CONTEXT=$("$VENV_PYTHON" "$SCRIPT_DIR/vector_store.py" --search "$USER_PROMPT" 2>/dev/null || echo "")
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
        echo "$ASSISTANT_OUT" | git apply --reject -
        echo "Patch application step completed."
    else
        echo ""
        echo "Patch application cancelled by user."
    fi
else
    echo "$ASSISTANT_OUT"
fi
