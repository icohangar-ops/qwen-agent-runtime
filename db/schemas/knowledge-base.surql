-- ============================================================
-- Senso.AI Knowledge Base Schema
-- SurrealDB Multi-Model (Document + Graph + Vector + Full-Text)
-- ============================================================
-- Usage: surreal start --user root --pass root memory
--        surreal sql --user root --pass root < knowledge-base.surql
-- ============================================================

-- Namespace and database
USE NS senso;
USE DB knowledge;

-- ============================================================
-- TABLES
-- ============================================================

-- Repository: tracks each git repo in the Senso.AI ecosystem
DEFINE TABLE repository SCHEMAFULL
    PERMISSIONS
        FOR select FULL,
        FOR create WHERE $auth.level >= 'editor',
        FOR update WHERE $auth.level >= 'editor',
        FOR delete WHERE $auth.level >= 'admin';

DEFINE FIELD name ON TABLE repository TYPE string ASSERT string::len($value) > 0;
DEFINE FIELD description ON TABLE repository TYPE string;
DEFINE FIELD url ON TABLE repository TYPE string;
DEFINE FIELD platform ON TABLE repository TYPE string; -- github, codeberg
DEFINE FIELD owner ON TABLE repository TYPE string;
DEFINE FIELD visibility ON TABLE repository TYPE string DEFAULT 'private';
DEFINE FIELD language ON TABLE repository TYPE string;
DEFINE FIELD topics ON TABLE repository TYPE array;
DEFINE FIELD created_at ON TABLE repository TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON TABLE repository TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_repo_name ON TABLE repository FIELDS name UNIQUE;
DEFINE INDEX idx_repo_platform ON TABLE repository FIELDS platform;

-- Document: individual knowledge documents (markdown, papers, guides)
DEFINE TABLE document SCHEMAFULL
    PERMISSIONS
        FOR select FULL,
        FOR create WHERE $auth.level >= 'editor',
        FOR update WHERE $auth.level >= 'editor',
        FOR delete WHERE $auth.level >= 'admin';

DEFINE FIELD title ON TABLE document TYPE string ASSERT string::len($value) > 0;
DEFINE FIELD content ON TABLE document TYPE string;
DEFINE FIELD summary ON TABLE document TYPE string;
DEFINE FIELD doc_type ON TABLE document TYPE string; -- paper, guide, spec, readme, whitepaper
DEFINE FIELD format ON TABLE document TYPE string DEFAULT 'markdown';
DEFINE FIELD repository ON TABLE document TYPE record<repository>;
DEFINE FIELD file_path ON TABLE document TYPE string;
DEFINE FIELD authors ON TABLE document TYPE array;
DEFINE FIELD tags ON TABLE document TYPE array;
DEFINE FIELD status ON TABLE document TYPE string DEFAULT 'draft'; -- draft, review, published, archived
DEFINE FIELD version ON TABLE document TYPE string DEFAULT '1.0';
DEFINE FIELD created_at ON TABLE document TYPE datetime DEFAULT time::now();
DEFINE FIELD updated_at ON TABLE document TYPE datetime DEFAULT time::now();

DEFINE INDEX idx_doc_title ON TABLE document FIELDS title;
DEFINE INDEX idx_doc_type ON TABLE document FIELDS doc_type;
DEFINE INDEX idx_doc_repo ON TABLE repository FIELDS repository;
DEFINE INDEX idx_doc_status ON TABLE document FIELDS status;
DEFINE INDEX ft_doc_content ON TABLE document FIELDS content, title, summary SEARCH ANALYZER bm25 TOKENIZERS blank,camel,class;

-- Vector index for semantic search on document content
DEFINE INDEX vec_doc_content ON TABLE document FIELDS content MTREE DIMENSIONS 1536 DISTANCE COSINE;

-- Category: taxonomy for organizing documents
DEFINE TABLE category SCHEMAFULL
    PERMISSIONS
        FOR select FULL,
        FOR create WHERE $auth.level >= 'editor',
        FOR update WHERE $auth.level >= 'editor',
        FOR delete WHERE $auth.level >= 'admin';

DEFINE FIELD name ON TABLE repository TYPE string ASSERT string::len($value) > 0;
DEFINE FIELD slug ON TABLE repository TYPE string ASSERT string::len($value) > 0;
DEFINE FIELD description ON TABLE repository TYPE string;
DEFINE FIELD parent ON TABLE category TYPE option<record<category>>;

DEFINE INDEX idx_cat_slug ON TABLE category FIELDS slug UNIQUE;

-- ============================================================
-- GRAPH EDGES
-- ============================================================

-- Document belongs to a repository
DEFINE TABLE belongs_to SCHEMAFULL TYPE RELATION IN document OUT repository;

-- Document categorized under a category (supports multi-categorization)
DEFINE TABLE categorized_as SCHEMAFULL TYPE RELATION IN document OUT category;

-- Document references another document (cross-references)
DEFINE TABLE references SCHEMAFULL TYPE RELATION IN document OUT document;

-- Document is part of a series (ordered collection)
DEFINE TABLE part_of SCHEMAFULL TYPE RELATION IN document OUT document;

-- ============================================================
-- EVENTS (triggers)
-- ============================================================

-- Auto-update updated_at timestamp on document changes
DEFINE EVENT update_timestamp ON TABLE document WHEN $before.updated_at != $after.updated_at THEN (
    UPDATE $id SET updated_at = time::now()
);

-- Log when a document status changes
DEFINE EVENT log_status_change ON TABLE document WHEN $before.status != $after.status THEN (
    CREATE audit_log SET
        action = 'status_change',
        resource = $value.id,
        detail = {
            from: $before.status,
            to: $after.status
        },
        timestamp = time::now()
);

-- ============================================================
-- SAMPLE DATA
-- ============================================================

-- Repositories
CREATE repository SET
    name = 'qwen-agent-runtime',
    description = 'AI-powered shell command execution with guardrails',
    url = 'https://codeberg.org/cubiczan/qwen-agent-runtime',
    platform = 'codeberg',
    owner = 'cubiczan',
    visibility = 'private',
    language = 'python',
    topics = ['ai', 'agent', 'llm', 'cli', 'powershell', 'security'];

CREATE repository SET
    name = 'senso-ai-knowledge-base',
    description = 'Central knowledge base for the Senso.AI ecosystem',
    url = 'https://codeberg.org/cubiczan/senso-ai-knowledge-base',
    platform = 'codeberg',
    owner = 'cubiczan',
    visibility = 'private',
    language = 'markdown',
    topics = ['knowledge-base', 'documentation', 'ai'];

-- Categories
CREATE category SET name = 'Architecture', slug = 'architecture', description = 'System design and architecture documents';
CREATE category SET name = 'Security', slug = 'security', description = 'Security models, guardrails, and threat assessments';
CREATE category SET name = 'Operations', slug = 'operations', description = 'Deployment, monitoring, and runbooks';
CREATE category SET name = 'Research', slug = 'research', description = 'Research papers and technical investigations';

-- ============================================================
-- EXAMPLE QUERIES (reference for agent integration)
-- ============================================================

-- Full-text search across all documents
-- SELECT * FROM document WHERE content @@ 'agent guardrails deny-list';
-- SELECT * FROM document WHERE title @@ 'architecture' AND status = 'published';

-- Semantic/vector search (requires vector embeddings)
-- SELECT *, vector::similarity::cosine(content, <vector>[0.1, 0.2, ...]) AS similarity
-- FROM document ORDER BY similarity DESC LIMIT 10;

-- Graph traversal: find all documents in a repo that reference another
-- SELECT <-references.in.title FROM document WHERE id = document:abc123;

-- Graph traversal: find all documents in a category
-- SELECT in.id, in.title FROM categorized_as WHERE out = category:architecture;

-- Multi-hop: documents in category that belong to a specific repo
-- SELECT in.id, in.title, in.status FROM categorized_as
-- WHERE out = category:security
-- AND in.repository = repository:qwen-agent-runtime;

-- Real-time: subscribe to new documents in a category
-- LIVE SELECT * FROM document WHERE status = 'published' PARALLEL;
