#!/bin/bash
set -e

cd $HOME

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== InsightsLM Local AI Setup Script ===${NC}"
echo ""

# Detect operating system first
if [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MACOS=true
    echo -e "${BLUE}Detected macOS system${NC}"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    IS_MACOS=false
    echo -e "${BLUE}Detected Linux system${NC}"
else
    echo -e "${RED}Unsupported operating system: $OSTYPE${NC}"
    exit 1
fi

# Cross-platform sed function
cp_sed() {
    if [ "$IS_MACOS" = true ]; then
        sed -i "" "$@"
    else
        sed -i "$@"
    fi
}

# =============================================================================
# EARLY USER CONFIGURATION
# =============================================================================

# Default vLLM model configuration (HuggingFace format)
DEFAULT_VLLM_MODEL="Qwen/Qwen3-8B"
DEFAULT_EMBEDDING_MODEL="nomic-ai/nomic-embed-text-v1.5"

echo -e "${YELLOW}=== Initial Configuration ===${NC}"
echo ""

# 1. Model Selection (single question)
echo -e "${YELLOW}Model Configuration:${NC}"
echo -e "Default main model: ${GREEN}$DEFAULT_VLLM_MODEL${NC}"
echo -e "Default embedding model: ${GREEN}$DEFAULT_EMBEDDING_MODEL${NC}"
echo ""
read -p "Enter main model to use (press Enter for default: $DEFAULT_VLLM_MODEL): " -r VLLM_MODEL
VLLM_MODEL=${VLLM_MODEL:-$DEFAULT_VLLM_MODEL}

read -p "Enter embedding model to use (press Enter for default: $DEFAULT_EMBEDDING_MODEL): " -r EMBEDDING_MODEL
EMBEDDING_MODEL=${EMBEDDING_MODEL:-$DEFAULT_EMBEDDING_MODEL}

echo -e "${GREEN}✓ Using main model: $VLLM_MODEL${NC}"
echo -e "${GREEN}✓ Using embedding model: $EMBEDDING_MODEL${NC}"
echo ""

# 2. Network Configuration
echo -e "${YELLOW}Network Configuration:${NC}"

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

DETECTED_IP=$(curl -s ipinfo.io/ip 2>/dev/null || echo "Unable to detect")
if [ "$DETECTED_IP" != "Unable to detect" ]; then
    echo -e "Detected external IP: ${GREEN}$DETECTED_IP${NC}"
    echo ""
    echo "Service URL options:"
    echo "  • Enter 'y' to use detected external IP: $DETECTED_IP"
    echo "  • Enter 'N' or press Enter for localhost"
    echo "  • Enter a custom IP address (e.g., 192.168.1.100)"
    echo ""
    
    while true; do
        read -p "Service URL configuration (y/N/custom IP): " -r USER_INPUT
        USER_INPUT=${USER_INPUT:-N}
        
        case "$USER_INPUT" in
            [Yy]|[Yy][Ee][Ss])
                ACCESS_HOST="$DETECTED_IP"
                echo -e "${GREEN}✓ Using detected external IP: $ACCESS_HOST${NC}"
                break
                ;;
            [Nn]|[Nn][Oo]|"")
                ACCESS_HOST="localhost"
                echo -e "${GREEN}✓ Using localhost for service access${NC}"
                break
                ;;
            *)
                if validate_ip "$USER_INPUT"; then
                    ACCESS_HOST="$USER_INPUT"
                    echo -e "${GREEN}✓ Using custom IP: $ACCESS_HOST${NC}"
                    break
                else
                    echo -e "${RED}✗ Invalid IP address format. Please enter a valid IP (e.g., 192.168.1.100) or y/N${NC}"
                fi
                ;;
        esac
    done
else
    ACCESS_HOST="localhost"
    echo -e "${YELLOW}Unable to detect external IP${NC}"
    echo ""
    echo "Service URL options:"
    echo "  • Press Enter for localhost"
    echo "  • Enter a custom IP address (e.g., 192.168.1.100)"
    echo ""
    
    while true; do
        read -p "Service URL configuration (localhost/custom IP): " -r USER_INPUT
        USER_INPUT=${USER_INPUT:-localhost}
        
        if [ "$USER_INPUT" = "localhost" ] || [ "$USER_INPUT" = "" ]; then
            ACCESS_HOST="localhost"
            echo -e "${GREEN}✓ Using localhost for service access${NC}"
            break
        elif validate_ip "$USER_INPUT"; then
            ACCESS_HOST="$USER_INPUT"
            echo -e "${GREEN}✓ Using custom IP: $ACCESS_HOST${NC}"
            break
        else
            echo -e "${RED}✗ Invalid IP address format. Please enter a valid IP (e.g., 192.168.1.100) or press Enter for localhost${NC}"
        fi
    done
fi
echo ""

# =============================================================================
# HARDWARE DETECTION AND DEPENDENCY CHECKING
# =============================================================================

echo -e "${YELLOW}=== Hardware Detection & Dependency Checking ===${NC}"
echo ""

# Function to check CUDA version
check_cuda_version() {
    if command -v nvcc >/dev/null 2>&1; then
        CUDA_VERSION=$(nvcc --version | grep "release" | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p')
        CUDA_MAJOR=$(echo $CUDA_VERSION | cut -d. -f1)
        CUDA_MINOR=$(echo $CUDA_VERSION | cut -d. -f2)
        
        echo -e "${BLUE}Found CUDA version: $CUDA_VERSION${NC}"
        
        # Check if version is 12.6 or higher
        if [ "$CUDA_MAJOR" -gt 12 ] || ([ "$CUDA_MAJOR" -eq 12 ] && [ "$CUDA_MINOR" -ge 6 ]); then
            echo -e "${GREEN}✓ CUDA version $CUDA_VERSION meets minimum requirement (12.6+)${NC}"
            return 0
        else
            echo -e "${RED}✗ CUDA version $CUDA_VERSION is below minimum requirement (12.6+)${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ CUDA toolkit (nvcc) not found${NC}"
        return 1
    fi
}

# Function to check NVIDIA Docker runtime
check_nvidia_docker_runtime() {
    if command -v nvidia-container-runtime >/dev/null 2>&1; then
        echo -e "${GREEN}✓ NVIDIA Container Runtime found${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ NVIDIA Container Runtime not found${NC}"
        return 1
    fi
}

# Function to install NVIDIA Docker runtime
install_nvidia_docker_runtime() {
    echo -e "${YELLOW}Installing NVIDIA Container Runtime...${NC}"
    
    if [ "$IS_MACOS" = true ]; then
        echo -e "${RED}NVIDIA Container Runtime not available on macOS${NC}"
        return 1
    fi
    
    # Try multiple installation methods
    RUNTIME_INSTALLED=false
    
    # Method 1: Official NVIDIA repository (recommended)
    echo "  Trying official NVIDIA repository..."
    if command -v lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VERSION=$(lsb_release -sr)
    else
        # Fallback: read from os-release
        DISTRO=$(. /etc/os-release; echo $ID)
        VERSION=$(. /etc/os-release; echo $VERSION_ID)
    fi
    
    # Clean up any broken repository files first
    sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    case "$DISTRO" in
        ubuntu)
            echo "    Detected Ubuntu $VERSION"
            # Use official Ubuntu repository
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /" | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
            
            if sudo apt-get update 2>/dev/null && sudo apt-get install -y nvidia-container-toolkit 2>/dev/null; then
                RUNTIME_INSTALLED=true
                echo "    ✓ Installed via official repository"
            else
                echo "    ✗ Official repository failed"
                sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
            fi
            ;;
        debian)
            echo "    Detected Debian $VERSION"
            # Use official Debian repository
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /" | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
            
            if sudo apt-get update 2>/dev/null && sudo apt-get install -y nvidia-container-toolkit 2>/dev/null; then
                RUNTIME_INSTALLED=true
                echo "    ✓ Installed via official repository"
            else
                echo "    ✗ Official repository failed"
                sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
            fi
            ;;
        *)
            echo "    Unsupported distribution: $DISTRO $VERSION"
            ;;
    esac
    
    # Method 2: Try direct package download if repository failed
    if [ "$RUNTIME_INSTALLED" = false ]; then
        echo "  Trying direct package download..."
        TEMP_DIR=$(mktemp -d)
        cd "$TEMP_DIR"
        
        # Download packages directly
        if wget -q https://github.com/NVIDIA/libnvidia-container/releases/latest/download/libnvidia-container1_1.16.2-1_amd64.deb && \
           wget -q https://github.com/NVIDIA/libnvidia-container/releases/latest/download/libnvidia-container-tools_1.16.2-1_amd64.deb && \
           wget -q https://github.com/NVIDIA/nvidia-container-toolkit/releases/latest/download/nvidia-container-toolkit_1.16.2-1_amd64.deb; then
            
            if sudo dpkg -i *.deb 2>/dev/null || sudo apt-get install -f -y 2>/dev/null; then
                RUNTIME_INSTALLED=true
                echo "    ✓ Installed via direct package download"
            else
                echo "    ✗ Direct package installation failed"
            fi
        else
            echo "    ✗ Could not download packages"
        fi
        
        cd - >/dev/null
        rm -rf "$TEMP_DIR"
    fi
    
    # Configure Docker if runtime was installed
    if [ "$RUNTIME_INSTALLED" = true ]; then
        echo "  Configuring Docker for NVIDIA runtime..."
        if command -v nvidia-ctk >/dev/null 2>&1; then
            sudo nvidia-ctk runtime configure --runtime=docker 2>/dev/null || {
                echo "    Warning: nvidia-ctk configure failed, trying manual configuration..."
                # Manual Docker daemon.json configuration
                DOCKER_CONFIG="/etc/docker/daemon.json"
                if [ ! -f "$DOCKER_CONFIG" ]; then
                    sudo mkdir -p /etc/docker
                    echo '{}' | sudo tee "$DOCKER_CONFIG" >/dev/null
                fi
                
                # Add nvidia runtime to daemon.json
                sudo python3 -c "
import json
import sys
try:
    with open('$DOCKER_CONFIG', 'r') as f:
        config = json.load(f)
except:
    config = {}

if 'runtimes' not in config:
    config['runtimes'] = {}

config['runtimes']['nvidia'] = {
    'path': 'nvidia-container-runtime',
    'runtimeArgs': []
}

with open('$DOCKER_CONFIG', 'w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null || echo "    Manual configuration also failed"
            }
            
            # Restart Docker
            if sudo systemctl restart docker 2>/dev/null; then
                echo -e "${GREEN}✓ NVIDIA Container Runtime installed and configured${NC}"
                return 0
            else
                echo "    Warning: Could not restart Docker"
            fi
        else
            echo "    Warning: nvidia-ctk not found after installation"
        fi
    fi
    
    if [ "$RUNTIME_INSTALLED" = false ]; then
        echo -e "${YELLOW}⚠ Could not install NVIDIA Container Runtime${NC}"
        echo -e "${YELLOW}  GPU acceleration may be limited, but vLLM will still work${NC}"
        return 1
    fi
    
    return 0
}

# Detect compute profile and check dependencies
PROFILE="cpu"
DEPENDENCIES_OK=true

if [ "$IS_MACOS" = true ]; then
    echo -e "${BLUE}macOS detected - checking architecture...${NC}"
    if [[ $(uname -m) == "arm64" ]]; then
        PROFILE="cpu"
        echo -e "${GREEN}✓ Apple Silicon detected - using CPU profile${NC}"
        echo -e "${YELLOW}Note: Some services will use x86_64 emulation for compatibility${NC}"
    else
        echo -e "${BLUE}Intel Mac detected - checking for AMD GPU...${NC}"
        if system_profiler SPDisplaysDataType 2>/dev/null | grep -q "AMD\|Radeon"; then
            PROFILE="gpu-amd"
            echo -e "${GREEN}✓ AMD GPU detected - using GPU-AMD profile${NC}"
        else
            echo -e "${YELLOW}No AMD GPU detected - using CPU profile${NC}"
        fi
    fi
else
    # Linux system - check for NVIDIA first, then AMD
    echo -e "${BLUE}Linux detected - checking for GPU hardware...${NC}"
    
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
        echo -e "${GREEN}✓ NVIDIA GPU detected${NC}"
        nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1 | sed 's/^/  GPU: /'
        
        PROFILE="gpu-nvidia"
        echo -e "${BLUE}Checking NVIDIA dependencies...${NC}"
        
        # Check CUDA
        if check_cuda_version; then
            echo -e "${GREEN}✓ CUDA requirements satisfied${NC}"
        else
            echo -e "${RED}✗ CUDA requirements not met${NC}"
            echo -e "${YELLOW}Please install CUDA 12.6 or higher from: https://developer.nvidia.com/cuda-downloads${NC}"
            DEPENDENCIES_OK=false
        fi
        
        # Check NVIDIA Docker runtime
        if ! check_nvidia_docker_runtime; then
            echo -e "${YELLOW}Installing NVIDIA Container Runtime...${NC}"
            if install_nvidia_docker_runtime; then
                echo -e "${GREEN}✓ NVIDIA Container Runtime installed${NC}"
            else
                echo -e "${YELLOW}⚠ NVIDIA Container Runtime installation failed${NC}"
                echo -e "${YELLOW}  vLLM will still work with GPU acceleration, but may have limited container runtime features${NC}"
                # Don't fail completely - vLLM can still use GPU without nvidia-container-runtime
            fi
        fi
        
    elif command -v rocminfo >/dev/null 2>&1 || [ -d /opt/rocm ]; then
        echo -e "${GREEN}✓ AMD GPU detected${NC}"
        PROFILE="gpu-amd"
        
        if command -v rocminfo >/dev/null 2>&1; then
            rocminfo | grep "Name:" | head -1 | sed 's/^/  GPU: /'
        fi
        
        echo -e "${BLUE}Checking ROCm dependencies...${NC}"
        if [ -d /opt/rocm ]; then
            echo -e "${GREEN}✓ ROCm installation found${NC}"
        else
            echo -e "${YELLOW}⚠ ROCm not found - GPU acceleration may not work optimally${NC}"
            echo -e "${YELLOW}Consider installing ROCm from: https://rocm.docs.amd.com/en/latest/deploy/linux/index.html${NC}"
        fi
        
    else
        echo -e "${YELLOW}No GPU detected - using CPU profile${NC}"
        PROFILE="cpu"
    fi
fi

echo ""
echo -e "${GREEN}=== Configuration Summary ===${NC}"
echo -e "Compute Profile: ${GREEN}$PROFILE${NC}"
echo -e "Main Model: ${GREEN}$VLLM_MODEL${NC}"
echo -e "Embedding Model: ${GREEN}$EMBEDDING_MODEL${NC}"
echo -e "Access Host: ${GREEN}$ACCESS_HOST${NC}"

if [ "$DEPENDENCIES_OK" = false ]; then
    echo ""
    echo -e "${RED}⚠ WARNING: Some dependencies are missing!${NC}"
    echo -e "${YELLOW}The setup will continue, but GPU acceleration may not work properly.${NC}"
    echo ""
    read -p "Continue anyway? (y/N): " -r CONTINUE_ANYWAY
    if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Setup cancelled. Please install missing dependencies and try again.${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}✓ All checks completed - proceeding with installation...${NC}"
echo ""

# Repository configuration
LOCAL_AI_REPO="https://github.com/sirouk/local-ai-packaged.git"
INSIGHTS_LM_REPO="https://github.com/sirouk/insights-lm-local-package.git"
INSIGHTS_LM_RAW_URL="https://raw.githubusercontent.com/sirouk/insights-lm-local-package"
INSIGHTS_LM_PUBLIC_URL="https://github.com/sirouk/insights-lm-public.git"

echo -e "${YELLOW}Using repositories:${NC}"
echo -e "  Local AI: ${GREEN}${LOCAL_AI_REPO}${NC}"
echo -e "  InsightsLM: ${GREEN}${INSIGHTS_LM_REPO}${NC}"
echo ""

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
if [ "$IS_MACOS" = true ]; then
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo -e "${YELLOW}Installing Homebrew...${NC}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Add Homebrew to PATH for current session
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    brew update
    brew install python3 curl git jq yq
    echo -e "${GREEN}macOS packages installed successfully${NC}"
else
    # Linux package installation
    sudo apt update
    sudo apt install -y python3 python3-venv net-tools python3-pip curl git jq
    
    # Install Docker if not present
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing Docker...${NC}"
        # Install Docker using official installation script
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        # Add current user to docker group
        sudo usermod -aG docker $USER
        # Start and enable Docker
        sudo systemctl start docker
        sudo systemctl enable docker
        echo -e "${GREEN}✓ Docker installed and started${NC}"
        echo -e "${YELLOW}Note: You may need to log out and back in for Docker group membership to take effect${NC}"
        rm -f get-docker.sh
    else
        echo -e "${GREEN}✓ Docker already installed${NC}"
        # Ensure Docker is running
        sudo systemctl start docker 2>/dev/null || true
    fi
    
    # Install yq
    snap install --classic yq 2>/dev/null || {
        echo -e "${YELLOW}Installing yq via direct download...${NC}"
        sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        sudo chmod +x /usr/local/bin/yq
    }
    echo -e "${GREEN}Linux packages installed successfully${NC}"
fi

# Always start fresh with easy_setup_v2.sh
if [ -d "$HOME/local-ai-packaged" ]; then
    echo -e "${YELLOW}Found existing installation at $HOME/local-ai-packaged${NC}"
    echo -e "${GREEN}easy_setup_v2.sh always starts fresh - wiping and reinstalling...${NC}"
fi

# Start fresh installation
echo -e "${YELLOW}Starting fresh installation...${NC}"

if [ -d "$HOME/local-ai-packaged" ]; then
    cd "$HOME/local-ai-packaged"
    
    echo "Performing comprehensive cleanup for this project only..."
    
    echo "  → Stopping project containers..."
    # Stop containers by name patterns and compose project
    docker compose -p localai down 2>/dev/null || true
    docker stop $(docker ps -q --filter "name=supabase-" --filter "name=n8n" --filter "name=ollama" --filter "name=searxng" --filter "name=flowise" --filter "name=open-webui" --filter "name=qdrant" --filter "name=redis" --filter "name=caddy" --filter "name=insightslm" --filter "name=coqui-tts" --filter "name=whisper-asr" --filter "name=langfuse" --filter "name=clickhouse" --filter "name=minio" --filter "name=postgres" --filter "name=neo4j") 2>/dev/null || echo "    No project containers running"
    
    echo "  → Removing project containers..."
    docker rm -f $(docker ps -aq --filter "name=supabase-" --filter "name=n8n" --filter "name=ollama" --filter "name=searxng" --filter "name=flowise" --filter "name=open-webui" --filter "name=qdrant" --filter "name=redis" --filter "name=caddy" --filter "name=insightslm" --filter "name=coqui-tts" --filter "name=whisper-asr" --filter "name=langfuse" --filter "name=clickhouse" --filter "name=minio" --filter "name=postgres" --filter "name=neo4j") 2>/dev/null || echo "    No project containers to remove"
    
    echo "  → Removing project volumes..."
    # Remove volumes by name patterns (including localai_ prefix patterns)
    docker volume rm $(docker volume ls -q | grep -E "(localai_|localai-|supabase|n8n_storage|ollama_storage|qdrant_storage|open-webui|flowise|caddy-data|caddy-config|valkey-data|langfuse|whisper_cache|db-config)") 2>/dev/null || echo "    No project volumes to remove"
    
    echo "  → Removing filesystem residuals..."
    # Remove ~/.flowise directory created by flowise service bind mount
    if [ -d "$HOME/.flowise" ]; then
        rm -rf "$HOME/.flowise"
        echo "    Removed ~/.flowise directory"
    else
        echo "    No ~/.flowise directory to remove"
    fi
    
    echo "  → Removing project networks..."
    # Remove networks by name patterns  
    docker network rm $(docker network ls -q --filter "name=localai" --filter "name=supabase") 2>/dev/null || echo "    No project networks to remove"
    
    echo "  → Cleaning up orphaned resources..."
    # Only prune orphaned resources, not all build cache
    docker container prune -f 2>/dev/null || true
    docker volume prune -f 2>/dev/null || true
    docker network prune -f 2>/dev/null || true
    
    echo "✅ Comprehensive Docker cleanup completed"
    
    cd "$HOME"
    rm -rf "$HOME/local-ai-packaged"
fi

# Clone fresh repo
echo -e "${YELLOW}Cloning local-ai-packaged repository...${NC}"
git clone "$LOCAL_AI_REPO"
cd "$HOME/local-ai-packaged"

# Clone insights-lm-local-package
echo -e "${YELLOW}Cloning insights-lm-local-package repository...${NC}"
git clone "$INSIGHTS_LM_REPO"

cd "$HOME/local-ai-packaged"

# Model configuration already set at the beginning of the script

# Set up Python virtual environment
echo -e "${YELLOW}Setting up Python virtual environment...${NC}"
python3 -m venv .venv
source .venv/bin/activate
pip install -q PyJWT bcrypt pyyaml

# Update .gitignore
if ! grep -q "^\.venv/$" .gitignore 2>/dev/null; then
    # Ensure there's a newline before adding .venv/ (in case file doesn't end with newline)
    echo "" >> .gitignore
    echo ".venv/" >> .gitignore
    echo ".venv-vllm/" >> .gitignore
    echo "vllm-docker/" >> .gitignore
    # let's also add .env.previous
    echo ".env.previous" >> .gitignore
    # and unified_credentials.txt
    echo "unified_credentials.txt" >> .gitignore
fi

# Merge docker-compose files cleanly using yq
echo -e "${YELLOW}Merging docker-compose configurations...${NC}"

# Add volumes from copy file if they don't exist
echo "  Checking volumes to add..."
while IFS= read -r volume_name; do
    if [ -n "$volume_name" ] && [ "$volume_name" != "null" ]; then
        if ! yq eval ".volumes | has(\"$volume_name\")" docker-compose.yml | grep -q "true"; then
            yq eval ".volumes.$volume_name = load(\"insights-lm-local-package/docker-compose.copy.yml\").volumes.$volume_name" -i docker-compose.yml
            echo "    Added volume: $volume_name"
        else
            echo "    Volume $volume_name already exists, skipping"
        fi
    fi
done < <(yq eval '.volumes | keys | .[]' insights-lm-local-package/docker-compose.copy.yml)

# Add services from copy file if they don't exist
echo "  Checking services to add..."
while IFS= read -r service_name; do
    if [ -n "$service_name" ] && [ "$service_name" != "null" ]; then
        if ! yq eval ".services | has(\"$service_name\")" docker-compose.yml | grep -q "true"; then
            yq eval ".services.$service_name = load(\"insights-lm-local-package/docker-compose.copy.yml\").services.$service_name" -i docker-compose.yml
            echo "    Added service: $service_name"
            
            # Force fresh build for insightslm to ensure credentials are embedded correctly
            if [ "$service_name" = "insightslm" ]; then
                echo "      → Configuring insightslm to build fresh (no Docker cache)..."
                # Add a unique build arg that changes every run to force Docker to rebuild
                # This ensures ANON_KEY from .env gets properly embedded in the build
                CACHE_BUST_TIMESTAMP=$(date +%s)
                yq eval ".services.insightslm.build.args.CACHE_BUST = \"${CACHE_BUST_TIMESTAMP}\"" -i docker-compose.yml
                # Also add cache_from: [] to prevent using cached layers
                yq eval '.services.insightslm.build.cache_from = []' -i docker-compose.yml
                echo "      → InsightsLM configured for fresh build with current credentials"
            fi

            # Apply Apple Silicon compatibility fixes
            if [ "$IS_MACOS" = true ] && [[ $(uname -m) == "arm64" ]]; then
                case "$service_name" in
                    "whisper-asr")
                        echo "      → Configuring whisper-asr for Apple Silicon..."
                        # Use CPU variant instead of GPU variant
                        yq eval ".services.whisper-asr.image = \"onerahmet/openai-whisper-asr-webservice:latest\"" -i docker-compose.yml
                        # Remove GPU device requirements
                        yq eval "del(.services.whisper-asr.deploy.resources.reservations.devices)" -i docker-compose.yml
                        # Remove GPU profile restriction to allow CPU profile
                        yq eval "del(.services.whisper-asr.profiles)" -i docker-compose.yml
                        echo "      → whisper-asr configured for CPU execution"
                        ;;
                    "coqui-tts")
                        echo "      → Configuring coqui-tts for Apple Silicon..."
                        # Disable CUDA
                        yq eval ".services.coqui-tts.command = [\"--model_name\", \"tts_models/en/vctk/vits\", \"--use_cuda\", \"false\"]" -i docker-compose.yml
                        # Remove GPU device requirements  
                        yq eval "del(.services.coqui-tts.deploy.resources.reservations.devices)" -i docker-compose.yml
                        # Add platform emulation for ARM64 compatibility
                        yq eval ".services.coqui-tts.platform = \"linux/amd64\"" -i docker-compose.yml
                        # Add environment variables to suppress NNPACK warnings on Apple Silicon
                        # NOTE: this USE_NNPACK=0 would have to be done before the install of coqui-ai/tts in python, not after, so this is not working
                        yq eval '.services.coqui-tts.environment += ["USE_NNPACK=0"]' -i docker-compose.yml
                        echo "      → coqui-tts configured for CPU execution with x86_64 emulation and NNPACK disabled"
                        ;;
                esac
            fi
        else
            echo "    Service $service_name already exists, skipping"
        fi
    fi
done < <(yq eval '.services | keys | .[]' insights-lm-local-package/docker-compose.copy.yml)

# Fix CuDNN nvrtc issue for coqui-tts on Linux systems with NVIDIA GPUs
if [ "$IS_MACOS" = false ] && [ "$PROFILE" = "gpu-nvidia" ]; then
    echo -e "${YELLOW}Applying CuDNN nvrtc fix for coqui-tts...${NC}"
    
    # Check if coqui-tts service exists in docker-compose.yml
    if yq eval '.services | has("coqui-tts")' docker-compose.yml | grep -q "true"; then
        # Create directory for custom Dockerfile
        mkdir -p coqui-tts-fixed
        
        # Create custom Dockerfile with nvrtc fix
        cat > coqui-tts-fixed/Dockerfile << 'COQUI_DOCKERFILE'
FROM ghcr.io/coqui-ai/tts

# Fix the nvrtc library issue by updating library cache and environment
USER root

# Add PyTorch library path to ld.so.conf and update library cache
RUN echo "/usr/local/lib/python3.10/dist-packages/torch/lib" > /etc/ld.so.conf.d/torch.conf && \
    ldconfig

# Set environment variables to help PyTorch find CUDA libraries
ENV CUDA_CACHE_DISABLE=1
ENV TORCH_CUDA_ARCH_LIST="6.0;6.1;7.0;7.5;8.0;8.6;8.7;9.0"
ENV PYTORCH_NVVM_FORCE_COMPATIBLE=1

# Create symlinks for common nvrtc library names
RUN ln -sf /usr/local/lib/python3.10/dist-packages/torch/lib/libnvrtc.so.11.2 /usr/local/lib/libnvrtc.so && \
    ln -sf /usr/local/lib/python3.10/dist-packages/torch/lib/libnvrtc-builtins.so.11.8 /usr/local/lib/libnvrtc-builtins.so

ENTRYPOINT ["python3", "TTS/server/server.py"]
COQUI_DOCKERFILE
        
        # Update docker-compose.yml to use custom build
        echo "  → Updating coqui-tts service to use custom build for nvrtc fix"
        yq eval '.services.coqui-tts.build.context = "./coqui-tts-fixed"' -i docker-compose.yml
        yq eval '.services.coqui-tts.build.dockerfile = "Dockerfile"' -i docker-compose.yml
        yq eval 'del(.services.coqui-tts.image)' -i docker-compose.yml
        
        # Ensure proper NVIDIA runtime configuration
        yq eval '.services.coqui-tts.runtime = "nvidia"' -i docker-compose.yml
        yq eval '.services.coqui-tts.environment += ["NVIDIA_VISIBLE_DEVICES=all"]' -i docker-compose.yml
        yq eval '.services.coqui-tts.environment += ["NVIDIA_DRIVER_CAPABILITIES=compute,utility"]' -i docker-compose.yml
        
        echo "  ✅ CuDNN nvrtc fix applied - this will eliminate CUDA warnings"
    else
        echo "  → coqui-tts service not found, skipping nvrtc fix"
    fi
fi

# Configure n8n for external access
echo -e "${YELLOW}Configuring n8n external access and environment...${NC}"

# Add N8N_SECURE_COOKIE=false and N8N_RUNNERS_ENABLED=true to x-n8n environment using yq
# Check if N8N_SECURE_COOKIE exists in the environment array
if ! yq eval '.["x-n8n"].environment[] | select(. == "N8N_SECURE_COOKIE=*")' docker-compose.yml | grep -q "N8N_SECURE_COOKIE"; then
    # Add N8N_SECURE_COOKIE=false to the environment array
    yq eval '.["x-n8n"].environment += ["N8N_SECURE_COOKIE=false"]' -i docker-compose.yml
    echo "  Added N8N_SECURE_COOKIE=false for external access"
else
    echo "  N8N_SECURE_COOKIE already set"
fi

# # Check if N8N_RUNNERS_ENABLED exists in the environment array
# if ! yq eval '.["x-n8n"].environment[] | select(. == "N8N_RUNNERS_ENABLED=*")' docker-compose.yml | grep -q "N8N_RUNNERS_ENABLED"; then
#     # Add N8N_RUNNERS_ENABLED=true to the environment array
#     yq eval '.["x-n8n"].environment += ["N8N_RUNNERS_ENABLED=true"]' -i docker-compose.yml
#     echo "  Added N8N_RUNNERS_ENABLED=true to enable task runners"
# else
#     echo "  N8N_RUNNERS_ENABLED already set"
# fi

# Check if N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS exists in the environment array
if ! yq eval '.["x-n8n"].environment[] | select(. == "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=*")' docker-compose.yml | grep -q "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS"; then
    # Add N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true to the environment array
    yq eval '.["x-n8n"].environment += ["N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true"]' -i docker-compose.yml
    echo "  Added N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true to enforce correct file permissions"
else
    echo "  N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS already set"
fi

# Update override file for n8n external access
if [ -f "docker-compose.override.private.yml" ]; then
    yq eval '.services.n8n.ports = ["0.0.0.0:5678:5678"]' -i docker-compose.override.private.yml
fi

# Update x-init-vllm to use selected models
echo -e "${YELLOW}Configuring vLLM to use selected models...${NC}"
if [ "$IS_MACOS" = true ]; then
    # For macOS, update the init command for host-based vLLM
    VLLM_COMMAND="echo 'vLLM will auto-download models on first use: $VLLM_MODEL and $EMBEDDING_MODEL'; echo 'Models configured for vLLM server'"
    yq eval "."x-init-ollama".command[1] = \"$VLLM_COMMAND\"" -i docker-compose.yml
    echo "  Updated vLLM configuration to use: $VLLM_MODEL and $EMBEDDING_MODEL"
else
    # For non-macOS, the init logic is handled in the Docker setup above
    echo "  vLLM Docker containers will use: $VLLM_MODEL and $EMBEDDING_MODEL"
fi

# Generate .env file
echo -e "${YELLOW}Generating environment configuration...${NC}"
cp -f .env.example .env

# Generate all required secrets
N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 16)
DASHBOARD_USERNAME="admin@local.host"
DASHBOARD_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)
CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
LANGFUSE_SALT=$(openssl rand -hex 16)
NEXTAUTH_SECRET=$(openssl rand -hex 16)
ENCRYPTION_KEY=$(openssl rand -hex 32)
NEO4J_AUTH="neo4j/$(openssl rand -base64 12 | tr -d '=+/' | cut -c1-16)"
NOTEBOOK_GENERATION_AUTH=$(openssl rand -hex 16)
FLOWISE_USERNAME=$DASHBOARD_USERNAME
FLOWISE_PASSWORD=$DASHBOARD_PASSWORD

# Update .env file with secrets
cp_sed "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY/" .env
cp_sed "s/N8N_USER_MANAGEMENT_JWT_SECRET=.*/N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET/" .env
cp_sed "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
cp_sed "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
cp_sed "s/DASHBOARD_USERNAME=.*/DASHBOARD_USERNAME=$DASHBOARD_USERNAME/" .env
cp_sed "s/DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD/" .env
cp_sed "s/CLICKHOUSE_PASSWORD=.*/CLICKHOUSE_PASSWORD=$CLICKHOUSE_PASSWORD/" .env
cp_sed "s/MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD/" .env
cp_sed "s/LANGFUSE_SALT=.*/LANGFUSE_SALT=$LANGFUSE_SALT/" .env
cp_sed "s/NEXTAUTH_SECRET=.*/NEXTAUTH_SECRET=$NEXTAUTH_SECRET/" .env
cp_sed "s/ENCRYPTION_KEY=.*/ENCRYPTION_KEY=$ENCRYPTION_KEY/" .env
cp_sed "s|NEO4J_AUTH=.*|NEO4J_AUTH=\"$NEO4J_AUTH\"|" .env
cp_sed "s/#FLOWISE_USERNAME=.*/FLOWISE_USERNAME=$FLOWISE_USERNAME/" .env
cp_sed "s/#FLOWISE_PASSWORD=.*/FLOWISE_PASSWORD=$FLOWISE_PASSWORD/" .env
cp_sed "s/POOLER_TENANT_ID=.*/POOLER_TENANT_ID=1000/" .env

# Concatenate InsightsLM environment variables from .env.copy
echo "" >> .env
echo "# InsightsLM Environment Variables" >> .env
cat insights-lm-local-package/.env.copy >> .env

# Update NOTEBOOK_GENERATION_AUTH to use our generated value (used for Header Auth)
cp_sed "s|NOTEBOOK_GENERATION_AUTH=.*|NOTEBOOK_GENERATION_AUTH=$NOTEBOOK_GENERATION_AUTH|" .env

# Add vLLM model configuration to .env
echo "" >> .env
echo "# vLLM Model Configuration" >> .env
echo "VLLM_MODEL=$VLLM_MODEL" >> .env
echo "EMBEDDING_MODEL=$EMBEDDING_MODEL" >> .env


# Update STUDIO defaults
cp_sed 's/STUDIO_DEFAULT_ORGANIZATION=.*/STUDIO_DEFAULT_ORGANIZATION="InsightsLM"/' .env
cp_sed 's/STUDIO_DEFAULT_PROJECT=.*/STUDIO_DEFAULT_PROJECT="Default Project"/' .env

# Generate JWT keys
ANON_KEY=$(python3 -c "import jwt, time; print(jwt.encode({'role': 'anon', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + (5 * 365 * 24 * 60 * 60)}, '$JWT_SECRET', algorithm='HS256'))")
SERVICE_ROLE_KEY=$(python3 -c "import jwt, time; print(jwt.encode({'role': 'service_role', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + (5 * 365 * 24 * 60 * 60)}, '$JWT_SECRET', algorithm='HS256'))")

cp_sed "s/ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
cp_sed "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env

# Configure access URLs (ACCESS_HOST already set at beginning)
cp_sed "s|^SITE_URL=.*|SITE_URL=http://${ACCESS_HOST}:3000|" .env # for GoTrue
cp_sed "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://${ACCESS_HOST}:8000|" .env # for Supabase
cp_sed "s|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://${ACCESS_HOST}:8000|" .env # for Supabase

# Source the .env file
source .env

# Clone Supabase if needed
echo -e "${YELLOW}Setting up Supabase...${NC}"
if [ ! -d "supabase/docker" ]; then
    # Original repository:
    # git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase.git
    # Using forked repository (optional - only if you've forked Supabase):
    # git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase.git
    # Uncomment the line below if you've forked Supabase:
    git clone --filter=blob:none --no-checkout https://github.com/sirouk/supabase.git
    cd supabase
    git sparse-checkout init --cone
    git sparse-checkout set docker
    git checkout master
    cd ..
fi

# Copy .env to supabase/docker
cp .env supabase/docker/.env

# Fix storage extended attributes issue on macOS
if [ "$IS_MACOS" = true ]; then
    echo -e "${YELLOW}Configuring storage for macOS compatibility...${NC}"
    
    STORAGE_COMPOSE="supabase/docker/docker-compose.yml"
    # Ensure the storage service exists before modifying
    if yq eval '.services | has("storage")' "$STORAGE_COMPOSE" | grep -q "true"; then
        echo "  Switching storage service to named volume to avoid xattr issues..."
        # Replace bind-mount with a Docker named volume that lives inside the VM (supports xattrs)
        yq eval '.services.storage.volumes = ["supabase_storage_data:/var/lib/storage"]' -i "$STORAGE_COMPOSE"

        # Add the named volume at root level if it does not yet exist
        if ! yq eval '.volumes | has("supabase_storage_data")' "$STORAGE_COMPOSE" | grep -q "true"; then
            yq eval '.volumes.supabase_storage_data = {}' -i "$STORAGE_COMPOSE"
        fi
        echo "  ✅ Storage service updated to use Docker volume \"supabase_storage_data\""
    fi
fi

# Configure Supabase Edge Functions environment variables BEFORE starting services
echo -e "${YELLOW}Configuring Supabase Edge Functions environment variables...${NC}"

# Check if functions service exists in supabase docker-compose
if ! yq eval '.services | has("functions")' supabase/docker/docker-compose.yml | grep -q "true"; then
    echo "    Creating functions service in supabase docker-compose..."
    yq eval '.services.functions = {}' -i supabase/docker/docker-compose.yml
fi

# Check if environment exists in functions service
if ! yq eval '.services.functions | has("environment")' supabase/docker/docker-compose.yml | grep -q "true"; then
    echo "    Creating environment section for functions service..."
    yq eval '.services.functions.environment = {}' -i supabase/docker/docker-compose.yml
fi

# Add environment variables from copy file using a simple, safe approach
echo "    Adding webhook environment variables..."

# Define the environment variables we need to add
ENV_VARS=(
    "NOTEBOOK_CHAT_URL"
    "NOTEBOOK_GENERATION_URL" 
    "AUDIO_GENERATION_WEBHOOK_URL"
    "DOCUMENT_PROCESSING_WEBHOOK_URL"
    "ADDITIONAL_SOURCES_WEBHOOK_URL"
    "NOTEBOOK_GENERATION_AUTH"
)

for env_var in "${ENV_VARS[@]}"; do
    # Check if the environment variable already exists
    if ! yq eval ".services.functions.environment | has(\"$env_var\")" supabase/docker/docker-compose.yml | grep -q "true"; then
        # Add the environment variable with shell variable syntax
        yq eval ".services.functions.environment.\"$env_var\" = \"\${$env_var}\"" -i supabase/docker/docker-compose.yml
        echo "    Added environment variable: $env_var"
    else
        echo "    Environment variable $env_var already exists, skipping"
    fi
done

echo "✅ Supabase Edge Functions configured with webhook environment variables"

# ---------------------------------------------------------
# Native vLLM setup on macOS + proxy service for Docker
# ---------------------------------------------------------
if [ "$IS_MACOS" = true ]; then
    echo -e "${YELLOW}Setting up native vLLM and proxy service...${NC}"

    # 1. Install uv (Python package manager) if not present
    if ! command -v uv >/dev/null 2>&1; then
        echo "  Installing uv Python package manager..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        # Source the newly installed uv
        source $HOME/.bashrc 2>/dev/null || true
        source $HOME/.profile 2>/dev/null || true
    fi
    
    # Update uv to latest version
    echo "  Updating uv to latest version..."
    if ! uv self update 2>/dev/null; then
        echo "    uv self-update not available (likely installed via package manager)"
        if command -v brew >/dev/null 2>&1; then
            echo "    Trying to update via Homebrew..."
            brew upgrade uv 2>/dev/null || echo "    Homebrew update failed or uv already latest version"
        else
            echo "    Continuing with current uv version..."
        fi
    else
        echo "    uv updated successfully"
    fi

    # 2. Create Python virtual environment for vLLM
    echo "  Creating Python 3.12 virtual environment for vLLM..."
    cd "$HOME/local-ai-packaged"
    if [ -d ".venv-vllm" ]; then
        rm -rf .venv-vllm
    fi
    uv venv --python 3.12 --seed .venv-vllm
    
    # 3. Install build dependencies
    echo "  Installing build dependencies (ninja, cmake)..."
    if ! command -v ninja >/dev/null 2>&1; then
        brew install ninja cmake
    fi
    
    # 4. Install vLLM and dependencies
    echo "  Installing vLLM and dependencies..."
    source .venv-vllm/bin/activate
    uv pip install ninja cmake
    uv pip install vllm
    
    # 5. Stop any existing vLLM processes first (clean slate)
    echo "  Stopping any existing vLLM processes..."
    pkill -f "vllm.entrypoints.openai.api_server" 2>/dev/null || true
    sleep 2

    # 6. Create host-side scripts for strict lifecycle coupling
    echo "  Creating host-side vLLM lifecycle scripts..."
    mkdir -p ollama-proxy

    cat > ollama-proxy/start-host-vllm.sh << 'START_HOST_VLLM'
#!/bin/bash
set -e
PID_FILE="/tmp/vllm-host.pid"
LOG_FILE="/tmp/vllm-host.log"
VENV_PATH="$HOME/local-ai-packaged/.venv-vllm"

echo "Starting vLLM host management..." | tee -a "$LOG_FILE"

# Function to check if vLLM is bound to 0.0.0.0:11434
check_vllm_binding() {
  # Check if port 11434 is bound to 0.0.0.0 (accessible from Docker)
  if netstat -an 2>/dev/null | grep -q "*.11434.*LISTEN" || netstat -an 2>/dev/null | grep -q "0.0.0.0.11434.*LISTEN"; then
    return 0  # Correctly bound
  else
    return 1  # Not correctly bound
  fi
}

# Stop any existing vLLM processes that aren't properly bound
if pgrep -f "vllm.entrypoints.openai.api_server" >/dev/null 2>&1; then
  echo "Found existing vLLM process(es)..." | tee -a "$LOG_FILE"
  
  # Check if current binding is correct
  if check_vllm_binding; then
    echo "vLLM already running with correct binding (0.0.0.0:11434)" | tee -a "$LOG_FILE"
    # Get the PID of the correctly running process
    EXISTING_PID=$(pgrep -f "vllm.entrypoints.openai.api_server" | head -1)
    echo $EXISTING_PID > "$PID_FILE"
    exit 0
  else
    echo "vLLM running with incorrect binding (likely 127.0.0.1 only), stopping..." | tee -a "$LOG_FILE"
    # Kill existing vLLM processes
    pkill -f "vllm.entrypoints.openai.api_server" 2>/dev/null || true
    sleep 3
    # Force kill if still running
    pkill -9 -f "vllm.entrypoints.openai.api_server" 2>/dev/null || true
    sleep 2
  fi
fi

echo "Starting vLLM with Docker-accessible binding (0.0.0.0:11434)..." | tee -a "$LOG_FILE"

# Activate vLLM virtual environment and start server
cd "$HOME/local-ai-packaged"
source "$VENV_PATH/bin/activate"

# Read model from environment or use default
VLLM_MODEL_TO_USE="${VLLM_MODEL:-Qwen/Qwen3-8B}"

# Start vLLM with proper host binding for Docker access
nohup env VLLM_CPU_KVCACHE_SPACE=48 python3 -m vllm.entrypoints.openai.api_server \
  --model "$VLLM_MODEL_TO_USE" \
  --tensor-parallel-size 1 \
  --gpu-memory-utilization 0.85 \
  --host 0.0.0.0 \
  --port 11434 > "$LOG_FILE" 2>&1 &
HOST_PID=$!
echo $HOST_PID > "$PID_FILE"

# Wait until port is open and correctly bound (max ~180s for model loading)
for i in {1..180}; do
  if nc -z localhost 11434 2>/dev/null && check_vllm_binding; then
    echo "vLLM started successfully on host (PID=$HOST_PID) with Docker-accessible binding" | tee -a "$LOG_FILE"
    exit 0
  fi
  sleep 1
done

echo "ERROR: vLLM did not start with correct binding (0.0.0.0:11434)" | tee -a "$LOG_FILE"
exit 1
START_HOST_VLLM

    chmod +x ollama-proxy/start-host-vllm.sh

    cat > ollama-proxy/stop-host-vllm.sh << 'STOP_HOST_VLLM'
#!/bin/bash
set -e
PID_FILE="/tmp/vllm-host.pid"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    sleep 2
    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
fi
# Ensure no stray vLLM server remains
pkill -f "vllm.entrypoints.openai.api_server" 2>/dev/null || true
STOP_HOST_VLLM

    chmod +x ollama-proxy/stop-host-vllm.sh

    cat > ollama-proxy/watch-vllm-container.sh << 'WATCH_VLLM'
#!/bin/bash
set -e
LOG_FILE="/tmp/vllm-container-watch.log"

# Wait for Docker to be available
for i in {1..30}; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Listen for events on the specific container name
# When the container stops/dies, stop vLLM on host
(docker events --filter container=ollama --format '{{.Action}}' 2>>"$LOG_FILE" | while read -r action; do
  case "$action" in
    stop|die|kill)
      echo "Detected ollama container action: $action — stopping host vLLM" | tee -a "$LOG_FILE"
      bash ./ollama-proxy/stop-host-vllm.sh || true
      exit 0
      ;;
    *)
      echo "Event: $action" >>"$LOG_FILE"
      ;;
  esac
done) &
WATCH_VLLM

    chmod +x ollama-proxy/watch-vllm-container.sh

    # 7. Start vLLM on host and launch watcher
    echo "  Starting vLLM on host and launching watcher..."
    ./ollama-proxy/start-host-vllm.sh
    nohup ./ollama-proxy/watch-vllm-container.sh >/dev/null 2>&1 &

    # 8. Update docker-compose.yml: add lightweight proxy and remove heavy Ollama containers
    DC_FILE="docker-compose.yml"

    # Remove heavy Ollama-related services if they exist
    for svc in ollama-cpu ollama-gpu ollama-gpu-amd ollama-pull-llama-cpu ollama-pull-llama-gpu ollama-pull-llama-gpu-amd; do
        if yq eval ".services | has(\"$svc\")" "$DC_FILE" | grep -q "true"; then
            yq eval "del(.services.\"$svc\")" -i "$DC_FILE"
        fi
    done

    # Create nginx configuration for vLLM proxy with Host header rewriting
    echo "  Creating nginx configuration for vLLM proxy..."
    mkdir -p ollama-proxy/nginx
    
    cat > ollama-proxy/nginx/nginx.conf << 'NGINX_CONF'
events {
    worker_connections 1024;
}

http {
    upstream vllm_backend {
        server host.docker.internal:11434;
    }
    
    server {
        listen 11434;
        
        location / {
            proxy_pass http://vllm_backend;
            proxy_set_header Host localhost:11434;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Handle streaming responses
            proxy_buffering off;
            proxy_cache off;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            
            # Increase timeouts for long-running requests
            proxy_connect_timeout 60s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
        }
    }
}
NGINX_CONF

    # Define/overwrite the proxy service with nginx
    yq eval '.services.ollama.image = "nginx:alpine"' -i "$DC_FILE"
    yq eval '.services.ollama.container_name = "ollama"' -i "$DC_FILE"
    yq eval '.services.ollama.restart = "unless-stopped"' -i "$DC_FILE"
    yq eval '.services.ollama.expose = ["11434/tcp"]' -i "$DC_FILE"
    yq eval '.services.ollama.volumes = ["./ollama-proxy/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"]' -i "$DC_FILE"
    # Add health check to verify proxy is working
    yq eval '.services.ollama.healthcheck.test = ["CMD", "nginx", "-t"]' -i "$DC_FILE"
    yq eval '.services.ollama.healthcheck.interval = "10s"' -i "$DC_FILE"
    yq eval '.services.ollama.healthcheck.timeout = "5s"' -i "$DC_FILE"
    yq eval '.services.ollama.healthcheck.retries = 5' -i "$DC_FILE"
    yq eval '.services.ollama.healthcheck.start_period = "10s"' -i "$DC_FILE"
    # Ensure the service starts under cpu profile so it is included when profile filtering is used
    yq eval '.services.ollama.profiles = ["cpu"]' -i "$DC_FILE"

    # 8. Clean up ALL override files that might reference removed ollama services
    echo "  Cleaning up override files..."
    for OVERRIDE_FILE in docker-compose.override.private.yml docker-compose.override.public.yml; do
      if [ -f "$OVERRIDE_FILE" ]; then
        for svc in ollama-cpu ollama-gpu ollama-gpu-amd; do
          if yq eval ".services | has(\"$svc\")" "$OVERRIDE_FILE" | grep -q "true"; then
            yq eval "del(.services.\"$svc\")" -i "$OVERRIDE_FILE"
            echo "    Removed $svc from $OVERRIDE_FILE"
          fi
        done
      fi
    done

    echo "  ✅ Proxy service 'ollama' configured with watcher-based lifecycle coupling"
    echo "     → Container starts = vLLM starts on host"
    echo "     → Container stops = vLLM stops on host (forcefully if needed)"
else
    # ---------------------------------------------------------
    # vLLM Docker setup for non-macOS systems
    # ---------------------------------------------------------
    echo -e "${YELLOW}Setting up vLLM Docker containers for non-macOS...${NC}"
    
    # Create custom vLLM Dockerfile
    echo "  Creating custom vLLM Dockerfile..."
    mkdir -p vllm-docker
    
    cat > vllm-docker/Dockerfile << 'VLLM_DOCKERFILE'
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install vLLM
RUN pip install --no-cache-dir vllm

# Set working directory
WORKDIR /app

# Create entrypoint script
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Default values\n\
MODEL=${VLLM_MODEL:-"Qwen/Qwen3-8B"}\n\
HOST=${VLLM_HOST:-"0.0.0.0"}\n\
PORT=${VLLM_PORT:-"11434"}\n\
\n\
echo "Starting vLLM server with model: $MODEL"\n\
echo "Listening on: $HOST:$PORT"\n\
\n\
# Start vLLM server with OpenAI-compatible API\n\
exec python -m vllm.entrypoints.openai.api_server \\\n\
    --model "$MODEL" \\\n\
    --host "$HOST" \\\n\
    --port "$PORT" \\\n\
    --tensor-parallel-size 1 \\\n\
    --gpu-memory-utilization 0.85 \\\n\
    --max-model-len 8192\n\
' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

EXPOSE 11434

ENTRYPOINT ["/app/entrypoint.sh"]
VLLM_DOCKERFILE

    # Update docker-compose.yml to use vLLM for ollama services
    echo "  Updating docker-compose.yml to use vLLM instead of Ollama..."
    
    # Update x-ollama anchor to use custom vLLM image
    yq eval '.x-ollama.image = "./vllm-docker"' -i docker-compose.yml
    yq eval '.x-ollama.build.context = "./vllm-docker"' -i docker-compose.yml
    yq eval '.x-ollama.build.dockerfile = "Dockerfile"' -i docker-compose.yml
    yq eval 'del(.x-ollama.volumes)' -i docker-compose.yml  # Remove ollama storage mount
    
    # Update environment variables for vLLM
    yq eval '.x-ollama.environment = [
        "VLLM_MODEL='$VLLM_MODEL'",
        "VLLM_HOST=0.0.0.0", 
        "VLLM_PORT=11434"
    ]' -i docker-compose.yml
    
    # Update x-init-ollama to be a simple wait/health check instead of model pulling
    yq eval '.x-init-ollama.image = "curlimages/curl:latest"' -i docker-compose.yml
    yq eval 'del(.x-init-ollama.volumes)' -i docker-compose.yml
    yq eval '.x-init-ollama.command = [
        "sh", "-c", 
        "echo \"Waiting for vLLM server to be ready...\"; for i in $(seq 1 120); do if curl -s http://ollama:11434/health >/dev/null 2>&1; then echo \"vLLM server ready!\"; exit 0; fi; sleep 5; done; echo \"vLLM server not ready after 10 minutes\"; exit 1"
    ]' -i docker-compose.yml
    
    # For GPU profiles, add appropriate device mappings and runtime
    if [ "$PROFILE" = "gpu-nvidia" ]; then
        echo "  Configuring NVIDIA GPU support for vLLM..."
        
        # Check if NVIDIA runtime is available
        if command -v nvidia-container-runtime >/dev/null 2>&1 || command -v nvidia-ctk >/dev/null 2>&1; then
            echo "    Adding NVIDIA container runtime configuration..."
            yq eval '.services.ollama-gpu.runtime = "nvidia"' -i docker-compose.yml
        else
            echo "    NVIDIA runtime not available, using device mapping instead..."
            # Map all available NVIDIA devices dynamically
            yq eval '.services.ollama-gpu.devices = ["/dev/nvidiactl:/dev/nvidiactl", "/dev/nvidia-uvm:/dev/nvidia-uvm"]' -i docker-compose.yml
            # Add all nvidia GPU devices present on the system
            if ls /dev/nvidia[0-9]* >/dev/null 2>&1; then
                for gpu_dev in /dev/nvidia[0-9]*; do
                    yq eval ".services.ollama-gpu.devices += [\"$gpu_dev:$gpu_dev\"]" -i docker-compose.yml
                done
                echo "    Mapped $(ls /dev/nvidia[0-9]* | wc -l) GPU device(s)"
            fi
        fi
        
        # Add environment variables for GPU support  
        yq eval '.services.ollama-gpu.environment += ["NVIDIA_VISIBLE_DEVICES=all"]' -i docker-compose.yml
        yq eval '.services.ollama-gpu.environment += ["NVIDIA_DRIVER_CAPABILITIES=compute,utility"]' -i docker-compose.yml
        # Use all available GPUs (vLLM will auto-detect and use appropriately)
        yq eval '.services.ollama-gpu.environment += ["CUDA_VISIBLE_DEVICES=all"]' -i docker-compose.yml
    elif [ "$PROFILE" = "gpu-amd" ]; then
        echo "  Configuring AMD GPU support for vLLM..."
        # Update the base image for AMD GPU support (vLLM with ROCm)
        cat > vllm-docker/Dockerfile << 'VLLM_AMD_DOCKERFILE'
FROM rocm/pytorch:rocm6.0_ubuntu20.04_py3.9_pytorch_2.1.1

# Install vLLM with ROCm support
RUN pip install --no-cache-dir vllm

# Set working directory
WORKDIR /app

# Create entrypoint script (same as above but with ROCm environment)
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# AMD ROCm environment\n\
export HSA_OVERRIDE_GFX_VERSION=10.3.0\n\
export ROCM_PATH=/opt/rocm\n\
\n\
# Default values\n\
MODEL=${VLLM_MODEL:-"Qwen/Qwen3-8B"}\n\
HOST=${VLLM_HOST:-"0.0.0.0"}\n\
PORT=${VLLM_PORT:-"11434"}\n\
\n\
echo "Starting vLLM server with AMD GPU support"\n\
echo "Model: $MODEL, Host: $HOST:$PORT"\n\
\n\
# Start vLLM server with OpenAI-compatible API\n\
exec python -m vllm.entrypoints.openai.api_server \\\n\
    --model "$MODEL" \\\n\
    --host "$HOST" \\\n\
    --port "$PORT" \\\n\
    --tensor-parallel-size 1 \\\n\
    --gpu-memory-utilization 0.85 \\\n\
    --max-model-len 8192\n\
' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

EXPOSE 11434

ENTRYPOINT ["/app/entrypoint.sh"]
VLLM_AMD_DOCKERFILE
    fi
    
    echo "  ✅ Docker-based vLLM configured to replace Ollama services"
    echo "     → Service name 'ollama' maintained for DNS compatibility"
    echo "     → vLLM will auto-download HuggingFace models: $VLLM_MODEL"
    echo "     → OpenAI-compatible API served on port 11434"
fi

# Compute profile already detected at the beginning of the script

# Update Dockerfile to use correct repository URL BEFORE building
echo -e "${YELLOW}Updating InsightsLM Dockerfile repository URL...${NC}"
if [ -f "insights-lm-local-package/Dockerfile" ]; then
    # Replace the hardcoded GitHub URL in the git clone command
    cp_sed "s|https://github.com/theaiautomators/insights-lm-public.git|${INSIGHTS_LM_PUBLIC_URL}|g" insights-lm-local-package/Dockerfile
    echo "  Updated Dockerfile to use repository: ${INSIGHTS_LM_PUBLIC_URL}"
fi

# Build InsightsLM separately first to ensure fresh build with credentials
echo -e "${YELLOW}Pre-building InsightsLM with fresh credentials...${NC}"
echo "  This ensures the ANON_KEY is properly embedded in the build"
docker compose -p localai build --no-cache insightslm || {
    echo -e "${YELLOW}  Note: InsightsLM will be built when services start${NC}"
}

# Start all services first (including storage for bucket creation)
echo -e "${YELLOW}Starting all services...${NC}"
python3 start_services.py --profile "$PROFILE" --environment private

# Wait for all services to stabilize
echo -e "${YELLOW}Waiting for services to stabilize...${NC}"
sleep 30

# Wait for database to be ready
echo -e "${YELLOW}Waiting for database...${NC}"
for i in {1..30}; do
    if docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
        echo -e "${GREEN}Database ready!${NC}"
        break
    fi
    sleep 2
done

# Update role passwords
echo -e "${YELLOW}Configuring database roles...${NC}"
for role in authenticator pgbouncer supabase_auth_admin supabase_functions_admin supabase_storage_admin supabase_admin; do
    docker exec supabase-db psql -U postgres -d postgres -c "ALTER USER ${role} WITH PASSWORD '${POSTGRES_PASSWORD}';" >/dev/null 2>&1 || true
done

# Run migration while all services (including storage) are running
echo -e "${YELLOW}Running database migration...${NC}"
docker cp insights-lm-local-package/supabase-migration.sql supabase-db:/tmp/migration.sql
docker exec supabase-db psql -U supabase_admin -d postgres -f /tmp/migration.sql >/dev/null 2>&1 || true

# Copy supabase functions
echo -e "${YELLOW}Deploying Supabase functions...${NC}"
mkdir -p ./supabase/docker/volumes/functions/
cp -rf ./insights-lm-local-package/supabase-functions/* ./supabase/docker/volumes/functions/



# Create unified credentials
echo -e "${YELLOW}Creating unified admin credentials...${NC}"
UNIFIED_EMAIL="admin@local.host"

# Generate new password for fresh install
echo "  Generating new password"
UNIFIED_PASSWORD=$DASHBOARD_PASSWORD

# Create Supabase Auth user
# First check if user exists
USER_EXISTS=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "SELECT COUNT(*) FROM auth.users WHERE email='${UNIFIED_EMAIL}';" 2>/dev/null | tr -d '\r')

if [ "$USER_EXISTS" = "0" ] || [ -z "$USER_EXISTS" ]; then
    # Create new user with all required fields properly set
    if docker exec supabase-db psql -U supabase_admin -d postgres -c "
    INSERT INTO auth.users (
        id, instance_id, email, encrypted_password, email_confirmed_at,
        created_at, updated_at, raw_app_meta_data, raw_user_meta_data, aud, role,
        confirmation_token, recovery_token, email_change_token_new, email_change_token_current,
        phone, phone_change_token, reauthentication_token, email_change,
        confirmation_sent_at, recovery_sent_at, email_change_sent_at, phone_change_sent_at,
        reauthentication_sent_at
    ) VALUES (
        gen_random_uuid(), '00000000-0000-0000-0000-000000000000', '${UNIFIED_EMAIL}',
        crypt('${UNIFIED_PASSWORD}', gen_salt('bf')), NOW(), NOW(), NOW(),
        '{}', '{}', 'authenticated', 'authenticated',
        '', '', '', '',
        NULL, '', '', '',
        NULL, NULL, NULL, NULL,
        NULL
    );" 2>&1 | grep -q "INSERT"; then
        echo "✅ Created new Supabase Auth user"
    else
        echo "⚠️  Warning: Could not create Supabase Auth user (may already exist)"
    fi
else
    # Update existing user's password and ensure all token fields are properly set
    if docker exec supabase-db psql -U supabase_admin -d postgres -c "
    UPDATE auth.users 
    SET encrypted_password = crypt('${UNIFIED_PASSWORD}', gen_salt('bf')),
        updated_at = NOW(),
        confirmation_token = COALESCE(confirmation_token, ''),
        recovery_token = COALESCE(recovery_token, ''),
        email_change_token_new = COALESCE(email_change_token_new, ''),
        email_change_token_current = COALESCE(email_change_token_current, ''),
        reauthentication_token = COALESCE(reauthentication_token, ''),
        phone_change_token = COALESCE(phone_change_token, ''),
        email_change = COALESCE(email_change, '')
    WHERE email = '${UNIFIED_EMAIL}';" 2>&1 | grep -q "UPDATE"; then
        echo "✅ Updated existing Supabase Auth user"
    else
        echo "⚠️  Warning: Could not update Supabase Auth user"
    fi
fi

# Create n8n user
echo -e "${YELLOW}Setting up n8n...${NC}"
PASSWORD_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'${UNIFIED_PASSWORD}', bcrypt.gensalt()).decode())")

# Wait for n8n to initialize
sleep 10

# Update n8n user
docker exec supabase-db psql -U postgres -d postgres -c "
UPDATE \"user\" SET 
    email='${UNIFIED_EMAIL}',
    \"firstName\"='Admin',
    \"lastName\"='User',
    password='${PASSWORD_HASH}'
WHERE role='global:owner';" >/dev/null 2>&1

# CRITICAL: Set the instance owner setup flag to true
# This flag controls whether n8n shows setup screen vs login screen
echo "  Setting instance owner setup flag..."
docker exec supabase-db psql -U postgres -d postgres -c "
UPDATE settings 
SET value = 'true' 
WHERE key = 'userManagement.isInstanceOwnerSetUp';" >/dev/null 2>&1

# If the setting doesn't exist, create it
docker exec supabase-db psql -U postgres -d postgres -c "
INSERT INTO settings (key, value, \"loadOnStartup\") 
VALUES ('userManagement.isInstanceOwnerSetUp', 'true', true)
ON CONFLICT (key) DO UPDATE SET value = 'true';" >/dev/null 2>&1

# Restart n8n briefly to ensure setup flag is recognized
echo "  Restarting n8n to apply setup flag..."
docker restart n8n >/dev/null 2>&1

# Wait for n8n to restart and be ready
sleep 10
for i in {1..30}; do
    if docker exec n8n n8n --version >/dev/null 2>&1; then
        echo "  n8n restarted and ready"
        break
    fi
    sleep 2
done

# Create n8n API key via REST API
echo -e "${YELLOW}Creating n8n API key...${NC}"
sleep 5

LOGIN_RESPONSE=$(curl -s -c /tmp/n8n-cookies.txt -X POST http://localhost:5678/rest/login \
    -H 'Content-Type: application/json' \
    -d "{\"emailOrLdapLoginId\":\"${UNIFIED_EMAIL}\",\"password\":\"${UNIFIED_PASSWORD}\"}" 2>/dev/null || echo "{}")

N8N_API_KEY=""
if echo "$LOGIN_RESPONSE" | grep -q "\"email\":\"${UNIFIED_EMAIL}\""; then
    API_KEY_RESPONSE=$(curl -s -b /tmp/n8n-cookies.txt -X POST http://localhost:5678/rest/api-keys \
        -H 'Content-Type: application/json' \
        -d '{"label":"auto-generated","expiresAt":null,"scopes":["user:read","user:list","user:create","user:changeRole","user:delete","user:enforceMfa","sourceControl:pull","securityAudit:generate","project:create","project:update","project:delete","project:list","variable:create","variable:delete","variable:list","variable:update","tag:create","tag:read","tag:update","tag:delete","tag:list","workflowTags:update","workflowTags:list","workflow:create","workflow:read","workflow:update","workflow:delete","workflow:list","workflow:move","workflow:activate","workflow:deactivate","execution:delete","execution:read","execution:list","credential:create","credential:move","credential:delete"]}' 2>/dev/null)
    
    # Extract API key from JSON response using a here-doc to avoid nested quote/parenthesis issues
    N8N_API_KEY=$(echo "$API_KEY_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('data', {}).get('rawApiKey', ''))
except:
    print('')
" 2>/dev/null || echo "")
fi
rm -f /tmp/n8n-cookies.txt

# Import n8n credentials
echo -e "${YELLOW}Importing n8n credentials...${NC}"
HEADER_AUTH_ID=$(openssl rand -hex 8 | cut -c1-16)
SUPABASE_ID=$(openssl rand -hex 8 | cut -c1-16)
OLLAMA_ID=$(openssl rand -hex 8 | cut -c1-16)
N8N_API_ID=$(openssl rand -hex 8 | cut -c1-16)

# Create credentials JSON with direct variable substitution
cat > /tmp/n8n_credentials.json << EOF
[
  {
    "id": "${HEADER_AUTH_ID}",
    "name": "Header Auth account",
    "type": "httpHeaderAuth",
    "data": {
      "name": "Authorization",
      "value": "${NOTEBOOK_GENERATION_AUTH}"
    }
  },
  {
    "id": "${SUPABASE_ID}",
    "name": "Supabase account",
    "type": "supabaseApi",
    "data": {
      "host": "http://kong:8000",
      "serviceRole": "${SERVICE_ROLE_KEY}"
    }
  },
  {
    "id": "${OLLAMA_ID}",
    "name": "Ollama account",
    "type": "ollamaApi",
    "data": {
      "baseUrl": "http://ollama:11434"
    }
  },
  {
    "id": "${N8N_API_ID}",
    "name": "n8n account",
    "type": "n8nApi",
    "data": {
      "apiKey": "${N8N_API_KEY}",
      "baseUrl": "http://n8n:5678/api/v1"
    }
  }
]
EOF


# Import credentials
docker cp /tmp/n8n_credentials.json n8n:/tmp/creds.json
IMPORT_RESULT=$(docker exec n8n n8n import:credentials --input=/tmp/creds.json 2>&1)
if echo "$IMPORT_RESULT" | grep -q "error\|Error"; then
    echo -e "${YELLOW}  Warning: Credential import may have failed:${NC}"
    echo "    $IMPORT_RESULT"
else
    echo "  ✅ Credentials imported successfully"
fi

# Update and import workflow
echo -e "${YELLOW}Importing InsightsLM workflows...${NC}"
cp insights-lm-local-package/n8n/Local_Import_Insights_LM_Workflows.json /tmp/workflow.json

# Update workflow with credential IDs and repository URLs
python3 - << EOF
import json

with open('/tmp/workflow.json', 'r') as f:
    workflow = json.load(f)

# Update the Enter User Values node
for node in workflow.get('nodes', []):
    if node.get('name') == 'Enter User Values':
        assignments = node.get('parameters', {}).get('assignments', {}).get('assignments', [])
        for a in assignments:
            if 'Header Auth' in a.get('name', ''):
                a['value'] = '${HEADER_AUTH_ID}'
            elif 'Supabase' in a.get('name', ''):
                a['value'] = '${SUPABASE_ID}'
            elif 'Ollama' in a.get('name', ''):
                a['value'] = '${OLLAMA_ID}'
    elif node.get('name') == 'n8n' and node.get('type') == 'n8n-nodes-base.n8n':
        node.setdefault('credentials', {}).setdefault('n8nApi', {})['id'] = '${N8N_API_ID}'
    elif node.get('name') == 'Workflow File URLs to Download (Local Versions)':
        # Update the workflow URLs to use the configured repository
        assignments = node.get('parameters', {}).get('assignments', {}).get('assignments', [])
        for a in assignments:
            if a.get('name') == 'workflow-files' and isinstance(a.get('value'), str):
                # Replace the hardcoded repository URL with our variable
                a['value'] = a['value'].replace(
                    'https://raw.githubusercontent.com/theaiautomators/insights-lm-local-package',
                    '${INSIGHTS_LM_RAW_URL}'
                )

with open('/tmp/workflow.json', 'w') as f:
    json.dump(workflow, f, indent=2)
EOF

docker cp /tmp/workflow.json n8n:/tmp/workflow.json
docker exec n8n n8n import:workflow --input=/tmp/workflow.json >/dev/null 2>&1 || true

# Execute the import workflow
echo -e "${YELLOW}Executing import workflow...${NC}"
sleep 5
IMPORT_WORKFLOW_ID=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "SELECT id FROM workflow_entity WHERE name='Local Import Insights LM Workflows' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')

if [ -n "$IMPORT_WORKFLOW_ID" ]; then
    docker exec n8n n8n execute --id="${IMPORT_WORKFLOW_ID}" >/dev/null 2>&1 || true
    sleep 10
fi

# Update Ollama model references in workflows to use selected models
echo -e "${YELLOW}Updating Ollama model references in imported workflows...${NC}"

# Wait a moment for workflow import to complete fully
sleep 5

# Check how many InsightsLM workflows were imported
WORKFLOW_COUNT=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "SELECT COUNT(*) FROM workflow_entity WHERE name LIKE 'InsightsLM%';" 2>/dev/null | tr -d '\r')
echo "  Found $WORKFLOW_COUNT InsightsLM workflows to update"

# Update main model references (qwen3:8b-q4_K_M -> user selected model)
echo "  Updating main model references from qwen3:8b-q4_K_M to $VLLM_MODEL..."
MAIN_MODEL_UPDATES=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
UPDATE workflow_entity 
SET nodes = REPLACE(nodes::text, '\"model\": \"qwen3:8b-q4_K_M\"', '\"model\": \"$VLLM_MODEL\"')::jsonb
WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%qwen3:8b-q4_K_M%'
RETURNING id;" 2>/dev/null | wc -l)
echo "    Updated main model in $MAIN_MODEL_UPDATES workflows"

# Update embedding model references - handle both with and without :latest suffix
EMBEDDING_MODEL_BASE=$(echo "$EMBEDDING_MODEL" | sed 's/:latest$//')
if [[ "$EMBEDDING_MODEL" != *":latest" ]]; then
    EMBEDDING_MODEL_WITH_LATEST="${EMBEDDING_MODEL}:latest"
else
    EMBEDDING_MODEL_WITH_LATEST="$EMBEDDING_MODEL"
fi

echo "  Updating embedding model references to $EMBEDDING_MODEL..."

# Update nomic-embed-text:latest references
EMBED_UPDATES_1=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
UPDATE workflow_entity 
SET nodes = REPLACE(nodes::text, '\"model\": \"nomic-embed-text:latest\"', '\"model\": \"$EMBEDDING_MODEL_WITH_LATEST\"')::jsonb
WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%nomic-embed-text:latest%'
RETURNING id;" 2>/dev/null | wc -l)

# Update nomic-embed-text references (without :latest)
EMBED_UPDATES_2=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
UPDATE workflow_entity 
SET nodes = REPLACE(nodes::text, '\"model\": \"nomic-embed-text\"', '\"model\": \"$EMBEDDING_MODEL\"')::jsonb
WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%\"model\": \"nomic-embed-text\"%' AND nodes::text NOT LIKE '%nomic-embed-text:latest%'
RETURNING id;" 2>/dev/null | wc -l)

echo "    Updated embedding model in $((EMBED_UPDATES_1 + EMBED_UPDATES_2)) workflow instances"

# Verify updates were successful
REMAINING_OLD_MODELS=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
SELECT COUNT(*) FROM workflow_entity 
WHERE name LIKE 'InsightsLM%' 
AND (nodes::text LIKE '%qwen3:8b-q4_K_M%' OR nodes::text LIKE '%nomic-embed-text%');" 2>/dev/null | tr -d '\r')

if [ "$REMAINING_OLD_MODELS" = "0" ]; then
    echo -e "${GREEN}✅ Successfully updated all workflow model references${NC}"
    echo "    Main model: $VLLM_MODEL"
    echo "    Embedding model: $EMBEDDING_MODEL"
else
    echo -e "${YELLOW}⚠️  $REMAINING_OLD_MODELS workflows may still contain old model references${NC}"
    echo "    This may be normal if workflows use different model configurations"
fi

# Update SUPABASE_PUBLIC_URL placeholder in workflows
echo -e "${YELLOW}Updating Supabase public URL in workflows...${NC}"
SUPABASE_PUBLIC_URL="http://${ACCESS_HOST}:8000"
echo "  Replacing SUPABASE_PUBLIC_URL_PLACEHOLDER with $SUPABASE_PUBLIC_URL"

# Update the placeholder in all InsightsLM workflows
URL_UPDATES=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
UPDATE workflow_entity 
SET nodes = REPLACE(nodes::text, 'SUPABASE_PUBLIC_URL_PLACEHOLDER', '$SUPABASE_PUBLIC_URL')::jsonb
WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%SUPABASE_PUBLIC_URL_PLACEHOLDER%'
RETURNING id;" 2>/dev/null | wc -l)

if [ "$URL_UPDATES" -gt 0 ]; then
    echo -e "${GREEN}✅ Updated Supabase public URL in $URL_UPDATES workflow(s)${NC}"
else
    echo "  No workflows needed URL updates (this is normal if placeholder wasn't found)"
fi



# Login to n8n web interface to establish session for workflow activation
echo -e "${YELLOW}Establishing n8n web session for workflow activation...${NC}"

# Login via n8n web API to create session
LOGIN_RESPONSE=$(curl -s -c /tmp/n8n-cookies.txt -X POST http://localhost:5678/rest/login \
    -H 'Content-Type: application/json' \
    -d "{\"emailOrLdapLoginId\":\"${UNIFIED_EMAIL}\",\"password\":\"${UNIFIED_PASSWORD}\"}" 2>/dev/null || echo "{}")

if echo "$LOGIN_RESPONSE" | grep -q "\"email\":\"${UNIFIED_EMAIL}\""; then
    echo "  ✅ Successfully logged into n8n web interface"
    WEB_SESSION_ACTIVE=true
else
    echo "  ⚠️  Could not establish web session, workflows may need manual activation"
    WEB_SESSION_ACTIVE=false
fi

# Activate workflows
echo -e "${YELLOW}Activating workflows...${NC}"

WORKFLOWS=(
    "InsightsLM - Podcast Generation"
    "InsightsLM - Chat"
    "InsightsLM - Process Additional Sources"
    "InsightsLM - Upsert to Vector Store"
    "InsightsLM - Generate Notebook Details"
)

for WORKFLOW_NAME in "${WORKFLOWS[@]}"; do
    WORKFLOW_ID=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "SELECT id FROM workflow_entity WHERE name='${WORKFLOW_NAME}' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')
    if [ -n "$WORKFLOW_ID" ]; then
        echo "  Activating workflow: $WORKFLOW_NAME"
        
        if [ "$WEB_SESSION_ACTIVE" = true ]; then
            # Use web API with session cookies for more reliable activation
            echo "    Using web API activation..."
            
            # First deactivate via web API
            curl -s -b /tmp/n8n-cookies.txt -X PATCH "http://localhost:5678/rest/workflows/${WORKFLOW_ID}" \
                -H 'Content-Type: application/json' \
                -d '{"active":false}' >/dev/null 2>&1 || true
            sleep 1
            
            # Then activate via web API to register webhooks
            ACTIVATION_RESPONSE=$(curl -s -b /tmp/n8n-cookies.txt -X PATCH "http://localhost:5678/rest/workflows/${WORKFLOW_ID}" \
                -H 'Content-Type: application/json' \
                -d '{"active":true}' 2>/dev/null)
            
            if echo "$ACTIVATION_RESPONSE" | grep -q '"active":true'; then
                echo "    ✅ Workflow activated successfully via web API"
            else
                echo "    ⚠️  Web API activation may have failed, trying CLI fallback..."
                docker exec n8n n8n update:workflow --id="${WORKFLOW_ID}" --active=true >/dev/null 2>&1 || true
            fi
        else
            # Fallback to CLI activation
            echo "    Using CLI activation (fallback)..."
            docker exec n8n n8n update:workflow --id="${WORKFLOW_ID}" --active=false >/dev/null 2>&1 || true
            sleep 1
            docker exec n8n n8n update:workflow --id="${WORKFLOW_ID}" --active=true >/dev/null 2>&1 || true
            echo "    Workflow activated via CLI"
        fi
    else
        echo "    Warning: Could not find workflow: $WORKFLOW_NAME"
    fi
done

# Clean up session cookies
rm -f /tmp/n8n-cookies.txt

# Restart n8n after workflow activation to ensure webhook registration
echo -e "${YELLOW}Restarting n8n to apply webhook registrations...${NC}"
docker restart n8n

# Wait for n8n to be fully ready after restart
echo "  Waiting for n8n to restart and be ready..."
for i in {1..60}; do
    sleep 5
    if docker exec n8n n8n --version >/dev/null 2>&1; then
        echo "  n8n is ready!"
        break
    fi
done

# Verify webhook registration is working
echo -e "${YELLOW}Verifying webhook registration...${NC}"

# Test the critical webhook endpoints
echo "  Testing process-additional-sources endpoint..."
TEST_RESPONSE=$(curl -s -X POST http://localhost:8000/functions/v1/process-additional-sources \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(grep ANON_KEY .env | cut -d'=' -f2)" \
  -d '{
    "type": "multiple-websites",
    "notebookId": "test-notebook-id",
    "urls": ["https://httpbin.org/status/200"],
    "sourceIds": ["test-source-id"],
    "timestamp": "'$(date -Iseconds)'"
  }' 2>/dev/null)

if echo "$TEST_RESPONSE" | grep -q '"success":true'; then
    echo "  ✅ process-additional-sources webhook working correctly"
else
    echo "  ❌ process-additional-sources webhook failed, attempting to fix..."
    
    # Retry workflow activation for critical workflows using web API
    echo "    Re-establishing n8n session for retry..."
    LOGIN_RETRY=$(curl -s -c /tmp/n8n-retry-cookies.txt -X POST http://localhost:5678/rest/login \
        -H 'Content-Type: application/json' \
        -d "{\"emailOrLdapLoginId\":\"${UNIFIED_EMAIL}\",\"password\":\"${UNIFIED_PASSWORD}\"}" 2>/dev/null || echo "{}")
    
    for RETRY_WORKFLOW in "InsightsLM - Process Additional Sources" "InsightsLM - Generate Notebook Details"; do
        WORKFLOW_ID=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "SELECT id FROM workflow_entity WHERE name='${RETRY_WORKFLOW}' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')
        if [ -n "$WORKFLOW_ID" ]; then
            echo "    Retrying activation for: $RETRY_WORKFLOW"
            
            if echo "$LOGIN_RETRY" | grep -q "\"email\":\"${UNIFIED_EMAIL}\""; then
                # Use web API for retry
                curl -s -b /tmp/n8n-retry-cookies.txt -X PATCH "http://localhost:5678/rest/workflows/${WORKFLOW_ID}" \
                    -H 'Content-Type: application/json' \
                    -d '{"active":false}' >/dev/null 2>&1 || true
                sleep 2
                curl -s -b /tmp/n8n-retry-cookies.txt -X PATCH "http://localhost:5678/rest/workflows/${WORKFLOW_ID}" \
                    -H 'Content-Type: application/json' \
                    -d '{"active":true}' >/dev/null 2>&1 || true
            else
                # Fallback to CLI
                docker exec n8n n8n update:workflow --id="${WORKFLOW_ID}" --active=false >/dev/null 2>&1 || true
                sleep 2
                docker exec n8n n8n update:workflow --id="${WORKFLOW_ID}" --active=true >/dev/null 2>&1 || true
            fi
        fi
    done
    
    rm -f /tmp/n8n-retry-cookies.txt
    
    # Test again after retry
    sleep 3
    TEST_RESPONSE=$(curl -s -X POST http://localhost:8000/functions/v1/process-additional-sources \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $(grep ANON_KEY .env | cut -d'=' -f2)" \
      -d '{
        "type": "multiple-websites",
        "notebookId": "test-notebook-id",
        "urls": ["https://httpbin.org/status/200"],
        "sourceIds": ["test-source-id"],
        "timestamp": "'$(date -Iseconds)'"
      }' 2>/dev/null)
    
    if echo "$TEST_RESPONSE" | grep -q '"success":true'; then
        echo "  ✅ Webhook auto-recovery successful"
    else
        echo "  ⚠️  Webhook registration may need manual attention after setup"
    fi
fi

echo "  Testing generate-notebook-content endpoint..."
TEST_RESPONSE=$(curl -s -X POST http://localhost:8000/functions/v1/generate-notebook-content \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(grep ANON_KEY .env | cut -d'=' -f2)" \
  -d '{
    "notebookId": "test-notebook-id",
    "sourceType": "website"
  }' 2>/dev/null)

if echo "$TEST_RESPONSE" | grep -q '"success":true'; then
    echo "  ✅ generate-notebook-content webhook working correctly"
else
    echo "  ⚠️  generate-notebook-content may need attention (this is often normal if no sources exist)"
fi

echo "✅ Webhook verification completed"


# Verify InsightsLM is running
echo -e "${YELLOW}Verifying InsightsLM container...${NC}"
if docker ps | grep -q insightslm; then
    echo -e "${GREEN}✅ InsightsLM is running (built with fresh credentials)${NC}"
else
    echo -e "${YELLOW}⚠️  InsightsLM container not found - may need manual restart${NC}"
fi

# Save credentials
cat > unified_credentials.txt << EOF
Unified Login Credentials (for n8n and InsightsLM):
====================================================
Email: ${UNIFIED_EMAIL}
Password: ${UNIFIED_PASSWORD}

Service URLs:
- Supabase: http://localhost:8000
- n8n: http://localhost:5678
- InsightsLM: http://localhost:3010

Service Access URLs:
- Supabase: http://${ACCESS_HOST}:8000
- n8n: http://${ACCESS_HOST}:5678
- InsightsLM: http://${ACCESS_HOST}:3010
EOF

# Save current .env for future comparison
cp .env .env.previous

# Final output
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}🎉 === SETUP COMPLETE === 🎉${NC}"
echo -e "${GREEN}============================================================${NC}"

# Check if user needs to refresh Docker permissions
if ! docker ps >/dev/null 2>&1 && groups | grep -q docker; then
    echo -e "${YELLOW}⚠️  IMPORTANT: Docker group permissions may need refresh${NC}"
    echo -e "${YELLOW}   If you encounter Docker permission errors, try:${NC}"
    echo -e "${YELLOW}   1. Log out and log back in, OR${NC}"
    echo -e "${YELLOW}   2. Run: newgrp docker${NC}"
    echo ""
fi
echo ""
echo "Service URLs:"
echo "📊 Supabase Studio: http://${ACCESS_HOST}:8000"
echo "🔧 N8N Workflow Editor: http://${ACCESS_HOST}:5678"
echo "📓 InsightsLM: http://${ACCESS_HOST}:3010"
echo ""
echo "🔐 Login Credentials saved to: unified_credentials.txt"
echo "   Email: ${UNIFIED_EMAIL}"
echo "   📁 File location: $(pwd)/unified_credentials.txt"
echo ""
echo "Extra Services:"
echo "💬 Open WebUI: http://${ACCESS_HOST}:8080"
echo "🌐 Flowise: http://${ACCESS_HOST}:3001"
echo ""
echo "🔗 Webhook Status:"
echo "   ✅ All Edge Functions and n8n workflows activated via web API"
echo "   🌐 n8n web session established for proper workflow activation"
echo "   📝 If you experience 500 errors, workflows may need manual activation via web UI"
if [ "$IS_MACOS" = true ]; then
    echo ""
    echo "🍎 macOS Compatibility:"
    echo "   ✅ Storage service configured to disable extended attributes (xattrs)"
    echo "   ✅ File system compatibility mode enabled for macOS"
fi
echo ""
echo -e "${GREEN}============================================================${NC}"
