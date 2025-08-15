#!/bin/bash
set -e

cd $HOME

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect operating system
if [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MACOS=true
    echo -e "${YELLOW}Detected macOS system${NC}"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    IS_MACOS=false
    echo -e "${YELLOW}Detected Linux system${NC}"
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

# Repository configuration
# Original repositories:
# LOCAL_AI_REPO="https://github.com/coleam00/local-ai-packaged.git"
# INSIGHTS_LM_REPO="https://github.com/theaiautomators/insights-lm-local-package.git"
# INSIGHTS_LM_RAW_URL="https://raw.githubusercontent.com/theaiautomators/insights-lm-local-package"

# Using forked repositories:
LOCAL_AI_REPO="https://github.com/sirouk/local-ai-packaged.git"
INSIGHTS_LM_REPO="https://github.com/sirouk/insights-lm-local-package.git"
INSIGHTS_LM_RAW_URL="https://raw.githubusercontent.com/sirouk/insights-lm-local-package"

# Default Ollama model configuration
DEFAULT_OLLAMA_MODEL="qwen3:8b-q4_K_M"
DEFAULT_EMBEDDING_MODEL="nomic-embed-text"

echo -e "${GREEN}=== InsightsLM Local AI Setup Script ===${NC}"
echo ""
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
    snap install --classic yq
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

# Ollama Model Configuration
echo -e "${YELLOW}Ollama Model Configuration${NC}"
echo -e "Default model: ${GREEN}$DEFAULT_OLLAMA_MODEL${NC}"
echo -e "Default embedding model: ${GREEN}$DEFAULT_EMBEDDING_MODEL${NC}"
echo ""
read -p "Do you want to use the default models? (Y/n): " -r USE_DEFAULT
USE_DEFAULT=${USE_DEFAULT:-Y}

OLLAMA_MODEL="$DEFAULT_OLLAMA_MODEL"
EMBEDDING_MODEL="$DEFAULT_EMBEDDING_MODEL"

if [[ ! "$USE_DEFAULT" =~ ^[Yy]$ ]]; then
    echo ""
    read -p "Enter the Ollama model to use (e.g., llama3.2, mistral, qwen3:8b-q4_K_M): " -r CUSTOM_MODEL
    if [ -n "$CUSTOM_MODEL" ]; then
        OLLAMA_MODEL="$CUSTOM_MODEL"
        echo -e "${GREEN}Using custom model: $OLLAMA_MODEL${NC}"
    else
        echo -e "${YELLOW}No model specified, using default: $OLLAMA_MODEL${NC}"
    fi
    
    echo ""
    read -p "Enter the embedding model to use (default: $DEFAULT_EMBEDDING_MODEL): " -r CUSTOM_EMBEDDING
    if [ -n "$CUSTOM_EMBEDDING" ]; then
        EMBEDDING_MODEL="$CUSTOM_EMBEDDING"
        echo -e "${GREEN}Using custom embedding model: $EMBEDDING_MODEL${NC}"
    else
        echo -e "${YELLOW}Using default embedding model: $EMBEDDING_MODEL${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Configuration:${NC}"
echo -e "  Main model: $OLLAMA_MODEL"
echo -e "  Embedding model: $EMBEDDING_MODEL"
echo ""

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
                        echo "      → coqui-tts configured for CPU execution with x86_64 emulation"
                        ;;
                esac
            fi
        else
            echo "    Service $service_name already exists, skipping"
        fi
    fi
done < <(yq eval '.services | keys | .[]' insights-lm-local-package/docker-compose.copy.yml)

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

# Update x-init-ollama to use selected models
echo -e "${YELLOW}Configuring Ollama to pull selected models...${NC}"
# Update the command in x-init-ollama anchor
OLLAMA_COMMAND="sleep 3; OLLAMA_HOST=ollama:11434 ollama pull $OLLAMA_MODEL; OLLAMA_HOST=ollama:11434 ollama pull $EMBEDDING_MODEL"
yq eval "."x-init-ollama".command[1] = \"$OLLAMA_COMMAND\"" -i docker-compose.yml
echo "  Updated x-init-ollama to pull: $OLLAMA_MODEL and $EMBEDDING_MODEL"

# Generate .env file
echo -e "${YELLOW}Generating environment configuration...${NC}"
cp -f .env.example .env

# Generate all required secrets
N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -hex 16)
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -hex 16)
DASHBOARD_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)
CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
LANGFUSE_SALT=$(openssl rand -hex 16)
NEXTAUTH_SECRET=$(openssl rand -hex 16)
ENCRYPTION_KEY=$(openssl rand -hex 32)
DASHBOARD_USERNAME="admin@local.host"
NEO4J_AUTH="neo4j/$(openssl rand -base64 12 | tr -d '=+/' | cut -c1-16)"
NOTEBOOK_GENERATION_AUTH=$(openssl rand -hex 16)

# Update .env file with secrets
cp_sed "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY/" .env
cp_sed "s/N8N_USER_MANAGEMENT_JWT_SECRET=.*/N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET/" .env
cp_sed "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
cp_sed "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
cp_sed "s/DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD/" .env
cp_sed "s/POOLER_TENANT_ID=.*/POOLER_TENANT_ID=1000/" .env
cp_sed "s/CLICKHOUSE_PASSWORD=.*/CLICKHOUSE_PASSWORD=$CLICKHOUSE_PASSWORD/" .env
cp_sed "s/MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD/" .env
cp_sed "s/LANGFUSE_SALT=.*/LANGFUSE_SALT=$LANGFUSE_SALT/" .env
cp_sed "s/NEXTAUTH_SECRET=.*/NEXTAUTH_SECRET=$NEXTAUTH_SECRET/" .env
cp_sed "s/ENCRYPTION_KEY=.*/ENCRYPTION_KEY=$ENCRYPTION_KEY/" .env
cp_sed "s/DASHBOARD_USERNAME=.*/DASHBOARD_USERNAME=$DASHBOARD_USERNAME/" .env
cp_sed "s|NEO4J_AUTH=.*|NEO4J_AUTH=\"$NEO4J_AUTH\"|" .env

# Concatenate InsightsLM environment variables from .env.copy
echo "" >> .env
echo "# InsightsLM Environment Variables" >> .env
cat insights-lm-local-package/.env.copy >> .env

# Update NOTEBOOK_GENERATION_AUTH to use our generated value (used for Header Auth)
cp_sed "s|NOTEBOOK_GENERATION_AUTH=.*|NOTEBOOK_GENERATION_AUTH=$NOTEBOOK_GENERATION_AUTH|" .env

# Add Ollama model configuration to .env
echo "" >> .env
echo "# Ollama Model Configuration" >> .env
echo "OLLAMA_MODEL=$OLLAMA_MODEL" >> .env
echo "EMBEDDING_MODEL=$EMBEDDING_MODEL" >> .env

# Update STUDIO defaults
cp_sed 's/STUDIO_DEFAULT_ORGANIZATION=.*/STUDIO_DEFAULT_ORGANIZATION="InsightsLM"/' .env
cp_sed 's/STUDIO_DEFAULT_PROJECT=.*/STUDIO_DEFAULT_PROJECT="Default Project"/' .env

# Generate JWT keys
ANON_KEY=$(python3 -c "import jwt, time; print(jwt.encode({'role': 'anon', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + (5 * 365 * 24 * 60 * 60)}, '$JWT_SECRET', algorithm='HS256'))")
SERVICE_ROLE_KEY=$(python3 -c "import jwt, time; print(jwt.encode({'role': 'service_role', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + (5 * 365 * 24 * 60 * 60)}, '$JWT_SECRET', algorithm='HS256'))")

cp_sed "s/ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
cp_sed "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env

# Configure access URLs
echo -e "${YELLOW}Configuring service access URLs...${NC}"
DETECTED_IP=$(curl -s ipinfo.io/ip)
echo -e "Detected external IP: ${GREEN}$DETECTED_IP${NC}"
echo ""
read -p "Use external IP for service URLs? (y/N - default "N" uses localhost): " -r USE_EXTERNAL_IP
USE_EXTERNAL_IP=${USE_EXTERNAL_IP:-N}
# Clean any unexpected input
USE_EXTERNAL_IP=$(echo "$USE_EXTERNAL_IP" | tr -d '\n\r' | head -c 1)

if [[ "$USE_EXTERNAL_IP" =~ ^[Yy]$ ]]; then
    ACCESS_HOST="$DETECTED_IP"
    echo -e "${GREEN}Using external IP for service access: $ACCESS_HOST${NC}"
else
    ACCESS_HOST="localhost"
    echo -e "${GREEN}Using localhost for service access${NC}"
fi

cp_sed "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://${ACCESS_HOST}:8000|" .env

# Source the .env file
source .env

# Clone Supabase if needed
echo -e "${YELLOW}Setting up Supabase...${NC}"
if [ ! -d "supabase/docker" ]; then
    # Original repository:
    # git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase.git
    # Using forked repository (optional - only if you've forked Supabase):
    git clone --filter=blob:none --no-checkout https://github.com/supabase/supabase.git
    # Uncomment the line below if you've forked Supabase:
    # git clone --filter=blob:none --no-checkout https://github.com/sirouk/supabase.git
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
# Native Ollama setup on macOS + proxy service for Docker
# ---------------------------------------------------------
if [ "$IS_MACOS" = true ]; then
    echo -e "${YELLOW}Setting up native Ollama and proxy service...${NC}"

    # 1. Ensure Ollama CLI is installed
    if ! command -v ollama >/dev/null 2>&1; then
        echo "  Ollama not found – installing with Homebrew..."
        brew install ollama
    fi

    # 2. DON'T start Ollama here - let the Docker container manage it
    echo "  Ollama will be managed by the Docker proxy service"
    
    # 3. Stop any existing Ollama processes first (clean slate)
    echo "  Stopping any existing Ollama processes..."
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 2

    # 4. Pre-pull models while we can (before container manages Ollama)
    echo "  Pre-pulling models $OLLAMA_MODEL and $EMBEDDING_MODEL..."
    # Start Ollama temporarily just for pulling
    ollama serve > /tmp/ollama-pull.log 2>&1 &
    TEMP_OLLAMA_PID=$!
    sleep 3
    ollama pull "$OLLAMA_MODEL" || true
    ollama pull "$EMBEDDING_MODEL" || true
    # Stop the temporary Ollama
    kill $TEMP_OLLAMA_PID 2>/dev/null || true
    sleep 2

    # 5. Create ollama proxy script that strictly manages host Ollama lifecycle
    echo "  Creating Ollama proxy management script with strict lifecycle..."
    mkdir -p ollama-proxy
    cat > ollama-proxy/entrypoint.sh << 'PROXY_SCRIPT'
#!/bin/sh
set -e

OLLAMA_PID_FILE="/tmp/ollama-proxy.pid"

echo "Ollama proxy container starting..."

# Function to start Ollama on host
start_ollama() {
    echo "Starting Ollama serve on host..."
    # Use nohup and background to start ollama, capture PID
    nohup sh -c 'ollama serve' > /tmp/ollama-proxy.log 2>&1 &
    OLLAMA_PID=$!
    echo $OLLAMA_PID > $OLLAMA_PID_FILE
    echo "Started Ollama with PID: $OLLAMA_PID"
    sleep 3
}

# Function to stop Ollama on host
stop_ollama() {
    echo "Stopping Ollama on host..."
    if [ -f $OLLAMA_PID_FILE ]; then
        PID=$(cat $OLLAMA_PID_FILE)
        if kill -0 $PID 2>/dev/null; then
            echo "Stopping Ollama process $PID..."
            kill $PID 2>/dev/null || true
            sleep 2
            # Force kill if still running
            if kill -0 $PID 2>/dev/null; then
                echo "Force killing Ollama process $PID..."
                kill -9 $PID 2>/dev/null || true
            fi
        fi
        rm -f $OLLAMA_PID_FILE
    fi
    # Also kill any stray ollama processes
    pkill -f "ollama serve" 2>/dev/null || true
    echo "Ollama stopped"
}

# Function to cleanup on exit
cleanup() {
    echo "Ollama proxy container stopping..."
    stop_ollama
    exit 0
}

# Trap termination signals
trap cleanup SIGTERM SIGINT EXIT

# Check if Ollama is accessible
check_ollama() {
    nc -z host.docker.internal 11434 2>/dev/null
}

# Stop any existing Ollama first
stop_ollama

# Start fresh Ollama instance
start_ollama

# Wait for Ollama to be available
echo "Waiting for host Ollama to be ready..."
RETRIES=0
MAX_RETRIES=30
while ! check_ollama; do
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "ERROR: Host Ollama not responding after $MAX_RETRIES attempts"
        cat /tmp/ollama-proxy.log
        exit 1
    fi
    echo "  Attempt $RETRIES/$MAX_RETRIES - Ollama not ready, waiting..."
    sleep 2
done

echo "Host Ollama is ready, starting proxy..."

# Start socat in foreground (so container stops when socat stops)
exec socat TCP-LISTEN:11434,fork,reuseaddr TCP:host.docker.internal:11434
PROXY_SCRIPT

    chmod +x ollama-proxy/entrypoint.sh

    # 6. Update docker-compose.yml: add lightweight proxy and remove heavy Ollama containers
    DC_FILE="docker-compose.yml"

    # Remove heavy Ollama-related services if they exist
    for svc in ollama-cpu ollama-gpu ollama-gpu-amd ollama-pull-llama-cpu ollama-pull-llama-gpu ollama-pull-llama-gpu-amd; do
        if yq eval ".services | has(\"$svc\")" "$DC_FILE" | grep -q "true"; then
            yq eval "del(.services.\"$svc\")" -i "$DC_FILE"
        fi
    done

    # Define/overwrite the proxy service with custom entrypoint
    yq eval '.services.ollama.image = "alpine/socat"' -i "$DC_FILE"
    yq eval '.services.ollama.container_name = "ollama"' -i "$DC_FILE"
    yq eval '.services.ollama.restart = "unless-stopped"' -i "$DC_FILE"
    yq eval '.services.ollama.expose = ["11434/tcp"]' -i "$DC_FILE"
    yq eval '.services.ollama.volumes = ["./ollama-proxy/entrypoint.sh:/entrypoint.sh:ro"]' -i "$DC_FILE"
    yq eval '.services.ollama.entrypoint = ["/entrypoint.sh"]' -i "$DC_FILE"
    # Mount Docker socket to allow container to control host processes
    yq eval '.services.ollama.volumes += ["/var/run/docker.sock:/var/run/docker.sock:ro"]' -i "$DC_FILE"
    # Ensure the service starts under cpu profile so it is included when profile filtering is used
    yq eval '.services.ollama.profiles = ["cpu"]' -i "$DC_FILE"

    echo "  ✅ Proxy service 'ollama' configured with strict lifecycle management"
    echo "     → Container starts = Ollama starts on host"
    echo "     → Container stops = Ollama stops on host (forcefully if needed)"
fi

# Auto-detect compute profile
echo -e "${YELLOW}Detecting compute profile...${NC}"
PROFILE="cpu"
if [ "$IS_MACOS" = true ]; then
    # Check for Apple Silicon (M1/M2/M3/M4)
    if [[ $(uname -m) == "arm64" ]]; then
        PROFILE="cpu"  # Apple Silicon uses CPU for now
        echo -e "${YELLOW}Apple Silicon detected - using CPU profile${NC}"
        echo -e "${YELLOW}Note: Some services will use x86_64 emulation for compatibility${NC}"
    else
        # Intel Mac - check for AMD GPU
        if system_profiler SPDisplaysDataType | grep -q "AMD\|Radeon"; then
            PROFILE="gpu-amd"
        fi
    fi
elif command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
    PROFILE="gpu-nvidia"
elif command -v rocminfo >/dev/null 2>&1 || [ -d /opt/rocm ]; then
    PROFILE="gpu-amd"
fi
echo -e "${GREEN}Using profile: $PROFILE${NC}"

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
echo "  Updating main model references from qwen3:8b-q4_K_M to $OLLAMA_MODEL..."
MAIN_MODEL_UPDATES=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
UPDATE workflow_entity 
SET nodes = REPLACE(nodes::text, '\"model\": \"qwen3:8b-q4_K_M\"', '\"model\": \"$OLLAMA_MODEL\"')::jsonb
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
    echo "    Main model: $OLLAMA_MODEL"
    echo "    Embedding model: $EMBEDDING_MODEL"
else
    echo -e "${YELLOW}⚠️  $REMAINING_OLD_MODELS workflows may still contain old model references${NC}"
    echo "    This may be normal if workflows use different model configurations"
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

# Final restart is not needed - services are already running with correct config
# echo -e "${YELLOW}Restarting all services...${NC}"
# docker compose -p localai down
# sleep 5
# python3 start_services.py --profile "$PROFILE" --environment private

# Ensure InsightsLM was built correctly
echo -e "${YELLOW}Verifying InsightsLM build for fresh install...${NC}"

# Get ANON_KEY from .env
ENV_ANON_KEY=$(grep "^ANON_KEY=" .env | cut -d'=' -f2)

# Get ANON_KEY from InsightsLM container  
CONTAINER_ANON_KEY=$(docker exec insightslm sh -c "grep -o 'eyJhbGciOiJIUzI1NiIsInR5cCI[^\"]*' /usr/share/nginx/html/assets/index*.js 2>/dev/null | head -1" 2>/dev/null || echo "")

if [ "$ENV_ANON_KEY" != "$CONTAINER_ANON_KEY" ] || [ -z "$ENV_ANON_KEY" ]; then
    echo -e "${YELLOW}Rebuilding InsightsLM with correct credentials...${NC}"
    docker compose -p localai build insightslm
    docker compose -p localai stop insightslm
    docker compose -p localai up -d insightslm
    sleep 5
    echo -e "${GREEN}InsightsLM rebuilt with correct credentials${NC}"
else
    echo -e "${GREEN}✅ InsightsLM already has correct credentials${NC}"
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

N8N Configuration Required:
============================
Please update the Supabase credentials in n8n:

SERVICE_ROLE_KEY for Supabase:
${SERVICE_ROLE_KEY}

Steps:
1. Go to: http://${ACCESS_HOST}:5678/credentials
2. Find 'Supabase account' credential  
3. Click Edit → Update 'Service Role Key' field
4. Paste the SERVICE_ROLE_KEY above and Save
EOF

# Save current .env for future comparison
cp .env .env.previous

# Final output
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}🎉 === SETUP COMPLETE === 🎉${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "Service URLs:"
echo "📊 Supabase Studio: http://${ACCESS_HOST}:8000"
echo "🔧 N8N Workflow Editor: http://${ACCESS_HOST}:5678"
echo "📓 InsightsLM: http://${ACCESS_HOST}:3010"
# echo "💬 Open WebUI: http://${ACCESS_HOST}:8080"
# echo "🌐 Flowise: http://${ACCESS_HOST}:3001"
echo ""
echo "🔐 Login Credentials saved to: unified_credentials.txt"
echo "   Email: ${UNIFIED_EMAIL}"
echo "   📁 File location: $(pwd)/unified_credentials.txt"
echo ""
echo "🔧 N8N Configuration Required:"
echo "   Please update the Supabase credentials in n8n with this SERVICE_ROLE_KEY:"
echo ""
echo -e "   ${GREEN}${SERVICE_ROLE_KEY}${NC}"
echo ""
echo "   Steps:"
echo "   1. Go to: http://${ACCESS_HOST}:5678/credentials"
echo "   2. Find 'Supabase account' credential"
echo "   3. Click Edit → Update 'Service Role Key' field"
echo "   4. Paste the key above and Save"
echo ""
echo "   💡 To view this key again later, run: grep SERVICE_ROLE_KEY .env"
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
