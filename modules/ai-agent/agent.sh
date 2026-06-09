#!/usr/bin/env bash
set -euo pipefail

MODEL="gemma4:e4b"
URL="http://localhost:11434/api/chat"
HISTORY_FILE=".agent_history.json"
VENV_PYTHON="$HOME/.local/share/sys-env/ai-venv/bin/python3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APPLY_PATCH=false
QUERY_ONLY=false
USER_PROMPT=""

# Parse operational flags
for arg in "$@"; do
    case "$arg" in
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
            fi
            ;;
    esac
done

INPUT_CONTEXT=""
if [ ! -t 0 ]; then
    INPUT_CONTEXT=$(cat)
fi

if [ -z "$USER_PROMPT" ] && [ -z "$INPUT_CONTEXT" ]; then
    echo "Usage: $0 \"instruction\" [--apply] [--query] [--clear]"
    exit 1
fi

# Semantic Retrieval Hook
SEMANTIC_CONTEXT=""
if [ -f ".repo_vectors.hnsw" ] && [ -n "$USER_PROMPT" ]; then
    if [ -x "$SCRIPT_DIR/vector_store.py" ]; then
        SEMANTIC_CONTEXT=$("$VENV_PYTHON" "$SCRIPT_DIR/vector_store.py" --search "$USER_PROMPT" 2>/dev/null || echo "")
    fi
fi

# Construct payload text layers
FULL_CONTENT=""
if [ -n "$SEMANTIC_CONTEXT" ] && [ "$SEMANTIC_CONTEXT" != "[]" ]; then
    FULL_CONTENT="Semantic Context:\n${SEMANTIC_CONTEXT}\n\n"
fi
if [ -n "$INPUT_CONTEXT" ]; then
    FULL_CONTENT="${FULL_CONTENT}Input Context:\n${INPUT_CONTEXT}\n\n"
fi
FULL_CONTENT="${FULL_CONTENT}${USER_PROMPT}"

# System Prompt Assignment based on operational mode
if [ "$QUERY_ONLY" = true ]; then
    SYSTEM_ROLE="You are a precise terminal-native systems developer. Provide direct, technical plaintext explanations or analyses using standard engineering nomenclature. Avoid conversational filler, marketing hyperbole, or formatting descriptions."
else
    SYSTEM_ROLE="You are a precise terminal-native systems developer. When modifications are requested, output your answer EXCLUSIVELY as a valid unified diff patch file that can be read by 'git apply'. Do not include markdown code block backticks (\`\`\`) or any introductory or summary prose."
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
    echo "Applying patch directly via git..."
    echo "$ASSISTANT_OUT" | git apply --reject -
    echo "Patch application step completed."
else
    echo "$ASSISTANT_OUT"
fi
