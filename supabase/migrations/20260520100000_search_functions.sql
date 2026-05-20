-- Busca full-text por transcrições
CREATE OR REPLACE FUNCTION search_content_fulltext(
  search_query text,
  filter_course_id uuid DEFAULT NULL
)
RETURNS TABLE (
  chunk_id    uuid,
  content_id  uuid,
  chunk_text  text,
  start_time  numeric,
  content_title text,
  thumbnail_url text,
  module_title  text,
  course_title  text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cc.id          AS chunk_id,
    cc.content_id,
    cc.text        AS chunk_text,
    cc.start_time,
    c.title        AS content_title,
    co.thumbnail_url,
    m.title        AS module_title,
    co.title       AS course_title
  FROM content_chunks cc
  JOIN contents c  ON c.id  = cc.content_id
  JOIN modules  m  ON m.id  = c.module_id
  JOIN courses  co ON co.id = m.course_id
  WHERE cc.text ILIKE '%' || search_query || '%'
    AND (filter_course_id IS NULL OR co.id = filter_course_id)
  ORDER BY co.title, m.order_index, c.order_index, cc.start_time
  LIMIT 20;
$$;

-- Busca semântica por embeddings (pgvector)
CREATE OR REPLACE FUNCTION search_content_semantic(
  query_embedding vector(1536),
  filter_course_id uuid DEFAULT NULL,
  match_count int DEFAULT 20
)
RETURNS TABLE (
  chunk_id    uuid,
  content_id  uuid,
  chunk_text  text,
  start_time  numeric,
  content_title text,
  thumbnail_url text,
  module_title  text,
  course_title  text,
  distance    float
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    cc.id          AS chunk_id,
    cc.content_id,
    cc.text        AS chunk_text,
    cc.start_time,
    c.title        AS content_title,
    co.thumbnail_url,
    m.title        AS module_title,
    co.title       AS course_title,
    (cc.embedding <=> query_embedding) AS distance
  FROM content_chunks cc
  JOIN contents c  ON c.id  = cc.content_id
  JOIN modules  m  ON m.id  = c.module_id
  JOIN courses  co ON co.id = m.course_id
  WHERE cc.embedding IS NOT NULL
    AND (filter_course_id IS NULL OR co.id = filter_course_id)
  ORDER BY distance ASC
  LIMIT match_count;
$$;
