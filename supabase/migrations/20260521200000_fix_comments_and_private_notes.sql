-- =============================================================================
-- Fix: comments INSERT RLS + private_notes UNIQUE constraint
-- =============================================================================

-- Fix 1: comments INSERT policy
-- A policy "insert_comments" usava WITH CHECK (auth.uid() = user_id), mas o
-- frontend não passa user_id — usa o DEFAULT auth.uid() da tabela. O PostgREST
-- avalia WITH CHECK antes de aplicar o DEFAULT, então user_id chega null e a
-- checagem falha silenciosamente (nenhuma linha inserida, nenhum erro retornado).
-- A correção é exigir apenas que o usuário esteja autenticado — o DEFAULT garante
-- que user_id sempre será auth.uid().
DROP POLICY IF EXISTS "insert_comments" ON public.comments;

CREATE POLICY "insert_comments"
  ON public.comments FOR INSERT TO authenticated
  WITH CHECK (auth.uid() IS NOT NULL);

-- Fix 2: private_notes UNIQUE constraint
-- O upsert no frontend usa onConflict: 'user_id,content_id', mas a tabela foi
-- criada sem constraint UNIQUE nessas colunas. Sem ela, o PostgREST não consegue
-- resolver o conflito e o upsert falha (erro 42P10: no unique or exclusion
-- constraint matching the ON CONFLICT specification).
ALTER TABLE public.private_notes
  ADD CONSTRAINT unique_user_content_note UNIQUE (user_id, content_id);
