-- =============================================================================
-- Inovação Academy — Migration inicial completa
-- Gerada em: 2026-05-18
-- =============================================================================

-- ============================================================
-- FUNÇÕES AUXILIARES
-- ============================================================

-- Função: has_role — verifica se o usuário logado possui um dos papéis informados
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

-- Função: handle_new_user — cria perfil automaticamente ao cadastrar novo usuário
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

-- Função: update_updated_at_column — atualiza campo updated_at automaticamente
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- ============================================================
-- TABELAS
-- ============================================================

-- Tabela: perfis (vinculada a auth.users)
CREATE TABLE IF NOT EXISTS public.perfis (
    id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    role        text NOT NULL DEFAULT 'disabled'
                    CHECK (role = ANY (ARRAY['admin', 'publicador', 'aluno', 'disabled'])),
    name        text NOT NULL,
    avatar_url  text,
    email       text
);

-- Tabela: courses
CREATE TABLE IF NOT EXISTS public.courses (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title        text NOT NULL,
    description  text,
    thumbnail_url text,
    created_at   timestamptz NOT NULL DEFAULT timezone('utc', now())
);

-- Tabela: modules
CREATE TABLE IF NOT EXISTS public.modules (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id    uuid NOT NULL REFERENCES public.courses(id) ON DELETE CASCADE,
    title        text NOT NULL,
    order_index  integer DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT timezone('utc', now())
);

-- Tabela: contents
CREATE TABLE IF NOT EXISTS public.contents (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    module_id     uuid NOT NULL REFERENCES public.modules(id) ON DELETE CASCADE,
    title         text NOT NULL,
    content_type  text NOT NULL CHECK (content_type = ANY (ARRAY['video', 'document'])),
    body_text     text,
    video_url     text,
    file_url      text,
    order_index   integer DEFAULT 0,
    created_at    timestamptz NOT NULL DEFAULT timezone('utc', now()),
    status        text DEFAULT 'uploaded',
    duration      numeric DEFAULT 0
);

-- Tabela: comments
CREATE TABLE IF NOT EXISTS public.comments (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id    uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    user_id       uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    comment_text  text NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT timezone('utc', now())
);

-- Tabela: private_notes
CREATE TABLE IF NOT EXISTS public.private_notes (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id  uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    note_text   text NOT NULL,
    updated_at  timestamptz NOT NULL DEFAULT timezone('utc', now())
);

-- Tabela: attachments
CREATE TABLE IF NOT EXISTS public.attachments (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id  uuid REFERENCES public.contents(id) ON DELETE CASCADE,
    name        text NOT NULL,
    file_url    text NOT NULL,
    file_type   text,
    file_size   bigint,
    created_at  timestamptz DEFAULT timezone('utc', now())
);

-- Tabela: user_progress
CREATE TABLE IF NOT EXISTS public.user_progress (
    user_id      uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
    content_id   uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    completed_at timestamptz DEFAULT timezone('utc', now()),
    PRIMARY KEY (user_id, content_id)
);

-- ============================================================
-- TRIGGERS
-- ============================================================

-- Trigger: novo usuário → criar perfil
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Trigger: atualizar updated_at em private_notes
CREATE OR REPLACE TRIGGER update_private_notes_updated_at
    BEFORE UPDATE ON public.private_notes
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- VIEWS
-- ============================================================

-- View: course_catalog — catálogo de cursos com contagens e progresso do usuário
CREATE OR REPLACE VIEW public.course_catalog AS
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

-- View: course_structure — hierarquia curso→módulo→conteúdo
CREATE OR REPLACE VIEW public.course_structure AS
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

-- View: content_comments_view — comentários com nome do usuário
CREATE OR REPLACE VIEW public.content_comments_view AS
SELECT
    com.id AS comment_id,
    com.comment_text,
    com.content_id,
    com.created_at,
    com.user_id,
    p.name AS user_name
FROM comments com
LEFT JOIN perfis p ON p.id = com.user_id;

-- View: content_private_notes_view — anotações privadas com metadados
CREATE OR REPLACE VIEW public.content_private_notes_view AS
SELECT
    content_id,
    id AS note_id,
    note_text,
    updated_at,
    user_id
FROM private_notes pn;

-- ============================================================
-- RLS — HABILITAR
-- ============================================================

ALTER TABLE public.perfis        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.modules       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contents      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.comments      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.private_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attachments   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_progress ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- RLS POLICIES — perfis
-- ============================================================

CREATE POLICY "select_perfis"
    ON public.perfis FOR SELECT TO authenticated USING (true);

CREATE POLICY "update_own_profile"
    ON public.perfis FOR UPDATE TO authenticated
    USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY "admin_perfis"
    ON public.perfis FOR ALL TO authenticated
    USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- ============================================================
-- RLS POLICIES — courses
-- ============================================================

CREATE POLICY "select_courses"
    ON public.courses FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin_courses"
    ON public.courses FOR ALL TO authenticated
    USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

CREATE POLICY "Gerenciamento de cursos por admin/publicador"
    ON public.courses FOR ALL TO authenticated
    USING (has_role(ARRAY['admin', 'publicador']))
    WITH CHECK (has_role(ARRAY['admin', 'publicador']));

-- ============================================================
-- RLS POLICIES — modules
-- ============================================================

CREATE POLICY "select_modules"
    ON public.modules FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin_modules"
    ON public.modules FOR ALL TO authenticated
    USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

CREATE POLICY "Gerenciamento de módulos por admin/publicador"
    ON public.modules FOR ALL TO authenticated
    USING (has_role(ARRAY['admin', 'publicador']))
    WITH CHECK (has_role(ARRAY['admin', 'publicador']));

-- ============================================================
-- RLS POLICIES — contents
-- ============================================================

CREATE POLICY "select_contents"
    ON public.contents FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin_contents"
    ON public.contents FOR ALL TO authenticated
    USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

CREATE POLICY "Gerenciamento de conteúdos por admin/publicador"
    ON public.contents FOR ALL TO authenticated
    USING (has_role(ARRAY['admin', 'publicador']))
    WITH CHECK (has_role(ARRAY['admin', 'publicador']));

-- ============================================================
-- RLS POLICIES — comments
-- ============================================================

CREATE POLICY "select_comments"
    ON public.comments FOR SELECT TO authenticated USING (true);

CREATE POLICY "insert_comments"
    ON public.comments FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "modify_own_comments"
    ON public.comments FOR ALL TO authenticated
    USING (auth.uid() = user_id OR has_role(ARRAY['admin']))
    WITH CHECK (auth.uid() = user_id OR has_role(ARRAY['admin']));

CREATE POLICY "Admins e publicadores podem moderar comentários"
    ON public.comments FOR ALL TO authenticated
    USING (has_role(ARRAY['admin', 'publicador']))
    WITH CHECK (has_role(ARRAY['admin', 'publicador']));

-- ============================================================
-- RLS POLICIES — private_notes
-- ============================================================

CREATE POLICY "own_private_notes"
    ON public.private_notes FOR ALL TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- RLS POLICIES — attachments
-- ============================================================

CREATE POLICY "select_attachments"
    ON public.attachments FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin_attachments"
    ON public.attachments FOR ALL TO authenticated
    USING (has_role(ARRAY['admin'])) WITH CHECK (has_role(ARRAY['admin']));

-- ============================================================
-- RLS POLICIES — user_progress
-- ============================================================

CREATE POLICY "own_user_progress"
    ON public.user_progress FOR ALL TO authenticated
    USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- STORAGE BUCKETS
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('avatars', 'avatars', true, null, null),
    ('courses', 'courses', true, 52428800, null),
    ('files',   'files',   true, null, null)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- STORAGE POLICIES — bucket: avatars
-- ============================================================

CREATE POLICY "Avatar public view"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'avatars');

CREATE POLICY "Avatar upload"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Avatar update"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
    WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

CREATE POLICY "Avatar delete"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- STORAGE POLICIES — bucket: courses
-- ============================================================

CREATE POLICY "Public Access"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'courses');

CREATE POLICY "Admins and Publicadores can upload"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'courses'
        AND EXISTS (
            SELECT 1 FROM perfis
            WHERE perfis.id = auth.uid()
            AND perfis.role = ANY (ARRAY['admin', 'publicador'])
        )
    );

CREATE POLICY "Admins and Publicadores can update"
    ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'courses'
        AND EXISTS (
            SELECT 1 FROM perfis
            WHERE perfis.id = auth.uid()
            AND perfis.role = ANY (ARRAY['admin', 'publicador'])
        )
    );

CREATE POLICY "Admins and Publicadores can delete"
    ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'courses'
        AND EXISTS (
            SELECT 1 FROM perfis
            WHERE perfis.id = auth.uid()
            AND perfis.role = ANY (ARRAY['admin', 'publicador'])
        )
    );

-- ============================================================
-- STORAGE POLICIES — bucket: files
-- ============================================================

CREATE POLICY "Public Access to Files"
    ON storage.objects FOR SELECT TO public
    USING (bucket_id = 'files');

CREATE POLICY "Admin Management of Files"
    ON storage.objects FOR ALL TO public
    USING (
        bucket_id = 'files'
        AND EXISTS (
            SELECT 1 FROM perfis
            WHERE perfis.id = auth.uid()
            AND perfis.role = ANY (ARRAY['admin', 'publicador'])
        )
    )
    WITH CHECK (
        bucket_id = 'files'
        AND EXISTS (
            SELECT 1 FROM perfis
            WHERE perfis.id = auth.uid()
            AND perfis.role = ANY (ARRAY['admin', 'publicador'])
        )
    );
