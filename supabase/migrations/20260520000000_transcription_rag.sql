-- =============================================================================
-- Inovação Academy — Transcrição + Busca Semântica (Whisper + RAG)
-- Adiciona pgvector, tabelas de transcrição/chunks, RPC de busca e RLS.
-- =============================================================================

-- ============================================================
-- EXTENSÃO
-- ============================================================
CREATE EXTENSION IF NOT EXISTS vector;

-- ============================================================
-- STATUS DE CONTEÚDO — amplia CHECK para a máquina de estados nova
-- ============================================================
-- (status hoje é text livre; passamos a documentar via CHECK)
ALTER TABLE public.contents
    DROP CONSTRAINT IF EXISTS contents_status_check;

ALTER TABLE public.contents
    ADD CONSTRAINT contents_status_check
    CHECK (status = ANY (ARRAY[
        'uploaded',
        'processed',
        'transcribing',
        'indexed',
        'failed'
    ]));

-- ============================================================
-- TABELA: content_transcriptions — uma por conteúdo
-- ============================================================
CREATE TABLE IF NOT EXISTS public.content_transcriptions (
    content_id    uuid PRIMARY KEY REFERENCES public.contents(id) ON DELETE CASCADE,
    language      text,
    full_text     text NOT NULL,
    segments_json jsonb NOT NULL,
    model         text NOT NULL,
    duration_sec  numeric,
    created_at    timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- TABELA: content_chunks — pedaços com embedding p/ busca vetorial
-- ============================================================
CREATE TABLE IF NOT EXISTS public.content_chunks (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id    uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    chunk_index   integer NOT NULL,
    text          text NOT NULL,
    start_time    numeric NOT NULL,
    end_time      numeric NOT NULL,
    token_count   integer,
    embedding     vector(1536),
    embedding_model text NOT NULL DEFAULT 'text-embedding-3-small',
    created_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (content_id, chunk_index)
);

-- Índice HNSW para similaridade de cosseno (pgvector ≥ 0.5)
CREATE INDEX IF NOT EXISTS content_chunks_embedding_idx
    ON public.content_chunks
    USING hnsw (embedding vector_cosine_ops);

CREATE INDEX IF NOT EXISTS content_chunks_content_id_idx
    ON public.content_chunks (content_id);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.content_transcriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.content_chunks         ENABLE ROW LEVEL SECURITY;

-- Leitura aberta para autenticados (mesma política das demais tabelas de conteúdo)
CREATE POLICY "select_transcriptions"
    ON public.content_transcriptions FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin_transcriptions"
    ON public.content_transcriptions FOR ALL TO authenticated
    USING (has_role(ARRAY['admin', 'publicador']))
    WITH CHECK (has_role(ARRAY['admin', 'publicador']));

CREATE POLICY "select_chunks"
    ON public.content_chunks FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin_chunks"
    ON public.content_chunks FOR ALL TO authenticated
    USING (has_role(ARRAY['admin', 'publicador']))
    WITH CHECK (has_role(ARRAY['admin', 'publicador']));

-- ============================================================
-- RPC: search_transcripts — busca vetorial top-k
-- ============================================================
-- Recebe um embedding já calculado no cliente/worker e retorna os
-- chunks mais similares, com metadados do conteúdo/curso.
--
-- SECURITY INVOKER → respeita RLS de quem chamou (authenticated).
-- ============================================================
CREATE OR REPLACE FUNCTION public.search_transcripts(
    query_embedding vector(1536),
    match_count int DEFAULT 10,
    course_filter uuid DEFAULT NULL,
    min_similarity float DEFAULT 0.0
)
RETURNS TABLE (
    chunk_id      uuid,
    content_id    uuid,
    content_title text,
    module_id     uuid,
    course_id     uuid,
    course_title  text,
    chunk_text    text,
    start_time    numeric,
    end_time      numeric,
    similarity    float
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    SELECT
        ch.id AS chunk_id,
        co.id AS content_id,
        co.title AS content_title,
        m.id AS module_id,
        c.id AS course_id,
        c.title AS course_title,
        ch.text AS chunk_text,
        ch.start_time,
        ch.end_time,
        1 - (ch.embedding <=> query_embedding) AS similarity
    FROM public.content_chunks ch
    JOIN public.contents co ON co.id = ch.content_id
    JOIN public.modules  m  ON m.id  = co.module_id
    JOIN public.courses  c  ON c.id  = m.course_id
    WHERE
        ch.embedding IS NOT NULL
        AND (course_filter IS NULL OR c.id = course_filter)
        AND (1 - (ch.embedding <=> query_embedding)) >= min_similarity
    ORDER BY ch.embedding <=> query_embedding ASC
    LIMIT match_count;
$$;

GRANT EXECUTE ON FUNCTION public.search_transcripts(vector, int, uuid, float)
    TO authenticated;

-- ============================================================
-- DATABASE WEBHOOK (helper) — registrar manualmente no painel
-- ============================================================
-- O webhook deve ser criado em:
--   Database → Webhooks → New Hook
--     Table: contents
--     Events: UPDATE
--     Condition: record.status = 'processed' AND old_record.status != 'processed'
--     URL: https://<worker-host>/webhook/content-processed
--     HTTP Headers: Authorization: Bearer <WORKER_WEBHOOK_SECRET>
-- ============================================================
