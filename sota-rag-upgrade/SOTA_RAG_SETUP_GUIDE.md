# SOTA RAG Setup Guide

## Overview

This guide will help you upgrade from the current InsightsLM system to the State-of-the-Art (SOTA) RAG system with advanced features like hybrid search, contextual embeddings, GraphRAG, and multimodal capabilities.

## Quick Start

### Option 1: Use easy_deploy.sh (Recommended)
```bash
./easy_deploy.sh
```

This interactive script will:
- Guide you through configuration options
- Handle database migration
- Configure workflows and services
- Set up API integrations

### Option 2: Manual Upgrade
```bash
# 1. Run the upgrade orchestrator
python3 upgrade-to-sota-rag.py

# 2. Configure environment
# Edit .env file with your API keys

# 3. Import workflows  
python3 workflows/import-sota-workflows.py
```

## Deployment Modes

### Phase 1: External APIs
- **Best for**: Testing and immediate advanced features
- **Requirements**: OpenAI, Mistral, Cohere, Zep API keys
- **Pros**: Full feature set, proven performance
- **Cons**: API costs, external dependencies

### Phase 2: Local-Only  
- **Best for**: Privacy, no ongoing costs
- **Requirements**: Powerful local hardware, local model alternatives
- **Pros**: Completely private, no API costs
- **Cons**: Requires local model research and configuration

## Features Available

### Core SOTA RAG Features
✅ **Hybrid Search** - Combines vector and keyword search with RRF ranking  
✅ **Advanced Metadata Filtering** - Sophisticated document filtering  
✅ **Contextual Embeddings** - AI-enhanced chunk embeddings  
✅ **Agentic RAG** - AI agent with multiple tools and memory  
✅ **Document Versioning** - Smart update detection and management  

### Optional Advanced Features
🔧 **GraphRAG/LightRAG** - Knowledge graph extraction and querying  
🔧 **Multimodal RAG** - Image and document processing  
🔧 **Long-term Memory** - User memory across sessions via Zep  
🔧 **Spreadsheet NLQ** - Natural language querying of tabular data  

## Database Schema Changes

### New Tables
- `documents_v2` - Enhanced vector store with FTS and metadata
- `record_manager_v2` - Document versioning and tracking
- `tabular_document_rows` - Spreadsheet data storage
- `metadata_fields` - Dynamic filtering configuration
- `n8n_chat_histories_v2` - Enhanced chat storage

### Migration Safety
- Original tables are backed up automatically
- Compatibility views maintain frontend functionality
- Rollback capability via backup files

## API Configuration

### Required API Keys (Phase 1)

#### OpenAI
```bash
OPENAI_API_KEY=your_openai_key_here
```
- Used for: Main LLM operations, embeddings, contextual enhancement
- Get key: https://platform.openai.com/api-keys

#### Mistral
```bash
MISTRAL_API_KEY=your_mistral_key_here
```
- Used for: OCR processing, multimodal document analysis
- Get key: https://console.mistral.ai/

#### Cohere
```bash
COHERE_API_KEY=your_cohere_key_here
```
- Used for: Result reranking and relevance optimization
- Get key: https://dashboard.cohere.ai/api-keys

#### Zep (Optional)
```bash
ZEP_API_KEY=your_zep_key_here
LIGHTRAG_SERVER_URL=your_lightrag_server_url
```
- Used for: Long-term memory and knowledge graphs
- Get key: https://www.getzep.com/ (free tier available)

## Local Alternatives (Phase 2)

### LLM Models
- Replace OpenAI with Ollama models
- Ensure embedding models output 1536 dimensions
- Configure model parameters in workflows

### OCR Processing
- **Option 1**: Tesseract + PDF preprocessing
- **Option 2**: Local vision models (LLaVA, etc.)
- **Option 3**: PaddleOCR for document processing

### Reranking
- **Option 1**: sentence-transformers cross-encoder
- **Option 2**: Local BGE reranker models
- **Option 3**: Custom ranking algorithms

## Workflow Configuration

### Main SOTA RAG Workflow
- **File**: `TheAIAutomators.com - RAG SOTA - v2.0 BLUEPRINT.json`
- **Features**: Hybrid search, metadata filtering, contextual embeddings
- **Dependencies**: Supabase, n8n, embedding service

### Sub-workflows

#### Knowledge Graph Workflow
- **File**: `Knowledge Graph Updates - SOTA RAG Blueprint - v1.0 BLUEPRINT.json`
- **Purpose**: LightRAG integration for knowledge extraction
- **Requirements**: LightRAG server or local alternative

#### Multimodal RAG Workflow  
- **File**: `Multimodal RAG - TheAIAutomators - SOTA RAG Sub-workflow - 1.0 BLUEPRINT.json`
- **Purpose**: Image and multimodal document processing
- **Requirements**: Vision models, OCR capabilities

## Frontend Compatibility

The enhanced deployment provides full compatibility between InsightsLM and SOTA RAG:

### Independent System Operation
- **Database Layer**: Separate schemas for complete independence (documents vs documents_v2)
- **API Layer**: InsightsLM endpoints use original functions, SOTA RAG uses enhanced functions  
- **Workflow Layer**: Both systems run with separate credentials and data stores
- **Storage Layer**: Independent vector stores with different embedding dimensions

### System Separation Benefits
- **InsightsLM**: Uses 768-dimensional embeddings (nomic-embed-text) with original schema
- **SOTA RAG**: Uses 1536-dimensional embeddings (text-embedding-3-small) with enhanced schema  
- **No Interference**: Systems operate completely independently
- **Preserve Functionality**: InsightsLM works exactly as before

### Service URLs
- **InsightsLM UI**: `http://localhost:3010` - Original notebook interface (independent operation)
- **SOTA RAG Workflows**: `http://localhost:5678` - n8n workflow management (independent operation)  
- **Supabase Studio**: `http://localhost:8000` - Database management for both systems

### Future Integration
For planned integration roadmap, see `SOTA_PLANS.md` which outlines how to:
1. Route InsightsLM document processing through SOTA RAG workflows
2. Enhance InsightsLM search with SOTA RAG capabilities
3. Expose SOTA RAG advanced features through InsightsLM UI

For current independent system details, see `INSIGHTSLM_SOTA_RAG_COMPATIBILITY.md`.

## Monitoring and Troubleshooting

### Health Checks
```bash
# Database connectivity
docker exec supabase-db pg_isready -U postgres

# n8n status
docker exec n8n n8n --version

# Edge functions
curl http://localhost:8000/functions/v1/vector-search

# Workflow status
curl -H "Authorization: Bearer $ANON_KEY" \
  http://localhost:5678/rest/workflows
```

### Common Issues

#### Database Migration Fails
- Check database permissions
- Verify Supabase is running
- Review migration logs

#### Workflow Import Fails
- Verify n8n is accessible
- Check credential configurations
- Ensure API keys are valid

#### Edge Functions Not Working
- Check function deployment
- Verify environment variables
- Review function logs

## Performance Considerations

### Vector Index Optimization
- HNSW index on embeddings for fast similarity search
- GIN index on FTS for keyword search
- Composite indices on metadata fields

### Memory Usage
- Large models require significant RAM
- Consider batch processing for large documents
- Monitor Docker resource usage

### API Rate Limits
- OpenAI: 3,500 RPM (Tier 1), 90,000 RPM (Tier 5)
- Mistral: Varies by plan
- Cohere: 1,000 requests/minute (Trial)
- Zep: 300 requests/minute (Free)

## Migration Rollback

If you need to rollback to the previous InsightsLM system:

```bash
# 1. Stop current services
python3 start_services.py --stop

# 2. Restore from backup
BACKUP_DIR="backup_YYYYMMDD_HHMMSS"  # Use your actual backup directory
cp $BACKUP_DIR/.env .env
cp $BACKUP_DIR/docker-compose.yml docker-compose.yml

# 3. Restore database
docker exec supabase-db psql -U supabase_admin -d postgres -f /dev/stdin < $BACKUP_DIR/insightslm_data_backup.sql

# 4. Restart services
python3 start_services.py --profile cpu --environment private
```

## Support and Community

- **Documentation**: SOTA_RAG_UPGRADE_ROADMAP.md
- **Issues**: GitHub Issues on the local-ai-packaged repository  
- **Community**: The AI Automators community forums
- **Original SOTA Templates**: TheAIAutomators.com RAG templates

## Success Metrics

After successful deployment, you should have:
- ✅ Enhanced vector search with hybrid ranking
- ✅ Advanced metadata filtering capabilities
- ✅ Contextual embeddings for better relevance
- ✅ Document versioning and change tracking
- ✅ Spreadsheet and tabular data support
- ✅ Multimodal document processing (if enabled)
- ✅ Knowledge graph integration (if enabled)
- ✅ Long-term memory across sessions (if enabled)

The SOTA RAG system provides significantly enhanced capabilities while maintaining compatibility with your existing InsightsLM frontend and workflows.
