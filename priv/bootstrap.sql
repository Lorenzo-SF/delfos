-- Delfos bootstrap SQL
-- Versioned: 2.1.0 (2026-07-07)
--
-- Apply this script to bootstrap a fresh delfos database:
--   psql -h <host> -p <port> -U <user> -d <database> -f bootstrap.sql
--
-- Or from the release binary: `delfos doctor --fix`
--
-- Requirements:
--   - PostgreSQL >= 17
--   - pgvector extension installed (apt: postgresql-17-pgvector)
--   - pgcrypto extension (for gen_random_uuid)

-- ─── Extensions ────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ─── Projects ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS projects (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    path            TEXT NOT NULL,
    primary_stack   VARCHAR(64),
    all_stacks      TEXT[] DEFAULT '{}',
    git_remote      TEXT,
    git_branch      VARCHAR(255),
    last_commit     VARCHAR(64),
    last_scanned    TIMESTAMP,
    config          JSONB DEFAULT '{}',
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS projects_path_idx ON projects(path);

-- ─── Files ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS files (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    path            TEXT NOT NULL,
    language        VARCHAR(64),
    size_bytes      BIGINT,
    line_count      INTEGER,
    last_modified   TIMESTAMP,
    last_indexed    TIMESTAMP,
    content_hash    VARCHAR(64),
    git_churn       INTEGER DEFAULT 0,
    git_authors     TEXT[] DEFAULT '{}',
    risk_score      DOUBLE PRECISION DEFAULT 0.0,
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS files_project_path_idx ON files(project_id, path);
CREATE INDEX        IF NOT EXISTS files_project_risk_idx ON files(project_id, risk_score);

-- ─── Symbols ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS symbols (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,
    qualified_name  TEXT,
    kind            VARCHAR(64) NOT NULL,
    visibility      VARCHAR(32),
    line_start      INTEGER,
    line_end        INTEGER,
    signature       TEXT,
    docstring       TEXT,
    content         TEXT,
    language        VARCHAR(64),
    metadata        JSONB DEFAULT '{}',
    embedding       vector(1024),
    summary         TEXT,
    summary_hash    VARCHAR(64),
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS symbols_project_kind_idx     ON symbols(project_id, kind);
CREATE INDEX IF NOT EXISTS symbols_file_idx             ON symbols(file_id);
CREATE INDEX IF NOT EXISTS symbols_project_qname_idx    ON symbols(project_id, qualified_name);

-- IVFFlat index for vector similarity (replaced by HNSW if available)
CREATE INDEX IF NOT EXISTS symbols_embedding_idx
    ON symbols USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- HNSW index (preferred for vector(1024))
CREATE INDEX IF NOT EXISTS symbols_embedding_hnsw_idx
    ON symbols USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 200);

-- FTS index for BM25-style search
CREATE INDEX IF NOT EXISTS symbols_fts_idx ON symbols
    USING gin(to_tsvector('simple',
        coalesce(name,'') || ' ' || coalesce(qualified_name,'') || ' ' || coalesce(content,'')));

-- ─── Chunks ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chunks (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol_id       UUID REFERENCES symbols(id) ON DELETE CASCADE,
    file_id         UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    line_start      INTEGER,
    line_end        INTEGER,
    chunk_index     INTEGER,
    token_count     INTEGER,
    embedding       vector(1024),
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS chunks_project_idx ON chunks(project_id);
CREATE INDEX IF NOT EXISTS chunks_symbol_idx  ON chunks(symbol_id);

CREATE INDEX IF NOT EXISTS chunks_embedding_idx
    ON chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

CREATE INDEX IF NOT EXISTS chunks_embedding_hnsw_idx
    ON chunks USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 200);

CREATE INDEX IF NOT EXISTS chunks_fts_idx ON chunks
    USING gin(to_tsvector('simple', content));

-- ─── Summaries ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS summaries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    level           INTEGER NOT NULL,
    scope           VARCHAR(64) NOT NULL,
    file_id         UUID REFERENCES files(id) ON DELETE SET NULL,
    symbol_id       UUID REFERENCES symbols(id) ON DELETE SET NULL,
    content         TEXT NOT NULL,
    content_hash    VARCHAR(64),
    embedding       vector(1024),
    model_used      VARCHAR(128),
    generated_at    TIMESTAMP,
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS summaries_project_level_scope_idx
    ON summaries(project_id, level, scope);

CREATE INDEX IF NOT EXISTS summaries_embedding_idx
    ON summaries USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ─── Relationships ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS relationships (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    from_id         UUID NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,
    to_id           UUID NOT NULL REFERENCES symbols(id) ON DELETE CASCADE,
    kind            VARCHAR(64) NOT NULL,
    weight          DOUBLE PRECISION DEFAULT 1.0,
    metadata        JSONB DEFAULT '{}',
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS relationships_from_to_kind_idx
    ON relationships(from_id, to_id, kind);
CREATE INDEX        IF NOT EXISTS relationships_project_from_kind_idx
    ON relationships(project_id, from_id, kind);
CREATE INDEX        IF NOT EXISTS relationships_project_to_kind_idx
    ON relationships(project_id, to_id, kind);

-- ─── File metrics ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS file_metrics (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_id             UUID NOT NULL REFERENCES files(id) ON DELETE CASCADE,
    project_id          UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    afferent_coupling   INTEGER DEFAULT 0,
    efferent_coupling   INTEGER DEFAULT 0,
    instability         DOUBLE PRECISION DEFAULT 0.0,
    in_cycle            BOOLEAN DEFAULT FALSE,
    test_coverage_est   DOUBLE PRECISION,
    todo_count          INTEGER DEFAULT 0,
    complexity_score    DOUBLE PRECISION DEFAULT 0.0,
    debt_score          DOUBLE PRECISION DEFAULT 0.0,
    inserted_at         TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS file_metrics_file_idx ON file_metrics(file_id);
CREATE INDEX        IF NOT EXISTS file_metrics_project_debt_idx
    ON file_metrics(project_id, debt_score);

-- ─── Agent sessions (for ranking feedback) ────────────────────────────
CREATE TABLE IF NOT EXISTS agent_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    query           TEXT,
    retrieved_ids   UUID[] DEFAULT '{}',
    was_useful      BOOLEAN,
    metadata        JSONB DEFAULT '{}',
    inserted_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS agent_sessions_project_idx ON agent_sessions(project_id);

-- ─── Bootstrap marker ──────────────────────────────────────────────────
-- The bootstrap marker lets us tell whether the bootstrap script (vs
-- Ecto migrations) was used to provision the database. We INSERT it
-- at the end of the script so partial failures are visible.
CREATE TABLE IF NOT EXISTS _delfos_bootstrap (
    version     VARCHAR(32) PRIMARY KEY,
    applied_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO _delfos_bootstrap (version) VALUES ('2.1.0')
ON CONFLICT (version) DO NOTHING;