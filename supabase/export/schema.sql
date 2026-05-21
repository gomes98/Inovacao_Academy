-- =============================================================================
-- Inovação Academy — Schema completo para Supabase self-hosted
-- Gerado em: 2026-05-21
-- Postgres 17 | pgvector 0.8.0
--
-- INSTRUÇÕES DE USO:
--   1. Suba seu Supabase self-hosted (docker compose up)
--   2. Acesse o SQL Editor ou conecte via psql
--   3. Execute este arquivo na ordem:
--        psql -h localhost -p 5432 -U postgres -d postgres -f schema.sql
--   4. Execute seed.sql para dados de referência (badges, point_rules)
--   5. Crie os usuários admin manualmente via Supabase Auth UI
-- =============================================================================


-- =============================================================================
-- 1. EXTENSÕES
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";


-- =============================================================================
-- 2. TABELAS
-- =============================================================================

-- perfis (espelha auth.users, criado via trigger)
CREATE TABLE IF NOT EXISTS public.perfis (
    id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    role        text NOT NULL DEFAULT 'disabled'
                  CHECK (role = ANY (ARRAY['admin','publicador','aluno','disabled'])),
    name        text NOT NULL,
    avatar_url  text,
    email       text
);

ALTER TABLE public.perfis ENABLE ROW LEVEL SECURITY;

-- courses
CREATE TABLE IF NOT EXISTS public.courses (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title         text NOT NULL,
    description   text,
    thumbnail_url text,
    created_at    timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.courses ENABLE ROW LEVEL SECURITY;

-- modules
CREATE TABLE IF NOT EXISTS public.modules (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id   uuid NOT NULL REFERENCES public.courses(id) ON DELETE RESTRICT,
    title       text NOT NULL,
    order_index integer DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.modules ENABLE ROW LEVEL SECURITY;

-- contents
CREATE TABLE IF NOT EXISTS public.contents (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id     uuid NOT NULL REFERENCES public.modules(id) ON DELETE CASCADE,
    title         text NOT NULL,
    content_type  text NOT NULL CHECK (content_type = ANY (ARRAY['video','document'])),
    body_text     text,
    video_url     text,
    file_url      text,
    order_index   integer DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT timezone('utc', now()),
    status        text DEFAULT 'uploaded'
                    CHECK (status = ANY (ARRAY['uploaded','processed','transcribing','indexed','failed'])),
    duration      numeric DEFAULT 0,
    thumbnail_url text
);

ALTER TABLE public.contents ENABLE ROW LEVEL SECURITY;

-- comments
CREATE TABLE IF NOT EXISTS public.comments (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id   uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    comment_text text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT timezone('utc', now()),
    parent_id    uuid REFERENCES public.comments(id) ON DELETE CASCADE
);

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

-- private_notes
CREATE TABLE IF NOT EXISTS public.private_notes (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    note_text  text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.private_notes ENABLE ROW LEVEL SECURITY;

-- attachments
CREATE TABLE IF NOT EXISTS public.attachments (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id  uuid REFERENCES public.contents(id) ON DELETE CASCADE,
    name        text NOT NULL,
    file_url    text NOT NULL,
    file_type   text,
    file_size   bigint,
    created_at  timestamptz DEFAULT timezone('utc', now())
);

ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;

-- user_progress
CREATE TABLE IF NOT EXISTS public.user_progress (
    user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    content_id   uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    completed_at timestamptz DEFAULT timezone('utc', now()),
    PRIMARY KEY (user_id, content_id)
);

ALTER TABLE public.user_progress ENABLE ROW LEVEL SECURITY;

-- content_transcriptions
CREATE TABLE IF NOT EXISTS public.content_transcriptions (
    content_id    uuid PRIMARY KEY REFERENCES public.contents(id) ON DELETE CASCADE,
    language      text,
    full_text     text NOT NULL,
    segments_json jsonb NOT NULL,
    model         text NOT NULL,
    duration_sec  numeric,
    created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.content_transcriptions ENABLE ROW LEVEL SECURITY;

-- content_chunks (RAG)
CREATE TABLE IF NOT EXISTS public.content_chunks (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id      uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    chunk_index     integer NOT NULL,
    text            text NOT NULL,
    start_time      numeric NOT NULL,
    end_time        numeric NOT NULL,
    token_count     integer,
    embedding       vector,
    embedding_model text NOT NULL DEFAULT 'text-embedding-3-small',
    created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.content_chunks ENABLE ROW LEVEL SECURITY;

-- permission_groups
CREATE TABLE IF NOT EXISTS public.permission_groups (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    description text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.permission_groups ENABLE ROW LEVEL SECURITY;

-- user_groups
CREATE TABLE IF NOT EXISTS public.user_groups (
    user_id  uuid NOT NULL REFERENCES public.perfis(id) ON DELETE CASCADE,
    group_id uuid NOT NULL REFERENCES public.permission_groups(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, group_id)
);

ALTER TABLE public.user_groups ENABLE ROW LEVEL SECURITY;

-- user_access_mode
CREATE TABLE IF NOT EXISTS public.user_access_mode (
    user_id uuid PRIMARY KEY REFERENCES public.perfis(id) ON DELETE CASCADE,
    mode    text NOT NULL DEFAULT 'restricted'
              CHECK (mode = ANY (ARRAY['all_courses','restricted']))
);

ALTER TABLE public.user_access_mode ENABLE ROW LEVEL SECURITY;

-- user_course_access
CREATE TABLE IF NOT EXISTS public.user_course_access (
    user_id   uuid NOT NULL REFERENCES public.perfis(id) ON DELETE CASCADE,
    course_id uuid NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, course_id)
);

ALTER TABLE public.user_course_access ENABLE ROW LEVEL SECURITY;

-- group_course_access
CREATE TABLE IF NOT EXISTS public.group_course_access (
    group_id  uuid NOT NULL REFERENCES public.permission_groups(id) ON DELETE CASCADE,
    course_id uuid NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, course_id)
);

ALTER TABLE public.group_course_access ENABLE ROW LEVEL SECURITY;

-- point_rules
CREATE TABLE IF NOT EXISTS public.point_rules (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type text NOT NULL UNIQUE,
    points     integer NOT NULL,
    is_active  boolean DEFAULT true
);

ALTER TABLE public.point_rules ENABLE ROW LEVEL SECURITY;

-- point_events
CREATE TABLE IF NOT EXISTS public.point_events (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_id     uuid NOT NULL REFERENCES public.permission_groups(id) ON DELETE CASCADE,
    event_type   text NOT NULL,
    points       integer NOT NULL,
    reference_id uuid NOT NULL,
    created_at   timestamptz DEFAULT now()
);

ALTER TABLE public.point_events ENABLE ROW LEVEL SECURITY;

-- user_points
CREATE TABLE IF NOT EXISTS public.user_points (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_id     uuid NOT NULL REFERENCES public.permission_groups(id) ON DELETE CASCADE,
    total_points integer NOT NULL DEFAULT 0,
    updated_at   timestamptz DEFAULT now(),
    UNIQUE (user_id, group_id)
);

ALTER TABLE public.user_points ENABLE ROW LEVEL SECURITY;

-- badges
CREATE TABLE IF NOT EXISTS public.badges (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug            text NOT NULL UNIQUE,
    name            text NOT NULL,
    description     text NOT NULL,
    icon_url        text,
    condition_type  text NOT NULL,
    condition_value integer NOT NULL
);

ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;

-- user_badges
CREATE TABLE IF NOT EXISTS public.user_badges (
    id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    badge_id  uuid NOT NULL REFERENCES public.badges(id) ON DELETE CASCADE,
    earned_at timestamptz DEFAULT now()
);

ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;

-- user_streaks
CREATE TABLE IF NOT EXISTS public.user_streaks (
    user_id           uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    current_streak    integer NOT NULL DEFAULT 0,
    last_activity_date date,
    updated_at        timestamptz DEFAULT now()
);

ALTER TABLE public.user_streaks ENABLE ROW LEVEL SECURITY;


-- =============================================================================
-- 3. FUNÇÕES
-- =============================================================================

-- Função auxiliar: has_role
CREATE OR REPLACE FUNCTION public.has_role(required_roles text[])
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.perfis
        WHERE id = auth.uid()
        AND role = ANY(required_roles)
    );
END;
$$;

-- Trigger: criar perfil ao criar usuário auth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.perfis (id, name, role, email)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'name', 'Usuário Novo'),
    'disabled',
    new.email
  );
  RETURN NEW;
END;
$$;

-- Trigger: update updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- Gamificação: atualizar pontos do usuário
CREATE OR REPLACE FUNCTION public.fn_update_user_points()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.user_points (user_id, group_id, total_points, updated_at)
  VALUES (new.user_id, new.group_id, new.points, now())
  ON CONFLICT (user_id, group_id)
  DO UPDATE SET
    total_points = public.user_points.total_points + new.points,
    updated_at = now();
  RETURN new;
END;
$$;

-- Gamificação: validar event_type contra point_rules
CREATE OR REPLACE FUNCTION public.fn_validate_point_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_points integer;
BEGIN
  SELECT points INTO v_points
  FROM public.point_rules
  WHERE event_type = new.event_type AND is_active = true;

  IF v_points IS NULL THEN
    RAISE EXCEPTION 'event_type % not found in point_rules or is inactive', new.event_type;
  END IF;

  new.points := v_points;
  RETURN new;
END;
$$;

-- Gamificação: atualizar streak
CREATE OR REPLACE FUNCTION public.fn_update_streak(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_last_date date;
  v_today     date := current_date;
  v_streak    integer;
BEGIN
  SELECT last_activity_date, current_streak
  INTO v_last_date, v_streak
  FROM public.user_streaks
  WHERE user_id = p_user_id;

  IF v_last_date IS NULL THEN
    INSERT INTO public.user_streaks (user_id, current_streak, last_activity_date)
    VALUES (p_user_id, 1, v_today)
    ON CONFLICT (user_id) DO UPDATE
      SET current_streak = 1, last_activity_date = v_today, updated_at = now();
  ELSIF v_last_date = v_today THEN
    NULL;
  ELSIF v_last_date = v_today - 1 THEN
    UPDATE public.user_streaks
    SET current_streak = current_streak + 1, last_activity_date = v_today, updated_at = now()
    WHERE user_id = p_user_id;
  ELSE
    UPDATE public.user_streaks
    SET current_streak = 1, last_activity_date = v_today, updated_at = now()
    WHERE user_id = p_user_id;
  END IF;
END;
$$;

-- Gamificação: verificar e conceder badges
CREATE OR REPLACE FUNCTION public.fn_check_badges(p_user_id uuid, p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_video_count   integer;
  v_comment_count integer;
  v_streak        integer;
  v_rank          integer;
  v_badge         record;
BEGIN
  SELECT count(*) INTO v_video_count
  FROM public.point_events
  WHERE user_id = p_user_id AND event_type IN ('video_watched', 'video_completed');

  SELECT count(*) INTO v_comment_count
  FROM public.point_events
  WHERE user_id = p_user_id AND event_type IN ('comment_posted', 'comment_replied');

  SELECT current_streak INTO v_streak
  FROM public.user_streaks
  WHERE user_id = p_user_id;
  v_streak := COALESCE(v_streak, 0);

  SELECT rank_position INTO v_rank
  FROM public.group_ranking_view
  WHERE user_id = p_user_id AND group_id = p_group_id;
  v_rank := COALESCE(v_rank, 999);

  FOR v_badge IN SELECT * FROM public.badges LOOP
    CONTINUE WHEN EXISTS (
      SELECT 1 FROM public.user_badges
      WHERE user_id = p_user_id AND badge_id = v_badge.id
    );

    IF v_badge.condition_type = 'video_count' AND v_video_count >= v_badge.condition_value THEN
      INSERT INTO public.user_badges (user_id, badge_id) VALUES (p_user_id, v_badge.id) ON CONFLICT DO NOTHING;
    ELSIF v_badge.condition_type = 'comment_count' AND v_comment_count >= v_badge.condition_value THEN
      INSERT INTO public.user_badges (user_id, badge_id) VALUES (p_user_id, v_badge.id) ON CONFLICT DO NOTHING;
    ELSIF v_badge.condition_type = 'ranking_position' AND v_rank <= v_badge.condition_value THEN
      INSERT INTO public.user_badges (user_id, badge_id) VALUES (p_user_id, v_badge.id) ON CONFLICT DO NOTHING;
    ELSIF v_badge.condition_type = 'streak_days' AND v_streak >= v_badge.condition_value THEN
      INSERT INTO public.user_badges (user_id, badge_id) VALUES (p_user_id, v_badge.id) ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;
END;
$$;

-- Gamificação: trigger que chama check_badges e update_streak
CREATE OR REPLACE FUNCTION public.fn_trigger_check_badges()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF new.event_type IN ('video_watched', 'video_completed') THEN
    PERFORM public.fn_update_streak(new.user_id);
  END IF;
  PERFORM public.fn_check_badges(new.user_id, new.group_id);
  RETURN new;
END;
$$;

-- Busca semântica (RAG)
CREATE OR REPLACE FUNCTION public.search_content_semantic(
    query_embedding vector,
    filter_course_id uuid DEFAULT NULL,
    match_count integer DEFAULT 20
)
RETURNS TABLE(
    chunk_id     uuid,
    content_id   uuid,
    chunk_text   text,
    start_time   numeric,
    content_title text,
    thumbnail_url text,
    module_title text,
    course_title text,
    distance     double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
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

-- Busca full-text
CREATE OR REPLACE FUNCTION public.search_content_fulltext(
    search_query     text,
    filter_course_id uuid DEFAULT NULL
)
RETURNS TABLE(
    chunk_id     uuid,
    content_id   uuid,
    chunk_text   text,
    start_time   numeric,
    content_title text,
    thumbnail_url text,
    module_title text,
    course_title text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
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

-- Busca semântica em transcrições (alias legado)
CREATE OR REPLACE FUNCTION public.search_transcripts(
    query_embedding  vector,
    match_count      integer DEFAULT 10,
    course_filter    uuid DEFAULT NULL,
    min_similarity   double precision DEFAULT 0.0
)
RETURNS TABLE(
    chunk_id     uuid,
    content_id   uuid,
    content_title text,
    module_id    uuid,
    course_id    uuid,
    course_title text,
    chunk_text   text,
    start_time   numeric,
    end_time     numeric,
    similarity   double precision
)
LANGUAGE sql
STABLE
SET search_path TO 'public'
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


-- =============================================================================
-- 4. VIEWS (com security_invoker para respeitar RLS)
-- =============================================================================

CREATE OR REPLACE VIEW public.content_comments_view
WITH (security_invoker = true)
AS
SELECT
    c.id           AS comment_id,
    c.content_id,
    c.comment_text,
    c.created_at,
    c.user_id,
    c.parent_id,
    p.name         AS user_name
FROM comments c
LEFT JOIN perfis p ON p.id = c.user_id;

CREATE OR REPLACE VIEW public.content_private_notes_view
WITH (security_invoker = true)
AS
SELECT
    content_id,
    id         AS note_id,
    note_text,
    updated_at,
    user_id
FROM private_notes pn;

CREATE OR REPLACE VIEW public.course_catalog
WITH (security_invoker = true)
AS
SELECT
    c.id           AS course_id,
    c.title        AS course_title,
    c.description  AS course_description,
    c.thumbnail_url,
    count(DISTINCT m.id)           AS total_modules,
    count(DISTINCT co.id)          AS total_contents,
    count(DISTINCT up.content_id)  AS completed_contents
FROM courses c
LEFT JOIN modules m       ON m.course_id = c.id
LEFT JOIN contents co     ON co.module_id = m.id
LEFT JOIN user_progress up ON up.content_id = co.id AND up.user_id = auth.uid()
GROUP BY c.id;

CREATE OR REPLACE VIEW public.course_structure
WITH (security_invoker = true)
AS
SELECT
    c.id           AS course_id,
    c.title        AS course_title,
    m.id           AS module_id,
    m.title        AS module_title,
    m.order_index  AS module_order,
    co.id          AS content_id,
    co.title       AS content_title,
    co.content_type,
    co.order_index AS content_order,
    co.duration    AS content_duration,
    (up.content_id IS NOT NULL) AS is_completed
FROM courses c
JOIN modules m        ON m.course_id = c.id
JOIN contents co      ON co.module_id = m.id
LEFT JOIN user_progress up ON up.content_id = co.id AND up.user_id = auth.uid();

CREATE OR REPLACE VIEW public.group_ranking_view
WITH (security_invoker = true)
AS
SELECT
    up.user_id,
    up.group_id,
    up.total_points,
    p.name       AS user_name,
    p.avatar_url,
    rank() OVER (PARTITION BY up.group_id ORDER BY up.total_points DESC) AS rank_position
FROM user_points up
JOIN perfis p ON p.id = up.user_id;


-- =============================================================================
-- 5. TRIGGERS
-- =============================================================================

-- Criar perfil quando novo usuário se registra
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Atualizar updated_at em private_notes
DROP TRIGGER IF EXISTS update_private_notes_updated_at ON public.private_notes;
CREATE TRIGGER update_private_notes_updated_at
  BEFORE UPDATE ON public.private_notes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Gamificação: validar + acumular pontos
DROP TRIGGER IF EXISTS before_point_event_insert_validate ON public.point_events;
CREATE TRIGGER before_point_event_insert_validate
  BEFORE INSERT ON public.point_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_validate_point_event();

DROP TRIGGER IF EXISTS after_point_event_insert ON public.point_events;
CREATE TRIGGER after_point_event_insert
  AFTER INSERT ON public.point_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_update_user_points();

DROP TRIGGER IF EXISTS after_point_event_check_badges ON public.point_events;
CREATE TRIGGER after_point_event_check_badges
  AFTER INSERT ON public.point_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_trigger_check_badges();


-- =============================================================================
-- 6. RLS POLICIES — perfis
-- =============================================================================

CREATE POLICY "select_perfis"          ON public.perfis FOR SELECT TO authenticated USING (true);
CREATE POLICY "update_own_profile"     ON public.perfis FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "admin_perfis"           ON public.perfis FOR ALL    TO authenticated USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — courses
-- =============================================================================

CREATE POLICY "courses_admin_all" ON public.courses FOR ALL USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));
CREATE POLICY "courses_access"    ON public.courses FOR SELECT USING (
    has_role(ARRAY['publicador'])
    OR EXISTS (SELECT 1 FROM user_access_mode WHERE user_id = auth.uid() AND mode = 'all_courses')
    OR EXISTS (SELECT 1 FROM user_course_access WHERE user_id = auth.uid() AND course_id = courses.id)
    OR EXISTS (
        SELECT 1 FROM user_groups ug
        JOIN group_course_access gca ON gca.group_id = ug.group_id
        WHERE ug.user_id = auth.uid() AND gca.course_id = courses.id
    )
);

-- =============================================================================
-- 6. RLS POLICIES — modules
-- =============================================================================

CREATE POLICY "select_modules"  ON public.modules FOR SELECT TO authenticated USING (true);
CREATE POLICY "admin_modules"   ON public.modules FOR ALL    TO authenticated USING (has_role(ARRAY['admin','publicador'])) WITH CHECK (has_role(ARRAY['admin','publicador']));

-- =============================================================================
-- 6. RLS POLICIES — contents
-- =============================================================================

CREATE POLICY "select_contents" ON public.contents FOR SELECT TO authenticated USING (true);
CREATE POLICY "admin_contents"  ON public.contents FOR ALL    TO authenticated USING (has_role(ARRAY['admin','publicador'])) WITH CHECK (has_role(ARRAY['admin','publicador']));

-- =============================================================================
-- 6. RLS POLICIES — comments
-- =============================================================================

CREATE POLICY "select_comments"  ON public.comments FOR SELECT  TO authenticated USING (true);
CREATE POLICY "insert_comments"  ON public.comments FOR INSERT  TO authenticated WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "modify_own_comments" ON public.comments FOR ALL  TO authenticated
    USING ((auth.uid() = user_id) OR has_role(ARRAY['admin']))
    WITH CHECK ((auth.uid() = user_id) OR has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — private_notes
-- =============================================================================

CREATE POLICY "own_private_notes" ON public.private_notes FOR ALL TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- =============================================================================
-- 6. RLS POLICIES — attachments
-- =============================================================================

CREATE POLICY "select_attachments" ON public.attachments FOR SELECT TO authenticated USING (true);
CREATE POLICY "admin_attachments"  ON public.attachments FOR ALL    TO authenticated
    USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — user_progress
-- =============================================================================

CREATE POLICY "own_user_progress" ON public.user_progress FOR ALL TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- =============================================================================
-- 6. RLS POLICIES — content_transcriptions
-- =============================================================================

CREATE POLICY "select_transcriptions" ON public.content_transcriptions FOR SELECT TO authenticated USING (true);
CREATE POLICY "admin_transcriptions"  ON public.content_transcriptions FOR ALL    TO authenticated
    USING (has_role(ARRAY['admin','publicador'])) WITH CHECK (has_role(ARRAY['admin','publicador']));

-- =============================================================================
-- 6. RLS POLICIES — content_chunks
-- =============================================================================

CREATE POLICY "select_chunks" ON public.content_chunks FOR SELECT TO authenticated USING (true);
CREATE POLICY "admin_chunks"  ON public.content_chunks FOR ALL    TO authenticated
    USING (has_role(ARRAY['admin','publicador'])) WITH CHECK (has_role(ARRAY['admin','publicador']));

-- =============================================================================
-- 6. RLS POLICIES — permission_groups
-- =============================================================================

CREATE POLICY "permission_groups_select_authenticated" ON public.permission_groups FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "permission_groups_admin_all"            ON public.permission_groups FOR ALL   USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — user_groups
-- =============================================================================

CREATE POLICY "user_groups_select_own" ON public.user_groups FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "user_groups_admin_all"  ON public.user_groups FOR ALL   USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — user_access_mode
-- =============================================================================

CREATE POLICY "user_access_mode_select_own" ON public.user_access_mode FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "user_access_mode_admin_all"  ON public.user_access_mode FOR ALL   USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — user_course_access
-- =============================================================================

CREATE POLICY "user_course_access_select_own" ON public.user_course_access FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "user_course_access_admin_all"  ON public.user_course_access FOR ALL   USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — group_course_access
-- =============================================================================

CREATE POLICY "group_course_access_select_authenticated" ON public.group_course_access FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "group_course_access_admin_all"            ON public.group_course_access FOR ALL   USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — point_rules
-- =============================================================================

CREATE POLICY "anyone read point_rules"  ON public.point_rules FOR SELECT USING (true);
CREATE POLICY "admin manage point_rules" ON public.point_rules FOR ALL   USING (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — point_events
-- =============================================================================

CREATE POLICY "users read own point_events"  ON public.point_events FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "admin read all point_events"  ON public.point_events FOR SELECT USING (has_role(ARRAY['admin']));
CREATE POLICY "users insert own point_events" ON public.point_events FOR INSERT
    WITH CHECK (
        auth.uid() = user_id
        AND EXISTS (SELECT 1 FROM user_groups WHERE user_id = auth.uid() AND group_id = point_events.group_id)
    );

-- =============================================================================
-- 6. RLS POLICIES — user_points
-- =============================================================================

CREATE POLICY "anyone read user_points" ON public.user_points FOR SELECT USING (true);

-- =============================================================================
-- 6. RLS POLICIES — badges
-- =============================================================================

CREATE POLICY "anyone read badges"  ON public.badges FOR SELECT USING (true);
CREATE POLICY "admin manage badges" ON public.badges FOR ALL   USING (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — user_badges
-- =============================================================================

CREATE POLICY "anyone read user_badges"  ON public.user_badges FOR SELECT USING (true);
CREATE POLICY "admin insert user_badges" ON public.user_badges FOR INSERT WITH CHECK (has_role(ARRAY['admin']));

-- =============================================================================
-- 6. RLS POLICIES — user_streaks
-- =============================================================================

CREATE POLICY "users manage own streaks" ON public.user_streaks FOR ALL USING (auth.uid() = user_id);


-- =============================================================================
-- 7. STORAGE BUCKETS
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('avatars', 'avatars', true,  NULL,     NULL),
    ('courses', 'courses', true,  52428800, NULL),
    ('files',   'files',   true,  NULL,     NULL)
ON CONFLICT (id) DO NOTHING;


-- =============================================================================
-- 8. STORAGE POLICIES
-- =============================================================================

-- avatars
CREATE POLICY "Avatar public view" ON storage.objects FOR SELECT USING (bucket_id = 'avatars');
CREATE POLICY "Avatar upload"      ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "Avatar update"      ON storage.objects FOR UPDATE TO authenticated
    USING  (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
    WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);
CREATE POLICY "Avatar delete"      ON storage.objects FOR DELETE TO authenticated
    USING  (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- courses
CREATE POLICY "Public Access"                ON storage.objects FOR SELECT USING (bucket_id = 'courses');
CREATE POLICY "Admins and Publicadores can upload" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'courses' AND EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND role = ANY (ARRAY['admin','publicador'])));
CREATE POLICY "Admins and Publicadores can update" ON storage.objects FOR UPDATE TO authenticated
    USING  (bucket_id = 'courses' AND EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND role = ANY (ARRAY['admin','publicador'])));
CREATE POLICY "Admins and Publicadores can delete" ON storage.objects FOR DELETE TO authenticated
    USING  (bucket_id = 'courses' AND EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND role = ANY (ARRAY['admin','publicador'])));

-- files
CREATE POLICY "Public Access to Files"   ON storage.objects FOR SELECT USING (bucket_id = 'files');
CREATE POLICY "Admin Management of Files" ON storage.objects FOR ALL
    USING      (bucket_id = 'files' AND EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND role = ANY (ARRAY['admin','publicador'])))
    WITH CHECK (bucket_id = 'files' AND EXISTS (SELECT 1 FROM perfis WHERE id = auth.uid() AND role = ANY (ARRAY['admin','publicador'])));
