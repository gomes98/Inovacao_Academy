-- =============================================================================
-- Grupo "Geral" fixo: usuários sem grupo acumulam pontos no grupo Geral
-- e aparecem no ranking global.
-- =============================================================================

-- UUID fixo para o grupo Geral — nunca mude este valor
DO $$
BEGIN
  INSERT INTO public.permission_groups (id, name)
  VALUES ('00000000-0000-0000-0000-000000000001', 'Geral')
  ON CONFLICT (id) DO NOTHING;
END;
$$;

-- Função: retorna o group_id do usuário ou o UUID do grupo Geral como fallback
CREATE OR REPLACE FUNCTION public.fn_resolve_group_id(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT COALESCE(
    (SELECT group_id FROM public.user_groups WHERE user_id = p_user_id LIMIT 1),
    '00000000-0000-0000-0000-000000000001'
  );
$$;

-- Ajusta a RLS de point_events: permite inserção quando
-- (a) o usuário pertence ao grupo informado, OU
-- (b) o group_id informado é o grupo Geral (para usuários sem grupo)
DROP POLICY IF EXISTS "users insert own point_events" ON public.point_events;

CREATE POLICY "users insert own point_events"
  ON public.point_events FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = user_id
    AND (
      group_id = '00000000-0000-0000-0000-000000000001'
      OR EXISTS (
        SELECT 1 FROM public.user_groups
        WHERE user_groups.user_id = auth.uid()
          AND user_groups.group_id = point_events.group_id
      )
    )
  );
