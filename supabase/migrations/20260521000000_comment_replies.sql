-- Adiciona suporte a respostas aninhadas em comentários
ALTER TABLE comments ADD COLUMN parent_id uuid REFERENCES comments(id) ON DELETE CASCADE;

-- Recria a view para expor parent_id
DROP VIEW IF EXISTS content_comments_view;
CREATE VIEW content_comments_view AS
  SELECT
    c.id        AS comment_id,
    c.content_id,
    c.comment_text,
    c.created_at,
    c.user_id,
    c.parent_id,
    p.name AS user_name
  FROM comments c
  LEFT JOIN perfis p ON p.id = c.user_id;
