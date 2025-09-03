# InsightsLM + SOTA RAG Dual System Guide

## Overview

The enhanced `easy_deploy.sh` script deploys both InsightsLM and SOTA RAG as **completely independent systems** sharing the same infrastructure while operating separately. The script automatically manages all required repositories and validates dependencies based on your deployment selection.

## Dual Independent Architecture

### InsightsLM System (Independent Operation)
- **Purpose**: Complete notebook and content generation platform
- **Vector Embeddings**: 768-dimensional (using nomic-embed-text)
- **Database Tables**: `documents`, `notebooks`, `sources`, `notes`, `profiles`, `n8n_chat_histories`
- **Edge Functions**: Original InsightsLM functions for document processing, chat, etc.
- **Workflows**: Chat, Podcast Generation, Process Sources, Upsert to Vector, Generate Details
- **Status**: ✅ Fully functional with original capabilities

### SOTA RAG System (Independent Operation)
- **Purpose**: Advanced retrieval-augmented generation with hybrid search
- **Vector Embeddings**: 1536-dimensional (using text-embedding-3-small or similar)
- **Database Tables**: `documents_v2`, `record_manager_v2`, `metadata_fields`, `tabular_document_rows`
- **Edge Functions**: Enhanced vector-search and hybrid-search functions
- **Workflows**: Main RAG, Knowledge Graph (LightRAG), Multimodal RAG
- **Status**: ✅ Fully functional with advanced capabilities

## System Separation

### Database Independence
**InsightsLM Tables** (Original Schema):
```sql
-- documents: vector(768) for InsightsLM embeddings
-- notebooks, sources, notes: Full InsightsLM schema
-- n8n_chat_histories: Chat storage
-- All original RLS policies and functions preserved
```

**SOTA RAG Tables** (Enhanced Schema):
```sql
-- documents_v2: vector(1536) for SOTA RAG embeddings  
-- record_manager_v2: Document versioning and tracking
-- metadata_fields: Advanced filtering configuration
-- tabular_document_rows: Spreadsheet data support
```

### Workflow Independence
**InsightsLM Workflows**:
- Use original `documents` table and 768-dim embeddings
- Maintain original processing pipeline
- Continue working exactly as before

**SOTA RAG Workflows**:
- Use enhanced `documents_v2` table and 1536-dim embeddings
- Advanced hybrid search and contextual embeddings
- Independent processing and storage

### Edge Function Coexistence
- **InsightsLM Functions**: `generate-notebook-content`, `process-document`, `send-chat-message`, etc.
- **SOTA RAG Functions**: `vector-search`, `hybrid-search` (enhanced versions)
- **Shared Environment**: Both sets use the same Supabase instance and environment variables

## Workflow Integration

### Credential Management
Both systems use separate but compatible credentials:
- **InsightsLM**: Header Auth, Supabase (LM), Ollama (LM), N8N API
- **SOTA RAG**: OpenAI, Mistral, Cohere, Supabase (SOTA), Postgres (SOTA)

### Webhook URLs
All InsightsLM webhook URLs are preserved and configured:
- `NOTEBOOK_CHAT_URL`
- `NOTEBOOK_GENERATION_URL` 
- `AUDIO_GENERATION_WEBHOOK_URL`
- `DOCUMENT_PROCESSING_WEBHOOK_URL`
- `ADDITIONAL_SOURCES_WEBHOOK_URL`

## Usage Patterns

### For InsightsLM Users (Independent System)
1. **Access**: `http://localhost:3010`
2. **Functionality**: Create notebooks, upload documents, generate content
3. **Embeddings**: Native 768-dimensional vectors (nomic-embed-text)
4. **Storage**: Uses original `documents` table and InsightsLM functions
5. **Experience**: Exactly the same as original InsightsLM

### For SOTA RAG Users (Independent System)
1. **Access**: `http://localhost:5678` (n8n workflows)
2. **Functionality**: Advanced hybrid search, contextual embeddings, GraphRAG
3. **Embeddings**: Native 1536-dimensional vectors (text-embedding-3-small)
4. **Storage**: Uses enhanced `documents_v2` table and SOTA functions
5. **Features**: All advanced SOTA RAG capabilities available

### Current System Behavior
- **Documents**: Each system maintains its own vector store
- **Chat**: InsightsLM chat operates independently with original backend
- **Search**: Each system has its own search capabilities and data
- **Future**: Integration planned via SOTA_PLANS.md roadmap

## Verification Steps

### 1. Test InsightsLM Functionality (Independent)
```bash
# Test notebook creation endpoint
curl -X POST http://localhost:8000/functions/v1/generate-notebook-content \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"notebookId": "test", "sourceType": "website"}'

# Verify InsightsLM uses original documents table
psql -h localhost -p 5432 -U readonly -d postgres -c \
  "SELECT COUNT(*), pg_typeof(embedding) FROM documents LIMIT 1;"
# Should show vector(768)
```

### 2. Test SOTA RAG Functions (Independent)
```bash
# Test enhanced vector search with 1536-dim embedding
curl -X POST http://localhost:8000/functions/v1/vector-search \
  -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query_embedding": [0.1, 0.2, ...], "match_count": 5}'

# Verify SOTA RAG uses documents_v2 table  
psql -h localhost -p 5432 -U readonly -d postgres -c \
  "SELECT COUNT(*), pg_typeof(embedding) FROM documents_v2 LIMIT 1;"
# Should show vector(1536)
```

### 3. Verify Independent Workflow Status
```bash
# Check InsightsLM workflows are active
curl -H "Authorization: Bearer $ANON_KEY" \
  http://localhost:5678/rest/workflows | jq '.data[] | select(.name | contains("InsightsLM")) | {name, active}'

# Check SOTA RAG workflows are active  
curl -H "Authorization: Bearer $ANON_KEY" \
  http://localhost:5678/rest/workflows | jq '.data[] | select(.name | contains("SOTA")) | {name, active}'
```

### 4. Test System Separation
```bash
# Upload document via InsightsLM - should only appear in documents table
# Upload document via SOTA RAG - should only appear in documents_v2 table
# Both systems should operate completely independently
```

## Troubleshooting

### InsightsLM Issues
If InsightsLM doesn't work as expected:
- **Check Original Functions**: Verify all InsightsLM edge functions deployed
- **Database Access**: Ensure original `documents` table exists with vector(768)
- **Workflow Status**: Verify InsightsLM workflows are active
- **Credentials**: Check Header Auth, Supabase (LM), and Ollama credentials

### SOTA RAG Issues  
If SOTA RAG workflows fail:
- **Enhanced Functions**: Verify vector-search and hybrid-search functions deployed
- **Database Access**: Ensure `documents_v2` table exists with vector(1536)
- **API Keys**: Verify external API keys if using Phase 1 deployment
- **Sub-workflows**: Check Knowledge Graph and Multimodal workflows if enabled

### System Independence
If systems interfere with each other:
- **Credential Conflicts**: Each system uses separate credential sets
- **Database Isolation**: Each system uses separate tables  
- **Workflow Isolation**: No workflow dependencies between systems

## Current System Benefits

### Independent Operation
- **InsightsLM**: Works exactly as before - no changes to user experience
- **SOTA RAG**: Full advanced capabilities available immediately
- **No Interference**: Systems don't affect each other's operation

### Infrastructure Sharing
- **Database**: Single Supabase instance with separate schemas
- **n8n**: Single instance with workflows from both systems
- **Docker**: Shared containers and networking
- **Authentication**: Unified admin credentials across services

### Future Integration Ready
- **Modular Design**: Systems designed for future integration
- **Clean Separation**: Easy to add bridge workflows later
- **Data Preservation**: Both systems maintain their own data integrity
- **Extensibility**: Ready for planned integration phases

## Integration Planning

For future integration between systems, see `SOTA_PLANS.md` which outlines:
1. **Phase 1**: Document processing integration (InsightsLM → SOTA RAG pipeline)
2. **Phase 2**: Search enhancement integration  
3. **Phase 3**: Advanced feature exposure through InsightsLM UI
4. **Phase 4**: Complete backend unification

## Support

For issues with the dual system setup:
1. Check `DEPLOYMENT_SUMMARY.txt` for configuration details
2. Verify both database schemas exist and are populated correctly
3. Test each system independently before troubleshooting interactions
4. Consult `SOTA_PLANS.md` for planned integration roadmap
