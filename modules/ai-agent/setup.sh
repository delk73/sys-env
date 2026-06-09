
#!/usr/bin/env bash
# =============================================================================
# delk73/sys-env - Local AI Toolchain Bootstrap
# =============================================================================
set -euo pipefail

echo "=== Initializing Local AI Environment Primitives ==="

# 1. Install core system utilities if missing
echo "Checking system package dependencies..."
sudo apt-get update -y
sudo apt-get install -y jq curl python3-pip python3-venv

# 2. Verify NVIDIA CUDA toolkit presence for the RTX 3060 Ti
if ! command -v nvidia-smi &> /dev/null; then
    echo "Warning: nvidia-smi not found. Ensure NVIDIA proprietary drivers are installed."
else
    echo "NVIDIA Driver detected:"
    nvidia-smi --query-gpu=name,driver_version --format=csv
fi

# 3. Setup an isolated virtual environment to prevent system Python pollution
VENV_DIR="$HOME/.local/share/sys-env/ai-venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating isolated Python virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
fi

# Activate venv and update core pip layout
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install --upgrade pip

# 4. Install production-grade vector and embedding math bindings
echo "Installing local tensor and vector indexing libraries..."
pip install sentence-transformers hnswlib numpy

# 5. Verify or download the Ollama local background daemon
if ! command -v ollama &> /dev/null; then
    echo "Installing Ollama background daemon..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama daemon already installed."
fi

echo "Pulling local VRAM-optimized model weights (Gemma 4 E4B)..."
ollama pull gemma4:e4b

echo "=== Bootstrap Complete. Modules ready for deployment. ==="


# Find and index all code files automatically
find modules/ config/ -type f \( -name "*.sh" -o -name "*.py" -o -name "*.toml" \) | while read -r file; do
    vector-store --index "$file"
done
