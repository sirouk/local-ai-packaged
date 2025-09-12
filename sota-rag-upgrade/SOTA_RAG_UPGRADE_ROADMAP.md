# SOTA RAG Upgrade Roadmap

## Milestones

### 1. System Analysis & Planning (Difficulty: 4/10)
Complete understanding of current InsightsLM system and SOTA requirements.

### 2. Database Schema Migration (Difficulty: 6/10)
Migrate from simple InsightsLM schema to SOTA RAG schema with advanced capabilities.

### 3. Edge Functions Upgrade (Difficulty: 7/10)
Replace basic edge functions with SOTA RAG edge functions supporting hybrid search, vector operations, and advanced features.

### 4. Workflow Migration & Configuration (Difficulty: 8/10)
Import and configure the main SOTA RAG workflow with all sub-workflows and dependencies.

### 5. Static Deployment Infrastructure (Difficulty: 5/10)
Create easy_deploy.sh for static file deployment without repository downloads.

### 6. API Integration Phase 1 (Difficulty: 6/10)
Configure OpenAI, Mistral, Cohere, and Zep integrations for first deployment.

### 7. Ollama Migration Phase 2 (Difficulty: 8/10)
Replace external APIs with local Ollama equivalents where possible.

---

## Tasks

### Milestone 1: System Analysis & Planning
- ✅ **Analyze current InsightsLM architecture**
  - Current: Simple RAG with basic vector search, local Ollama only
  - Uses `documents` table, `n8n_chat_histories`, basic edge functions
  - Focus on notebook generation and podcast creation

- ✅ **Analyze SOTA RAG requirements**
  - Advanced schema: `documents_v2`, `record_manager_v2`, `tabular_document_rows`, `metadata_fields`
  - Hybrid search with RRF ranking, contextual embeddings, GraphRAG
  - Multi-modal support, long-term memory, advanced metadata filtering

### Milestone 2: Database Schema Migration (In Progress)

#### Tasks:
- **Create schema migration script** (Difficulty: 5/10)
  - Migrate from `documents` to `documents_v2` with vector(1536) and FTS
  - Add `record_manager_v2` for document tracking and versioning
  - Add `tabular_document_rows` for spreadsheet data support
  - Add `metadata_fields` for advanced filtering capabilities
  - Preserve existing InsightsLM data during migration

- **Create database functions** (Difficulty: 7/10)
  - Deploy `hybrid_search_v2_with_details` function for advanced search
  - Deploy vector search functions with filtering
  - Add match functions for backward compatibility

#### Subtasks:
- Create backup of current `documents` and `n8n_chat_histories` tables
- Create migration script that maps InsightsLM data to SOTA schema
- Add vector extension and HNSW indices
- Test migration with sample data

### Milestone 3: Edge Functions Upgrade

#### Tasks:
- **Deploy SOTA edge functions** (Difficulty: 6/10)
  - Replace current edge functions with `vector-search` and `hybrid-search`
  - Ensure compatibility with existing InsightsLM frontend API contracts
  - Add backward compatibility layer if needed

- **Update edge function environment** (Difficulty: 4/10)
  - Configure new environment variables in Supabase functions
  - Update authentication and CORS settings

#### Subtasks:
- Create `supabase/functions/vector-search/index.ts`
- Create `supabase/functions/hybrid-search/index.ts`
- Update existing InsightsLM functions to work with new schema
- Test edge functions with both old and new data formats

### Milestone 4: Workflow Migration & Configuration

#### Tasks:
- **Import main SOTA RAG workflow** (Difficulty: 7/10)
  - Import `TheAIAutomators.com - RAG SOTA - v2.0 BLUEPRINT.json`
  - Configure for local deployment with available services
  - Replace external service references with local equivalents where possible

- **Configure sub-workflows** (Difficulty: 8/10)
  - Import and configure Knowledge Graph workflow (LightRAG)
  - Import and configure Multimodal RAG sub-workflow
  - Set up modular feature toggles (LightRAG, Multimodal, Contextual Embeddings)

- **Update existing InsightsLM workflows** (Difficulty: 6/10)
  - Modify chat workflow to use new vector store structure
  - Update text extraction to support new metadata fields
  - Enhance notebook generation with SOTA features

#### Subtasks:
- Create workflow import script with credential ID substitution
- Configure workflow settings for local deployment
- Set up proper workflow connections and dependencies
- Test workflow execution with sample data

### Milestone 5: Static Deployment Infrastructure

#### Tasks:
- **Create easy_deploy.sh script** (Difficulty: 5/10)
  - Similar to easy_setup_v2.sh but uses static files
  - No repository downloads, works with files in place
  - Maintains all existing functionality

- **Update deployment configuration** (Difficulty: 4/10)
  - Ensure frontend works with new backend structure
  - Update environment variable handling
  - Configure service dependencies

#### Subtasks:
- Copy easy_setup_v2.sh structure
- Remove git clone operations
- Add local file validation and setup
- Test deployment process

### Milestone 6: API Integration Phase 1

#### Tasks:
- **Configure OpenAI integration** (Difficulty: 4/10)
  - Set up OpenAI API credentials for LLM operations
  - Configure embedding models
  - Set up rate limiting and error handling

- **Configure Mistral integration** (Difficulty: 5/10)
  - Set up Mistral API for OCR and document processing
  - Configure multimodal capabilities
  - Add fallback mechanisms

- **Configure Cohere integration** (Difficulty: 4/10)
  - Set up Cohere for reranking functionality
  - Configure rerank models and parameters

- **Configure Zep integration** (Difficulty: 6/10)
  - Set up Zep account and project
  - Configure long-term memory workflows
  - Set up user isolation and session management

#### Subtasks:
- Create API key management system
- Add credential templates to deployment script
- Configure rate limiting and quota management
- Set up monitoring and alerting for API usage

### Milestone 7: Ollama Migration Phase 2

#### Tasks:
- **Replace OpenAI with Ollama** (Difficulty: 7/10)
  - Modify workflows to use local Ollama models
  - Ensure embedding compatibility (1536 dimensions)
  - Maintain performance and quality

- **Replace Mistral OCR** (Difficulty: 8/10)
  - Research and implement local OCR alternative
  - Options: Tesseract, PaddleOCR, or other local solutions
  - Maintain multimodal document processing capabilities

- **Implement local reranking** (Difficulty: 9/10)
  - Replace Cohere with local reranking models
  - Options: sentence-transformers, local cross-encoders
  - Ensure ranking quality matches external services

#### Subtasks:
- Research and test local alternatives
- Create wrapper services for local models
- Update workflow configurations
- Performance testing and optimization

---

## Dependencies & Requirements

### External Services (Phase 1):
- OpenAI API (GPT-4, embeddings)
- Mistral API (OCR, vision models)  
- Cohere API (reranking)
- Zep (long-term memory)
- Google Drive API (optional, for ingestion)

### Local Services:
- Supabase (database, vector store, auth, storage)
- n8n (workflow orchestration)
- Ollama (local LLMs and embeddings)
- Docker (containerization)
- nginx (reverse proxy)

### New Database Tables:
- `documents_v2` (enhanced vector store)
- `record_manager_v2` (document versioning)
- `tabular_document_rows` (spreadsheet data)
- `metadata_fields` (filtering configuration)

### New Edge Functions:
- `vector-search` (vector similarity search)
- `hybrid-search` (combined vector + keyword search)
- Enhanced InsightsLM functions with new schema support

---

## Implementation Order

1. **Database Migration** - Critical foundation
2. **Edge Functions** - Core functionality 
3. **Static Deployment Script** - Infrastructure
4. **Main SOTA Workflow** - Core RAG capabilities
5. **API Integrations** - External services
6. **Sub-workflows** - Advanced features
7. **Frontend Compatibility** - User interface
8. **Local Migration** - Full local deployment

---

## Risk Assessment

### High Risk (Difficulty 8-10):
- Workflow complexity and integration
- Local replacements for external services
- Data migration without loss

### Medium Risk (Difficulty 6-7):
- API integration and rate limiting
- Database function compatibility
- Performance optimization

### Low Risk (Difficulty 3-5):
- Static deployment infrastructure  
- Basic configuration updates
- Environment variable management

---

## Success Criteria

### Phase 1 (External APIs):
- All SOTA RAG features working with external APIs
- Successful migration of existing InsightsLM data
- Frontend compatibility maintained
- Static deployment process functional

### Phase 2 (Local Only):
- Full local operation with Ollama
- Local OCR and reranking implemented
- Performance comparable to external services
- No external API dependencies

---

## Timeline Estimates

- **Phase 1 Setup**: 2-3 days
- **Database Migration**: 1 day
- **Workflow Configuration**: 2 days
- **API Integration**: 1 day
- **Testing & Validation**: 1 day
- **Phase 2 Local Migration**: 3-4 days (research + implementation)

**Total: 10-14 days for complete upgrade**
