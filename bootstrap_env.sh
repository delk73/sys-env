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
HELIX_VERSION="25.07.1"

printf "[+] Executing environment state sync for Ubuntu 24.04...\n"
printf "[+] Working Directory Vector: %s\n" "$REPO_ROOT"

# 1. Ensure Directory Baseline Exists
mkdir -p "$REPO_ROOT/config"
mkdir -p "$LITELLM_CONF_DIR" "$TMUXINATOR_CONF_DIR" "$HELIX_CONF_DIR"

# 2. Base Package Sync
sudo apt update -y
sudo apt install -y \
    build-essential curl git tmux jq python3-pip moreutils software-properties-common

# Native Package Registration for GitHub CLI
if ! command -v gh &> /dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update -y && sudo apt install -y gh
fi

# 3. Official Pre-Compiled Helix Distribution Deployment
if ! command -v hx &> /dev/null || [[ "$(hx --version | awk '{print $2}')" != "$HELIX_VERSION" ]]; then
    printf "[+] Deploying official pre-compiled Helix %s assets...\n" "$HELIX_VERSION"
    
    DOWNLOAD_DIR=$(mktemp -d)
    ARCH=$(dpkg --print-architecture)
    
    if [[ "$ARCH" == "amd64" ]]; then
        DIR_SUFFIX="x86_64-linux"
    else
        DIR_SUFFIX="aarch64-linux"
    fi
    TARBALL="helix-$HELIX_VERSION-$DIR_SUFFIX.tar.xz"

    curl -sSL -o "$DOWNLOAD_DIR/$TARBALL" "https://github.com/helix-editor/helix/releases/download/$HELIX_VERSION/$TARBALL"
    tar -xf "$DOWNLOAD_DIR/$TARBALL" -C "$DOWNLOAD_DIR"
    
    (
        cd "$DOWNLOAD_DIR/helix-$HELIX_VERSION-$DIR_SUFFIX"
        
        sudo cp hx /usr/local/bin/hx
        
        # Deploy runtime to official shared path hierarchy
        sudo mkdir -p /usr/local/share/helix
        sudo rm -rf /usr/local/share/helix/runtime
        sudo cp -r runtime /usr/local/share/helix/
        
        # Explicit permissions reset
        sudo chmod -R a+rX /usr/local/share/helix/runtime
    )
    
    rm -rf "$DOWNLOAD_DIR"
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
# Declarative Configuration Assembly
# ---------------------------------------------------------------------

printf "[+] Generating unified model routing manifest...\n"
cat << 'EOF' > "$REPO_ROOT/config/litellm_config.yaml"
model_list:
  - model_name: local-reasoning
    litellm_params:
      model: ollama/gemma4:e4b
      api_base: "http://127.0.0.1:11434"
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

# 7. Declarative Runtime Symlinking
printf "[+] Linking configuration vectors...\n"
ln -sf "$REPO_ROOT/config/litellm_config.yaml" "$LITELLM_CONF_DIR/config.yaml"
ln -sf "$REPO_ROOT/config/tmuxinator.yaml" "$TMUXINATOR_CONF_DIR/workspace.yml"
ln -sf "$REPO_ROOT/config/helix_config.toml" "$HELIX_CONF_DIR/config.toml"

ln -sfn /usr/local/share/helix/runtime "$HELIX_CONF_DIR/runtime"

# 8. Local Hardware Model Allocations (3060 Ti)
if command -v ollama &> /dev/null; then
    printf "[+] Syncing 3060 Ti memory-mapped weights (Gemma 4)...\n"
    ollama pull gemma4:e4b
fi

# Terminal and Multiplexer Configuration
if ! grep -q 'COLORTERM="truecolor"' "$HOME/.bashrc"; then
    echo 'export COLORTERM="truecolor"' >> "$HOME/.bashrc"
    echo 'export TERM="xterm-256color"' >> "$HOME/.bashrc"
fi

cat << 'EOF' > "$HOME/.tmux.conf"
set -g default-terminal "xterm-256color"
set -as terminal-features ",xterm-256color:RGB"
EOF

printf "[+] Environment state alignment complete.\n"