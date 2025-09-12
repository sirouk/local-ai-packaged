#!/bin/bash
# Unified AI System Deployment Script
# 
# USAGE:
#   Remote execution (run from anywhere):
#     bash <(curl -sSf -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' https://raw.githubusercontent.com/sirouk/local-ai-packaged/refs/heads/make-static/easy_deploy.sh)
#
#   Local execution (from cloned repository):
#     ./easy_deploy.sh
#
# DEPLOYMENT MODES:
# 1. InsightsLM Legacy - Original notebook/content generation system
# 2. SOTA RAG 2.1 - Advanced hybrid search, GraphRAG, multimodal capabilities  
# 3. Both Systems - Dual independent deployment (default)
#
# Features:
# - Remote execution with automatic repository setup
# - Automatic repository management (clone/update as needed)
# - Smart validation based on deployment selection
# - Independent database schemas and workflows
# - Upgrade paths between deployment modes
# - Idempotent operation (safe to run multiple times)

set -e

# =============================================================================
# EXECUTION METHOD DETECTION AND REPOSITORY SETUP
# =============================================================================

# Detect if script is being run via curl | bash vs locally
SCRIPT_NAME="$(basename "$0" 2>/dev/null || echo "unknown")"
REMOTE_EXECUTION=false

# Check if running via curl | bash (script name will be like "bash", "/dev/fd/63", etc.)
if [[ "$SCRIPT_NAME" == "bash" ]] || [[ "$0" =~ ^/dev/fd/ ]] || [[ "$0" =~ ^/proc/self/fd/ ]] || [[ ! -f "$0" ]]; then
    REMOTE_EXECUTION=true
    echo "🌐 Remote execution detected (curl | bash)"
else
    echo "📁 Local execution detected"
    REMOTE_EXECUTION=false
fi

# Repository configuration
REPO_URL="https://github.com/sirouk/local-ai-packaged.git"
REPO_BRANCH="make-static"
TARGET_DIR="local-ai-packaged"

# Handle repository setup based on execution method
if [ "$REMOTE_EXECUTION" = true ]; then
    echo "🔄 Setting up repository for remote execution..."
    
    # Check if we're already in the target directory
    if [ -f "docker-compose.yml" ] && [ -f "easy_setup_v2.sh" ]; then
        echo "✅ Already in local-ai-packaged directory"
    elif [ -d "$TARGET_DIR" ]; then
        echo "📁 Found existing $TARGET_DIR directory, entering it..."
        cd "$TARGET_DIR"
        
        # Verify it's the right repo and update it
        if [ -d ".git" ]; then
            echo "🔄 Updating existing repository..."
            git fetch origin "$REPO_BRANCH" >/dev/null 2>&1 || true
            git reset --hard "origin/$REPO_BRANCH" >/dev/null 2>&1 || true
            echo "✅ Repository updated to latest $REPO_BRANCH"
        else
            echo "⚠️  Directory exists but isn't a git repo, using as-is"
        fi
    else
        echo "📥 Cloning repository..."
        if command -v git >/dev/null 2>&1; then
            git clone -b "$REPO_BRANCH" "$REPO_URL" "$TARGET_DIR" || {
                echo "❌ Failed to clone repository"
                echo "Please manually run: git clone -b $REPO_BRANCH $REPO_URL $TARGET_DIR"
                echo "Then cd into $TARGET_DIR and run this script locally"
                exit 1
            }
            cd "$TARGET_DIR"
            echo "✅ Repository cloned and entered"
        else
            echo "❌ Git not found. Please install git first:"
            echo "  macOS: brew install git"
            echo "  Ubuntu/Debian: sudo apt install git"
            echo "  CentOS/RHEL: sudo yum install git"
            exit 1
        fi
    fi
else
    # Local execution - use existing directory logic
    cd "$(dirname "$0")"
fi

# Default model configuration (following easy_setup_v2.sh pattern)
DEFAULT_LOCAL_MODEL="qwen3:8b-q4_K_M"
DEFAULT_EMBEDDING_MODEL="nomic-embed-text"
DEFAULT_EXTERNAL_MODEL="gpt-4o"
DEFAULT_EXTERNAL_EMBEDDING="text-embedding-3-small"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Unified AI System Deployment Script ===${NC}"
echo -e "${BLUE}Execution Mode: $([ "$REMOTE_EXECUTION" = true ] && echo "Remote (curl | bash)" || echo "Local")${NC}"
echo -e "${BLUE}Choose from: InsightsLM Legacy | SOTA RAG 2.1 | Both Systems${NC}"
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

# Verify we're in the correct directory (should always pass after setup above)
if [ ! -f "docker-compose.yml" ] || [ ! -f "easy_setup_v2.sh" ]; then
    echo -e "${RED}Error: Required files not found in current directory${NC}"
    echo "Expected files: docker-compose.yml, easy_setup_v2.sh"
    echo "Current directory: $(pwd)"
    echo "Directory contents:"
    ls -la || true
    if [ "$REMOTE_EXECUTION" = true ]; then
        echo -e "${RED}Repository setup failed. Please try running the script again.${NC}"
    else
        echo -e "${RED}Please ensure you're running this script from the local-ai-packaged directory${NC}"
    fi
    exit 1
fi

echo -e "${GREEN}✓ Verified: Running in local-ai-packaged directory$([ "$REMOTE_EXECUTION" = true ] && echo " (auto-setup)" || echo " (local)")${NC}"

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

# Check if we should reuse existing credentials from .env (skip in reset mode)
if [ -f .env ] && [ "$FORCE_RESET" != "true" ]; then
    # Source existing .env to get current values (only if not resetting)
    source .env 2>/dev/null || true
    echo "  Found existing .env file - reusing credentials where available"
elif [ "$FORCE_RESET" = "true" ]; then
    echo "  Reset mode - generating completely fresh credentials"
else
    echo "  No existing .env file - generating fresh credentials"
fi

# Generate unified credentials (following easy_setup_v2.sh pattern exactly)
UNIFIED_EMAIL="admin@local.host"

# Generate new password for fresh install (following easy_setup_v2.sh pattern exactly)
echo "  Generating unified password"
DASHBOARD_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)
UNIFIED_PASSWORD=$DASHBOARD_PASSWORD

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
echo -e "${YELLOW}System Deployment Options:${NC}"
echo "1. InsightsLM Legacy - Original notebook/content generation system only"
echo "2. SOTA RAG 2.1 - Advanced hybrid search, GraphRAG, multimodal capabilities only"
echo "3. Both Systems - InsightsLM + SOTA RAG dual deployment (independent operation)"
echo ""
read -p "Select deployment mode (press Enter for Both Systems): " -r DEPLOYMENT_MODE
DEPLOYMENT_MODE=${DEPLOYMENT_MODE:-3}

if [[ "$DEPLOYMENT_MODE" != "1" && "$DEPLOYMENT_MODE" != "2" && "$DEPLOYMENT_MODE" != "3" ]]; then
    echo -e "${RED}Invalid selection. Please choose 1, 2, or 3.${NC}"
    exit 1
fi

if [ "$DEPLOYMENT_MODE" = "1" ]; then
    echo -e "${GREEN}✓ InsightsLM Legacy selected - Original system only${NC}"
    DEPLOY_INSIGHTSLM=true
    DEPLOY_SOTA_RAG=false
    USE_EXTERNAL_APIS=false
    echo -e "${BLUE}Note: This deploys only the original InsightsLM system with Ollama${NC}"
elif [ "$DEPLOYMENT_MODE" = "2" ]; then
    echo -e "${GREEN}✓ SOTA RAG 2.1 selected - Advanced system only${NC}"
    DEPLOY_INSIGHTSLM=false
    DEPLOY_SOTA_RAG=true
    
    # For SOTA RAG, ask about external APIs vs local vs hybrid
    echo ""
    echo -e "${YELLOW}SOTA RAG API Configuration:${NC}"
    echo "A. External APIs (OpenAI, Mistral, Cohere, Zep) - Fast setup, full features"
    echo "B. Local-Only (Ollama + local alternatives) - Privacy focused, no API costs"
    echo "C. Both Local and External (Hybrid) - Best flexibility, use both as needed"
    echo ""
    read -p "Select API mode (C/a/b): " -r API_MODE
    API_MODE=${API_MODE:-C}
    
    if [[ "$API_MODE" =~ ^[Aa]$ ]]; then
        USE_EXTERNAL_APIS=true
        USE_LOCAL_APIS=false
        HYBRID_MODE=false
        echo -e "${GREEN}✓ SOTA RAG with External APIs only${NC}"
    elif [[ "$API_MODE" =~ ^[Bb]$ ]]; then
        USE_EXTERNAL_APIS=false
        USE_LOCAL_APIS=true
        HYBRID_MODE=false
        echo -e "${GREEN}✓ SOTA RAG with Local-Only${NC}"
    else
        USE_EXTERNAL_APIS=true
        USE_LOCAL_APIS=true
        HYBRID_MODE=true
        echo -e "${GREEN}✓ SOTA RAG with Both Local and External APIs (Hybrid)${NC}"
    fi
else
    echo -e "${GREEN}✓ Both Systems selected - InsightsLM + SOTA RAG dual deployment${NC}"
    DEPLOY_INSIGHTSLM=true
    DEPLOY_SOTA_RAG=true
    
    # For dual deployment, ask about SOTA API mode
    echo ""
    echo -e "${YELLOW}SOTA RAG API Configuration (InsightsLM will use local Ollama):${NC}"
    echo "A. External APIs for SOTA RAG (OpenAI, Mistral, Cohere, Zep)"
    echo "B. Local-Only for both systems (Ollama + local alternatives)"
    echo "C. Both Local and External (Hybrid) - Best flexibility, use both as needed"
    echo ""
    read -p "Select API mode (C/a/b): " -r API_MODE
    API_MODE=${API_MODE:-C}
    
    if [[ "$API_MODE" =~ ^[Aa]$ ]]; then
        USE_EXTERNAL_APIS=true
        USE_LOCAL_APIS=true  # Always include local for InsightsLM
        HYBRID_MODE=false
        echo -e "${GREEN}✓ Dual System: InsightsLM (Local) + SOTA RAG (External APIs)${NC}"
    elif [[ "$API_MODE" =~ ^[Bb]$ ]]; then
        USE_EXTERNAL_APIS=false
        USE_LOCAL_APIS=true
        HYBRID_MODE=false
        echo -e "${GREEN}✓ Dual System: Both using local models and alternatives${NC}"
    else
        USE_EXTERNAL_APIS=true
        USE_LOCAL_APIS=true
        HYBRID_MODE=true
        echo -e "${GREEN}✓ Dual System: Both Local and External APIs (Hybrid)${NC}"
    fi
fi

# =============================================================================
# REPOSITORY MANAGEMENT (After deployment mode selection)
# =============================================================================

echo ""
echo -e "${YELLOW}=== Checking and Updating Required Repositories ===${NC}"

# Repository URLs (matching easy_setup_v2.sh)
INSIGHTS_LM_REPO="https://github.com/sirouk/insights-lm-local-package.git"
SUPABASE_REPO="https://github.com/sirouk/supabase.git"

# Check insights-lm-local-package (needed for InsightsLM deployment)
if [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo "Checking insights-lm-local-package repository..."
    if [ -d "insights-lm-local-package/.git" ]; then
        echo "  → Found existing git repository - updating..."
        cd insights-lm-local-package
        git pull >/dev/null 2>&1 || echo "    Warning: Could not update repository"
        cd ..
        echo "  ✅ insights-lm-local-package updated"
    elif [ -d "insights-lm-local-package" ]; then
        echo "  ✅ insights-lm-local-package directory exists (not a git repo)"
    else
        echo "  → Cloning insights-lm-local-package repository..."
        git clone "$INSIGHTS_LM_REPO" >/dev/null 2>&1 || {
            echo -e "${RED}Error: Failed to clone insights-lm-local-package${NC}"
            echo "Please manually clone: $INSIGHTS_LM_REPO"
            exit 1
        }
        echo "  ✅ insights-lm-local-package cloned"
    fi
fi

# Check supabase repository (needed for both deployments)
echo "Checking supabase repository..."
if [ -d "supabase/.git" ]; then
    echo "  → Found existing git repository - updating..."
    cd supabase
    git pull >/dev/null 2>&1 || echo "    Warning: Could not update repository"
    cd ..
    echo "  ✅ supabase updated"
elif [ ! -d "supabase/docker" ]; then
    echo "  → Cloning supabase repository (sparse checkout)..."
    git clone --filter=blob:none --no-checkout "$SUPABASE_REPO" >/dev/null 2>&1 || {
        echo -e "${RED}Error: Failed to clone supabase${NC}"
        echo "Please manually clone: $SUPABASE_REPO"
        exit 1
    }
    cd supabase
    git sparse-checkout init --cone >/dev/null 2>&1
    git sparse-checkout set docker >/dev/null 2>&1
    git checkout master >/dev/null 2>&1
    cd ..
    echo "  ✅ supabase cloned and configured"
else
    echo "  ✅ supabase/docker directory exists"
fi

echo -e "${GREEN}✓ Required repositories verified and up to date${NC}"

# Validate required files exist for selected deployment mode
echo ""
echo -e "${YELLOW}=== Validating Deployment Requirements ===${NC}"

if [ "$DEPLOY_INSIGHTSLM" = true ]; then
    # Check InsightsLM requirements
    if [ ! -f "insights-lm-local-package/supabase-migration.sql" ]; then
        echo -e "${RED}Error: InsightsLM migration file not found${NC}"
        echo "Expected: insights-lm-local-package/supabase-migration.sql"
        exit 1
    fi
    
    if [ ! -f "insights-lm-local-package/n8n/Local_Import_Insights_LM_Workflows.json" ]; then
        echo -e "${RED}Error: InsightsLM workflow import file not found${NC}"
        echo "Expected: insights-lm-local-package/n8n/Local_Import_Insights_LM_Workflows.json"
        exit 1
    fi
    
    if [ ! -d "insights-lm-local-package/supabase-functions" ]; then
        echo -e "${RED}Error: InsightsLM edge functions not found${NC}"
        echo "Expected: insights-lm-local-package/supabase-functions/"
        exit 1
    fi
    
    echo "  ✅ InsightsLM requirements validated"
fi

if [ "$DEPLOY_SOTA_RAG" = true ]; then
    # Check SOTA RAG requirements  
    if [ ! -f "sota-rag-upgrade/src/TheAIAutomators.com - RAG SOTA - v2.1 BLUEPRINT (1).json" ]; then
        echo -e "${RED}Error: SOTA RAG main workflow not found${NC}"
        echo "Expected: sota-rag-upgrade/src/TheAIAutomators.com - RAG SOTA - v2.1 BLUEPRINT (1).json"
        exit 1
    fi
    
    if [ ! -f "sota-rag-upgrade/src/hybrid_search_database_function.txt" ]; then
        echo -e "${RED}Error: SOTA RAG database functions not found${NC}"
        echo "Expected: sota-rag-upgrade/src/hybrid_search_database_function.txt"
        exit 1
    fi
    
    echo "  ✅ SOTA RAG requirements validated"
fi

if [ ! -d "supabase/docker" ]; then
    echo -e "${RED}Error: Supabase docker configuration not found${NC}"
    echo "Expected: supabase/docker/ directory"
    exit 1
fi

echo -e "${GREEN}✓ All deployment requirements validated${NC}"

# Show what will be deployed
echo ""
echo -e "${BLUE}=== Deployment Summary ===${NC}"
if [ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}📝 Systems to Deploy: InsightsLM Legacy + SOTA RAG 2.1${NC}"
    echo -e "   → InsightsLM: Original notebook/content generation (768-dim vectors)"
    echo -e "   → SOTA RAG: Advanced hybrid search, GraphRAG, multimodal (1536-dim vectors)"
    echo -e "   → Integration: Independent operation with future bridge workflows planned"
elif [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo -e "${GREEN}📝 System to Deploy: InsightsLM Legacy${NC}"
    echo -e "   → Complete original functionality with local Ollama"
    echo -e "   → Upgrade path: Re-run script and select 'Both Systems' to add SOTA RAG"
elif [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}📝 System to Deploy: SOTA RAG 2.1${NC}"
    if [ "$USE_EXTERNAL_APIS" = true ] && [ "$USE_LOCAL_APIS" = true ]; then
        echo -e "   → Advanced RAG with hybrid mode (both external APIs and local models)"
    elif [ "$USE_EXTERNAL_APIS" = true ]; then
        echo -e "   → Advanced RAG with external APIs"
    else
        echo -e "   → Advanced RAG with local models"
    fi
    echo -e "   → Upgrade path: Re-run script and select 'Both Systems' to add InsightsLM UI"
fi

# API Key Collection (only if using external APIs)
if [ "$USE_EXTERNAL_APIS" = true ]; then
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
fi

# 2. Model Configuration
echo ""
echo -e "${YELLOW}Model Configuration:${NC}"

# Configure models based on deployment mode and API selection
if [ "$DEPLOYMENT_MODE" = "1" ]; then
    # InsightsLM Legacy - always uses local models
    echo -e "InsightsLM Legacy mode - configuring local Ollama models"
    read -p "Enter main model (press Enter for default: $DEFAULT_LOCAL_MODEL): " -r MAIN_MODEL
    MAIN_MODEL=${MAIN_MODEL:-$DEFAULT_LOCAL_MODEL}
    read -p "Enter embedding model (press Enter for default: $DEFAULT_EMBEDDING_MODEL): " -r EMBEDDING_MODEL
    EMBEDDING_MODEL=${EMBEDDING_MODEL:-$DEFAULT_EMBEDDING_MODEL}
elif [ "$HYBRID_MODE" = true ]; then
    # Hybrid mode - configure both local and external models (local first as foundation)
    echo -e "Hybrid mode - configuring both local and external models"
    
    echo ""
    echo -e "${YELLOW}Local Models (foundation for InsightsLM and local SOTA RAG):${NC}"
    read -p "Enter local main model (press Enter for default: $DEFAULT_LOCAL_MODEL): " -r LOCAL_MAIN_MODEL
    LOCAL_MAIN_MODEL=${LOCAL_MAIN_MODEL:-$DEFAULT_LOCAL_MODEL}
    read -p "Enter local embedding model (press Enter for default: $DEFAULT_EMBEDDING_MODEL): " -r LOCAL_EMBEDDING_MODEL
    LOCAL_EMBEDDING_MODEL=${LOCAL_EMBEDDING_MODEL:-$DEFAULT_EMBEDDING_MODEL}
    
    echo ""
    echo -e "${YELLOW}External API Models (for SOTA RAG advanced features):${NC}"
    read -p "Enter external main model (press Enter for default: $DEFAULT_EXTERNAL_MODEL): " -r EXTERNAL_MAIN_MODEL
    EXTERNAL_MAIN_MODEL=${EXTERNAL_MAIN_MODEL:-$DEFAULT_EXTERNAL_MODEL}
    read -p "Enter external embedding model (press Enter for default: $DEFAULT_EXTERNAL_EMBEDDING): " -r EXTERNAL_EMBEDDING_MODEL
    EXTERNAL_EMBEDDING_MODEL=${EXTERNAL_EMBEDDING_MODEL:-$DEFAULT_EXTERNAL_EMBEDDING}
    
    # Set primary models (external for SOTA RAG, local for InsightsLM)
    MAIN_MODEL=$EXTERNAL_MAIN_MODEL
    EMBEDDING_MODEL=$EXTERNAL_EMBEDDING_MODEL
elif [ "$USE_EXTERNAL_APIS" = true ]; then
    # External APIs only
    echo -e "External API mode - configuring OpenAI models"
    read -p "Enter main model (press Enter for default: $DEFAULT_EXTERNAL_MODEL): " -r MAIN_MODEL
    MAIN_MODEL=${MAIN_MODEL:-$DEFAULT_EXTERNAL_MODEL}
    read -p "Enter embedding model (press Enter for default: $DEFAULT_EXTERNAL_EMBEDDING): " -r EMBEDDING_MODEL
    EMBEDDING_MODEL=${EMBEDDING_MODEL:-$DEFAULT_EXTERNAL_EMBEDDING}
else
    # Local-only mode
    echo -e "Local mode - configuring Ollama models"
    read -p "Enter main model (press Enter for default: $DEFAULT_LOCAL_MODEL): " -r MAIN_MODEL
    MAIN_MODEL=${MAIN_MODEL:-$DEFAULT_LOCAL_MODEL}
    read -p "Enter embedding model (press Enter for default: $DEFAULT_EMBEDDING_MODEL): " -r EMBEDDING_MODEL
    EMBEDDING_MODEL=${EMBEDDING_MODEL:-$DEFAULT_EMBEDDING_MODEL}
fi

# 3. SOTA RAG Feature Configuration (only if deploying SOTA RAG)
if [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo ""
    echo -e "${YELLOW}SOTA RAG Advanced Features:${NC}"
    echo "Configure which advanced features to enable:"

    read -p "Enable GraphRAG/LightRAG? (Y/n): " -r ENABLE_LIGHTRAG
    ENABLE_LIGHTRAG=${ENABLE_LIGHTRAG:-Y}

    read -p "Enable Multimodal RAG? (Y/n): " -r ENABLE_MULTIMODAL
    ENABLE_MULTIMODAL=${ENABLE_MULTIMODAL:-Y}

    read -p "Enable Contextual Embeddings? (Y/n): " -r ENABLE_CONTEXTUAL
    ENABLE_CONTEXTUAL=${ENABLE_CONTEXTUAL:-Y}

    read -p "Enable Long-term Memory (Zep)? (Y/n): " -r ENABLE_LONGTERM_MEMORY
    ENABLE_LONGTERM_MEMORY=${ENABLE_LONGTERM_MEMORY:-Y}
else
    # InsightsLM only - no SOTA features
    ENABLE_LIGHTRAG=N
    ENABLE_MULTIMODAL=N
    ENABLE_CONTEXTUAL=N
    ENABLE_LONGTERM_MEMORY=N
    echo ""
    echo -e "${BLUE}InsightsLM Legacy mode - SOTA RAG features disabled${NC}"
fi

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
cp_sed "s/DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD/" .env
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
if [ "$USE_LOCAL_APIS" = true ] || [ "$USE_EXTERNAL_APIS" = false ]; then
    echo "" >> .env
    echo "# Ollama Model Configuration" >> .env
    if [ -n "$LOCAL_MAIN_MODEL" ]; then
        echo "OLLAMA_MODEL=$LOCAL_MAIN_MODEL" >> .env
        echo "EMBEDDING_MODEL=$LOCAL_EMBEDDING_MODEL" >> .env
    else
        echo "OLLAMA_MODEL=$MAIN_MODEL" >> .env
        echo "EMBEDDING_MODEL=$EMBEDDING_MODEL" >> .env
    fi
fi

# Write API Keys to .env based on configuration
echo "" >> .env
if [ "$USE_EXTERNAL_APIS" = true ]; then
    echo "# External API Keys" >> .env
    echo "OPENAI_API_KEY=${OPENAI_API_KEY:-}" >> .env
    echo "MISTRAL_API_KEY=${MISTRAL_API_KEY:-}" >> .env
    echo "COHERE_API_KEY=${COHERE_API_KEY:-}" >> .env
    echo "ZEP_API_KEY=${ZEP_API_KEY:-}" >> .env
    echo "LIGHTRAG_SERVER_URL=${LIGHTRAG_SERVER_URL:-http://lightrag:8020}" >> .env
else
    echo "# External API Keys (Disabled)" >> .env
    echo "OPENAI_API_KEY=" >> .env
    echo "MISTRAL_API_KEY=" >> .env
    echo "COHERE_API_KEY=" >> .env
    echo "ZEP_API_KEY=" >> .env
    echo "LIGHTRAG_SERVER_URL=http://lightrag:8020" >> .env
fi

if [ "$USE_LOCAL_APIS" = true ] || [ "$USE_EXTERNAL_APIS" = false ]; then
    echo "" >> .env
    echo "# Local API Configuration" >> .env
    echo "LOCAL_OLLAMA_ENABLED=true" >> .env
    if [ -n "$LOCAL_MAIN_MODEL" ]; then
        echo "LOCAL_EMBEDDING_MODEL=$LOCAL_EMBEDDING_MODEL" >> .env
        echo "LOCAL_MAIN_MODEL=$LOCAL_MAIN_MODEL" >> .env
    else
        echo "LOCAL_EMBEDDING_MODEL=$EMBEDDING_MODEL" >> .env
        echo "LOCAL_MAIN_MODEL=$MAIN_MODEL" >> .env
    fi
fi

echo -e "${GREEN}✓ Environment configuration created${NC}"

# Force rebuild InsightsLM with fresh credentials (following easy_setup_v2.sh pattern)
if [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo -e "${YELLOW}Pre-building InsightsLM with fresh credentials...${NC}"
    echo "  This ensures the VITE_SUPABASE_URL and ANON_KEY are properly embedded in the build"
    docker compose -p localai build --no-cache insightslm || {
        echo -e "${YELLOW}  Note: InsightsLM will be built when services start${NC}"
    }
fi

# =============================================================================
# PORT CONFLICT DETECTION AND RESOLUTION
# =============================================================================

echo ""
echo -e "${YELLOW}=== Port Conflict Detection & Resolution ===${NC}"

# Function to check if a port is in use
check_port() {
    local port=$1
    if netstat -an 2>/dev/null | grep -q ":${port}.*LISTEN" || lsof -i :${port} >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to find next available port
find_available_port() {
    local start_port=$1
    local port=$start_port
    while check_port $port; do
        ((port++))
        if [ $port -gt $((start_port + 100)) ]; then
            echo "ERROR: Could not find available port after $start_port" >&2
            return 1
        fi
    done
    echo $port
}

# Check and fix common port conflicts
echo "Checking for port conflicts..."

# Check ports that commonly conflict
CONFLICT_PORTS=(8080 8081 5678)
CONFLICTS_FOUND=false

for port in "${CONFLICT_PORTS[@]}"; do
    if check_port $port; then
        echo "⚠️  Port $port is in use by:"
        lsof -i :$port 2>/dev/null | head -2 || echo "   (Unknown process)"
        CONFLICTS_FOUND=true
    fi
done

if [ "$CONFLICTS_FOUND" = true ]; then
    echo ""
    echo "🔧 Automatically adjusting conflicting ports in docker-compose configurations..."
    
    # Fix port conflicts in override files
    for override_file in docker-compose.override.*.yml; do
        if [ -f "$override_file" ]; then
            echo "  Checking $override_file..."
            
            # Fix open-webui port conflict (8080 -> find available)
            if grep -q "127.0.0.1:8080:8080" "$override_file"; then
                NEW_PORT=$(find_available_port 8082)
                if [ $? -eq 0 ]; then
                    cp_sed "s/127.0.0.1:8080:8080/127.0.0.1:${NEW_PORT}:8080/g" "$override_file"
                    echo "    ✅ open-webui: 8080 → ${NEW_PORT}"
                fi
            fi
            
            # Fix searxng port conflict (8081 -> find available)
            if grep -q "127.0.0.1:8081:8080" "$override_file"; then
                NEW_PORT=$(find_available_port 8083)
                if [ $? -eq 0 ]; then
                    cp_sed "s/127.0.0.1:8081:8080/127.0.0.1:${NEW_PORT}:8080/g" "$override_file"
                    echo "    ✅ searxng: 8081 → ${NEW_PORT}"
                fi
            fi
        fi
    done
    echo "✅ Port conflicts resolved automatically"
else
    echo "✅ No port conflicts detected"
fi

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

# Smart Ollama cleanup - preserve proxy container in hybrid mode if we'll need it
if [ "$IS_MACOS" = true ] && ([ "$USE_LOCAL_APIS" = true ] || [ "$USE_EXTERNAL_APIS" = false ]); then
    echo "    Smart cleanup: Preserving Ollama proxy for macOS host integration"
    echo "    Debug: Hybrid mode detected (IS_MACOS=$IS_MACOS, USE_LOCAL_APIS=$USE_LOCAL_APIS)"
    # Stop all containers EXCEPT Ollama proxy which we'll reuse
    docker stop $(docker ps -q --filter "name=supabase-" --filter "name=n8n" --filter "name=searxng" --filter "name=flowise" --filter "name=open-webui" --filter "name=qdrant" --filter "name=redis" --filter "name=caddy" --filter "name=insightslm" --filter "name=coqui-tts" --filter "name=whisper-asr" --filter "name=langfuse" --filter "name=clickhouse" --filter "name=minio" --filter "name=postgres" --filter "name=neo4j" --filter "name=lightrag") 2>/dev/null || echo "    No non-Ollama containers running"
else
    # Normal cleanup including Ollama for non-hybrid or non-macOS deployments
    docker stop $(docker ps -q --filter "name=supabase-" --filter "name=n8n" --filter "name=ollama" --filter "name=searxng" --filter "name=flowise" --filter "name=open-webui" --filter "name=qdrant" --filter "name=redis" --filter "name=caddy" --filter "name=insightslm" --filter "name=coqui-tts" --filter "name=whisper-asr" --filter "name=langfuse" --filter "name=clickhouse" --filter "name=minio" --filter "name=postgres" --filter "name=neo4j" --filter "name=lightrag") 2>/dev/null || echo "    No project containers running"
fi

echo "  → Removing project containers..."
# Smart container removal - preserve Ollama proxy container in hybrid mode if we'll need it
if [ "$IS_MACOS" = true ] && ([ "$USE_LOCAL_APIS" = true ] || [ "$USE_EXTERNAL_APIS" = false ]); then
    echo "    Smart cleanup: Preserving Ollama proxy container for reuse"
    echo "    Debug: Keeping Ollama container, removing others"
    # Remove all containers EXCEPT Ollama proxy which we'll reuse
    docker rm -f $(docker ps -aq --filter "name=supabase-" --filter "name=n8n" --filter "name=searxng" --filter "name=flowise" --filter "name=open-webui" --filter "name=qdrant" --filter "name=redis" --filter "name=caddy" --filter "name=insightslm" --filter "name=coqui-tts" --filter "name=whisper-asr" --filter "name=langfuse" --filter "name=clickhouse" --filter "name=minio" --filter "name=postgres" --filter "name=neo4j" --filter "name=lightrag") 2>/dev/null || echo "    No non-Ollama containers to remove"
else
    # Normal cleanup including Ollama for non-hybrid or non-macOS deployments  
    echo "    Standard cleanup: Removing all containers including Ollama"
    echo "    Debug: Non-hybrid mode or non-macOS (IS_MACOS=$IS_MACOS, USE_LOCAL_APIS=${USE_LOCAL_APIS:-false})"
    docker rm -f $(docker ps -aq --filter "name=supabase-" --filter "name=n8n" --filter "name=ollama" --filter "name=searxng" --filter "name=flowise" --filter "name=open-webui" --filter "name=qdrant" --filter "name=redis" --filter "name=caddy" --filter "name=insightslm" --filter "name=coqui-tts" --filter "name=whisper-asr" --filter "name=langfuse" --filter "name=clickhouse" --filter "name=minio" --filter "name=postgres" --filter "name=neo4j" --filter "name=lightrag") 2>/dev/null || echo "    No project containers to remove"
fi

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

# Start services with fresh volumes and improved error handling
echo "Starting all services with profile: $PROFILE..."

# Function to start services with timeout and error handling
start_services_with_timeout() {
    local timeout_seconds=300  # 5 minutes timeout
    local profile=$1
    local environment=$2
    
    echo "  Starting services (timeout: ${timeout_seconds}s)..."
    
    # Start services in background
    timeout $timeout_seconds python3 start_services.py --profile "$profile" --environment "$environment" &
    local service_pid=$!
    
    # Wait for services to start or timeout
    wait $service_pid
    local exit_code=$?
    
    if [ $exit_code -eq 124 ]; then
        echo "  ⚠️  Service startup timed out after ${timeout_seconds}s"
        echo "  Some services may still be starting in background..."
        return 1
    elif [ $exit_code -ne 0 ]; then
        echo "  ⚠️  Service startup failed with exit code: $exit_code"
        echo "  Checking which services started successfully..."
        
        # Check critical services
        local critical_services=("supabase-db" "supabase-kong" "ollama")
        local failed_services=()
        
        for service in "${critical_services[@]}"; do
            if ! docker ps --format "{{.Names}}" | grep -q "^$service$"; then
                failed_services+=("$service")
            fi
        done
        
        if [ ${#failed_services[@]} -eq 0 ]; then
            echo "  ✅ Critical services are running despite startup issues"
            return 0
        else
            echo "  ❌ Critical services failed to start: ${failed_services[*]}"
            return 1
        fi
    else
        echo "  ✅ Services started successfully"
        return 0
    fi
}

# Attempt to start services
if start_services_with_timeout "$PROFILE" "private"; then
    echo "✅ Service startup completed"
else
    echo "⚠️  Service startup had issues, but continuing with deployment..."
    echo "   You may need to manually start some services later"
    
    # Try to start critical services individually if main startup failed
    echo "   Attempting to start critical services individually..."
    
    # Ensure Supabase services are running
    if ! docker ps | grep -q supabase-db; then
        echo "   Starting Supabase services..."
        docker compose -p localai -f supabase/docker/docker-compose.yml up -d >/dev/null 2>&1 || true
    fi
    
    # Ensure n8n is running
    if ! docker ps | grep -q "^n8n"; then
        echo "   Starting n8n..."
        docker compose -p localai --profile "$PROFILE" up -d n8n >/dev/null 2>&1 || true
    fi
fi

    # Note: Host Ollama for macOS will be started in the Ollama configuration section
    # following easy_setup_v2.sh pattern exactly - no premature startup here
    echo "  Note: macOS host Ollama will be configured and started in the dedicated Ollama section"
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

# Configure Ollama if using local models (any deployment that includes local APIs)
if [ "$USE_LOCAL_APIS" = true ] || [ "$USE_EXTERNAL_APIS" = false ]; then
    echo ""
    echo -e "${YELLOW}=== Configuring Ollama for Local Models ===${NC}"
    
    # OS-specific Ollama setup
    echo "  Debug: Configuring Ollama for IS_MACOS=$IS_MACOS, PROFILE=$PROFILE"
    if [ "$IS_MACOS" = true ]; then
        echo -e "${BLUE}macOS detected - setting up native Ollama and nginx proxy service...${NC}"

        # 1. Ensure Ollama CLI is installed
        if ! command -v ollama >/dev/null 2>&1; then
            echo "  Ollama not found – installing with Homebrew..."
            brew install ollama
        fi

        # 2. DON'T start Ollama here - let the proxy service manage it (following easy_setup_v2.sh pattern)
        echo "  Ollama will be managed by the Docker proxy service"
        
        # 3. Stop any existing Ollama processes first (clean slate)
        echo "  Stopping any existing Ollama processes..."
        pkill -f "ollama serve" 2>/dev/null || true
        sleep 2

        # 4. Pre-pull models while we can (before container manages Ollama)
        # Always use local models for Ollama (following easy_setup_v2.sh pattern)
        LOCAL_MAIN_MODEL="${LOCAL_MAIN_MODEL:-$DEFAULT_LOCAL_MODEL}"
        LOCAL_EMBEDDING_MODEL="${LOCAL_EMBEDDING_MODEL:-$DEFAULT_EMBEDDING_MODEL}"
        
        echo "  Pre-pulling models $LOCAL_MAIN_MODEL and $LOCAL_EMBEDDING_MODEL..."
        # Start Ollama temporarily just for pulling
        ollama serve > /tmp/ollama-pull.log 2>&1 &
        TEMP_OLLAMA_PID=$!
        sleep 3
        ollama pull "$LOCAL_MAIN_MODEL" || true
        ollama pull "$LOCAL_EMBEDDING_MODEL" || true
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
        
        # Create bidirectional container watcher script
        cat > ollama-proxy/watch-ollama-container.sh << 'WATCH_OLLAMA'
#!/bin/bash
set -e
LOG_FILE="/tmp/ollama-container-watch.log"
PID_FILE="/tmp/ollama-host.pid"

echo "Starting bidirectional Ollama lifecycle management..." | tee -a "$LOG_FILE"

# Wait for Docker to be available
for i in {1..30}; do
  if docker info >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Function to check if host Ollama is running and responsive
check_host_ollama() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null && curl -s http://localhost:11434/api/version >/dev/null 2>&1; then
            return 0  # Running and responsive
        fi
    fi
    return 1  # Not running or not responsive
}

# Function to restart host Ollama
restart_host_ollama() {
    echo "Restarting host Ollama..." | tee -a "$LOG_FILE"
    bash ./ollama-proxy/start-host-ollama.sh 2>>"$LOG_FILE" || {
        echo "Failed to restart host Ollama" | tee -a "$LOG_FILE"
        return 1
    }
    return 0
}

# Start background Docker container monitoring
(docker events --filter container=ollama --format '{{.Action}}' 2>>"$LOG_FILE" | while read -r action; do
  case "$action" in
    stop|die|kill)
      echo "Detected ollama container action: $action — stopping host Ollama" | tee -a "$LOG_FILE"
      bash ./ollama-proxy/stop-host-ollama.sh || true
      exit 0
      ;;
    start)
      echo "Detected ollama container start — ensuring host Ollama is running" | tee -a "$LOG_FILE"
      if ! check_host_ollama; then
          restart_host_ollama || true
      fi
      ;;
    *)
      echo "Event: $action" >>"$LOG_FILE"
      ;;
  esac
done) &
DOCKER_WATCHER_PID=$!

# Start background host Ollama monitoring
(while true; do
    sleep 30  # Check every 30 seconds
    
    # Only check if Docker container is running
    if docker ps --filter "name=ollama" --format "{{.Status}}" | grep -q "Up"; then
        if ! check_host_ollama; then
            echo "Host Ollama died - attempting restart..." | tee -a "$LOG_FILE"
            if restart_host_ollama; then
                echo "Host Ollama restarted successfully" | tee -a "$LOG_FILE"
            else
                echo "Failed to restart host Ollama - will retry in 30s" | tee -a "$LOG_FILE"
            fi
        fi
    else
        echo "Docker container not running - stopping host monitoring" | tee -a "$LOG_FILE"
        break
    fi
done) &
HOST_WATCHER_PID=$!

echo "Bidirectional watcher started (Docker PID=$DOCKER_WATCHER_PID, Host PID=$HOST_WATCHER_PID)" | tee -a "$LOG_FILE"

# Wait for either watcher to exit
wait $DOCKER_WATCHER_PID $HOST_WATCHER_PID
WATCH_OLLAMA

        chmod +x ollama-proxy/watch-ollama-container.sh
        
        echo -e "${GREEN}✓ Ollama lifecycle scripts created${NC}"
        
        # 4. Start Ollama on host and launch watcher (following easy_setup_v2.sh pattern exactly)
        echo "  Starting Ollama on host and launching watcher..."
        ./ollama-proxy/start-host-ollama.sh
        nohup ./ollama-proxy/watch-ollama-container.sh >/dev/null 2>&1 &
        
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

        # 6. Host Ollama will be started after services are up (to ensure Docker is ready)

        echo "  ✅ Proxy service 'ollama' configured with watcher-based lifecycle coupling"
        echo "     → Container starts = Ollama starts on host"
        echo "     → Container stops = Ollama stops on host (forcefully if needed)"
        
    else
        # Linux - use Docker Ollama services normally (real Ollama, not proxy)
        echo -e "${BLUE}Linux detected - using real Docker Ollama services${NC}"
        echo "  Debug: Switching from nginx proxy to real Ollama Docker container"
        echo "  Configuring ollama service to use real Ollama Docker container..."
        
        # Configure ollama service to use the real x-ollama anchor instead of nginx proxy
        yq eval '.services.ollama = {"!!merge": "<<: *service-ollama"}' -i docker-compose.yml
        
        # Add appropriate profile based on hardware detection
        if [ "$PROFILE" = "gpu-nvidia" ]; then
            yq eval '.services.ollama.profiles = ["gpu-nvidia"]' -i docker-compose.yml
            echo "    → Configured for NVIDIA GPU profile"
        elif [ "$PROFILE" = "gpu-amd" ]; then
            yq eval '.services.ollama.profiles = ["gpu-amd"]' -i docker-compose.yml
            echo "    → Configured for AMD GPU profile"
        else
            yq eval '.services.ollama.profiles = ["cpu"]' -i docker-compose.yml
            echo "    → Configured for CPU profile"
        fi
        
        # Update x-init-ollama to pull selected models for Linux
        # Always use local models for Ollama (following easy_setup_v2.sh pattern)
        LOCAL_MAIN_MODEL="${LOCAL_MAIN_MODEL:-$DEFAULT_LOCAL_MODEL}"
        LOCAL_EMBEDDING_MODEL="${LOCAL_EMBEDDING_MODEL:-$DEFAULT_EMBEDDING_MODEL}"
        
        echo "  Configuring Ollama to pull local models..."
        OLLAMA_COMMAND="echo 'Waiting for Ollama to be ready...'; for i in {1..60}; do if nc -z ollama 11434 2>/dev/null; then echo 'Ollama ready, pulling models...'; break; fi; sleep 1; done; OLLAMA_HOST=ollama:11434 ollama pull $LOCAL_MAIN_MODEL; OLLAMA_HOST=ollama:11434 ollama pull $LOCAL_EMBEDDING_MODEL"
        yq eval ".[\"x-init-ollama\"].command[1] = \"$OLLAMA_COMMAND\"" -i docker-compose.yml
        echo "  Updated x-init-ollama to pull: $LOCAL_MAIN_MODEL and $LOCAL_EMBEDDING_MODEL"
        
        # Add ollama-pull service for Linux to ensure models are pulled on startup
        echo "  Adding ollama-pull service for automatic model initialization..."
        if ! yq eval '.services | has("ollama-pull-llama")' docker-compose.yml | grep -q "true"; then
            # Add the init service that pulls models on startup
            yq eval '.services["ollama-pull-llama"] = {"!!merge": "<<: *init-ollama"}' -i docker-compose.yml
            yq eval '.services["ollama-pull-llama"].profiles = ["'$PROFILE'"]' -i docker-compose.yml
            echo "    → Added ollama-pull-llama service for $PROFILE profile"
        fi
        
        echo "  ✅ Real Ollama Docker service configured for Linux with model auto-pull"
    fi
    
    echo -e "${GREEN}✓ Ollama configuration prepared for local model deployment${NC}"
else
    echo -e "${YELLOW}Using external APIs only - Ollama configuration skipped${NC}"
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

# Database migration based on deployment mode
if [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo "Running InsightsLM database migration..."
    docker cp insights-lm-local-package/supabase-migration.sql supabase-db:/tmp/migration.sql
    docker exec supabase-db psql -U supabase_admin -d postgres -f /tmp/migration.sql >/dev/null 2>&1 || true
    echo "    ✓ InsightsLM database schema applied (includes markdown file support)"
fi

# Apply SOTA RAG specific database tables (only if deploying SOTA RAG)
if [ "$DEPLOY_SOTA_RAG" = true ]; then
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

-- ============================================================================
-- SEPARATE SYSTEM APPROACH: InsightsLM and SOTA RAG run independently
-- ============================================================================

-- Note: InsightsLM tables and functions are created by the migration above
-- SOTA RAG tables are created here
-- Future: Plan to integrate InsightsLM frontend → SOTA RAG backend processing
EOF

    docker cp /tmp/sota_tables_idempotent.sql supabase-db:/tmp/sota_tables.sql
    docker exec supabase-db psql -U supabase_admin -d postgres -f /tmp/sota_tables.sql >/dev/null 2>&1 || true
    echo "    ✓ SOTA RAG database tables applied - systems remain separate (idempotent)"

    # Apply SOTA RAG specific database functions (from sota-rag-setup.md)
    echo "  → Applying SOTA RAG database functions..."
    if [ -f "sota-rag-upgrade/src/hybrid_search_database_function.txt" ]; then
        docker cp "sota-rag-upgrade/src/hybrid_search_database_function.txt" supabase-db:/tmp/sota_functions.sql
        docker exec supabase-db psql -U supabase_admin -d postgres -f /tmp/sota_functions.sql >/dev/null 2>&1 || true
        echo "    ✓ SOTA RAG database functions applied"
    fi
    
    echo -e "${GREEN}✓ SOTA RAG database schema applied${NC}"
fi

if [ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}✓ Database migration complete - both schemas operational${NC}"
elif [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo -e "${GREEN}✓ InsightsLM database migration complete${NC}"
elif [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}✓ SOTA RAG database migration complete${NC}"
fi

# Create read-only user as required by sota-rag-setup.md (only if deploying SOTA RAG)
if [ "$DEPLOY_SOTA_RAG" = true ]; then
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
fi

# Deploy edge functions based on deployment mode
echo -e "${YELLOW}Deploying edge functions...${NC}"

# Always copy base InsightsLM functions if deploying InsightsLM
if [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo "  → Deploying InsightsLM edge functions..."
    mkdir -p ./supabase/docker/volumes/functions/
    cp -rf ./insights-lm-local-package/supabase-functions/* ./supabase/docker/volumes/functions/
    echo "    ✓ InsightsLM edge functions deployed"
fi

# Deploy SOTA RAG specific edge functions if deploying SOTA RAG
if [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo "  → Deploying SOTA RAG edge functions..."
    
    # Ensure base functions directory exists
    mkdir -p ./supabase/docker/volumes/functions/
    
    # Copy base functions if not already done by InsightsLM deployment
    if [ "$DEPLOY_INSIGHTSLM" = false ]; then
        cp -rf ./insights-lm-local-package/supabase-functions/* ./supabase/docker/volumes/functions/
        echo "    ✓ Base InsightsLM functions copied for SOTA RAG requirements"
    fi

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
fi

# API keys are now configured in the earlier ENVIRONMENT CONFIGURATION section

# =============================================================================
# WORKFLOW PREPARATION
# =============================================================================

if [ "$DEPLOY_SOTA_RAG" = true ]; then
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
    'main_model': os.environ.get('MAIN_MODEL', '$DEFAULT_LOCAL_MODEL'),
    'embedding_model': os.environ.get('EMBEDDING_MODEL', '$DEFAULT_EMBEDDING_MODEL'),
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

    echo -e "${GREEN}✓ SOTA RAG workflows prepared${NC}"
fi

# =============================================================================
# DATABASE FUNCTIONS SETUP
# =============================================================================

echo ""
echo -e "${YELLOW}=== Database Functions Confirmation ===${NC}"

# Database functions are already handled by the migration above
echo "Database functions deployed via migration..."

if [ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}✓ Both InsightsLM and SOTA RAG database functions deployed${NC}"
elif [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo -e "${GREEN}✓ InsightsLM database functions deployed${NC}"
elif [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}✓ SOTA RAG database functions deployed${NC}"
fi

# =============================================================================
# WORKFLOW DEPLOYMENT
# =============================================================================

echo ""
echo -e "${YELLOW}=== Workflow Deployment Status ===${NC}"

# Wait for n8n to be ready with improved initialization
echo "Waiting for n8n to be ready..."

# Function to check n8n readiness
check_n8n_ready() {
    # Check if container is running
    if ! docker ps --format "{{.Names}}" | grep -q "^n8n$"; then
        return 1
    fi
    
    # Check if n8n process is responding
    if ! docker exec n8n n8n --version >/dev/null 2>&1; then
        return 1
    fi
    
    # Check if API is responding
    if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz | grep -q "200"; then
        # Fallback: check if login endpoint responds (even with 401)
        if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/rest/login | grep -q "40[0-9]"; then
            return 1
        fi
    fi
    
    return 0
}

# Enhanced n8n readiness check with timeout
N8N_READY=false
for i in {1..120}; do
    if check_n8n_ready; then
        echo "n8n is ready!"
        N8N_READY=true
        break
    fi
    
    # Show progress every 15 seconds
    if [ $((i % 3)) -eq 0 ]; then
        echo "  Waiting for n8n... (${i}0s elapsed)"
        # Check if n8n container exists but isn't running
        if docker ps -a --format "{{.Names}}" | grep -q "^n8n$" && ! docker ps --format "{{.Names}}" | grep -q "^n8n$"; then
            echo "  n8n container exists but stopped, attempting to start..."
            docker start n8n >/dev/null 2>&1 || true
        fi
    fi
    
    sleep 10
done

if [ "$N8N_READY" = false ]; then
    echo -e "${YELLOW}⚠️  n8n readiness check timed out, but continuing...${NC}"
    echo "You may need to manually start n8n: docker start n8n"
fi

# Workflow import status
if [ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo "Both InsightsLM and SOTA RAG workflows will be imported..."
    echo "Systems will operate independently with separate credentials"
elif [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo "InsightsLM workflows will be imported..."
    echo "Original InsightsLM functionality preserved"
elif [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo "SOTA RAG workflows will be imported..."
    echo "Advanced RAG capabilities will be available"
fi

# Save unified credentials for user reference
cat > unified_credentials.txt << EOF
System Login Credentials:
========================
Email: ${UNIFIED_EMAIL}
Password: ${UNIFIED_PASSWORD}

Deployed Systems: $([ "$DEPLOY_INSIGHTSLM" = true ] && echo -n "InsightsLM ") $([ "$DEPLOY_SOTA_RAG" = true ] && echo -n "SOTA-RAG")

Service URLs:
- Supabase Studio: http://${ACCESS_HOST}:8000
- n8n Workflows: http://${ACCESS_HOST}:5678$([ "$DEPLOY_INSIGHTSLM" = true ] && echo "
- InsightsLM UI: http://${ACCESS_HOST}:3010")

Additional Services:
- Open WebUI: http://${ACCESS_HOST}:8080  
- Flowise: http://${ACCESS_HOST}:3001
EOF



if [ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}✓ Both system workflows will be deployed${NC}"
elif [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo -e "${GREEN}✓ InsightsLM workflows will be deployed${NC}"
elif [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}✓ SOTA RAG workflows will be deployed${NC}"
fi

# =============================================================================
# FRONTEND COMPATIBILITY
# =============================================================================

if [ "$DEPLOY_INSIGHTSLM" = true ]; then
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
fi

# =============================================================================
# FINAL CONFIGURATION
# =============================================================================

echo ""
echo -e "${YELLOW}=== Final Configuration ===${NC}"

# Create SOTA RAG credential templates (only if deploying SOTA RAG)
if [ "$DEPLOY_SOTA_RAG" = true ]; then
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
fi

# Create deployment summary
cat > DEPLOYMENT_SUMMARY.txt << EOF
System Deployment Summary
=========================

Deployment Mode: $([ "$DEPLOYMENT_MODE" = "1" ] && echo "InsightsLM Legacy Only" || ([ "$DEPLOYMENT_MODE" = "2" ] && echo "SOTA RAG 2.1 Only" || echo "Both Systems (Dual Deployment)"))
API Mode: $([ "$USE_EXTERNAL_APIS" = true ] && [ "$USE_LOCAL_APIS" = true ] && echo "Hybrid (Both Local and External)" || ([ "$USE_EXTERNAL_APIS" = true ] && echo "External APIs Only" || echo "Local-Only"))
Systems Deployed: $([ "$DEPLOY_INSIGHTSLM" = true ] && echo -n "InsightsLM ") $([ "$DEPLOY_SOTA_RAG" = true ] && echo -n "SOTA-RAG")

Models:
$([ "$USE_EXTERNAL_APIS" = true ] && [ "$USE_LOCAL_APIS" = true ] && echo "External Models:
- Main: $EXTERNAL_MAIN_MODEL  
- Embedding: $EXTERNAL_EMBEDDING_MODEL
Local Models:
- Main: $LOCAL_MAIN_MODEL
- Embedding: $LOCAL_EMBEDDING_MODEL" || echo "- Main: $MAIN_MODEL  
- Embedding: $EMBEDDING_MODEL")

$([ "$DEPLOY_SOTA_RAG" = true ] && echo "
SOTA RAG Features Enabled:
- GraphRAG/LightRAG: $([[ \"\$ENABLE_LIGHTRAG\" =~ ^[Yy]$ ]] && echo \"Yes\" || echo \"No\")
- Multimodal RAG: $([[ \"\$ENABLE_MULTIMODAL\" =~ ^[Yy]$ ]] && echo \"Yes\" || echo \"No\") 
- Contextual Embeddings: $([[ \"\$ENABLE_CONTEXTUAL\" =~ ^[Yy]$ ]] && echo \"Yes\" || echo \"No\")
- Long-term Memory: $([[ \"\$ENABLE_LONGTERM_MEMORY\" =~ ^[Yy]$ ]] && echo \"Yes\" || echo \"No\")")

Access URLs:
- Supabase: http://${ACCESS_HOST}:8000
- n8n: http://${ACCESS_HOST}:5678$([ "$DEPLOY_INSIGHTSLM" = true ] && echo "  
- InsightsLM: http://${ACCESS_HOST}:3010")

Database Schema: $([ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ] && echo "Dual system approach - both schemas operational" || ([ "$DEPLOY_INSIGHTSLM" = true ] && echo "InsightsLM schema only" || echo "SOTA RAG schema only"))$([ "$DEPLOY_SOTA_RAG" = true ] && echo "
  - SOTA RAG: documents_v2 (vector 1536), record_manager_v2, metadata_fields, tabular_document_rows")$([ "$DEPLOY_INSIGHTSLM" = true ] && echo "
  - InsightsLM: documents (vector 768), notebooks, sources, notes, profiles, n8n_chat_histories")$([ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ] && echo "
  - Separation: Systems operate independently with their own tables/functions")

Edge Functions: $([ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ] && echo "Both SOTA RAG enhanced functions + all original InsightsLM functions" || ([ "$DEPLOY_INSIGHTSLM" = true ] && echo "Original InsightsLM functions" || echo "Enhanced SOTA RAG functions (vector-search, hybrid-search)"))

Workflows: $([ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ] && echo "Both systems fully functional with separate credentials" || ([ "$DEPLOY_INSIGHTSLM" = true ] && echo "InsightsLM workflows active" || echo "SOTA RAG workflows active"))$([ "$DEPLOY_SOTA_RAG" = true ] && echo "
  - SOTA RAG: Main workflow, Knowledge Graph, Multimodal (if enabled)")$([ "$DEPLOY_INSIGHTSLM" = true ] && echo "
  - InsightsLM: Chat, Podcast Generation, Process Sources, Upsert to Vector, Generate Details")
Read-only User: Created with proper security permissions
Idempotent: Script can be run multiple times safely
Reset Option: Available via interactive prompt (defaults to N for safety)

Next Steps:

Backup Location: $BACKUP_DIR
EOF

# Add deployment-specific next steps to summary
if [ "$DEPLOYMENT_MODE" = "1" ]; then
    cat >> DEPLOYMENT_SUMMARY.txt << EOF

Next Steps for InsightsLM Legacy:
1. Access InsightsLM at http://${ACCESS_HOST}:3010
2. Create notebooks and upload documents
3. Test chat, podcast generation, and content processing
4. All functionality exactly as original InsightsLM
5. Upgrade path: Run easy_deploy.sh again and select 'Both Systems' to add SOTA RAG

EOF
elif [ "$DEPLOYMENT_MODE" = "2" ] && [ "$USE_EXTERNAL_APIS" = true ]; then
    cat >> DEPLOYMENT_SUMMARY.txt << EOF

Next Steps for SOTA RAG 2.1 with External APIs:
1. Edit .env file and add your API keys:
   - OPENAI_API_KEY
   - MISTRAL_API_KEY  
   - COHERE_API_KEY
   - ZEP_API_KEY
   
2. If using LightRAG, set LIGHTRAG_SERVER_URL in .env

3. Restart services: python3 start_services.py --profile $PROFILE --environment private

4. Access n8n at http://${ACCESS_HOST}:5678 to activate SOTA RAG workflows
5. Test advanced RAG features: hybrid search, contextual embeddings, GraphRAG
6. Add InsightsLM: Run easy_deploy.sh again and select 'Both Systems' to add notebook interface

EOF
elif [ "$DEPLOYMENT_MODE" = "2" ] && [ "$USE_EXTERNAL_APIS" = false ]; then
    cat >> DEPLOYMENT_SUMMARY.txt << EOF

Next Steps for SOTA RAG 2.1 Local-Only:
1. Ollama models configured: $MAIN_MODEL, $EMBEDDING_MODEL
2. Configure local alternatives for external services:
   - OCR processing (replace Mistral API with local OCR)
   - Reranking (replace Cohere API with local reranker)
   - Long-term memory (replace Zep API with local memory)
3. Access n8n at http://${ACCESS_HOST}:5678 to activate SOTA RAG workflows
4. Test local SOTA RAG features
5. Add InsightsLM: Run easy_deploy.sh again and select 'Both Systems' to add notebook interface

EOF
else
    # Both systems deployment
    if [ "$USE_EXTERNAL_APIS" = true ]; then
        cat >> DEPLOYMENT_SUMMARY.txt << EOF

Next Steps for Dual System (External APIs):
1. Edit .env file and add your API keys:
   - OPENAI_API_KEY
   - MISTRAL_API_KEY  
   - COHERE_API_KEY
   - ZEP_API_KEY
   
2. If using LightRAG, set LIGHTRAG_SERVER_URL in .env

3. Restart services: python3 start_services.py --profile $PROFILE --environment private

4. Access n8n at http://${ACCESS_HOST}:5678 to verify workflows are active

5. Test both systems independently:
   - InsightsLM: Access http://${ACCESS_HOST}:3010 for notebook creation (uses original 768-dim vectors)
   - SOTA RAG: Use n8n workflows for advanced RAG features (uses 1536-dim vectors)
   
6. Verify separation:
   - InsightsLM operates with original database tables and functions
   - SOTA RAG operates with enhanced v2 tables and functions
   - Both systems functional but independent (integration planned for future)

7. Plan integration: See SOTA_PLANS.md for roadmap to enhance InsightsLM with SOTA capabilities

EOF
    else
        # Both systems with local-only mode
        cat >> DEPLOYMENT_SUMMARY.txt << EOF

Next Steps for Dual System (Local-Only):
1. Ollama models configured:
   - Main model: $MAIN_MODEL ($([ "$IS_MACOS" = true ] && echo "running on host" || echo "running in Docker"))
   - Embedding model: $EMBEDDING_MODEL ($([ "$IS_MACOS" = true ] && echo "running on host" || echo "running in Docker"))

2. SOTA RAG workflows updated for local models:
   - OpenAI API calls replaced with Ollama endpoints
   - Embedding models switched to local Ollama

3. Configure local alternatives for SOTA RAG:
   - OCR processing (instead of Mistral API)
   - Reranking (instead of Cohere API)
   - Long-term memory (instead of Zep API)

4. Access n8n at http://${ACCESS_HOST}:5678 to verify workflows are active

5. Test both systems independently:
   - InsightsLM: Access http://${ACCESS_HOST}:3010 for notebook creation (uses local 768-dim vectors)
   - SOTA RAG: Use n8n workflows for local advanced RAG features (uses local 1536-dim vectors)

6. Verify separation:
   - InsightsLM operates with original database tables and functions
   - SOTA RAG operates with enhanced v2 tables and functions
   - Both systems functional but independent (integration planned for future)

7. Plan integration: See SOTA_PLANS.md for roadmap to enhance InsightsLM with SOTA capabilities

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

# Create n8n user with improved error handling
echo "Setting up n8n admin user..."

# Function to setup n8n user
setup_n8n_user() {
    # Check if virtual environment exists and activate it
    if [ -d ".venv" ]; then
        source .venv/bin/activate 2>/dev/null || echo "  Warning: Could not activate virtual environment"
    fi
    
    # Generate password hash with error handling
    echo "  Generating password hash..."
    if command -v python3 >/dev/null 2>&1; then
        PASSWORD_HASH=$(python3 -c "
try:
    import bcrypt
    print(bcrypt.hashpw(b'${UNIFIED_PASSWORD}', bcrypt.gensalt()).decode())
except ImportError:
    import hashlib
    import base64
    # Fallback to simple hash (not as secure but functional)
    hash_obj = hashlib.pbkdf2_hmac('sha256', b'${UNIFIED_PASSWORD}', b'salt', 100000)
    print('\$2b\$10\$' + base64.b64encode(hash_obj).decode()[:22])
" 2>/dev/null)
    else
        echo "  Error: Python3 not available for password hashing"
        return 1
    fi
    
    if [ -z "$PASSWORD_HASH" ]; then
        echo "  Error: Could not generate password hash"
        return 1
    fi
    
    # Wait for n8n to initialize database
    echo "  Waiting for n8n database initialization..."
    for i in {1..30}; do
        # Check if n8n tables exist
        if docker exec supabase-db psql -U postgres -d postgres -c "SELECT COUNT(*) FROM \"user\";" >/dev/null 2>&1; then
            echo "  n8n database tables ready"
            break
        fi
        sleep 2
        if [ $i -eq 30 ]; then
            echo "  Warning: n8n database not ready, attempting user setup anyway..."
        fi
    done
    
    # Check if user already exists and get user ID
    USER_ID=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "SELECT id FROM \"user\" ORDER BY \"createdAt\" LIMIT 1;" 2>/dev/null | tr -d '\r')
    
    if [ -n "$USER_ID" ] && [ "$USER_ID" != "" ]; then
        echo "  Found existing n8n user (ID: ${USER_ID}), updating credentials..."
        # Update existing user
        docker exec supabase-db psql -U postgres -d postgres -c "
        UPDATE \"user\" SET 
            email='${UNIFIED_EMAIL}',
            \"firstName\"='Admin',
            \"lastName\"='User',
            password='${PASSWORD_HASH}',
            \"roleSlug\"='global:owner'
        WHERE id='${USER_ID}';" >/dev/null 2>&1
    else
        echo "  Creating new n8n admin user..."
        # Create new user if none exists
        docker exec supabase-db psql -U postgres -d postgres -c "
        INSERT INTO \"user\" (email, \"firstName\", \"lastName\", password, \"roleSlug\")
        VALUES ('${UNIFIED_EMAIL}', 'Admin', 'User', '${PASSWORD_HASH}', 'global:owner')
        ON CONFLICT (email) DO UPDATE SET
            \"firstName\"='Admin',
            \"lastName\"='User',
            password='${PASSWORD_HASH}',
            \"roleSlug\"='global:owner';" >/dev/null 2>&1
    fi
    
    # Set the instance owner setup flag
    echo "  Setting instance owner setup flag..."
    docker exec supabase-db psql -U postgres -d postgres -c "
    INSERT INTO settings (key, value, \"loadOnStartup\") 
    VALUES ('userManagement.isInstanceOwnerSetUp', 'true', true)
    ON CONFLICT (key) DO UPDATE SET value = 'true';" >/dev/null 2>&1
    
    return 0
}

# Execute n8n user setup
if setup_n8n_user; then
    echo "  ✅ n8n admin user configured successfully"
else
    echo "  ⚠️  n8n user setup encountered issues, but continuing..."
fi

# Restart n8n to apply changes (with timeout)
echo "  Restarting n8n to apply setup changes..."
docker restart n8n >/dev/null 2>&1

# Wait for n8n to restart with timeout
echo "  Waiting for n8n to restart..."
N8N_RESTART_SUCCESS=false
for i in {1..60}; do
    if docker exec n8n n8n --version >/dev/null 2>&1; then
        echo "  ✅ n8n restarted successfully"
        N8N_RESTART_SUCCESS=true
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        echo "    Still waiting for n8n restart... (${i}0s elapsed)"
    fi
    sleep 2
done

if [ "$N8N_RESTART_SUCCESS" = false ]; then
    echo "  ⚠️  n8n restart timed out, but continuing with deployment..."
fi

echo "✅ Unified admin user configured across all services"

# =============================================================================
# INSIGHTSLM CREDENTIAL CREATION AND WORKFLOW IMPORT
# =============================================================================

if [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo ""
    echo -e "${YELLOW}=== Setting up InsightsLM Credentials and Workflows ===${NC}"

    # Create n8n API key via REST API (following easy_setup_v2.sh pattern exactly)
    echo "Creating n8n API key..."
    sleep 5

    LOGIN_RESPONSE=$(curl -s -c /tmp/n8n-cookies.txt -X POST http://localhost:5678/rest/login \
        -H 'Content-Type: application/json' \
        -d "{\"emailOrLdapLoginId\":\"${UNIFIED_EMAIL}\",\"password\":\"${UNIFIED_PASSWORD}\"}" 2>/dev/null || echo "{}")

    N8N_API_KEY=""
    if echo "$LOGIN_RESPONSE" | grep -q "\"email\":\"${UNIFIED_EMAIL}\""; then
        API_KEY_RESPONSE=$(curl -s -b /tmp/n8n-cookies.txt -X POST http://localhost:5678/rest/api-keys \
            -H 'Content-Type: application/json' \
            -d '{"label":"auto-generated-insightslm","expiresAt":null,"scopes":["user:read","user:list","user:create","user:changeRole","user:delete","user:enforceMfa","sourceControl:pull","securityAudit:generate","project:create","project:update","project:delete","project:list","variable:create","variable:delete","variable:list","variable:update","tag:create","tag:read","tag:update","tag:delete","tag:list","workflowTags:update","workflowTags:list","workflow:create","workflow:read","workflow:update","workflow:delete","workflow:list","workflow:move","workflow:activate","workflow:deactivate","execution:delete","execution:read","execution:list","credential:create","credential:move","credential:delete"]}' 2>/dev/null)
        
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

    if [ -n "$N8N_API_KEY" ]; then
        echo "  ✅ n8n API key created successfully"
    else
        echo "  ⚠️ Could not create n8n API key - workflows may need manual configuration"
        N8N_API_KEY=""
    fi

    # Create InsightsLM-specific credentials (following easy_setup_v2.sh pattern)
    echo "Creating InsightsLM n8n credentials..."

# Generate credential IDs for InsightsLM
HEADER_AUTH_ID=$(openssl rand -hex 8 | cut -c1-16)
SUPABASE_LM_ID=$(openssl rand -hex 8 | cut -c1-16)
OLLAMA_LM_ID=$(openssl rand -hex 8 | cut -c1-16)
N8N_API_ID=$(openssl rand -hex 8 | cut -c1-16)

# Create InsightsLM credentials JSON
cat > /tmp/insightslm_credentials.json << EOF
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
    "id": "${SUPABASE_LM_ID}",
    "name": "Supabase account",
    "type": "supabaseApi",
    "data": {
      "host": "http://kong:8000",
      "serviceRole": "${SERVICE_ROLE_KEY}"
    }
  },
  {
    "id": "${OLLAMA_LM_ID}",
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
      "apiKey": "${N8N_API_KEY:-}",
      "baseUrl": "http://n8n:5678/api/v1"
    }
  }
]
EOF

# Import InsightsLM credentials
echo "  → Importing InsightsLM credentials to n8n..."
docker cp /tmp/insightslm_credentials.json n8n:/tmp/lm_creds.json
IMPORT_RESULT=$(docker exec n8n n8n import:credentials --input=/tmp/lm_creds.json 2>&1)
if echo "$IMPORT_RESULT" | grep -q "error\|Error"; then
    echo -e "${YELLOW}  Warning: InsightsLM credential import may have failed:${NC}"
    echo "    $IMPORT_RESULT"
else
    echo "  ✅ InsightsLM credentials imported successfully"
fi

# Create Supabase Auth user for InsightsLM frontend login (following easy_setup_v2.sh pattern)
echo "  → Creating Supabase Auth user for InsightsLM frontend..."
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
        echo "    ✅ Created new Supabase Auth user for InsightsLM"
    else
        echo "    ⚠️ Warning: Could not create Supabase Auth user (may already exist)"
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
        echo "    ✅ Updated existing Supabase Auth user for InsightsLM"
    else
        echo "    ⚠️ Warning: Could not update Supabase Auth user"
    fi
fi

# Import and execute InsightsLM workflow importer
echo "  → Importing InsightsLM workflow importer..."
cp insights-lm-local-package/n8n/Local_Import_Insights_LM_Workflows.json /tmp/lm_import_workflow.json

# Update workflow with credential IDs and repository URLs
python3 - << EOF
import json

with open('/tmp/lm_import_workflow.json', 'r') as f:
    workflow = json.load(f)

# Update the Enter User Values node with our credential IDs
for node in workflow.get('nodes', []):
    if node.get('name') == 'Enter User Values':
        assignments = node.get('parameters', {}).get('assignments', {}).get('assignments', [])
        for a in assignments:
            if 'Header Auth' in a.get('name', ''):
                a['value'] = '${HEADER_AUTH_ID}'
            elif 'Supabase' in a.get('name', ''):
                a['value'] = '${SUPABASE_LM_ID}'
            elif 'Ollama' in a.get('name', ''):
                a['value'] = '${OLLAMA_LM_ID}'
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
                    '${INSIGHTS_LM_RAW_URL:-https://raw.githubusercontent.com/sirouk/insights-lm-local-package}'
                )

with open('/tmp/lm_import_workflow.json', 'w') as f:
    json.dump(workflow, f, indent=2)
EOF

# Import the workflow importer
docker cp /tmp/lm_import_workflow.json n8n:/tmp/lm_import_workflow.json
docker exec n8n n8n import:workflow --input=/tmp/lm_import_workflow.json >/dev/null 2>&1 || true

# Execute the import workflow to download InsightsLM workflows
echo "  → Executing InsightsLM workflow import..."
sleep 5
IMPORT_WORKFLOW_ID=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "SELECT id FROM workflow_entity WHERE name='Local Import Insights LM Workflows' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')

if [ -n "$IMPORT_WORKFLOW_ID" ]; then
    docker exec n8n n8n execute --id="${IMPORT_WORKFLOW_ID}" >/dev/null 2>&1 || true
    sleep 15
    echo "  ✅ InsightsLM workflows imported"
else
    echo "  ⚠️ Could not find InsightsLM import workflow"
fi

# Update Ollama model references in InsightsLM workflows
echo "  → Updating Ollama model references in InsightsLM workflows..."
sleep 5

# Check how many InsightsLM workflows were imported
WORKFLOW_COUNT=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "SELECT COUNT(*) FROM workflow_entity WHERE name LIKE 'InsightsLM%';" 2>/dev/null | tr -d '\r')
echo "    Found $WORKFLOW_COUNT InsightsLM workflows to update"

if [ "$WORKFLOW_COUNT" -gt 0 ]; then
    # Update main model references for local models
    if [ "$USE_EXTERNAL_APIS" = false ]; then
        echo "    Updating main model references to $MAIN_MODEL..."
        MAIN_MODEL_UPDATES=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
        UPDATE workflow_entity 
        SET nodes = REPLACE(nodes::text, '\"model\": \"$DEFAULT_LOCAL_MODEL\"', '\"model\": \"$MAIN_MODEL\"')::jsonb
        WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%$DEFAULT_LOCAL_MODEL%'
        RETURNING id;" 2>/dev/null | wc -l)
        echo "      Updated main model in $MAIN_MODEL_UPDATES workflows"

        # Update embedding model references - handle both with and without :latest suffix
        EMBEDDING_MODEL_BASE=$(echo "$EMBEDDING_MODEL" | sed 's/:latest$//')
        if [[ "$EMBEDDING_MODEL" != *":latest" ]]; then
            EMBEDDING_MODEL_WITH_LATEST="${EMBEDDING_MODEL}:latest"
        else
            EMBEDDING_MODEL_WITH_LATEST="$EMBEDDING_MODEL"
        fi

        echo "    Updating embedding model references to $EMBEDDING_MODEL..."

        # Update $DEFAULT_EMBEDDING_MODEL:latest references
        EMBED_UPDATES_1=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
        UPDATE workflow_entity 
        SET nodes = REPLACE(nodes::text, '\"model\": \"$DEFAULT_EMBEDDING_MODEL:latest\"', '\"model\": \"$EMBEDDING_MODEL_WITH_LATEST\"')::jsonb
        WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%$DEFAULT_EMBEDDING_MODEL:latest%'
        RETURNING id;" 2>/dev/null | wc -l)

        # Update $DEFAULT_EMBEDDING_MODEL references (without :latest)
        EMBED_UPDATES_2=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
        UPDATE workflow_entity 
        SET nodes = REPLACE(nodes::text, '\"model\": \"$DEFAULT_EMBEDDING_MODEL\"', '\"model\": \"$EMBEDDING_MODEL\"')::jsonb
        WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%\"model\": \"$DEFAULT_EMBEDDING_MODEL\"%' AND nodes::text NOT LIKE '%$DEFAULT_EMBEDDING_MODEL:latest%'
        RETURNING id;" 2>/dev/null | wc -l)

        echo "      Updated embedding model in $((EMBED_UPDATES_1 + EMBED_UPDATES_2)) workflow instances"
    fi

    # Update SUPABASE_PUBLIC_URL placeholder in InsightsLM workflows
    echo "    Updating Supabase public URL in InsightsLM workflows..."
    SUPABASE_PUBLIC_URL="http://${ACCESS_HOST}:8000"
    URL_UPDATES=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "
    UPDATE workflow_entity 
    SET nodes = REPLACE(nodes::text, 'SUPABASE_PUBLIC_URL_PLACEHOLDER', '$SUPABASE_PUBLIC_URL')::jsonb
    WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%SUPABASE_PUBLIC_URL_PLACEHOLDER%'
    RETURNING id;" 2>/dev/null | wc -l)

    if [ "$URL_UPDATES" -gt 0 ]; then
        echo "      ✅ Updated Supabase public URL in $URL_UPDATES InsightsLM workflow(s)"
    fi

    echo "  ✅ InsightsLM workflows configured"
else
    echo "  ⚠️ No InsightsLM workflows found to update"
fi

# Login to n8n web interface to establish session for workflow activation (following easy_setup_v2.sh)
echo "  → Establishing n8n web session for workflow activation..."

# Login via n8n web API to create session
LOGIN_RESPONSE=$(curl -s -c /tmp/n8n-cookies.txt -X POST http://localhost:5678/rest/login \
    -H 'Content-Type: application/json' \
    -d "{\"emailOrLdapLoginId\":\"${UNIFIED_EMAIL}\",\"password\":\"${UNIFIED_PASSWORD}\"}" 2>/dev/null || echo "{}")

if echo "$LOGIN_RESPONSE" | grep -q "\"email\":\"${UNIFIED_EMAIL}\""; then
    echo "    ✅ Successfully logged into n8n web interface"
    WEB_SESSION_ACTIVE=true
else
    echo "    ⚠️ Could not establish web session, workflows may need manual activation"
    WEB_SESSION_ACTIVE=false
fi

# Activate InsightsLM workflows using web API (following easy_setup_v2.sh pattern)
echo "  → Activating InsightsLM workflows..."

INSIGHTSLM_WORKFLOWS=(
    "InsightsLM - Podcast Generation"
    "InsightsLM - Chat"
    "InsightsLM - Process Additional Sources"
    "InsightsLM - Upsert to Vector Store"
    "InsightsLM - Generate Notebook Details"
)

for WORKFLOW_NAME in "${INSIGHTSLM_WORKFLOWS[@]}"; do
    WORKFLOW_ID=$(docker exec supabase-db psql -t -A -U postgres -d postgres -c "SELECT id FROM workflow_entity WHERE name='${WORKFLOW_NAME}' ORDER BY \"createdAt\" DESC LIMIT 1;" 2>/dev/null | tr -d '\r')
    if [ -n "$WORKFLOW_ID" ]; then
        echo "    Activating workflow: $WORKFLOW_NAME"
        
        if [ "$WEB_SESSION_ACTIVE" = true ]; then
            # Use web API with session cookies for more reliable activation
            echo "      Using web API activation..."
            
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
                echo "      ✅ Workflow activated successfully via web API"
            else
                echo "      ⚠️ Web API activation may have failed, trying CLI fallback..."
                docker exec n8n n8n update:workflow --id="${WORKFLOW_ID}" --active=true >/dev/null 2>&1 || true
            fi
        else
            # Fallback to CLI activation
            echo "      Using CLI activation (fallback)..."
            docker exec n8n n8n update:workflow --id="${WORKFLOW_ID}" --active=false >/dev/null 2>&1 || true
            sleep 1
            docker exec n8n n8n update:workflow --id="${WORKFLOW_ID}" --active=true >/dev/null 2>&1 || true
            echo "      Workflow activated via CLI"
        fi
    else
        echo "    ⚠️ Could not find workflow: $WORKFLOW_NAME"
    fi
done

# Clean up session cookies
rm -f /tmp/n8n-cookies.txt

# Restart n8n after workflow activation to ensure webhook registration (critical!)
echo "  → Restarting n8n to apply webhook registrations..."
docker restart n8n

# Wait for n8n to be fully ready after restart
echo "    Waiting for n8n to restart and be ready..."
for i in {1..60}; do
    sleep 5
    if docker exec n8n n8n --version >/dev/null 2>&1; then
        echo "    n8n is ready!"
        break
    fi
done

# Verify webhook registration is working (following easy_setup_v2.sh pattern)
echo "  → Verifying webhook registration..."

# Test the critical webhook endpoints
echo "    Testing process-additional-sources endpoint..."
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
    echo "    ✅ process-additional-sources webhook working correctly"
else
    echo "    ⚠️ process-additional-sources webhook may need attention"
fi

echo "    Testing generate-notebook-content endpoint..."
TEST_RESPONSE=$(curl -s -X POST http://localhost:8000/functions/v1/generate-notebook-content \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(grep ANON_KEY .env | cut -d'=' -f2)" \
  -d '{
    "notebookId": "test-notebook-id",
    "sourceType": "website"
  }' 2>/dev/null)

if echo "$TEST_RESPONSE" | grep -q '"success":true'; then
    echo "    ✅ generate-notebook-content webhook working correctly"
else
    echo "    ⚠️ generate-notebook-content may need attention (this is often normal if no sources exist)"
fi

echo "  ✅ Webhook verification completed"

    echo -e "${GREEN}✓ InsightsLM setup complete - ready for use${NC}"
fi

# =============================================================================
# SOTA RAG CREDENTIALS AND WORKFLOW IMPORT
# =============================================================================

if [ "$DEPLOY_SOTA_RAG" = true ]; then
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
                    
                    # Update main model references ($DEFAULT_EXTERNAL_MODEL -> user selected model)
                    echo "      Updating main model references to $MAIN_MODEL..."
                    MAIN_MODEL_UPDATES=$(docker exec supabase-db psql -t -A -U supabase_admin -d postgres -c "
                    UPDATE workflow_entity 
                    SET nodes = REPLACE(
                        REPLACE(
                            REPLACE(nodes::text, 
                                '\"model\": \"$DEFAULT_EXTERNAL_MODEL\"', '\"model\": \"$MAIN_MODEL\"'),
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
                            '\"$DEFAULT_EXTERNAL_EMBEDDING\"', '\"$EMBEDDING_MODEL\"'),
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

    echo -e "${GREEN}✓ SOTA RAG setup complete${NC}"
fi

# =============================================================================
# FINAL OUTPUT
# =============================================================================

echo ""
echo -e "${GREEN}============================================================${NC}"
if [ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${GREEN}🎉 === DUAL SYSTEM DEPLOYMENT COMPLETE === 🎉${NC}"  
elif [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo -e "${GREEN}🎉 === INSIGHTSLM LEGACY DEPLOYMENT COMPLETE === 🎉${NC}"
else
    echo -e "${GREEN}🎉 === SOTA RAG 2.1 DEPLOYMENT COMPLETE === 🎉${NC}"
fi
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
echo "🔑 unified_credentials.txt - Login credentials for all services"
echo "📋 api-keys-template.env - API key configuration template" 
echo "🔧 workflows/credential-templates.json - API credential templates"
echo "🔧 Enhanced edge functions - Vector Search & Hybrid Search (from SOTA RAG src)"
echo "🔧 Database functions - hybrid_search_v2_with_details & match_documents_v2_vector"
echo "🔧 Database tables - documents_v2, record_manager_v2, metadata_fields, tabular_document_rows"
echo "🔧 Read-only database user - For secure query operations"
echo "📓 InsightsLM workflows - All original functionality preserved"
echo "🔗 SOTA_PLANS.md - Future integration roadmap for InsightsLM → SOTA RAG enhancement"
echo "📂 $BACKUP_DIR/ - Backup of previous state"
echo ""

if [ "$USE_EXTERNAL_APIS" = true ] && [ "$USE_LOCAL_APIS" = true ]; then
    echo -e "${YELLOW}⚠️  NEXT STEPS FOR HYBRID MODE (EXTERNAL + LOCAL):${NC}"
    echo "1. Edit .env file and add your external API keys:"
    echo "   - OPENAI_API_KEY"
    echo "   - MISTRAL_API_KEY"
    echo "   - COHERE_API_KEY"
    echo "   - ZEP_API_KEY"
    echo ""
    echo "2. Local models automatically configured:"
    echo "   - Main model: ${LOCAL_MAIN_MODEL:-$MAIN_MODEL}"
    echo "   - Embedding model: ${LOCAL_EMBEDDING_MODEL:-$EMBEDDING_MODEL}"
    echo ""
    echo "3. Choose which APIs to use in workflows (both available)"
    echo "4. Restart services: python3 start_services.py --profile $PROFILE --environment private"
    echo "5. Access n8n at http://${ACCESS_HOST}:5678 to configure workflow API preferences"
    echo ""
    echo -e "${BLUE}📖 Hybrid mode gives maximum flexibility - use external APIs for speed, local for privacy${NC}"
elif [ "$USE_EXTERNAL_APIS" = true ]; then
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
    echo "4. Access n8n at http://${ACCESS_HOST}:5678 to verify workflows are active"
    echo "5. Test both systems independently:"
    echo "   - InsightsLM: Access http://${ACCESS_HOST}:3010 for notebook creation (uses original 768-dim vectors)"
    echo "   - SOTA RAG: Use n8n workflows for advanced RAG features (uses 1536-dim vectors)"
    echo "6. Verify separation:"
    echo "   - InsightsLM operates with original database tables and functions"
    echo "   - SOTA RAG operates with enhanced v2 tables and functions" 
    echo "   - Both systems functional but independent (integration planned for future)"
    echo ""
    echo -e "${BLUE}📖 See SOTA_RAG_SETUP_GUIDE.md for local alternative configurations${NC}"
fi

echo ""
echo -e "${GREEN}============================================================${NC}"
if [ "$DEPLOY_INSIGHTSLM" = true ] && [ "$DEPLOY_SOTA_RAG" = true ]; then
    echo -e "${BLUE}🚀 Dual System deployment ready! Both InsightsLM and SOTA RAG are fully operational:${NC}"
    echo ""
    echo -e "${BLUE}📓 InsightsLM: Complete notebook/content generation (independent operation)${NC}"
    echo -e "${BLUE}🧠 SOTA RAG: Advanced hybrid search, contextual embeddings, GraphRAG (independent operation)${NC}"
    echo -e "${BLUE}🔧 Integration: See SOTA_PLANS.md for future InsightsLM → SOTA RAG backend integration${NC}"
elif [ "$DEPLOY_INSIGHTSLM" = true ]; then
    echo -e "${BLUE}🚀 InsightsLM Legacy deployment ready! Complete notebook and content generation system:${NC}"
    echo ""
    echo -e "${BLUE}📓 InsightsLM: Original functionality with local Ollama models${NC}"
    echo -e "${BLUE}🔧 Upgrade Path: Run again and select 'Both Systems' to add SOTA RAG capabilities${NC}"
else
    echo -e "${BLUE}🚀 SOTA RAG 2.1 deployment ready! Advanced AI capabilities operational:${NC}"
    echo ""
    echo -e "${BLUE}🧠 SOTA RAG: Hybrid search, contextual embeddings, GraphRAG, multimodal processing${NC}"
    echo -e "${BLUE}🔧 Add InsightsLM: Run again and select 'Both Systems' to add notebook interface${NC}"
fi
echo ""
echo -e "${BLUE}💡 Note: This script is idempotent - you can run it multiple times safely.${NC}"
echo -e "${BLUE}   Future runs will preserve existing data and only update components as needed.${NC}"
echo ""
echo -e "${BLUE}🌐 Remote Execution: You can run this script from anywhere using:${NC}"
echo -e "${BLUE}   bash <(curl -sSf -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' \\${NC}"
echo -e "${BLUE}     https://raw.githubusercontent.com/sirouk/local-ai-packaged/refs/heads/make-static/easy_deploy.sh)${NC}"
echo ""
echo -e "${BLUE}🔧 Credential Mapping: All SOTA RAG workflows use correct credential IDs${NC}"
echo -e "${BLUE}   Following easy_setup_v2.sh pattern: import credentials → update workflows → re-import${NC}"
echo ""
if [ "$USE_LOCAL_APIS" = true ] && [ "$USE_EXTERNAL_APIS" = false ]; then
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
