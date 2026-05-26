-- =============================================================================
-- Fix views sem security_invoker — garante que RLS das tabelas subjacentes
-- seja respeitado para o usuário que consulta a view.
-- =============================================================================

CREATE OR REPLACE VIEW public.content_private_notes_view
WITH (security_invoker = true)
AS
SELECT
    pn.content_id,
    pn.id AS note_id,
    pn.note_text,
    pn.updated_at,
    pn.user_id
FROM private_notes pn;

CREATE OR REPLACE VIEW public.course_catalog
WITH (security_invoker = true)
AS
SELECT
    c.id AS course_id,
    c.title AS course_title,
    c.description AS course_description,
    c.thumbnail_url,
    count(DISTINCT m.id) AS total_modules,
    count(DISTINCT co.id) AS total_contents,
    count(DISTINCT up.content_id) AS completed_contents
FROM courses c
LEFT JOIN modules m ON m.course_id = c.id
LEFT JOIN contents co ON co.module_id = m.id
LEFT JOIN user_progress up ON up.content_id = co.id AND up.user_id = auth.uid()
GROUP BY c.id;

CREATE OR REPLACE VIEW public.course_structure
WITH (security_invoker = true)
AS
SELECT
    c.id AS course_id,
    c.title AS course_title,
    m.id AS module_id,
    m.title AS module_title,
    m.order_index AS module_order,
    co.id AS content_id,
    co.title AS content_title,
    co.content_type,
    co.order_index AS content_order,
    co.duration AS content_duration,
    (up.content_id IS NOT NULL) AS is_completed
FROM courses c
JOIN modules m ON m.course_id = c.id
JOIN contents co ON co.module_id = m.id
LEFT JOIN user_progress up ON up.content_id = co.id AND up.user_id = auth.uid();
