-- Fix security_definer_view: recreate views with security_invoker=true
-- so RLS policies on underlying tables are enforced for the querying user.

CREATE OR REPLACE VIEW public.content_comments_view
WITH (security_invoker = true)
AS
SELECT c.id AS comment_id,
    c.content_id,
    c.comment_text,
    c.created_at,
    c.user_id,
    c.parent_id,
    p.name AS user_name
FROM (comments c
    LEFT JOIN perfis p ON ((p.id = c.user_id)));

CREATE OR REPLACE VIEW public.group_ranking_view
WITH (security_invoker = true)
AS
SELECT up.user_id,
    up.group_id,
    up.total_points,
    p.name AS user_name,
    p.avatar_url,
    rank() OVER (PARTITION BY up.group_id ORDER BY up.total_points DESC) AS rank_position
FROM (user_points up
    JOIN perfis p ON ((p.id = up.user_id)));
