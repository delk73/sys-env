#!/usr/bin/env bash
set -euo pipefail

# Deterministic Path Resolution
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || pwd)"
if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="."
fi

LITELLM_CONF_DIR="$HOME/.config/litellm"
TMUXINATOR_CONF_DIR="$HOME/.config/tmuxinator"
HELIX_CONF_DIR="$HOME/.config/helix"

printf "[+] Executing environment state sync for Ubuntu 24.04...\n"
printf "[+] Working Directory Vector: %s\n" "$REPO_ROOT"

# 1. Ensure Directory Baseline Exists
mkdir -p "$REPO_ROOT/config"
mkdir -p "$LITELLM_CONF_DIR" "$TMUXINATOR_CONF_DIR" "$HELIX_CONF_DIR"

# 2. Base Package Sync
sudo apt update -y
sudo apt install -y \
    build-essential curl git tmux jq python3-pip moreutils software-properties-common

# 3. Native Binary Fetch for Lazygit (Bypassing broken Noble PPA)
if ! command -v lazygit &> /dev/null; then
    printf "[+] Fetching compiled architecture binary for lazygit...\n"
    LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
    tar -xf lazygit.tar.gz lazygit
    sudo install lazygit /usr/local/bin/
    rm -f lazygit lazygit.tar.gz
fi

# 4. Native Installation for Helix Text Engine
if ! command -v hx &> /dev/null; then
    printf "[+] Fetching compiled architecture binary for Helix...\n"
    HELIX_VERSION=$(curl -s "https://api.github.com/repos/helix-editor/helix/releases/latest" | jq -r '.tag_name')
    
    # Download the standard Linux x86_64 tarball
    curl -Lo helix.tar.xz "https://github.com/helix-editor/helix/releases/latest/download/helix-${HELIX_VERSION}-x86_64-linux.tar.xz"
    tar -xf helix.tar.xz
    
    # Install the runtime binary and move application assets to global shares
    sudo install "helix-${HELIX_VERSION}-x86_64-linux/hx" /usr/local/bin/
    sudo mkdir -p /usr/local/lib/helix
    sudo cp -r "helix-${HELIX_VERSION}-x86_64-linux/runtime" /usr/local/lib/helix/
    
    # Clean up local workspace artifacts
    rm -rf "helix-${HELIX_VERSION}-x86_64-linux" helix.tar.xz
fi

# 5. Physical Bus Access (Native USB Flashing Permissions)
printf "[+] Syncing physical hardware dialout and plugdev groups...\n"
sudo usermod -aG dialout "$USER"
sudo usermod -aG plugdev "$USER"

# 6. Stateless Token Gateway Installation
if ! command -v litellm &> /dev/null; then
    printf "[+] Deploying LiteLLM core proxy...\n"
    pip install litellm --break-system-packages
fi

# ---------------------------------------------------------------------
# Declarative Configuration Assembly via Heredocs
# ---------------------------------------------------------------------

printf "[+] Generating unified model routing manifest...\n"
cat << 'EOF' > "$REPO_ROOT/config/litellm_config.yaml"
model_list:
  - model_name: local-reasoning
    litellm_params:
      model: ollama/deepseek-r1:32b
      api_base: "http://<YOUR_OLLAMA_BOX_IP>:11434"
      temperature: 0.0

  - model_name: local-gpu-dense
    litellm_params:
      model: ollama/gemma4:e4b
      api_base: "http://127.0.0.1:11434"
      temperature: 0.0

  - model_name: cloud-heavyweight
    litellm_params:
      model: azure/<YOUR_DEPLOYMENT_NAME>
      api_base: "https://<YOUR_RESOURCE_NAME>.openai.azure.com/"
      api_key: "os.environ/AZURE_API_KEY"
      api_version: "2024-08-01-preview"
EOF

printf "[+] Generating tmuxinator window matrix blueprint...\n"
cat << 'EOF' > "$REPO_ROOT/config/tmuxinator.yaml"
name: precision-dev
root: ~/src/precision-signal

windows:
  - engine:
      layout: main-vertical
      panes:
        # Left Split: Spatial File Structure Radar
        - yazi
        # Primary Center Split: Focus Text Engine
        - hx .
        # Bottom Horizontal Split: Verification & Flashing Loop
        - clear && echo "=== Hardware Pipeline Target Ready ==="
EOF

printf "[+] Generating un-crufted helix typographical rules...\n"
cat << 'EOF' > "$REPO_ROOT/config/helix_config.toml"
theme = "brutalist"

[editor]
line-numbers = "relative"
cursorline = true
color-modes = true

[editor.lsp]
display-messages = true
display-inlay-hints = true
EOF

# 7. Declarative Runtime Symlinking
printf "[+] Linking configuration vectors...\n"
ln -sf "$REPO_ROOT/config/litellm_config.yaml" "$LITELLM_CONF_DIR/config.yaml"
ln -sf "$REPO_ROOT/config/tmuxinator.yaml" "$TMUXINATOR_CONF_DIR/workspace.yml"
ln -sf "$REPO_ROOT/config/helix_config.toml" "$HELIX_CONF_DIR/config.toml"

# 8. Local Hardware Model Allocations (3060 Ti)
if command -v ollama &> /dev/null; then
    printf "[+] Syncing 3060 Ti memory-mapped weights (Gemma 4)...\n"
    ollama pull gemma4:e4b
fi

printf "[+] Environment state alignment complete.\n"
