-- supabase/migrations/20260521_gamification.sql

-- 1. TABELAS

create table public.point_rules (
  id uuid primary key default gen_random_uuid(),
  event_type text unique not null,
  points integer not null,
  is_active boolean default true
);

insert into public.point_rules (event_type, points) values
  ('video_watched', 10),
  ('video_completed', 20),
  ('comment_posted', 5),
  ('comment_replied', 3);

create table public.point_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid not null references public.permission_groups(id) on delete cascade,
  event_type text not null,
  points integer not null,
  reference_id uuid not null,
  created_at timestamptz default now(),
  unique (user_id, event_type, reference_id)
);

create table public.user_points (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid not null references public.permission_groups(id) on delete cascade,
  total_points integer not null default 0,
  updated_at timestamptz default now(),
  unique (user_id, group_id)
);

create table public.badges (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  description text not null,
  icon_url text,
  condition_type text not null,
  condition_value integer not null
);

insert into public.badges (slug, name, description, condition_type, condition_value) values
  ('first_video',    'Primeiros Passos', 'Assista seu primeiro vídeo',              'video_count',      1),
  ('first_comment',  'Primeira Voz',     'Poste seu primeiro comentário',           'comment_count',    1),
  ('video_5',        'Maratonista',      'Assista 5 vídeos',                        'video_count',      5),
  ('comment_10',     'Participativo',    'Poste 10 comentários',                    'comment_count',    10),
  ('top3_group',     'Pódio',            'Esteja no top 3 do ranking do seu grupo', 'ranking_position', 3),
  ('streak_7',       'Constante',        'Assista vídeos por 7 dias seguidos',      'streak_days',      7);

create table public.user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  earned_at timestamptz default now(),
  unique (user_id, badge_id)
);

-- Tabela auxiliar para streak
create table public.user_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  current_streak integer not null default 0,
  last_activity_date date,
  updated_at timestamptz default now()
);

-- 2. VIEW DE RANKING

create or replace view public.group_ranking_view as
  select
    up.user_id,
    up.group_id,
    up.total_points,
    p.name as user_name,
    p.avatar_url,
    rank() over (partition by up.group_id order by up.total_points desc) as rank_position
  from public.user_points up
  join public.perfis p on p.id = up.user_id;

-- 3. FUNÇÃO: atualizar user_points após evento

create or replace function public.fn_update_user_points()
returns trigger language plpgsql security definer as $$
begin
  insert into public.user_points (user_id, group_id, total_points, updated_at)
  values (new.user_id, new.group_id, new.points, now())
  on conflict (user_id, group_id)
  do update set
    total_points = public.user_points.total_points + new.points,
    updated_at = now();
  return new;
end;
$$;

create trigger after_point_event_insert
  after insert on public.point_events
  for each row execute function public.fn_update_user_points();

-- 4. FUNÇÃO: verificar e conceder badges

create or replace function public.fn_check_badges(p_user_id uuid, p_group_id uuid)
returns void language plpgsql security definer as $$
declare
  v_video_count integer;
  v_comment_count integer;
  v_streak integer;
  v_rank integer;
  v_badge record;
begin
  -- Conta vídeos assistidos
  select count(*) into v_video_count
  from public.point_events
  where user_id = p_user_id and event_type in ('video_watched', 'video_completed');

  -- Conta comentários postados
  select count(*) into v_comment_count
  from public.point_events
  where user_id = p_user_id and event_type in ('comment_posted', 'comment_replied');

  -- Streak atual
  select current_streak into v_streak
  from public.user_streaks
  where user_id = p_user_id;
  v_streak := coalesce(v_streak, 0);

  -- Posição no ranking do grupo
  select rank_position into v_rank
  from public.group_ranking_view
  where user_id = p_user_id and group_id = p_group_id;
  v_rank := coalesce(v_rank, 999);

  for v_badge in select * from public.badges loop
    -- Pula se já conquistou
    continue when exists (
      select 1 from public.user_badges
      where user_id = p_user_id and badge_id = v_badge.id
    );

    if v_badge.condition_type = 'video_count' and v_video_count >= v_badge.condition_value then
      insert into public.user_badges (user_id, badge_id) values (p_user_id, v_badge.id) on conflict do nothing;
    elsif v_badge.condition_type = 'comment_count' and v_comment_count >= v_badge.condition_value then
      insert into public.user_badges (user_id, badge_id) values (p_user_id, v_badge.id) on conflict do nothing;
    elsif v_badge.condition_type = 'ranking_position' and v_rank <= v_badge.condition_value then
      insert into public.user_badges (user_id, badge_id) values (p_user_id, v_badge.id) on conflict do nothing;
    elsif v_badge.condition_type = 'streak_days' and v_streak >= v_badge.condition_value then
      insert into public.user_badges (user_id, badge_id) values (p_user_id, v_badge.id) on conflict do nothing;
    end if;
  end loop;
end;
$$;

-- 5. TRIGGER: chamar check_badges após evento

create or replace function public.fn_trigger_check_badges()
returns trigger language plpgsql security definer as $$
begin
  perform public.fn_check_badges(new.user_id, new.group_id);
  return new;
end;
$$;

create trigger after_point_event_check_badges
  after insert on public.point_events
  for each row execute function public.fn_trigger_check_badges();

-- 6. FUNÇÃO: atualizar streak

create or replace function public.fn_update_streak(p_user_id uuid)
returns void language plpgsql security definer as $$
declare
  v_last_date date;
  v_today date := current_date;
  v_streak integer;
begin
  select last_activity_date, current_streak
  into v_last_date, v_streak
  from public.user_streaks
  where user_id = p_user_id;

  if v_last_date is null then
    insert into public.user_streaks (user_id, current_streak, last_activity_date)
    values (p_user_id, 1, v_today)
    on conflict (user_id) do update set current_streak = 1, last_activity_date = v_today, updated_at = now();
  elsif v_last_date = v_today then
    null; -- já registrou hoje
  elsif v_last_date = v_today - interval '1 day' then
    update public.user_streaks
    set current_streak = current_streak + 1, last_activity_date = v_today, updated_at = now()
    where user_id = p_user_id;
  else
    update public.user_streaks
    set current_streak = 1, last_activity_date = v_today, updated_at = now()
    where user_id = p_user_id;
  end if;
end;
$$;

-- 7. RLS

alter table public.point_events enable row level security;
alter table public.user_points enable row level security;
alter table public.user_badges enable row level security;
alter table public.user_streaks enable row level security;
alter table public.point_rules enable row level security;
alter table public.badges enable row level security;

-- point_events: usuário insere os próprios, lê os próprios; admin lê tudo
create policy "users insert own point_events" on public.point_events
  for insert with check (auth.uid() = user_id);

create policy "users read own point_events" on public.point_events
  for select using (auth.uid() = user_id);

create policy "admin read all point_events" on public.point_events
  for select using (has_role(ARRAY['admin']));

-- user_points: todos leem (necessário para ranking do grupo), usuário atualiza o próprio
create policy "anyone read user_points" on public.user_points
  for select using (true);

create policy "users update own user_points" on public.user_points
  for all using (auth.uid() = user_id);

-- user_badges: todos leem, só sistema insere (security definer functions)
create policy "anyone read user_badges" on public.user_badges
  for select using (true);

create policy "admin insert user_badges" on public.user_badges
  for insert with check (has_role(ARRAY['admin']));

-- badges e point_rules: leitura pública, escrita só admin
create policy "anyone read badges" on public.badges for select using (true);
create policy "admin manage badges" on public.badges for all using (has_role(ARRAY['admin']));

create policy "anyone read point_rules" on public.point_rules for select using (true);
create policy "admin manage point_rules" on public.point_rules for all using (has_role(ARRAY['admin']));

-- user_streaks: usuário lê/escreve o próprio
create policy "users manage own streaks" on public.user_streaks
  for all using (auth.uid() = user_id);
