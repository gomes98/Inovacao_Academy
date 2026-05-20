-- =============================================================================
-- Course Access Control — Tabelas de permissão e RLS
-- =============================================================================

-- ------------------------------------------------------------
-- TABELAS
-- ------------------------------------------------------------

-- Modo geral de acesso do aluno (default: restricted = sem acesso)
CREATE TABLE IF NOT EXISTS public.user_access_mode (
  user_id uuid PRIMARY KEY REFERENCES public.perfis(id) ON DELETE CASCADE,
  mode    text NOT NULL DEFAULT 'restricted'
            CHECK (mode IN ('all_courses', 'restricted'))
);

-- Acesso individual a cursos específicos
CREATE TABLE IF NOT EXISTS public.user_course_access (
  user_id   uuid REFERENCES public.perfis(id)   ON DELETE CASCADE,
  course_id uuid REFERENCES public.courses(id)  ON DELETE CASCADE,
  PRIMARY KEY (user_id, course_id)
);

-- Grupos de permissão
CREATE TABLE IF NOT EXISTS public.permission_groups (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Cursos que um grupo pode acessar
CREATE TABLE IF NOT EXISTS public.group_course_access (
  group_id  uuid REFERENCES public.permission_groups(id) ON DELETE CASCADE,
  course_id uuid REFERENCES public.courses(id)           ON DELETE CASCADE,
  PRIMARY KEY (group_id, course_id)
);

-- Usuários que pertencem a um grupo
CREATE TABLE IF NOT EXISTS public.user_groups (
  user_id  uuid REFERENCES public.perfis(id)           ON DELETE CASCADE,
  group_id uuid REFERENCES public.permission_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, group_id)
);

-- ------------------------------------------------------------
-- RLS — HABILITAR
-- ------------------------------------------------------------

ALTER TABLE public.user_access_mode    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_course_access  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_groups   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_course_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_groups         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses             ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- POLICIES — user_access_mode
-- ------------------------------------------------------------

CREATE POLICY "user_access_mode_select_own"
  ON public.user_access_mode FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "user_access_mode_admin_all"
  ON public.user_access_mode FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICIES — user_course_access
-- ------------------------------------------------------------

CREATE POLICY "user_course_access_select_own"
  ON public.user_course_access FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "user_course_access_admin_all"
  ON public.user_course_access FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICIES — permission_groups
-- ------------------------------------------------------------

CREATE POLICY "permission_groups_select_authenticated"
  ON public.permission_groups FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "permission_groups_admin_all"
  ON public.permission_groups FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICIES — group_course_access
-- ------------------------------------------------------------

CREATE POLICY "group_course_access_select_authenticated"
  ON public.group_course_access FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "group_course_access_admin_all"
  ON public.group_course_access FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICIES — user_groups
-- ------------------------------------------------------------

CREATE POLICY "user_groups_select_own"
  ON public.user_groups FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "user_groups_admin_all"
  ON public.user_groups FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICY — courses SELECT (lógica central de acesso)
-- ------------------------------------------------------------

-- Garante que admins sempre vejam tudo mesmo com RLS ativo
CREATE POLICY "courses_admin_all"
  ON public.courses FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- Policy de SELECT para todos os usuários autenticados
CREATE POLICY "courses_access"
  ON public.courses FOR SELECT
  USING (
    -- Publicador vê tudo
    has_role(ARRAY['publicador'])

    -- Aluno com mode = 'all_courses'
    OR EXISTS (
      SELECT 1 FROM public.user_access_mode
      WHERE user_id = auth.uid() AND mode = 'all_courses'
    )

    -- Acesso individual ao curso
    OR EXISTS (
      SELECT 1 FROM public.user_course_access
      WHERE user_id = auth.uid() AND course_id = courses.id
    )

    -- Acesso via grupo
    OR EXISTS (
      SELECT 1 FROM public.user_groups ug
      JOIN public.group_course_access gca ON gca.group_id = ug.group_id
      WHERE ug.user_id = auth.uid() AND gca.course_id = courses.id
    )
  );
