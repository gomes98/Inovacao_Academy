-- =============================================================================
-- Fix RLS policies — corrige roles public→authenticated e lacunas de segurança
-- =============================================================================

-- ------------------------------------------------------------
-- badges: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "anyone read badges" ON public.badges;
DROP POLICY IF EXISTS "admin manage badges" ON public.badges;

CREATE POLICY "anyone read badges"
  ON public.badges FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin manage badges"
  ON public.badges FOR ALL TO authenticated
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- point_rules: public → authenticated + WITH CHECK
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "anyone read point_rules" ON public.point_rules;
DROP POLICY IF EXISTS "admin manage point_rules" ON public.point_rules;

CREATE POLICY "anyone read point_rules"
  ON public.point_rules FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin manage point_rules"
  ON public.point_rules FOR ALL TO authenticated
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- user_points: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "anyone read user_points" ON public.user_points;

CREATE POLICY "anyone read user_points"
  ON public.user_points FOR SELECT TO authenticated USING (true);

-- ------------------------------------------------------------
-- user_badges: public → authenticated + WITH CHECK no INSERT
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "anyone read user_badges" ON public.user_badges;
DROP POLICY IF EXISTS "admin insert user_badges" ON public.user_badges;

CREATE POLICY "anyone read user_badges"
  ON public.user_badges FOR SELECT TO authenticated USING (true);

CREATE POLICY "admin insert user_badges"
  ON public.user_badges FOR INSERT TO authenticated
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- user_streaks: public → authenticated + WITH CHECK
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "users manage own streaks" ON public.user_streaks;

CREATE POLICY "users manage own streaks"
  ON public.user_streaks FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ------------------------------------------------------------
-- point_events: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "users insert own point_events" ON public.point_events;
DROP POLICY IF EXISTS "users read own point_events" ON public.point_events;
DROP POLICY IF EXISTS "admin read all point_events" ON public.point_events;

CREATE POLICY "users insert own point_events"
  ON public.point_events FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.user_groups
      WHERE user_groups.user_id = auth.uid()
        AND user_groups.group_id = point_events.group_id
    )
  );

CREATE POLICY "users read own point_events"
  ON public.point_events FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "admin read all point_events"
  ON public.point_events FOR SELECT TO authenticated
  USING (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- courses: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "courses_admin_all" ON public.courses;
DROP POLICY IF EXISTS "courses_access" ON public.courses;

CREATE POLICY "courses_admin_all"
  ON public.courses FOR ALL TO authenticated
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

CREATE POLICY "courses_access"
  ON public.courses FOR SELECT TO authenticated
  USING (
    has_role(ARRAY['publicador'])
    OR EXISTS (
      SELECT 1 FROM public.user_access_mode
      WHERE user_id = auth.uid() AND mode = 'all_courses'
    )
    OR EXISTS (
      SELECT 1 FROM public.user_course_access
      WHERE user_id = auth.uid() AND course_id = courses.id
    )
    OR EXISTS (
      SELECT 1 FROM public.user_groups ug
      JOIN public.group_course_access gca ON gca.group_id = ug.group_id
      WHERE ug.user_id = auth.uid() AND gca.course_id = courses.id
    )
  );

-- ------------------------------------------------------------
-- permission_groups: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "permission_groups_select_authenticated" ON public.permission_groups;
DROP POLICY IF EXISTS "permission_groups_admin_all" ON public.permission_groups;

CREATE POLICY "permission_groups_select_authenticated"
  ON public.permission_groups FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "permission_groups_admin_all"
  ON public.permission_groups FOR ALL TO authenticated
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- group_course_access: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "group_course_access_select_authenticated" ON public.group_course_access;
DROP POLICY IF EXISTS "group_course_access_admin_all" ON public.group_course_access;

CREATE POLICY "group_course_access_select_authenticated"
  ON public.group_course_access FOR SELECT TO authenticated
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "group_course_access_admin_all"
  ON public.group_course_access FOR ALL TO authenticated
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- user_access_mode: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "user_access_mode_select_own" ON public.user_access_mode;
DROP POLICY IF EXISTS "user_access_mode_admin_all" ON public.user_access_mode;

CREATE POLICY "user_access_mode_select_own"
  ON public.user_access_mode FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "user_access_mode_admin_all"
  ON public.user_access_mode FOR ALL TO authenticated
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- user_course_access: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "user_course_access_select_own" ON public.user_course_access;
DROP POLICY IF EXISTS "user_course_access_admin_all" ON public.user_course_access;

CREATE POLICY "user_course_access_select_own"
  ON public.user_course_access FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "user_course_access_admin_all"
  ON public.user_course_access FOR ALL TO authenticated
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- user_groups: public → authenticated
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "user_groups_select_own" ON public.user_groups;
DROP POLICY IF EXISTS "user_groups_admin_all" ON public.user_groups;

CREATE POLICY "user_groups_select_own"
  ON public.user_groups FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "user_groups_admin_all"
  ON public.user_groups FOR ALL TO authenticated
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- attachments: adicionar policy para publicadores (INSERT/UPDATE/DELETE)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "publicador_attachments" ON public.attachments;

CREATE POLICY "publicador_attachments"
  ON public.attachments FOR ALL TO authenticated
  USING (has_role(ARRAY['admin', 'publicador']))
  WITH CHECK (has_role(ARRAY['admin', 'publicador']));

-- ------------------------------------------------------------
-- modules/contents: remover policies duplicadas (admin_* cobertos por publicador policy)
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "admin_modules" ON public.modules;
DROP POLICY IF EXISTS "admin_contents" ON public.contents;
