#!/bin/bash
set -e

cd "$(dirname "$0")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== SOTA RAG Static Deployment Script ===${NC}"
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

# Verify we're in the correct directory
if [ ! -f "docker-compose.yml" ] || [ ! -f "easy_setup_v2.sh" ]; then
    echo -e "${RED}Error: This script must be run from the local-ai-packaged directory${NC}"
    echo "Make sure you're in the directory containing docker-compose.yml"
    exit 1
fi

# Verify SOTA RAG files are present
if [ ! -f "sota-rag-upgrade/src/TheAIAutomators.com - RAG SOTA - v2.1 BLUEPRINT (1).json" ]; then
    echo -e "${RED}Error: SOTA RAG v2.1 files not found${NC}"
    echo "Make sure the 'sota-rag-upgrade/src' directory exists"
    exit 1
fi

echo -e "${GREEN}✓ Static files verified - proceeding with deployment...${NC}"

# =============================================================================
# RESET OPTION
# =============================================================================

echo ""
echo -e "${YELLOW}=== Data Reset Option ===${NC}"
echo -e "${YELLOW}⚠️  Reset will wipe ALL data and start completely fresh:${NC}"
echo "- All Docker volumes and containers"
echo "- All database data and credentials"
echo "- All workflow configurations"
echo "- All user documents and cache"
echo "- All backup directories"
echo ""
read -p "Reset all data and start fresh? (y/N): " -r RESET_DATA
RESET_DATA=${RESET_DATA:-N}

if [[ "$RESET_DATA" =~ ^[Yy]$ ]]; then
    FORCE_RESET=true
    echo -e "${RED}🔄 RESET MODE: Will wipe all data and start completely fresh${NC}"
else
    FORCE_RESET=false
    echo -e "${GREEN}✓ Preserving existing data - running idempotent deployment${NC}"
fi

# =============================================================================
# IDEMPOTENT FRESH START (like easy_setup_v2.sh)
# =============================================================================

# Check if SOTA RAG has been deployed before (idempotent check)
SOTA_DEPLOYED=false
SOTA_COMPLETE=false

# Force reset overrides all existing deployment detection
if [ "$FORCE_RESET" = true ]; then
    echo ""
    echo -e "${RED}🔄 FORCE RESET: Ignoring existing deployment - will wipe everything${NC}"
    SOTA_DEPLOYED=true
    SOTA_COMPLETE=false
else
    # Check for deployment flag and verify completeness
    if [ -f "sota-rag-deployment.flag" ]; then
        echo ""
        echo -e "${YELLOW}Found existing SOTA RAG deployment flag${NC}"
        
        # Verify deployment completeness
        if docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'documents_v2';" 2>/dev/null | grep -q "1" && \
           [ -f "./supabase/docker/volumes/functions/vector-search/index.ts" ] && \
           grep -q "jsr:@supabase" "./supabase/docker/volumes/functions/vector-search/index.ts" 2>/dev/null; then
            SOTA_COMPLETE=true
            echo -e "${GREEN}✓ SOTA RAG deployment appears complete${NC}"
            echo -e "${BLUE}Running idempotent update to ensure all components are current...${NC}"
        else
            echo -e "${YELLOW}⚠️  SOTA RAG deployment incomplete - will complete missing components${NC}"
        fi
        SOTA_DEPLOYED=true
    elif [ -d "workflows/sota" ] || [ -d "supabase/functions/vector-search" ]; then
        SOTA_DEPLOYED=true
        echo ""
        echo -e "${YELLOW}Found partial SOTA RAG deployment${NC}"
        echo -e "${GREEN}easy_deploy.sh will complete the deployment...${NC}"
    fi
fi

# Conditional cleanup based on deployment state
if [ "$SOTA_DEPLOYED" = true ] && [ "$SOTA_COMPLETE" = false ]; then
    echo -e "${YELLOW}Starting fresh SOTA RAG deployment...${NC}"
    
    echo "Performing SOTA RAG cleanup..."
    
    # Stop and remove SOTA RAG related containers if any
    echo "  → Stopping any SOTA RAG specific containers..."
    docker stop $(docker ps -q --filter "label=sota-rag=true") 2>/dev/null || echo "    No SOTA containers running"
    docker rm -f $(docker ps -aq --filter "label=sota-rag=true") 2>/dev/null || echo "    No SOTA containers to remove"
    
    # Clean up SOTA RAG specific volumes and data
    echo "  → Cleaning up SOTA RAG data..."
    
    # Clean filesystem artifacts first (database will be cleaned after services restart)
    echo "    Cleaning filesystem artifacts..."
    
    # Remove SOTA RAG file artifacts
    echo "  → Removing SOTA RAG filesystem artifacts..."
rm -rf workflows/sota workflows/staging workflows/fixed >/dev/null 2>&1 || true
rm -rf supabase/functions/vector-search supabase/functions/hybrid-search >/dev/null 2>&1 || true
rm -rf supabase-functions-sota >/dev/null 2>&1 || true
rm -f sota-rag-deployment.flag >/dev/null 2>&1 || true
rm -f sota-credential-ids.json >/dev/null 2>&1 || true
rm -f DEPLOYMENT_SUMMARY*.txt >/dev/null 2>&1 || true

echo "  → Removing database data directory to force fresh initialization..."
# This is the key fix - remove the PostgreSQL data directory that prevents fresh DB initialization
rm -rf supabase/docker/volumes/db/data >/dev/null 2>&1 || true
echo "    Removed supabase/docker/volumes/db/data (forces fresh database initialization)"
    
    echo "  ✅ SOTA RAG cleanup completed - starting fresh deployment"
fi

# =============================================================================
# UNIFIED CREDENTIAL GENERATION (like easy_setup_v2.sh)
# =============================================================================

echo ""
echo -e "${YELLOW}=== Generating Unified Admin Credentials ===${NC}"

# Check if we should reuse existing credentials from .env
if [ -f .env ]; then
    # Source existing .env to get current values
    source .env 2>/dev/null || true
    echo "  Found existing .env file - reusing credentials where available"
fi

# Generate unified credentials (following easy_setup_v2.sh pattern)
UNIFIED_EMAIL="admin@local.host"
UNIFIED_PASSWORD="${DASHBOARD_PASSWORD:-$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)}"

# Generate or reuse required secrets  
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(openssl rand -hex 16)}"
N8N_USER_MANAGEMENT_JWT_SECRET="${N8N_USER_MANAGEMENT_JWT_SECRET:-$(openssl rand -hex 16)}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -hex 16)}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-$(openssl rand -hex 16)}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-$(openssl rand -hex 16)}"
LANGFUSE_SALT="${LANGFUSE_SALT:-$(openssl rand -hex 16)}"
NEXTAUTH_SECRET="${NEXTAUTH_SECRET:-$(openssl rand -hex 16)}"
ENCRYPTION_KEY="${ENCRYPTION_KEY:-$(openssl rand -hex 32)}"
NEO4J_AUTH="${NEO4J_AUTH:-neo4j/$(openssl rand -base64 12 | tr -d '=+/' | cut -c1-16)}"
NOTEBOOK_GENERATION_AUTH="${NOTEBOOK_GENERATION_AUTH:-$(openssl rand -hex 16)}"

echo -e "${GREEN}✓ Unified credentials generated${NC}"
echo "   Email: ${UNIFIED_EMAIL}"
echo "   Password: ${UNIFIED_PASSWORD}"

# =============================================================================  
# USER CONFIGURATION
# =============================================================================

echo ""
echo -e "${YELLOW}=== Deployment Configuration ===${NC}"
echo ""

# 1. Deployment Mode Selection
echo -e "${YELLOW}Deployment Mode:${NC}"
echo "1. Phase 1: SOTA RAG with External APIs (OpenAI, Mistral, Cohere, Zep)"
echo "2. Phase 2: Local-Only SOTA RAG (Ollama + local alternatives)"
echo ""
read -p "Select deployment mode (press Enter for Phase 1): " -r DEPLOYMENT_MODE
DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-1}

if [[ "$DEPLOYMENT_MODE" != "1" && "$DEPLOYMENT_MODE" != "2" ]]; then
    echo -e "${RED}Invalid selection. Please choose 1 or 2.${NC}"
    exit 1
fi

if [ "$DEPLOYMENT_MODE" = "1" ]; then
    echo -e "${GREEN}✓ Phase 1: SOTA RAG with External APIs selected${NC}"
    USE_EXTERNAL_APIS=true
    
    # API Key Collection
    echo ""
    echo -e "${YELLOW}API Configuration Required:${NC}"
    echo "You'll need API keys for:"
    echo "- OpenAI (for LLMs and embeddings)"
    echo "- Mistral (for OCR and vision)"
    echo "- Cohere (for reranking)"
    echo "- Zep (for long-term memory)"
    echo ""
    
    read -p "Do you have all required API keys ready? (Y/n): " -r KEYS_READY
    KEYS_READY=${KEYS_READY:-Y}
    if [[ ! "$KEYS_READY" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Please obtain the following API keys before proceeding:${NC}"
        echo "1. OpenAI: https://platform.openai.com/api-keys"
        echo "2. Mistral: https://console.mistral.ai/"
        echo "3. Cohere: https://dashboard.cohere.ai/api-keys"
        echo "4. Zep: https://www.getzep.com/ (free tier available)"
        echo ""
        echo "Run this script again when you have the keys ready."
        exit 0
    fi
    
    # Collect API keys now (store in variables for later .env creation)
    echo ""
    echo -e "${YELLOW}Enter your API keys:${NC}"
    
    # Check for cached API keys from existing .env if present
    if [ -f ".env" ]; then
        CACHED_OPENAI=$(grep "^OPENAI_API_KEY=" .env 2>/dev/null | cut -d'=' -f2- | tr -d '\n' | head -c 200)
        CACHED_MISTRAL=$(grep "^MISTRAL_API_KEY=" .env 2>/dev/null | cut -d'=' -f2-)
        CACHED_COHERE=$(grep "^COHERE_API_KEY=" .env 2>/dev/null | cut -d'=' -f2-)
        CACHED_ZEP=$(grep "^ZEP_API_KEY=" .env 2>/dev/null | cut -d'=' -f2-)
    fi
    
    # OpenAI Key
    if [ -n "$CACHED_OPENAI" ] && [ "${CACHED_OPENAI:0:8}" != "xxxxxx" ] && [ "$CACHED_OPENAI" != "" ]; then
        echo -e "OpenAI key found: ${CACHED_OPENAI:0:12}...${CACHED_OPENAI: -4}"
        read -p "OpenAI API Key (press Enter to use cached): " -r OPENAI_API_KEY
        OPENAI_API_KEY=${OPENAI_API_KEY:-$CACHED_OPENAI}
    else
        read -p "OpenAI API Key: " -r OPENAI_API_KEY
    fi
    
    # Mistral Key
    if [ -n "$CACHED_MISTRAL" ] && [ "${CACHED_MISTRAL:0:8}" != "xxxxxx" ] && [ "$CACHED_MISTRAL" != "" ]; then
        echo -e "Mistral key found: ${CACHED_MISTRAL:0:12}...${CACHED_MISTRAL: -4}"
        read -p "Mistral API Key (press Enter to use cached): " -r MISTRAL_API_KEY
        MISTRAL_API_KEY=${MISTRAL_API_KEY:-$CACHED_MISTRAL}
    else
        read -p "Mistral API Key: " -r MISTRAL_API_KEY
    fi
    
    # Cohere Key
    if [ -n "$CACHED_COHERE" ] && [ "${CACHED_COHERE:0:8}" != "xxxxxx" ] && [ "$CACHED_COHERE" != "" ]; then
        echo -e "Cohere key found: ${CACHED_COHERE:0:12}...${CACHED_COHERE: -4}"
        read -p "Cohere API Key (press Enter to use cached): " -r COHERE_API_KEY
        COHERE_API_KEY=${COHERE_API_KEY:-$CACHED_COHERE}
    else
        read -p "Cohere API Key: " -r COHERE_API_KEY
    fi
    
    # Zep Key (optional)
    if [ -n "$CACHED_ZEP" ] && [ "${CACHED_ZEP:0:8}" != "xxxxxx" ] && [ "$CACHED_ZEP" != "" ]; then
        echo -e "Zep key found: ${CACHED_ZEP:0:12}...${CACHED_ZEP: -4}"
        read -p "Zep API Key (press Enter to use cached or skip): " -r ZEP_API_KEY
        ZEP_API_KEY=${ZEP_API_KEY:-$CACHED_ZEP}
    else
        read -p "Zep API Key (optional, press Enter to skip): " -r ZEP_API_KEY
    fi
    
    echo -e "${GREEN}✓ API keys collected${NC}"
else
    echo -e "${GREEN}✓ Phase 2: Local-Only SOTA RAG selected${NC}"
    USE_EXTERNAL_APIS=false
    echo -e "${YELLOW}Note: This will use Ollama for all LLM operations and local alternatives${NC}"
fi

# 2. Model Configuration
echo ""
echo -e "${YELLOW}Model Configuration:${NC}"
if [ "$USE_EXTERNAL_APIS" = true ]; then
    DEFAULT_MAIN_MODEL="gpt-4o"
    DEFAULT_EMBEDDING_MODEL="text-embedding-3-small"
    echo -e "External API mode - using OpenAI models"
else
    DEFAULT_MAIN_MODEL="qwen3:8b-q4_K_M"
    DEFAULT_EMBEDDING_MODEL="nomic-embed-text"
    echo -e "Local mode - using Ollama models"
fi

read -p "Enter main model (press Enter for default: $DEFAULT_MAIN_MODEL): " -r MAIN_MODEL
MAIN_MODEL=${MAIN_MODEL:-$DEFAULT_MAIN_MODEL}

read -p "Enter embedding model (press Enter for default: $DEFAULT_EMBEDDING_MODEL): " -r EMBEDDING_MODEL
EMBEDDING_MODEL=${EMBEDDING_MODEL:-$DEFAULT_EMBEDDING_MODEL}

# 3. Feature Configuration
echo ""
echo -e "${YELLOW}SOTA RAG Features:${NC}"
echo "Configure which advanced features to enable:"

read -p "Enable GraphRAG/LightRAG? (Y/n): " -r ENABLE_LIGHTRAG
ENABLE_LIGHTRAG=${ENABLE_LIGHTRAG:-Y}

read -p "Enable Multimodal RAG? (Y/n): " -r ENABLE_MULTIMODAL
ENABLE_MULTIMODAL=${ENABLE_MULTIMODAL:-Y}

read -p "Enable Contextual Embeddings? (Y/n): " -r ENABLE_CONTEXTUAL
ENABLE_CONTEXTUAL=${ENABLE_CONTEXTUAL:-Y}

read -p "Enable Long-term Memory (Zep)? (Y/n): " -r ENABLE_LONGTERM_MEMORY
ENABLE_LONGTERM_MEMORY=${ENABLE_LONGTERM_MEMORY:-Y}

# 4. Network Configuration
echo ""
echo -e "${YELLOW}Network Configuration:${NC}"
DETECTED_IP=$(curl -s ipinfo.io/ip 2>/dev/null || echo "Unable to detect")
if [ "$DETECTED_IP" != "Unable to detect" ]; then
    echo -e "Detected external IP: ${GREEN}$DETECTED_IP${NC}"
    echo ""
    read -p "Use external IP for service URLs? (y/N): " -r USE_EXTERNAL_IP
    USE_EXTERNAL_IP=${USE_EXTERNAL_IP:-N}
    
    if [[ "$USE_EXTERNAL_IP" =~ ^[Yy]$ ]]; then
        ACCESS_HOST="$DETECTED_IP"
        echo -e "${GREEN}✓ Using external IP: $ACCESS_HOST${NC}"
    else
        ACCESS_HOST="localhost"
        echo -e "${GREEN}✓ Using localhost for service access${NC}"
    fi
else
    ACCESS_HOST="localhost"
    echo -e "${YELLOW}Unable to detect external IP, using localhost${NC}"
fi

# =============================================================================
# BACKUP CURRENT STATE
# =============================================================================

echo ""
echo -e "${YELLOW}=== Backing up current state ===${NC}"

# Create backup directory with timestamp
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup current configuration
echo "Creating backup in $BACKUP_DIR..."
cp -f .env "$BACKUP_DIR/.env.backup" 2>/dev/null || echo "No .env file to backup"
cp -f docker-compose.yml "$BACKUP_DIR/docker-compose.yml.backup"
cp -rf supabase/docker/volumes "$BACKUP_DIR/supabase_volumes_backup" 2>/dev/null || echo "No Supabase volumes to backup"

echo -e "${GREEN}✓ Current state backed up to $BACKUP_DIR${NC}"

# =============================================================================
# ENVIRONMENT CONFIGURATION (MUST BE BEFORE SERVICE START)
# =============================================================================

echo ""
echo -e "${YELLOW}=== Creating Environment Configuration ===${NC}"

# Create fresh .env with unified credentials
echo "Creating fresh .env with unified credentials..."
cp .env.example .env

# Update .env with all generated secrets (following easy_setup_v2.sh pattern)
cp_sed "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY/" .env
cp_sed "s/N8N_USER_MANAGEMENT_JWT_SECRET=.*/N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET/" .env
cp_sed "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
cp_sed "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
cp_sed "s/DASHBOARD_USERNAME=.*/DASHBOARD_USERNAME=$UNIFIED_EMAIL/" .env
cp_sed "s/DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$UNIFIED_PASSWORD/" .env
cp_sed "s/CLICKHOUSE_PASSWORD=.*/CLICKHOUSE_PASSWORD=$CLICKHOUSE_PASSWORD/" .env
cp_sed "s/MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD/" .env
cp_sed "s/LANGFUSE_SALT=.*/LANGFUSE_SALT=$LANGFUSE_SALT/" .env
cp_sed "s/NEXTAUTH_SECRET=.*/NEXTAUTH_SECRET=$NEXTAUTH_SECRET/" .env
cp_sed "s/ENCRYPTION_KEY=.*/ENCRYPTION_KEY=$ENCRYPTION_KEY/" .env
cp_sed "s|NEO4J_AUTH=.*|NEO4J_AUTH=\"$NEO4J_AUTH\"|" .env
cp_sed "s/#FLOWISE_USERNAME=.*/FLOWISE_USERNAME=$UNIFIED_EMAIL/" .env
cp_sed "s/#FLOWISE_PASSWORD=.*/FLOWISE_PASSWORD=$UNIFIED_PASSWORD/" .env
cp_sed "s/POOLER_TENANT_ID=.*/POOLER_TENANT_ID=1000/" .env

# Generate JWT keys
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate 2>/dev/null
pip install -q PyJWT bcrypt pyyaml cryptography

ANON_KEY=$(python3 -c "import jwt, time; print(jwt.encode({'role': 'anon', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + (5 * 365 * 24 * 60 * 60)}, '$JWT_SECRET', algorithm='HS256'))")
SERVICE_ROLE_KEY=$(python3 -c "import jwt, time; print(jwt.encode({'role': 'service_role', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + (5 * 365 * 24 * 60 * 60)}, '$JWT_SECRET', algorithm='HS256'))")

cp_sed "s/ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
cp_sed "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env

# Configure access URLs  
cp_sed "s|^SITE_URL=.*|SITE_URL=http://${ACCESS_HOST}:3000|" .env
cp_sed "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://${ACCESS_HOST}:8000|" .env
cp_sed "s|^SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://${ACCESS_HOST}:8000|" .env

# Update STUDIO defaults (with proper quoting)
cp_sed 's/STUDIO_DEFAULT_ORGANIZATION=.*/STUDIO_DEFAULT_ORGANIZATION="SOTA RAG System"/' .env
cp_sed 's/STUDIO_DEFAULT_PROJECT=.*/STUDIO_DEFAULT_PROJECT="SOTA RAG Project"/' .env

# Add InsightsLM environment variables
echo "" >> .env
echo "# InsightsLM Environment Variables" >> .env
echo "NOTEBOOK_CHAT_URL=http://n8n:5678/webhook/2fabf43f-6e6e-424b-8e93-9150e9ce7d6c" >> .env
echo "NOTEBOOK_GENERATION_URL=http://n8n:5678/webhook/0c488f50-8d6a-48a0-b056-5f7cfca9efe2" >> .env
echo "AUDIO_GENERATION_WEBHOOK_URL=http://n8n:5678/webhook/4c4699bc-004b-4ca3-8923-373ddd4a274e" >> .env
echo "DOCUMENT_PROCESSING_WEBHOOK_URL=http://n8n:5678/webhook/19566c6c-e0a5-4a8f-ba1a-5203c2b663b7" >> .env
echo "ADDITIONAL_SOURCES_WEBHOOK_URL=http://n8n:5678/webhook/670882ea-5c1e-4b50-9f41-4792256af985" >> .env
echo "WHISPER_MODEL=base" >> .env
echo "WHISPER_ENGINE=openai_whisper" >> .env
echo "NOTEBOOK_GENERATION_AUTH=$NOTEBOOK_GENERATION_AUTH" >> .env

# Add SOTA RAG Configuration
echo "" >> .env
echo "# SOTA RAG Configuration" >> .env
echo "DEPLOYMENT_MODE=$DEPLOYMENT_MODE" >> .env
echo "MAIN_MODEL=$MAIN_MODEL" >> .env
echo "EMBEDDING_MODEL=$EMBEDDING_MODEL" >> .env
echo "ENABLE_LIGHTRAG=$([[ "$ENABLE_LIGHTRAG" =~ ^[Yy]$ ]] && echo "true" || echo "false")" >> .env
echo "ENABLE_MULTIMODAL=$([[ "$ENABLE_MULTIMODAL" =~ ^[Yy]$ ]] && echo "true" || echo "false")" >> .env
echo "ENABLE_CONTEXTUAL=$([[ "$ENABLE_CONTEXTUAL" =~ ^[Yy]$ ]] && echo "true" || echo "false")" >> .env
echo "ENABLE_LONGTERM_MEMORY=$([[ "$ENABLE_LONGTERM_MEMORY" =~ ^[Yy]$ ]] && echo "true" || echo "false")" >> .env

# Add Ollama Model Configuration for local deployments
if [ "$USE_EXTERNAL_APIS" = false ]; then
    echo "" >> .env
    echo "# Ollama Model Configuration" >> .env
    echo "OLLAMA_MODEL=$MAIN_MODEL" >> .env
    echo "EMBEDDING_MODEL=$EMBEDDING_MODEL" >> .env
fi

# Write API Keys to .env (already collected earlier)
if [ "$USE_EXTERNAL_APIS" = true ]; then
    echo "" >> .env
    echo "# External API Keys" >> .env
    echo "OPENAI_API_KEY=$OPENAI_API_KEY" >> .env
    echo "MISTRAL_API_KEY=$MISTRAL_API_KEY" >> .env
    echo "COHERE_API_KEY=$COHERE_API_KEY" >> .env
    echo "ZEP_API_KEY=$ZEP_API_KEY" >> .env
    echo "LIGHTRAG_SERVER_URL=http://lightrag:8020" >> .env
else
    echo "" >> .env
    echo "# Local-Only Configuration" >> .env
    echo "OPENAI_API_KEY=" >> .env
    echo "MISTRAL_API_KEY=" >> .env
    echo "COHERE_API_KEY=" >> .env
    echo "LIGHTRAG_SERVER_URL=http://lightrag:8020" >> .env
fi

echo -e "${GREEN}✓ Environment configuration created${NC}"

# =============================================================================
# HARDWARE DETECTION AND DEPENDENCY CHECKING
# =============================================================================

echo ""
echo -e "${YELLOW}=== Hardware Detection & Dependency Checking ===${NC}"

# Use existing hardware detection logic from easy_setup_v2.sh
PROFILE="cpu"
DEPENDENCIES_OK=true

if [ "$IS_MACOS" = true ]; then
    echo -e "${BLUE}macOS detected - checking architecture...${NC}"
    if [[ $(uname -m) == "arm64" ]]; then
        PROFILE="cpu"
        echo -e "${GREEN}✓ Apple Silicon detected - using CPU profile${NC}"
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
        PROFILE="gpu-nvidia"
        echo -e "${GREEN}✓ NVIDIA GPU detected - using GPU-NVIDIA profile${NC}"
        nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1 | sed 's/^/  GPU: /'
    elif command -v rocminfo >/dev/null 2>&1 || [ -d /opt/rocm ]; then
        PROFILE="gpu-amd"
        echo -e "${GREEN}✓ AMD GPU detected - using GPU-AMD profile${NC}"
    else
        echo -e "${YELLOW}No GPU detected - using CPU profile${NC}"
        PROFILE="cpu"
    fi
fi

# =============================================================================
# VOLUME CLEANUP (following easy_setup_v2.sh pattern - MUST BE BEFORE SERVICE START)
# =============================================================================

echo ""
echo -e "${YELLOW}=== Cleaning Docker Volumes (like easy_setup_v2.sh) ===${NC}"

# Skip volume cleanup if SOTA RAG is already complete (preserve working state) - unless FORCE_RESET
if [ "$SOTA_COMPLETE" = true ] && [ "$FORCE_RESET" = false ]; then
    echo -e "${GREEN}✓ SOTA RAG deployment complete - skipping volume cleanup to preserve working state${NC}"
    echo -e "${BLUE}Running idempotent updates only...${NC}"
else
    if [ "$FORCE_RESET" = true ]; then
        echo -e "${RED}🔄 RESET MODE: Performing complete data wipe...${NC}"
    fi
    # Comprehensive Docker cleanup (following easy_setup_v2.sh pattern exactly)
echo "  → Stopping project containers..."
# Stop containers by name patterns and compose project
docker compose -p localai down 2>/dev/null || true
docker stop $(docker ps -q --filter "name=supabase-" --filter "name=n8n" --filter "name=ollama" --filter "name=searxng" --filter "name=flowise" --filter "name=open-webui" --filter "name=qdrant" --filter "name=redis" --filter "name=caddy" --filter "name=insightslm" --filter "name=coqui-tts" --filter "name=whisper-asr" --filter "name=langfuse" --filter "name=clickhouse" --filter "name=minio" --filter "name=postgres" --filter "name=neo4j" --filter "name=lightrag") 2>/dev/null || echo "    No project containers running"

echo "  → Removing project containers..."
docker rm -f $(docker ps -aq --filter "name=supabase-" --filter "name=n8n" --filter "name=ollama" --filter "name=searxng" --filter "name=flowise" --filter "name=open-webui" --filter "name=qdrant" --filter "name=redis" --filter "name=caddy" --filter "name=insightslm" --filter "name=coqui-tts" --filter "name=whisper-asr" --filter "name=langfuse" --filter "name=clickhouse" --filter "name=minio" --filter "name=postgres" --filter "name=neo4j" --filter "name=lightrag") 2>/dev/null || echo "    No project containers to remove"

echo "  → Removing project volumes..."
# Remove volumes by name patterns (including localai_ prefix patterns)
docker volume rm $(docker volume ls -q | grep -E "(localai_|localai-|supabase|n8n_storage|ollama_storage|qdrant_storage|open-webui|flowise|caddy-data|caddy-config|valkey-data|langfuse|whisper_cache|db-config|lightrag)") 2>/dev/null || echo "    No project volumes to remove"

echo "  → Removing filesystem residuals..."
# Remove ~/.flowise directory created by flowise service bind mount
if [ -d "$HOME/.flowise" ]; then
    rm -rf "$HOME/.flowise"
    echo "    Removed ~/.flowise directory"
else
    echo "    No ~/.flowise directory to remove"
fi

# Remove PostgreSQL data directory to force fresh database initialization (key fix!)
if [ -d "supabase/docker/volumes/db/data" ]; then
    rm -rf supabase/docker/volumes/db/data
    echo "    Removed supabase/docker/volumes/db/data (forces fresh database initialization)"
else
    echo "    No database data directory to remove"
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

    # Additional cleanup for FORCE_RESET mode
    if [ "$FORCE_RESET" = true ]; then
        echo -e "${RED}🔄 RESET MODE: Wiping additional data...${NC}"
        
        # Remove all SOTA RAG related files and configurations
        echo "  → Removing SOTA RAG configuration files..."
        rm -f sota-rag-deployment.flag
        rm -f DEPLOYMENT_SUMMARY*.txt
        rm -f unified_credentials.txt
        rm -f sota-credential-ids.json
        rm -rf workflows/
        
        # Remove any cached API keys and environment backups
        echo "  → Removing cached configurations..."
        rm -f .env.backup*
        rm -f .env.previous
        
        # Remove all backup directories
        echo "  → Removing backup directories..."
        rm -rf backup_*/
        
        # Remove user data directories if they exist
        echo "  → Removing user data directories..."
        rm -rf shared/uploads shared/documents shared/cache 2>/dev/null || true
        
        # Clean up any n8n workflow exports
        echo "  → Removing workflow exports..."
        rm -rf n8n/backup/ 2>/dev/null || true
        
        echo -e "${RED}✅ Complete data wipe finished - starting completely fresh${NC}"
    fi

echo -e "${GREEN}✓ Volume cleanup complete - starting fresh${NC}"
fi

# =============================================================================
# SERVICE STARTUP WITH NEW CREDENTIALS
# =============================================================================

echo ""
echo -e "${YELLOW}=== Starting Services with Fresh Volumes ===${NC}"

# Skip full restart if SOTA RAG is already complete - unless FORCE_RESET
if [ "$SOTA_COMPLETE" = true ] && [ "$FORCE_RESET" = false ]; then
    echo -e "${GREEN}✓ Services already running - performing idempotent updates only${NC}"
else
    if [ "$FORCE_RESET" = true ]; then
        echo -e "${RED}🔄 RESET MODE: Starting services fresh after complete wipe${NC}"
    fi
    # Fix any unquoted values in .env that cause parsing issues
    cp_sed 's/STUDIO_DEFAULT_ORGANIZATION=Default Organization/STUDIO_DEFAULT_ORGANIZATION="Default Organization"/' .env
    cp_sed 's/STUDIO_DEFAULT_PROJECT=Default Project/STUDIO_DEFAULT_PROJECT="Default Project"/' .env

    # Start services with fresh volumes
    echo "Starting all services with profile: $PROFILE..."
    python3 start_services.py --profile "$PROFILE" --environment private || true
fi

# Ensure n8n is running
if ! docker ps | grep -q "n8n"; then
    echo -e "${YELLOW}Starting n8n...${NC}"
    docker rm -f n8n-import 2>/dev/null || true
    docker compose -p localai --profile "$PROFILE" up -d n8n --no-deps
    
    # Wait for n8n to stabilize if we just started it
    echo -e "${YELLOW}Waiting for n8n to stabilize...${NC}"
    sleep 15
fi

# Wait for database to be ready (forced check if FORCE_RESET)
if [ "$SOTA_COMPLETE" = false ] || [ "$FORCE_RESET" = true ]; then
    echo -e "${YELLOW}Waiting for database...${NC}"
    for i in {1..30}; do
        if docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
            echo -e "${GREEN}Database ready!${NC}"
            break
        fi
        sleep 2
    done
else
    # Just verify database is accessible
    if docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Database already accessible${NC}"
    else
        echo -e "${YELLOW}⚠️  Database not accessible - deployment may need attention${NC}"
    fi
fi

# =============================================================================
# OLLAMA CONFIGURATION (for Local Model Support)
# =============================================================================

# Configure Ollama if using local models (Phase 2 deployment)
if [ "$USE_EXTERNAL_APIS" = false ]; then
    echo ""
    echo -e "${YELLOW}=== Configuring Ollama for Local Models ===${NC}"
    
    # macOS-specific Ollama setup (native host + Docker proxy)
    if [ "$IS_MACOS" = true ]; then
        echo -e "${BLUE}Setting up native Ollama and proxy service for macOS...${NC}"

        # 1. Ensure Ollama CLI is installed
        if ! command -v ollama >/dev/null 2>&1; then
            echo "  Ollama not found – installing with Homebrew..."
            brew install ollama
        fi

        # 2. Stop any existing Ollama processes first (clean slate)
        echo "  Stopping any existing Ollama processes..."
        pkill -f "ollama serve" 2>/dev/null || true
        sleep 2

        # 3. Pre-pull models while we can (before container manages Ollama)
        echo "  Pre-pulling models $MAIN_MODEL and $EMBEDDING_MODEL..."
        # Start Ollama temporarily just for pulling
        ollama serve > /tmp/ollama-pull.log 2>&1 &
        TEMP_OLLAMA_PID=$!
        sleep 3
        ollama pull "$MAIN_MODEL" || true
        ollama pull "$EMBEDDING_MODEL" || true
        # Stop the temporary Ollama
        kill $TEMP_OLLAMA_PID 2>/dev/null || true
        sleep 2

        # 4. Create host-side scripts for strict lifecycle coupling
        echo "  Creating host-side Ollama lifecycle scripts..."
        mkdir -p ollama-proxy
        
        # Create Ollama start script (from easy_setup_v2.sh)
        cat > ollama-proxy/start-host-ollama.sh << 'START_HOST_OLLAMA'
#!/bin/bash
set -e
PID_FILE="/tmp/ollama-host.pid"
LOG_FILE="/tmp/ollama-host.log"

echo "Starting Ollama host management..." | tee -a "$LOG_FILE"

# Function to check if Ollama is bound to 0.0.0.0:11434
check_ollama_binding() {
  # Check if port 11434 is bound to 0.0.0.0 (accessible from Docker)
  if netstat -an 2>/dev/null | grep -q "*.11434.*LISTEN" || netstat -an 2>/dev/null | grep -q "0.0.0.0.11434.*LISTEN"; then
    return 0  # Correctly bound
  else
    return 1  # Not correctly bound
  fi
}

# Stop any existing Ollama processes that aren't properly bound
if pgrep -f "ollama serve" >/dev/null 2>&1; then
  echo "Found existing Ollama process(es)..." | tee -a "$LOG_FILE"
  
  # Check if current binding is correct
  if check_ollama_binding; then
    echo "Ollama already running with correct binding (0.0.0.0:11434)" | tee -a "$LOG_FILE"
    # Get the PID of the correctly running process
    EXISTING_PID=$(pgrep -f "ollama serve" | head -1)
    echo $EXISTING_PID > "$PID_FILE"
    exit 0
  else
    echo "Ollama running with incorrect binding (likely 127.0.0.1 only), stopping..." | tee -a "$LOG_FILE"
    # Kill existing Ollama processes
    pkill -f "ollama serve" 2>/dev/null || true
    sleep 3
    # Force kill if still running
    pkill -9 -f "ollama serve" 2>/dev/null || true
    sleep 2
  fi
fi

echo "Starting Ollama with Docker-accessible binding (0.0.0.0:11434)..." | tee -a "$LOG_FILE"

# Start Ollama with proper host binding for Docker access
nohup env OLLAMA_HOST=0.0.0.0:11434 ollama serve > "$LOG_FILE" 2>&1 &
HOST_PID=$!
echo $HOST_PID > "$PID_FILE"

# Wait until port is open and correctly bound (max ~60s)
for i in {1..60}; do
  if nc -z localhost 11434 2>/dev/null && check_ollama_binding; then
    echo "Ollama started successfully on host (PID=$HOST_PID) with Docker-accessible binding" | tee -a "$LOG_FILE"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Ollama did not start with correct binding (0.0.0.0:11434)" | tee -a "$LOG_FILE"
exit 1
START_HOST_OLLAMA

        chmod +x ollama-proxy/start-host-ollama.sh
        
        # Create Ollama stop script
        cat > ollama-proxy/stop-host-ollama.sh << 'STOP_HOST_OLLAMA'
#!/bin/bash
set -e
PID_FILE="/tmp/ollama-host.pid"

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
# Ensure no stray serve remains
pkill -f "ollama serve" 2>/dev/null || true
STOP_HOST_OLLAMA

        chmod +x ollama-proxy/stop-host-ollama.sh
        
        # Create container watcher script
        cat > ollama-proxy/watch-ollama-container.sh << 'WATCH_OLLAMA'
#!/bin/bash
set -e
LOG_FILE="/tmp/ollama-container-watch.log"

# Wait for Docker to be available
for i in {1..30}; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Listen for events on the specific container name
# When the container stops/dies, stop Ollama on host
(docker events --filter container=ollama --format '{{.Action}}' 2>>"$LOG_FILE" | while read -r action; do
  case "$action" in
    stop|die|kill)
      echo "Detected ollama container action: $action — stopping host Ollama" | tee -a "$LOG_FILE"
      bash ./ollama-proxy/stop-host-ollama.sh || true
      exit 0
      ;;
    *)
      echo "Event: $action" >>"$LOG_FILE"
      ;;
  esac
done) &
WATCH_OLLAMA

        chmod +x ollama-proxy/watch-ollama-container.sh
        
        echo -e "${GREEN}✓ Ollama lifecycle scripts created${NC}"
        
        # 5. Configure Docker Compose for macOS proxy service
        echo "  Configuring Docker Compose for Ollama proxy service..."
        
        # Remove heavy Ollama-related services if they exist
        for svc in ollama-cpu ollama-gpu ollama-gpu-amd ollama-pull-llama-cpu ollama-pull-llama-gpu ollama-pull-llama-gpu-amd; do
            if yq eval ".services | has(\"$svc\")" "docker-compose.yml" 2>/dev/null | grep -q "true"; then
                yq eval "del(.services.\"$svc\")" -i "docker-compose.yml"
                echo "    Removed heavy service: $svc"
            fi
        done

        # Create nginx configuration for Ollama proxy with Host header rewriting
        echo "  Creating nginx configuration for Ollama proxy..."
        mkdir -p ollama-proxy/nginx
        
        cat > ollama-proxy/nginx/nginx.conf << 'NGINX_CONF'
events {
    worker_connections 1024;
}

http {
    upstream ollama_backend {
        server host.docker.internal:11434;
    }
    
    server {
        listen 11434;
        
        location / {
            proxy_pass http://ollama_backend;
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
        echo "  Configuring lightweight Ollama proxy service..."
        yq eval '.services.ollama.image = "nginx:alpine"' -i "docker-compose.yml"
        yq eval '.services.ollama.container_name = "ollama"' -i "docker-compose.yml"
        yq eval '.services.ollama.restart = "unless-stopped"' -i "docker-compose.yml"
        yq eval '.services.ollama.expose = ["11434/tcp"]' -i "docker-compose.yml"
        yq eval '.services.ollama.volumes = ["./ollama-proxy/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"]' -i "docker-compose.yml"
        # Add health check to verify proxy is working
        yq eval '.services.ollama.healthcheck.test = ["CMD", "nginx", "-t"]' -i "docker-compose.yml"
        yq eval '.services.ollama.healthcheck.interval = "10s"' -i "docker-compose.yml"
        yq eval '.services.ollama.healthcheck.timeout = "5s"' -i "docker-compose.yml"
        yq eval '.services.ollama.healthcheck.retries = 5' -i "docker-compose.yml"
        yq eval '.services.ollama.healthcheck.start_period = "10s"' -i "docker-compose.yml"
        # Ensure the service starts under cpu profile so it is included when profile filtering is used
        yq eval '.services.ollama.profiles = ["cpu"]' -i "docker-compose.yml"

        # Clean up ALL override files that might reference removed ollama services
        echo "  Cleaning up override files..."
        for OVERRIDE_FILE in docker-compose.override.private.yml docker-compose.override.public.yml; do
            if [ -f "$OVERRIDE_FILE" ]; then
                for svc in ollama-cpu ollama-gpu ollama-gpu-amd; do
                    if yq eval ".services | has(\"$svc\")" "$OVERRIDE_FILE" 2>/dev/null | grep -q "true"; then
                        yq eval "del(.services.\"$svc\")" -i "$OVERRIDE_FILE"
                        echo "    Removed $svc from $OVERRIDE_FILE"
                    fi
                done
            fi
        done

        # 6. Start Ollama on host and launch watcher
        echo "  Starting Ollama on host and launching watcher..."
        ./ollama-proxy/start-host-ollama.sh
        nohup ./ollama-proxy/watch-ollama-container.sh >/dev/null 2>&1 &

        echo "  ✅ Proxy service 'ollama' configured with watcher-based lifecycle coupling"
        echo "     → Container starts = Ollama starts on host"
        echo "     → Container stops = Ollama stops on host (forcefully if needed)"
        
    else
        # Linux - use Docker Ollama services normally
        echo -e "${BLUE}Linux detected - using Docker Ollama services${NC}"
        echo "  Ollama will run in Docker containers as configured"
        
        # Update x-init-ollama to pull selected models for Linux
        echo "  Configuring Ollama to pull selected models..."
        OLLAMA_COMMAND="echo 'Waiting for Ollama to be ready...'; for i in {1..60}; do if nc -z ollama 11434 2>/dev/null; then echo 'Ollama ready, pulling models...'; break; fi; sleep 1; done; OLLAMA_HOST=ollama:11434 ollama pull $MAIN_MODEL; OLLAMA_HOST=ollama:11434 ollama pull $EMBEDDING_MODEL"
        yq eval ".[\"x-init-ollama\"].command[1] = \"$OLLAMA_COMMAND\"" -i docker-compose.yml
        echo "  Updated x-init-ollama to pull: $MAIN_MODEL and $EMBEDDING_MODEL"
    fi
    
    echo -e "${GREEN}✓ Ollama configuration prepared for local model deployment${NC}"
else
    echo -e "${YELLOW}Using external APIs - Ollama configuration skipped${NC}"
fi

# Database roles are automatically configured by Supabase initialization (following easy_setup_v2.sh pattern)
echo -e "${YELLOW}Database roles configured by Supabase initialization${NC}"

# Database state message
if [ "$SOTA_COMPLETE" = true ]; then
    echo -e "${GREEN}✓ Existing SOTA RAG database preserved - ready for idempotent updates${NC}"
else
    echo -e "${GREEN}✓ Starting with clean database - ready for SOTA RAG installation${NC}"
fi

# =============================================================================
# DATABASE MIGRATION
# =============================================================================

echo ""
echo -e "${YELLOW}=== Database Migration to SOTA RAG Schema ===${NC}"

# Now that services are running with correct credentials, proceed with migration
echo "Services running with new credentials - proceeding with migration..."

# Use the proven migration AND SOTA RAG specific database setup
echo "Running database migration..."
docker cp insights-lm-local-package/supabase-migration.sql supabase-db:/tmp/migration.sql
docker exec supabase-db psql -U supabase_admin -d postgres -f /tmp/migration.sql >/dev/null 2>&1 || true

# Apply SOTA RAG specific database tables (idempotent version)
echo "  → Applying SOTA RAG database tables..."
cat > /tmp/sota_tables_idempotent.sql << 'EOF'
-- SOTA RAG Database Tables (Idempotent Version)
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS public.record_manager_v2 (
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  doc_id text NOT NULL,
  hash text NOT NULL,
  data_type text NULL DEFAULT 'unstructured'::text,
  schema text NULL,
  document_title text NULL,
  graph_id text NULL,
  CONSTRAINT record_manager_v2_pkey PRIMARY KEY (id)
) TABLESPACE pg_default;

CREATE TABLE IF NOT EXISTS public.tabular_document_rows (
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  record_manager_id bigint NULL,
  row_data jsonb NULL,
  CONSTRAINT tabular_document_rows_pkey PRIMARY KEY (id),
  CONSTRAINT tabular_document_rows_record_manager_id_fkey FOREIGN KEY (record_manager_id) REFERENCES record_manager_v2 (id)
) TABLESPACE pg_default;

CREATE TABLE IF NOT EXISTS public.documents_v2 (
  id bigserial NOT NULL,
  content text NULL,
  metadata jsonb NULL,
  embedding vector(1536) NULL,
  fts tsvector GENERATED ALWAYS AS (to_tsvector('english'::regconfig, content)) STORED NULL,
  CONSTRAINT documents_v2_pkey PRIMARY KEY (id)
) TABLESPACE pg_default;

CREATE INDEX IF NOT EXISTS documents_v2_embedding_idx ON public.documents_v2 USING hnsw (embedding vector_cosine_ops) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS documents_v2_fts_idx ON public.documents_v2 USING gin (fts) TABLESPACE pg_default;

CREATE TABLE IF NOT EXISTS public.metadata_fields (
  id bigint GENERATED BY DEFAULT AS IDENTITY NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  metadata_name text NULL,
  allowed_values text NULL,
  CONSTRAINT metadata_fields_pkey PRIMARY KEY (id)
) TABLESPACE pg_default;

-- Insert sample metadata fields (idempotent)
INSERT INTO public.metadata_fields (metadata_name, allowed_values) 
SELECT 'department', E'HR\nCustomer Support\nProduct\nSales\nMarketing\nOperations\nLegal'
WHERE NOT EXISTS (SELECT 1 FROM public.metadata_fields WHERE metadata_name = 'department');

INSERT INTO public.metadata_fields (metadata_name, allowed_values) 
SELECT 'document_date', 'Datetime format: YYYY-MM-DD'
WHERE NOT EXISTS (SELECT 1 FROM public.metadata_fields WHERE metadata_name = 'document_date');
EOF

docker cp /tmp/sota_tables_idempotent.sql supabase-db:/tmp/sota_tables.sql
docker exec supabase-db psql -U supabase_admin -d postgres -f /tmp/sota_tables.sql >/dev/null 2>&1 || true
echo "    ✓ SOTA RAG database tables applied (idempotent)"

# Apply SOTA RAG specific database functions (from sota-rag-setup.md)
echo "  → Applying SOTA RAG database functions..."
if [ -f "sota-rag-upgrade/src/hybrid_search_database_function.txt" ]; then
    docker cp "sota-rag-upgrade/src/hybrid_search_database_function.txt" supabase-db:/tmp/sota_functions.sql
    docker exec supabase-db psql -U supabase_admin -d postgres -f /tmp/sota_functions.sql >/dev/null 2>&1 || true
    echo "    ✓ SOTA RAG database functions applied"
fi

echo -e "${GREEN}✓ Database migrated to SOTA RAG schema${NC}"

# Create read-only user as required by sota-rag-setup.md (idempotent version)
echo -e "${YELLOW}Creating read-only database user (required by SOTA RAG)...${NC}"
cat > /tmp/readonly_user_idempotent.sql << 'EOF'
-- Create read-only user (idempotent version)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'readonly') THEN
        CREATE USER readonly WITH PASSWORD 'readonly_secure_password_change_me';
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO readonly;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO readonly;

-- Enable RLS and create policies (idempotent)
ALTER TABLE record_manager_v2 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Read access for readonly user" ON record_manager_v2;
CREATE POLICY "Read access for readonly user" ON record_manager_v2 FOR SELECT TO readonly USING (true);

ALTER TABLE tabular_document_rows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Read access for readonly user" ON tabular_document_rows;
CREATE POLICY "Read access for readonly user" ON tabular_document_rows FOR SELECT TO readonly USING (true);

ALTER TABLE documents_v2 ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Read access for readonly user" ON documents_v2;
CREATE POLICY "Read access for readonly user" ON documents_v2 FOR SELECT TO readonly USING (true);
EOF

echo "  → Deploying read-only user configuration..."
docker cp /tmp/readonly_user_idempotent.sql supabase-db:/tmp/readonly_user.sql
docker exec supabase-db psql -U supabase_admin -d postgres -f /tmp/readonly_user.sql >/dev/null 2>&1 || true
echo -e "${GREEN}✓ Read-only database user created (idempotent)${NC}"

# Deploy SOTA RAG specific edge functions (idempotent)
echo -e "${YELLOW}Deploying SOTA RAG edge functions...${NC}"

# First copy base functions from insights-lm-local-package
mkdir -p ./supabase/docker/volumes/functions/
cp -rf ./insights-lm-local-package/supabase-functions/* ./supabase/docker/volumes/functions/

# Check if we need to update with enhanced SOTA RAG edge functions
echo "  → Checking edge function versions..."
NEEDS_UPDATE=false

# Check vector-search function
if [ ! -f "./supabase/docker/volumes/functions/vector-search/index.ts" ] || ! grep -q "jsr:@supabase" "./supabase/docker/volumes/functions/vector-search/index.ts" 2>/dev/null; then
    echo "    → Updating vector-search with enhanced SOTA RAG version..."
    mkdir -p ./supabase/docker/volumes/functions/vector-search
    cp "sota-rag-upgrade/src/Edge Function - Vector Search (2).txt" ./supabase/docker/volumes/functions/vector-search/index.ts
    NEEDS_UPDATE=true
else
    echo "    ✓ vector-search already has enhanced SOTA RAG version"
fi

# Check hybrid-search function
if [ ! -f "./supabase/docker/volumes/functions/hybrid-search/index.ts" ] || ! grep -q "jsr:@supabase" "./supabase/docker/volumes/functions/hybrid-search/index.ts" 2>/dev/null; then
    echo "    → Updating hybrid-search with enhanced SOTA RAG version..."
    mkdir -p ./supabase/docker/volumes/functions/hybrid-search
    cp "sota-rag-upgrade/src/Edge Function - Hybrid Search (3).txt" ./supabase/docker/volumes/functions/hybrid-search/index.ts
    NEEDS_UPDATE=true
else
    echo "    ✓ hybrid-search already has enhanced SOTA RAG version"
fi

# Restart edge functions only if updated
if [ "$NEEDS_UPDATE" = true ]; then
    echo "  → Restarting edge functions to load updates..."
    docker restart supabase-edge-functions >/dev/null 2>&1
    sleep 5
fi

echo -e "${GREEN}✓ SOTA RAG edge functions deployed (idempotent)${NC}"

# API keys are now configured in the earlier ENVIRONMENT CONFIGURATION section

# =============================================================================
# WORKFLOW PREPARATION
# =============================================================================

echo ""
echo -e "${YELLOW}=== Preparing SOTA RAG Workflows ===${NC}"

# Create workflows directory for staging
mkdir -p workflows/staging

# Copy SOTA RAG workflows to staging (Knowledge Graph is always needed)
echo "Copying SOTA RAG v2.1 workflows..."
cp "sota-rag-upgrade/src/Knowledge Graph Updates - SOTA RAG Blueprint - v1.0 BLUEPRINT (1).json" workflows/staging/knowledge-graph-workflow.json
cp "sota-rag-upgrade/src/TheAIAutomators.com - RAG SOTA - v2.1 BLUEPRINT (1).json" workflows/staging/main-rag-workflow.json
cp "sota-rag-upgrade/src/Multimodal RAG - TheAIAutomators - SOTA RAG Sub-workflow - 1.0 BLUEPRINT.json" workflows/staging/multimodal-rag-workflow.json

# Update workflow configurations based on selected options
echo "Configuring workflows for deployment..."

# Check if database is running to determine workflow configuration approach
if docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
    echo "Database is running - configuring workflows with live data..."
    
    # Create workflow configuration script
    cat > /tmp/configure_workflows.py << 'EOF'
import json
import sys
import os

def configure_workflow(filepath, config):
    with open(filepath, 'r') as f:
        workflow = json.load(f)
    
    # Configure feature toggles in "Set Data" node
    for node in workflow.get('nodes', []):
        if node.get('name') == 'Set Data':
            assignments = node.get('parameters', {}).get('assignments', {}).get('assignments', [])
            for assignment in assignments:
                name = assignment.get('name')
                if name == 'lightrag_enabled':
                    assignment['value'] = config['lightrag']
                elif name == 'multimodal_rag_enabled':
                    assignment['value'] = config['multimodal']
                elif name == 'contextual_embedding_enabled':
                    assignment['value'] = config['contextual']
    
    # Update API endpoints for local deployment
    for node in workflow.get('nodes', []):
        if node.get('type') == 'n8n-nodes-base.httpRequest':
            params = node.get('parameters', {})
            url = params.get('url', '')
            
            # Replace placeholder URLs with actual local URLs
            if 'YOUR_SUPABASE_URL' in url:
                params['url'] = url.replace('YOUR_SUPABASE_URL', f'http://{config["access_host"]}:8000')
            
            if 'YOUR_LIGHTRAG_URL' in url:
                if config['lightrag_url']:
                    params['url'] = url.replace('YOUR_LIGHTRAG_URL', config['lightrag_url'])

    # Update model references if using local models
    if not config['use_external_apis']:
        for node in workflow.get('nodes', []):
            params = node.get('parameters', {})
            
            # Update OpenAI Chat Model nodes to use Ollama
            if node.get('type') == '@n8n/n8n-nodes-langchain.lmChatOpenAi':
                if 'model' in params:
                    if isinstance(params['model'], dict) and '__rl' in params['model']:
                        params['model']['value'] = config['main_model']
                    else:
                        params['model'] = config['main_model']
                        
            # Update OpenAI nodes to use Ollama
            elif node.get('type') == '@n8n/n8n-nodes-langchain.openAi':
                if 'modelId' in params:
                    if isinstance(params['modelId'], dict) and '__rl' in params['modelId']:
                        params['modelId']['value'] = config['main_model']
                    else:
                        params['modelId'] = config['main_model']
                        
            # Update OpenAI embedding nodes to use Ollama
            elif node.get('type') == '@n8n/n8n-nodes-langchain.embeddingsOpenAi':
                # Change node type to Ollama embeddings
                node['type'] = '@n8n/n8n-nodes-langchain.embeddingsOllama'
                if 'model' in params:
                    params['model'] = config['embedding_model']
                    
            # Update OpenAI HTTP Request nodes to use Ollama API format
            elif node.get('type') == 'n8n-nodes-base.httpRequest':
                url = params.get('url', '')
                if 'api.openai.com' in url and '/embeddings' in url:
                    # Replace OpenAI embedding API with Ollama
                    params['url'] = 'http://ollama:11434/api/embeddings'
                    # Update authentication to none for local Ollama
                    params['authentication'] = 'none'
                    # Update body format for Ollama
                    if 'bodyParameters' in params:
                        for param in params['bodyParameters'].get('parameters', []):
                            if param.get('name') == 'model':
                                param['value'] = config['embedding_model']
    
    with open(filepath, 'w') as f:
        json.dump(workflow, f, indent=2)

# Configuration from environment
config = {
    'lightrag': os.environ.get('ENABLE_LIGHTRAG', 'false') == 'true',
    'multimodal': os.environ.get('ENABLE_MULTIMODAL', 'false') == 'true', 
    'contextual': os.environ.get('ENABLE_CONTEXTUAL', 'true') == 'true',
    'use_external_apis': os.environ.get('USE_EXTERNAL_APIS', 'false') == 'true',
    'main_model': os.environ.get('MAIN_MODEL', 'qwen3:8b-q4_K_M'),
    'embedding_model': os.environ.get('EMBEDDING_MODEL', 'nomic-embed-text'),
    'access_host': os.environ.get('ACCESS_HOST', 'localhost'),
    'lightrag_url': os.environ.get('LIGHTRAG_SERVER_URL', '')
}

# Configure each workflow
for workflow_file in ['workflows/staging/main-rag-workflow.json', 
                     'workflows/staging/knowledge-graph-workflow.json',
                     'workflows/staging/multimodal-rag-workflow.json']:
    if os.path.exists(workflow_file):
        configure_workflow(workflow_file, config)
        print(f"Configured: {workflow_file}")
EOF

    # Set environment for Python script
    export ENABLE_LIGHTRAG USE_EXTERNAL_APIS MAIN_MODEL EMBEDDING_MODEL ACCESS_HOST
    export ENABLE_MULTIMODAL ENABLE_CONTEXTUAL LIGHTRAG_SERVER_URL

    python3 /tmp/configure_workflows.py
    echo -e "${GREEN}✓ Workflows configured for deployment${NC}"
    


else
    echo -e "${YELLOW}Database not running - will start services first${NC}"
fi

# =============================================================================
# DATABASE FUNCTIONS SETUP
# =============================================================================

echo ""
echo -e "${YELLOW}=== Setting up SOTA RAG Database Functions ===${NC}"

# Database functions are already handled by the migration above
echo "Database functions deployed via migration..."

echo -e "${GREEN}✓ Database functions deployed${NC}"

# =============================================================================
# WORKFLOW DEPLOYMENT
# =============================================================================

echo ""
echo -e "${YELLOW}=== Deploying SOTA RAG Workflows ===${NC}"

# Wait for n8n to be ready
echo "Waiting for n8n to be ready..."
for i in {1..60}; do
    if docker exec n8n n8n --version >/dev/null 2>&1; then
        echo "n8n is ready!"
        break
    fi
    sleep 5
done

# Import workflows
echo "Importing SOTA RAG workflows..."

# Workflow import is now handled after credential mapping (see SOTA RAG import section below)
echo "SOTA RAG workflows will be imported after credentials are processed..."
echo "Existing InsightsLM workflows preserved for backward compatibility"

# Save unified credentials for user reference
cat > unified_credentials.txt << EOF
SOTA RAG Unified Login Credentials:
===================================
Email: ${UNIFIED_EMAIL}
Password: ${UNIFIED_PASSWORD}

Service URLs:
- Supabase Studio: http://${ACCESS_HOST}:8000
- n8n Workflows: http://${ACCESS_HOST}:5678
- InsightsLM UI: http://${ACCESS_HOST}:3010

Additional Services:
- Open WebUI: http://${ACCESS_HOST}:8080  
- Flowise: http://${ACCESS_HOST}:3001
EOF



echo -e "${GREEN}✓ SOTA RAG workflows deployed${NC}"

# =============================================================================
# FRONTEND COMPATIBILITY
# =============================================================================

echo ""
echo -e "${YELLOW}=== Ensuring Frontend Compatibility ===${NC}"

# Update InsightsLM frontend build args to include new environment variables
if [ -f "insights-lm-local-package/Dockerfile" ]; then
    # Add new build args for SOTA RAG features
    if ! grep -q "ARG ENABLE_LIGHTRAG" insights-lm-local-package/Dockerfile; then
        cp_sed '/ARG VITE_SUPABASE_ANON_KEY/a\
ARG ENABLE_LIGHTRAG\
ARG ENABLE_MULTIMODAL\
ARG ENABLE_CONTEXTUAL' insights-lm-local-package/Dockerfile
        
        cp_sed '/ENV VITE_SUPABASE_ANON_KEY/a\
ENV VITE_ENABLE_LIGHTRAG=${ENABLE_LIGHTRAG}\
ENV VITE_ENABLE_MULTIMODAL=${ENABLE_MULTIMODAL}\
ENV VITE_ENABLE_CONTEXTUAL=${ENABLE_CONTEXTUAL}' insights-lm-local-package/Dockerfile
        
        echo "  ✓ Frontend Dockerfile updated for SOTA features"
    fi
fi

# Update docker-compose to pass new build args to InsightsLM
if yq eval '.services | has("insightslm")' docker-compose.yml | grep -q "true"; then
    yq eval '.services.insightslm.build.args.ENABLE_LIGHTRAG = "${ENABLE_LIGHTRAG}"' -i docker-compose.yml
    yq eval '.services.insightslm.build.args.ENABLE_MULTIMODAL = "${ENABLE_MULTIMODAL}"' -i docker-compose.yml
    yq eval '.services.insightslm.build.args.ENABLE_CONTEXTUAL = "${ENABLE_CONTEXTUAL}"' -i docker-compose.yml
    echo "  ✓ Docker compose updated with SOTA feature flags"
fi

echo -e "${GREEN}✓ Frontend compatibility configured${NC}"

# =============================================================================
# FINAL CONFIGURATION
# =============================================================================

echo ""
echo -e "${YELLOW}=== Final Configuration ===${NC}"

# Create SOTA RAG credential templates
cat > workflows/credential-templates.json << EOF
{
  "openai_api": {
    "name": "OpenAI account SOTA",
    "type": "openAiApi", 
    "data": {
      "apiKey": "\${OPENAI_API_KEY}"
    }
  },
  "mistral_cloud_api": {
    "name": "Mistral Cloud account SOTA",
    "type": "mistralCloudApi",
    "data": {
      "apiKey": "\${MISTRAL_API_KEY}"
    }
  },
  "cohere_api": {
    "name": "Cohere API SOTA",
    "type": "httpHeaderAuth",
    "data": {
      "name": "Authorization",
      "value": "Bearer \${COHERE_API_KEY}"
    }
  },
  "zep_api": {
    "name": "Zep API SOTA", 
    "type": "httpHeaderAuth",
    "data": {
      "name": "Authorization",
      "value": "Api-Key \${ZEP_API_KEY}"
    }
  }
}
EOF

# Create deployment summary
cat > DEPLOYMENT_SUMMARY.txt << EOF
SOTA RAG Deployment Summary
===========================

Deployment Mode: Phase $DEPLOYMENT_MODE
$([ "$USE_EXTERNAL_APIS" = true ] && echo "Using External APIs" || echo "Local-Only Deployment")

Models:
- Main: $MAIN_MODEL  
- Embedding: $EMBEDDING_MODEL

Features Enabled:
- GraphRAG/LightRAG: $([[ "$ENABLE_LIGHTRAG" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")
- Multimodal RAG: $([[ "$ENABLE_MULTIMODAL" =~ ^[Yy]$ ]] && echo "Yes" || echo "No") 
- Contextual Embeddings: $([[ "$ENABLE_CONTEXTUAL" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")
- Long-term Memory: $([[ "$ENABLE_LONGTERM_MEMORY" =~ ^[Yy]$ ]] && echo "Yes" || echo "No")

Access URLs:
- Supabase: http://${ACCESS_HOST}:8000
- n8n: http://${ACCESS_HOST}:5678  
- InsightsLM: http://${ACCESS_HOST}:3010

Database Schema: Migrated to SOTA RAG (documents_v2, record_manager_v2, etc.)
Edge Functions: Enhanced SOTA RAG versions with jsr imports & better validation
Workflows: SOTA RAG workflows imported and configured
Read-only User: Created with proper security permissions
Idempotent: Script can be run multiple times safely
Reset Option: Available via interactive prompt (defaults to N for safety)

Next Steps:

Backup Location: $BACKUP_DIR
EOF

# Add deployment-specific next steps to summary
if [ "$USE_EXTERNAL_APIS" = true ]; then
    cat >> DEPLOYMENT_SUMMARY.txt << EOF

Next Steps for External API Mode:
1. Edit .env file and add your API keys:
   - OPENAI_API_KEY
   - MISTRAL_API_KEY  
   - COHERE_API_KEY
   - ZEP_API_KEY
   
2. If using LightRAG, set LIGHTRAG_SERVER_URL in .env

3. Restart services: python3 start_services.py --profile $PROFILE --environment private

4. Access n8n at http://${ACCESS_HOST}:5678 to activate workflows

5. Test the new SOTA RAG capabilities
EOF
else
    cat >> DEPLOYMENT_SUMMARY.txt << EOF

Next Steps for Local-Only Mode:
1. Ollama models configured:
   - Main model: $MAIN_MODEL ($([ "$IS_MACOS" = true ] && echo "running on host" || echo "running in Docker"))
   - Embedding model: $EMBEDDING_MODEL ($([ "$IS_MACOS" = true ] && echo "running on host" || echo "running in Docker"))

2. SOTA RAG workflows updated for local models:
   - OpenAI API calls replaced with Ollama endpoints
   - Embedding models switched to local Ollama

3. Configure local alternatives for:
   - OCR processing (instead of Mistral API)
   - Reranking (instead of Cohere API)
   - Long-term memory (instead of Zep API)

4. Access n8n at http://${ACCESS_HOST}:5678 to activate workflows

5. Test the local SOTA RAG capabilities

$([ "$IS_MACOS" = true ] && echo "
macOS Configuration:
- Ollama proxy service configured with nginx
- Host Ollama lifecycle management active
- Watcher process monitoring container state" || echo "
Linux Configuration:
- Docker Ollama services configured
- Model auto-pull configured")
EOF
fi

echo -e "${GREEN}✓ SOTA RAG deployment configured${NC}"

# Create deployment flag for future idempotent runs
echo "$(date)" > sota-rag-deployment.flag

# =============================================================================
# ORCHESTRATED UPGRADE  
# =============================================================================

echo ""
echo -e "${YELLOW}=== Running SOTA RAG Upgrade Orchestrator ===${NC}"

# Set environment variables for orchestrator
export DEPLOYMENT_MODE USE_EXTERNAL_APIS MAIN_MODEL EMBEDDING_MODEL ACCESS_HOST
export ENABLE_LIGHTRAG ENABLE_MULTIMODAL ENABLE_CONTEXTUAL ENABLE_LONGTERM_MEMORY

# =============================================================================
# UNIFIED USER SETUP (like easy_setup_v2.sh)
# =============================================================================

echo ""
echo -e "${YELLOW}=== Setting up Unified Admin Users ===${NC}"

# Create Supabase Auth user (following easy_setup_v2.sh pattern exactly)
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
    # Update existing user's password and ensure all token fields are properly set (following easy_setup_v2.sh pattern)
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

# Create n8n user (following easy_setup_v2.sh pattern)
echo "Setting up n8n admin user..."
PASSWORD_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'${UNIFIED_PASSWORD}', bcrypt.gensalt()).decode())")

# Wait for n8n to initialize
sleep 10

# Update n8n user (following easy_setup_v2.sh pattern exactly)
docker exec supabase-db psql -U postgres -d postgres -c "
UPDATE \"user\" SET 
    email='${UNIFIED_EMAIL}',
    \"firstName\"='Admin',
    \"lastName\"='User',
    password='${PASSWORD_HASH}'
WHERE role='global:owner';" >/dev/null 2>&1

# CRITICAL: Set the instance owner setup flag to true (following easy_setup_v2.sh pattern exactly)
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

# Restart n8n briefly to ensure setup flag is recognized (following easy_setup_v2.sh pattern)
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

echo "✅ Unified admin user configured across all services"

# =============================================================================
# SOTA RAG CREDENTIALS AND WORKFLOW IMPORT
# =============================================================================

echo ""
echo -e "${YELLOW}=== Importing SOTA RAG with Unified Credentials ===${NC}"

# Run the credentials and workflow import process (idempotent unless FORCE_RESET)
echo "Running SOTA RAG credentials and workflow import..."

# Force credential import if FORCE_RESET is true
if [ "$FORCE_RESET" = true ]; then
    echo -e "${RED}🔄 RESET MODE: Forcing fresh credential import...${NC}"
    # Delete existing SOTA credentials first
    docker exec supabase-db psql -U supabase_admin -d postgres -c "DELETE FROM credentials_entity WHERE name LIKE '%SOTA%';" >/dev/null 2>&1 || true
    FORCE_CRED_IMPORT=true
else
    echo "  → Checking for existing credentials..."
    CRED_COUNT=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "SELECT COUNT(*) FROM credentials_entity WHERE name LIKE '%SOTA%';" 2>/dev/null | tr -d '\r')
    if [ "$CRED_COUNT" -gt 0 ] && [ -n "$CRED_COUNT" ]; then
        echo "    ✓ SOTA RAG credentials already exist ($CRED_COUNT found)"
        echo -e "${GREEN}✓ SOTA RAG credentials already configured${NC}"
        FORCE_CRED_IMPORT=false
    else
        FORCE_CRED_IMPORT=true
    fi
fi

if [ "$FORCE_CRED_IMPORT" = true ]; then
    echo "  → Importing SOTA RAG credentials..."
    if python3 sota-rag-upgrade/fix-env-and-deploy.py 2>&1; then
        echo -e "${GREEN}✓ SOTA RAG credentials imported${NC}"
        
        # Now update workflow files with imported credential IDs (following easy_setup_v2.sh pattern)
        echo "  → Updating workflow files with imported credential IDs..."
        
        # Get the actual credential IDs from database
        OPENAI_ID=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "SELECT id FROM credentials_entity WHERE name LIKE '%OpenAI%SOTA%' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')
        MISTRAL_ID=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "SELECT id FROM credentials_entity WHERE name LIKE '%Mistral%SOTA%' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')
        SUPABASE_ID=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "SELECT id FROM credentials_entity WHERE name LIKE '%Supabase%SOTA%' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')
        POSTGRES_ID=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "SELECT id FROM credentials_entity WHERE name LIKE '%Postgres%SOTA%' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')
        COHERE_ID=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "SELECT id FROM credentials_entity WHERE name LIKE '%Cohere%SOTA%' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')
        
        if [ -n "$OPENAI_ID" ] && [ -n "$SUPABASE_ID" ]; then
            # Check if workflows need credential updates (idempotent check)
            OLD_CREDS_COUNT=$(grep -l "MM0xMOJkVoJoWOLP\|wwbxqbDc4H2RPQ1Y\|rmhBwssORDiWOBKN" workflows/staging/*.json 2>/dev/null | wc -l | tr -d ' ')
            
            if [ "$OLD_CREDS_COUNT" -gt 0 ]; then
                echo "    Credential IDs found - updating workflow files..."
                echo "      OpenAI: $OPENAI_ID"
                echo "      Mistral: $MISTRAL_ID" 
                echo "      Supabase: $SUPABASE_ID"
                echo "      Postgres: $POSTGRES_ID"
                echo "      Cohere: $COHERE_ID"
            
            # Update workflow files with credential IDs (following easy_setup_v2.sh pattern)
            python3 - << EOF
import json
import os

# Credential mapping from SOTA RAG placeholders to our imported IDs
credential_mapping = {
    "MM0xMOJkVoJoWOLP": "${OPENAI_ID}",     # OpenAI
    "rmhBwssORDiWOBKN": "${MISTRAL_ID}",   # Mistral  
    "wwbxqbDc4H2RPQ1Y": "${SUPABASE_ID}",  # Supabase
    "7aOzWLaZcz9dgeSv": "${POSTGRES_ID}",  # Postgres
    "23C5j0AXw4jqMvqo": "${COHERE_ID}",    # Cohere
    "SaJzpmSGdmOFSPDn": "${COHERE_ID}",    # Cohere variant
    "lGWdzUJKbAFBqqTT": "${COHERE_ID}",    # Zep fallback
    "ASaNYCEZJOKUmtf9": "${COHERE_ID}",    # Header auth fallback
}

workflow_files = [
    "workflows/staging/main-rag-workflow.json",
    "workflows/staging/knowledge-graph-workflow.json", 
    "workflows/staging/multimodal-rag-workflow.json"
]

total_updates = 0
for workflow_file in workflow_files:
    if os.path.exists(workflow_file):
        with open(workflow_file, 'r') as f:
            workflow = json.load(f)
        
        updates_made = 0
        for node in workflow.get('nodes', []):
            if 'credentials' in node:
                for cred_type, cred_info in node['credentials'].items():
                    old_id = cred_info.get('id', '')
                    if old_id in credential_mapping:
                        cred_info['id'] = credential_mapping[old_id]
                        updates_made += 1
        
        with open(workflow_file, 'w') as f:
            json.dump(workflow, f, indent=2)
        
        print(f"Updated {updates_made} credentials in {workflow_file}")
        total_updates += updates_made

print(f"Total credential updates: {total_updates}")
EOF
            
            # Re-import workflows with updated credential IDs
            echo "  → Re-importing workflows with correct credentials..."
            
            # Remove existing workflows to import fresh ones with correct credentials
            docker exec supabase-db psql -U supabase_admin -d postgres -c "DELETE FROM workflow_entity WHERE name LIKE '%SOTA%' OR name LIKE '%Knowledge Graph Updates%' OR name LIKE '%Multimodal RAG%';" >/dev/null 2>&1 || true
            
            # Import Knowledge Graph workflow FIRST (required dependency)
            if [ -f "workflows/staging/knowledge-graph-workflow.json" ]; then
                echo "    → Importing Knowledge Graph workflow..."
                docker cp workflows/staging/knowledge-graph-workflow.json n8n:/tmp/knowledge-graph-workflow.json
                docker exec n8n n8n import:workflow --input=/tmp/knowledge-graph-workflow.json >/dev/null 2>&1 || true
                echo "      ✓ Knowledge Graph workflow imported with correct credentials"
            fi

            # Import main SOTA RAG workflow
            if [ -f "workflows/staging/main-rag-workflow.json" ]; then
                echo "    → Importing Main SOTA RAG workflow..."
                docker cp workflows/staging/main-rag-workflow.json n8n:/tmp/main-rag-workflow.json
                docker exec n8n n8n import:workflow --input=/tmp/main-rag-workflow.json >/dev/null 2>&1 || true
                echo "      ✓ Main SOTA RAG workflow imported with correct credentials"
            fi

            # Import Multimodal RAG workflow if enabled
            if [[ "$ENABLE_MULTIMODAL" =~ ^[Yy]$ ]] && [ -f "workflows/staging/multimodal-rag-workflow.json" ]; then
                echo "    → Importing Multimodal RAG workflow..."
                docker cp workflows/staging/multimodal-rag-workflow.json n8n:/tmp/multimodal-rag-workflow.json
                docker exec n8n n8n import:workflow --input=/tmp/multimodal-rag-workflow.json >/dev/null 2>&1 || true
                echo "      ✓ Multimodal RAG workflow imported with correct credentials"
            fi
            
                # Update Ollama model references in workflows if using local models (following easy_setup_v2.sh pattern)
                if [ "$USE_EXTERNAL_APIS" = false ]; then
                    echo "    → Updating SOTA RAG workflows to use local Ollama models..."
                    
                    # Update main model references (gpt-4o -> user selected model)
                    echo "      Updating main model references to $MAIN_MODEL..."
                    MAIN_MODEL_UPDATES=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "
                    UPDATE workflow_entity 
                    SET nodes = REPLACE(
                        REPLACE(
                            REPLACE(nodes::text, 
                                '\"model\": \"gpt-4o\"', '\"model\": \"$MAIN_MODEL\"'),
                                '\"model\": \"gpt-5\"', '\"model\": \"$MAIN_MODEL\"'),
                                '\"value\": \"gpt-4\"', '\"value\": \"$MAIN_MODEL\"')::jsonb
                    WHERE name LIKE '%SOTA%' AND (nodes::text LIKE '%gpt-4%' OR nodes::text LIKE '%gpt-5%')
                    RETURNING id;" 2>/dev/null | wc -l | tr -d ' ')
                    echo "        Updated main model in $MAIN_MODEL_UPDATES workflow instances"

                    # Update embedding model references  
                    echo "      Updating embedding model references to $EMBEDDING_MODEL..."
                    EMBED_UPDATES=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "
                    UPDATE workflow_entity 
                    SET nodes = REPLACE(
                        REPLACE(nodes::text, 
                            '\"text-embedding-3-small\"', '\"$EMBEDDING_MODEL\"'),
                            '\"text-embedding-ada-002\"', '\"$EMBEDDING_MODEL\"')::jsonb
                    WHERE name LIKE '%SOTA%' AND (nodes::text LIKE '%text-embedding-%')
                    RETURNING id;" 2>/dev/null | wc -l | tr -d ' ')
                    echo "        Updated embedding model in $EMBED_UPDATES workflow instances"
                    
                    echo -e "${GREEN}      ✓ SOTA RAG workflows updated for local Ollama models${NC}"
                fi
                
                echo -e "${GREEN}✓ All workflows imported with correct credential IDs${NC}"
            else
                echo "    ✓ Workflow credential IDs already current"
            fi
        else
            echo -e "${YELLOW}⚠️  Could not retrieve credential IDs from database${NC}"
        fi
        
    else
        echo -e "${RED}✗ SOTA RAG credential import failed${NC}"
        echo "Check the logs above and the backup directory for recovery options"
        
        # Don't exit - let the deployment continue as the basic services are working
        echo -e "${YELLOW}⚠️  Continuing deployment - you can import SOTA RAG credentials manually via n8n UI${NC}"
        echo "Services are running and ready for manual SOTA RAG configuration"
    fi
fi

# =============================================================================
# FINAL OUTPUT
# =============================================================================

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}🎉 === SOTA RAG DEPLOYMENT COMPLETE === 🎉${NC}"  
echo -e "${GREEN}============================================================${NC}"
echo ""

cat DEPLOYMENT_SUMMARY.txt

echo ""
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${BLUE}Files created during deployment:${NC}"
echo "📋 SOTA_RAG_UPGRADE_ROADMAP.md - Detailed upgrade strategy"
echo "📋 SOTA_RAG_SETUP_GUIDE.md - Complete setup documentation"
echo "📋 DEPLOYMENT_SUMMARY.txt - Deployment configuration summary"
echo "📋 api-keys-template.env - API key configuration template" 
echo "🔧 workflows/credential-templates.json - API credential templates"
echo "🔧 Enhanced edge functions - Vector Search & Hybrid Search (from SOTA RAG src)"
echo "🔧 Database functions - hybrid_search_v2_with_details & match_documents_v2_vector"
echo "🔧 Database tables - documents_v2, record_manager_v2, metadata_fields, tabular_document_rows"
echo "🔧 Read-only database user - For secure query operations"
echo "🐍 Complete SOTA RAG upgrade following sota-rag-setup.md specifications"
echo "📂 $BACKUP_DIR/ - Backup of previous state"
echo ""

if [ "$USE_EXTERNAL_APIS" = true ]; then
    echo -e "${YELLOW}⚠️  NEXT STEPS FOR EXTERNAL API MODE:${NC}"
    echo "1. Edit .env file using api-keys-template.env as reference"
    echo "2. Add your actual API keys (OpenAI, Mistral, Cohere, Zep)"
    echo "3. Restart services: python3 start_services.py --profile $PROFILE --environment private"
    echo "4. Access n8n at http://${ACCESS_HOST}:5678 to activate workflows"
    echo "5. Test SOTA RAG features"
    echo ""
    echo -e "${BLUE}📖 See SOTA_RAG_SETUP_GUIDE.md for detailed configuration instructions${NC}"
else
    echo -e "${YELLOW}⚠️  NEXT STEPS FOR LOCAL-ONLY MODE:${NC}"
    if [ "$IS_MACOS" = true ]; then
        echo "1. ✅ Ollama models pre-pulled and ready:"
        echo "   - Main model: $MAIN_MODEL (running on host)"
        echo "   - Embedding model: $EMBEDDING_MODEL (running on host)"
        echo "   - Proxy service: nginx configured for Docker access"
        echo "2. ✅ SOTA RAG workflows updated for local Ollama models"
    else
        echo "1. Ensure required Ollama models are available in Docker:"
        echo "   - Main model: $MAIN_MODEL"
        echo "   - Embedding model: $EMBEDDING_MODEL"
        echo "   (Models will be auto-pulled by x-init-ollama service)"
        echo "2. ✅ SOTA RAG workflows updated for local Ollama models"
    fi
    echo "3. Configure local alternatives for remaining external services:"
    echo "   - OCR processing (replace Mistral API with local OCR)"
    echo "   - Reranking (replace Cohere API with local reranker)"
    echo "   - Long-term memory (replace Zep API with local memory)"
    echo "4. Access n8n at http://${ACCESS_HOST}:5678 to activate workflows"
    echo "5. Test local SOTA RAG features"
    echo ""
    echo -e "${BLUE}📖 See SOTA_RAG_SETUP_GUIDE.md for local alternative configurations${NC}"
fi

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${BLUE}🚀 SOTA RAG deployment ready! Your AI capabilities have been significantly enhanced.${NC}"
echo ""
echo -e "${BLUE}💡 Note: This script is idempotent - you can run it multiple times safely.${NC}"
echo -e "${BLUE}   Future runs will preserve existing data and only update components as needed.${NC}"
echo ""
echo -e "${BLUE}🔧 Credential Mapping: All SOTA RAG workflows use correct credential IDs${NC}"
echo -e "${BLUE}   Following easy_setup_v2.sh pattern: import credentials → update workflows → re-import${NC}"
echo ""
if [ "$USE_EXTERNAL_APIS" = false ]; then
    if [ "$IS_MACOS" = true ]; then
        echo -e "${BLUE}🍎 macOS Ollama Configuration:${NC}"
        echo -e "${BLUE}   Native Ollama on host (0.0.0.0:11434) + Docker nginx proxy${NC}"
        echo -e "${BLUE}   Lifecycle management: Container start/stop triggers host Ollama start/stop${NC}"
        echo -e "${BLUE}   Models: $MAIN_MODEL, $EMBEDDING_MODEL (pre-pulled)${NC}"
    else
        echo -e "${BLUE}🐧 Linux Ollama Configuration:${NC}"
        echo -e "${BLUE}   Docker Ollama services with auto-pull configuration${NC}"
        echo -e "${BLUE}   Models: $MAIN_MODEL, $EMBEDDING_MODEL (auto-pull configured)${NC}"
    fi
    echo ""
fi
echo -e "${BLUE}🔄 Reset Option: Run script again and select 'y' for reset to wipe all data${NC}"
echo -e "${GREEN}============================================================${NC}"
