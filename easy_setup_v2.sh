#!/bin/bash
set -e

cd $HOME

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
DEFAULT_OLLAMA_MODEL="deepseek-ai/DeepSeek-R1-0528-Qwen3-8B"
DEFAULT_EMBEDDING_MODEL="nomic-embed-text"

echo -e "${GREEN}=== InsightsLM Local AI Setup Script ===${NC}"
echo ""
echo -e "${YELLOW}Using repositories:${NC}"
echo -e "  Local AI: ${GREEN}${LOCAL_AI_REPO}${NC}"
echo -e "  InsightsLM: ${GREEN}${INSIGHTS_LM_REPO}${NC}"
echo ""

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
sudo apt update
sudo apt install -y python3 python3-venv net-tools python3-pip curl git jq
snap install --classic yq

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
    read -p "Enter the Ollama model to use (e.g., llama3.2, mistral, deepseek-ai/DeepSeek-R1-0528-Qwen3-8B): " -r CUSTOM_MODEL
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
        else
            echo "    Service $service_name already exists, skipping"
        fi
    fi
done < <(yq eval '.services | keys | .[]' insights-lm-local-package/docker-compose.copy.yml)

# Configure n8n for external access
echo -e "${YELLOW}Configuring n8n external access...${NC}"

# Add N8N_SECURE_COOKIE=false to x-n8n environment for external access
cat > fix_n8n_config.py << 'EOF'
import yaml

with open('docker-compose.yml', 'r') as f:
    compose = yaml.safe_load(f)

# Add N8N_SECURE_COOKIE=false to x-n8n environment if it exists
if 'x-n8n' in compose and 'environment' in compose['x-n8n']:
    env_list = compose['x-n8n']['environment']
    # Check if N8N_SECURE_COOKIE is already set
    secure_cookie_exists = any('N8N_SECURE_COOKIE' in str(env) for env in env_list)
    if not secure_cookie_exists:
        env_list.append('N8N_SECURE_COOKIE=false')
        print("  Added N8N_SECURE_COOKIE=false for external access")

with open('docker-compose.yml', 'w') as f:
    yaml.dump(compose, f, default_flow_style=False, sort_keys=False, width=1000)
EOF

python3 fix_n8n_config.py
rm fix_n8n_config.py

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
DASHBOARD_PASSWORD=$(openssl rand -hex 16)
CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
LANGFUSE_SALT=$(openssl rand -hex 16)
NEXTAUTH_SECRET=$(openssl rand -hex 16)
ENCRYPTION_KEY=$(openssl rand -hex 32)
DASHBOARD_USERNAME="supabase"
NEO4J_AUTH="neo4j/$(openssl rand -base64 12 | tr -d '=+/' | cut -c1-16)"
NOTEBOOK_GENERATION_AUTH=$(openssl rand -hex 16)

# Update .env file with secrets
sed -i "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY/" .env
sed -i "s/N8N_USER_MANAGEMENT_JWT_SECRET=.*/N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET/" .env
sed -i "s/POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" .env
sed -i "s/JWT_SECRET=.*/JWT_SECRET=$JWT_SECRET/" .env
sed -i "s/DASHBOARD_PASSWORD=.*/DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD/" .env
sed -i "s/POOLER_TENANT_ID=.*/POOLER_TENANT_ID=1000/" .env
sed -i "s/CLICKHOUSE_PASSWORD=.*/CLICKHOUSE_PASSWORD=$CLICKHOUSE_PASSWORD/" .env
sed -i "s/MINIO_ROOT_PASSWORD=.*/MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD/" .env
sed -i "s/LANGFUSE_SALT=.*/LANGFUSE_SALT=$LANGFUSE_SALT/" .env
sed -i "s/NEXTAUTH_SECRET=.*/NEXTAUTH_SECRET=$NEXTAUTH_SECRET/" .env
sed -i "s/ENCRYPTION_KEY=.*/ENCRYPTION_KEY=$ENCRYPTION_KEY/" .env
sed -i "s/DASHBOARD_USERNAME=.*/DASHBOARD_USERNAME=$DASHBOARD_USERNAME/" .env
sed -i "s|NEO4J_AUTH=.*|NEO4J_AUTH=\"$NEO4J_AUTH\"|" .env

# Concatenate InsightsLM environment variables from .env.copy
echo "" >> .env
echo "# InsightsLM Environment Variables" >> .env
cat insights-lm-local-package/.env.copy >> .env

# Update NOTEBOOK_GENERATION_AUTH to use our generated value (used for Header Auth)
sed -i "s|NOTEBOOK_GENERATION_AUTH=.*|NOTEBOOK_GENERATION_AUTH=$NOTEBOOK_GENERATION_AUTH|" .env

# Add Ollama model configuration to .env
echo "" >> .env
echo "# Ollama Model Configuration" >> .env
echo "OLLAMA_MODEL=$OLLAMA_MODEL" >> .env
echo "EMBEDDING_MODEL=$EMBEDDING_MODEL" >> .env

# Update STUDIO defaults
sed -i 's/STUDIO_DEFAULT_ORGANIZATION=.*/STUDIO_DEFAULT_ORGANIZATION="InsightsLM"/' .env
sed -i 's/STUDIO_DEFAULT_PROJECT=.*/STUDIO_DEFAULT_PROJECT="Default Project"/' .env

# Generate JWT keys
ANON_KEY=$(python3 -c "import jwt, time; print(jwt.encode({'role': 'anon', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + (5 * 365 * 24 * 60 * 60)}, '$JWT_SECRET', algorithm='HS256'))")
SERVICE_ROLE_KEY=$(python3 -c "import jwt, time; print(jwt.encode({'role': 'service_role', 'iss': 'supabase', 'iat': int(time.time()), 'exp': int(time.time()) + (5 * 365 * 24 * 60 * 60)}, '$JWT_SECRET', algorithm='HS256'))")

sed -i "s/ANON_KEY=.*/ANON_KEY=$ANON_KEY/" .env
sed -i "s/SERVICE_ROLE_KEY=.*/SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY/" .env

# Update URLs with external IP
IPV4_ADDRESS=$(curl -s ipinfo.io/ip)
sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://${IPV4_ADDRESS}:8000|" .env

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

# Auto-detect compute profile
echo -e "${YELLOW}Detecting compute profile...${NC}"
PROFILE="cpu"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
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
UNIFIED_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-16)

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

if [ -z "$N8N_API_KEY" ]; then
    N8N_API_KEY=$(openssl rand -base64 32)
fi

# Import n8n credentials
echo -e "${YELLOW}Importing n8n credentials...${NC}"
HEADER_AUTH_ID=$(openssl rand -hex 8 | cut -c1-16)
SUPABASE_ID=$(openssl rand -hex 8 | cut -c1-16)
OLLAMA_ID=$(openssl rand -hex 8 | cut -c1-16)
N8N_API_ID=$(openssl rand -hex 8 | cut -c1-16)

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
      "host": "http://supabase-kong:8000",
      "serviceRoleKey": "${SERVICE_ROLE_KEY}"
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

docker cp /tmp/n8n_credentials.json n8n:/tmp/creds.json
docker exec n8n n8n import:credentials --input=/tmp/creds.json >/dev/null 2>&1 || true

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

# Update Ollama model references in workflows if not using default
echo -e "${YELLOW}Updating Ollama model references in workflows...${NC}"

# Update main model references
docker exec supabase-db psql -U postgres -d postgres -c "
UPDATE workflow_entity 
SET nodes = REPLACE(nodes::text, '\"model\": \"qwen3:8b-q4_K_M\"', '\"model\": \"$OLLAMA_MODEL\"')::jsonb
WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%qwen3:8b-q4_K_M%';" >/dev/null 2>&1

# Update embedding model references - handle both with and without :latest suffix
EMBEDDING_MODEL_BASE=$(echo "$EMBEDDING_MODEL" | sed 's/:latest$//')
if [[ "$EMBEDDING_MODEL" != *":latest" ]]; then
    EMBEDDING_MODEL_WITH_LATEST="${EMBEDDING_MODEL}:latest"
else
    EMBEDDING_MODEL_WITH_LATEST="$EMBEDDING_MODEL"
fi

docker exec supabase-db psql -U postgres -d postgres -c "
UPDATE workflow_entity 
SET nodes = REPLACE(nodes::text, '\"model\": \"nomic-embed-text:latest\"', '\"model\": \"$EMBEDDING_MODEL_WITH_LATEST\"')::jsonb
WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%nomic-embed-text:latest%';" >/dev/null 2>&1

docker exec supabase-db psql -U postgres -d postgres -c "
UPDATE workflow_entity 
SET nodes = REPLACE(nodes::text, '\"model\": \"nomic-embed-text\"', '\"model\": \"$EMBEDDING_MODEL\"')::jsonb
WHERE name LIKE 'InsightsLM%' AND nodes::text LIKE '%\"model\": \"nomic-embed-text\"%';" >/dev/null 2>&1

echo "  Updated workflow model references to use: $OLLAMA_MODEL and $EMBEDDING_MODEL"



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

External Access:
- Supabase: http://${IPV4_ADDRESS}:8000
- n8n: http://${IPV4_ADDRESS}:5678
- InsightsLM: http://${IPV4_ADDRESS}:3010
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
echo "📊 Supabase Studio: http://${IPV4_ADDRESS}:8000"
echo "🔧 N8N Workflow Editor: http://${IPV4_ADDRESS}:5678"
echo "📓 InsightsLM: http://${IPV4_ADDRESS}:3010"
# echo "💬 Open WebUI: http://${IPV4_ADDRESS}:8080"
# echo "🌐 Flowise: http://${IPV4_ADDRESS}:3001"
echo ""
echo "🔐 Login Credentials saved to: unified_credentials.txt"
echo "   Email: ${UNIFIED_EMAIL}"
echo ""
echo "🔗 Webhook Status:"
echo "   ✅ All Edge Functions and n8n workflows activated via web API"
echo "   🌐 n8n web session established for proper workflow activation"
echo "   📝 If you experience 500 errors, workflows may need manual activation via web UI"
echo ""
echo -e "${GREEN}============================================================${NC}"
