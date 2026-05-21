# Gamificação Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar sistema de gamificação com pontos, níveis, badges e ranking por grupo no Inovação Academy LMS.

**Architecture:** Duas tabelas centrais — `point_events` (log auditável) e `user_points` (saldo agregado via Postgres trigger). Eventos são disparados pelo frontend via composable `useGamification`. Badges são verificados server-side via Postgres function. A UI apresenta feedback imediato (toast) na aula, widget expansível no dashboard e grid de badges no perfil.

**Tech Stack:** Nuxt 4, Vue 3, TypeScript, Supabase (PostgreSQL triggers, RLS, pg_cron), Tailwind CSS v4

**Nota sobre o VideoPlayer:** O componente já emite o evento `@progress-90` (90% assistido). Usaremos esse threshold para o evento `video_watched`.

---

## Mapa de Arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `supabase/migrations/20260521_gamification.sql` | Criar | Todas as tabelas, triggers, functions, RLS, seed de badges |
| `app/composables/useGamification.ts` | Criar | trackEvent, userPoints, userLevel, userBadges, groupRanking |
| `app/components/GamificationWidget.vue` | Criar | Widget expansível do dashboard (compacto/expandido) |
| `app/components/PointToast.vue` | Criar | Toast de feedback de pontos e badge desbloqueado |
| `app/components/BadgeGrid.vue` | Criar | Grid de badges (conquistados/bloqueados) |
| `app/pages/index.vue` | Modificar | Adicionar GamificationWidget acima dos cursos |
| `app/pages/lesson/[id].vue` | Modificar | trackEvent video_watched, video_completed, comment_posted/replied + PointToast |
| `app/components/CommentItem.vue` | Modificar | trackEvent comment_replied ao submeter resposta |
| `app/pages/profile.vue` | Modificar | Adicionar card de pontos/nível e BadgeGrid |
| `app/pages/admin/courses/index.vue` | Modificar | Link para nova página de gamification admin |
| `app/pages/admin/gamification.vue` | Criar | Editar point_rules, ver ranking por grupo, conceder badge manual |
| `app/types/database.types.ts` | Modificar | Adicionar tipos das novas tabelas |

---

## Task 1: Migration do Banco de Dados

**Files:**
- Create: `supabase/migrations/20260521_gamification.sql`

- [ ] **Step 1: Criar o arquivo de migration**

```sql
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
  group_id uuid not null references public.groups(id) on delete cascade,
  event_type text not null,
  points integer not null,
  reference_id uuid not null,
  created_at timestamptz default now(),
  unique (user_id, event_type, reference_id)
);

create table public.user_points (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
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
  for select using (has_role('admin'));

-- user_points: todos leem (necessário para ranking do grupo), usuário atualiza o próprio
create policy "anyone read user_points" on public.user_points
  for select using (true);

create policy "users update own user_points" on public.user_points
  for all using (auth.uid() = user_id);

-- user_badges: todos leem, só sistema insere (security definer functions)
create policy "anyone read user_badges" on public.user_badges
  for select using (true);

create policy "admin insert user_badges" on public.user_badges
  for insert with check (has_role('admin'));

-- badges e point_rules: leitura pública, escrita só admin
create policy "anyone read badges" on public.badges for select using (true);
create policy "admin manage badges" on public.badges for all using (has_role('admin'));

create policy "anyone read point_rules" on public.point_rules for select using (true);
create policy "admin manage point_rules" on public.point_rules for all using (has_role('admin'));

-- user_streaks: usuário lê/escreve o próprio
create policy "users manage own streaks" on public.user_streaks
  for all using (auth.uid() = user_id);
```

- [ ] **Step 2: Aplicar a migration**

```bash
supabase db push
```

Ou via MCP Supabase com `apply_migration`. Verificar que as tabelas aparecem no dashboard Supabase.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260521_gamification.sql
git commit -m "feat(db): add gamification tables, triggers, functions and RLS"
```

---

## Task 2: Composable useGamification

**Files:**
- Create: `app/composables/useGamification.ts`

Esta composable é o único ponto de entrada do frontend para o sistema de gamificação.

- [ ] **Step 1: Criar o arquivo**

```typescript
// app/composables/useGamification.ts

type EventType = 'video_watched' | 'video_completed' | 'comment_posted' | 'comment_replied'

interface Level {
  level: number
  name: string
  minPoints: number
  nextLevelPoints: number | null
  progress: number // 0-100
}

interface UserPointsRow {
  total_points: number
  group_id: string
}

interface BadgeRow {
  slug: string
  name: string
  description: string
  icon_url: string | null
  condition_type: string
  condition_value: number
}

interface UserBadgeRow {
  badge_id: string
  earned_at: string
  badges: BadgeRow
}

interface RankingRow {
  user_id: string
  user_name: string
  avatar_url: string | null
  total_points: number
  rank_position: number
}

const LEVELS = [
  { level: 1, name: 'Aprendiz',    minPoints: 0    },
  { level: 2, name: 'Explorador',  minPoints: 100  },
  { level: 3, name: 'Praticante',  minPoints: 300  },
  { level: 4, name: 'Especialista',minPoints: 700  },
  { level: 5, name: 'Mestre',      minPoints: 1500 },
]

function computeLevel(totalPoints: number): Level {
  let current = LEVELS[0]
  for (const lvl of LEVELS) {
    if (totalPoints >= lvl.minPoints) current = lvl
    else break
  }
  const idx = LEVELS.indexOf(current)
  const next = LEVELS[idx + 1] ?? null
  const progress = next
    ? Math.round(((totalPoints - current.minPoints) / (next.minPoints - current.minPoints)) * 100)
    : 100
  return {
    level: current.level,
    name: current.name,
    minPoints: current.minPoints,
    nextLevelPoints: next?.minPoints ?? null,
    progress,
  }
}

export function useGamification() {
  const supabase = useSupabaseClient()
  const user = useSupabaseUser()

  const userPointsData = ref<UserPointsRow | null>(null)
  const userBadgesData = ref<UserBadgeRow[]>([])
  const allBadgesData = ref<BadgeRow[]>([])
  const groupRankingData = ref<RankingRow[]>([])
  const newlyEarnedBadge = ref<BadgeRow | null>(null)
  const lastPointsEarned = ref<{ points: number; label: string } | null>(null)

  const totalPoints = computed(() => userPointsData.value?.total_points ?? 0)
  const groupId = computed(() => userPointsData.value?.group_id ?? null)
  const userLevel = computed(() => computeLevel(totalPoints.value))

  const earnedBadgeSlugs = computed(
    () => new Set(userBadgesData.value.map(ub => ub.badges.slug))
  )

  async function loadUserData() {
    if (!user.value?.id) return

    const [pointsRes, badgesRes, allBadgesRes] = await Promise.all([
      supabase
        .from('user_points')
        .select('total_points, group_id')
        .eq('user_id', user.value.id)
        .maybeSingle(),
      supabase
        .from('user_badges')
        .select('badge_id, earned_at, badges(slug, name, description, icon_url, condition_type, condition_value)')
        .eq('user_id', user.value.id),
      supabase.from('badges').select('slug, name, description, icon_url, condition_type, condition_value'),
    ])

    if (pointsRes.data) userPointsData.value = pointsRes.data as UserPointsRow
    if (badgesRes.data) userBadgesData.value = badgesRes.data as unknown as UserBadgeRow[]
    if (allBadgesRes.data) allBadgesData.value = allBadgesRes.data as BadgeRow[]
  }

  async function loadGroupRanking() {
    if (!groupId.value) return
    const { data } = await supabase
      .from('group_ranking_view')
      .select('user_id, user_name, avatar_url, total_points, rank_position')
      .eq('group_id', groupId.value)
      .order('rank_position', { ascending: true })
      .limit(10)
    if (data) groupRankingData.value = data as RankingRow[]
  }

  async function trackEvent(eventType: EventType, referenceId: string) {
    if (!user.value?.id || !groupId.value) return

    const { data: rule } = await supabase
      .from('point_rules')
      .select('points')
      .eq('event_type', eventType)
      .eq('is_active', true)
      .maybeSingle()

    if (!rule) return

    const { error } = await supabase.from('point_events').insert({
      user_id: user.value.id,
      group_id: groupId.value,
      event_type: eventType,
      points: rule.points,
      reference_id: referenceId,
    })

    // ON CONFLICT DO NOTHING: se já existe, o erro é ignorado silenciosamente
    if (error && error.code !== '23505') {
      console.error('[useGamification] trackEvent error:', error)
      return
    }

    if (!error) {
      // Notifica o toast de pontos
      const labels: Record<EventType, string> = {
        video_watched:   'Vídeo assistido!',
        video_completed: 'Aula concluída!',
        comment_posted:  'Comentário postado!',
        comment_replied: 'Resposta publicada!',
      }
      lastPointsEarned.value = { points: rule.points, label: labels[eventType] }

      // Atualiza streak se for evento de vídeo
      if (eventType === 'video_watched' || eventType === 'video_completed') {
        await supabase.rpc('fn_update_streak', { p_user_id: user.value.id })
      }

      // Recarrega dados para detectar badges novos
      const beforeSlugs = new Set(earnedBadgeSlugs.value)
      await loadUserData()
      const afterSlugs = earnedBadgeSlugs.value
      const newSlug = [...afterSlugs].find(s => !beforeSlugs.has(s))
      if (newSlug) {
        newlyEarnedBadge.value = allBadgesData.value.find(b => b.slug === newSlug) ?? null
      }

      await loadGroupRanking()
    }
  }

  function clearToasts() {
    lastPointsEarned.value = null
    newlyEarnedBadge.value = null
  }

  return {
    totalPoints,
    userLevel,
    userBadgesData,
    allBadgesData,
    earnedBadgeSlugs,
    groupRankingData,
    groupId,
    userPointsData,
    newlyEarnedBadge,
    lastPointsEarned,
    loadUserData,
    loadGroupRanking,
    trackEvent,
    clearToasts,
  }
}
```

- [ ] **Step 2: Verificar que o TypeScript não acusa erros**

```bash
npx nuxi typecheck
```

- [ ] **Step 3: Commit**

```bash
git add app/composables/useGamification.ts
git commit -m "feat: add useGamification composable"
```

---

## Task 3: Componente PointToast

**Files:**
- Create: `app/components/PointToast.vue`

Toast de feedback visual que aparece quando o aluno ganha pontos ou desbloqueia um badge.

- [ ] **Step 1: Criar o componente**

```vue
<!-- app/components/PointToast.vue -->
<script setup lang="ts">
interface Props {
  points: number | null
  label: string | null
  badge: { name: string; icon_url: string | null } | null
}
const props = defineProps<Props>()
const emit = defineEmits(['close'])

const visible = ref(false)

watch(
  () => props.points || props.badge,
  (val) => {
    if (val) {
      visible.value = true
      setTimeout(() => {
        visible.value = false
        emit('close')
      }, 3000)
    }
  }
)
</script>

<template>
  <Transition name="toast">
    <div
      v-if="visible && (points || badge)"
      class="fixed bottom-6 right-6 z-50 flex flex-col gap-2"
    >
      <div
        v-if="points && label"
        class="flex items-center gap-3 px-5 py-3 rounded-2xl bg-purple-600/90 backdrop-blur-md border border-purple-400/30 shadow-2xl text-white"
      >
        <span class="text-xl font-black text-yellow-300">+{{ points }}</span>
        <span class="text-sm font-medium">{{ label }}</span>
      </div>
      <div
        v-if="badge"
        class="flex items-center gap-3 px-5 py-3 rounded-2xl bg-yellow-500/20 backdrop-blur-md border border-yellow-400/30 shadow-2xl text-white"
      >
        <span class="text-2xl">{{ badge.icon_url ?? '🏅' }}</span>
        <div>
          <p class="text-xs text-yellow-300 font-bold uppercase tracking-widest">Badge Desbloqueado!</p>
          <p class="text-sm font-semibold">{{ badge.name }}</p>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.toast-enter-active,
.toast-leave-active {
  transition: all 0.3s ease;
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateY(20px);
}
</style>
```

- [ ] **Step 2: Commit**

```bash
git add app/components/PointToast.vue
git commit -m "feat: add PointToast component for gamification feedback"
```

---

## Task 4: Componente BadgeGrid

**Files:**
- Create: `app/components/BadgeGrid.vue`

Grade visual de todos os badges, mostrando conquistados em cor e bloqueados em cinza.

- [ ] **Step 1: Criar o componente**

```vue
<!-- app/components/BadgeGrid.vue -->
<script setup lang="ts">
interface Badge {
  slug: string
  name: string
  description: string
  icon_url: string | null
}

interface Props {
  allBadges: Badge[]
  earnedSlugs: Set<string>
}
defineProps<Props>()

const BADGE_EMOJIS: Record<string, string> = {
  first_video:   '🎬',
  first_comment: '💬',
  video_5:       '🏃',
  comment_10:    '🗣️',
  top3_group:    '🏆',
  streak_7:      '🔥',
}
</script>

<template>
  <div class="grid grid-cols-3 sm:grid-cols-6 gap-4">
    <div
      v-for="badge in allBadges"
      :key="badge.slug"
      class="flex flex-col items-center gap-2 p-3 rounded-2xl border transition-all"
      :class="earnedSlugs.has(badge.slug)
        ? 'bg-yellow-500/10 border-yellow-500/30'
        : 'bg-white/[0.02] border-white/5 opacity-40'"
      :title="badge.description"
    >
      <span class="text-3xl">{{ badge.icon_url ?? BADGE_EMOJIS[badge.slug] ?? '🏅' }}</span>
      <span class="text-[10px] text-center font-semibold leading-tight"
        :class="earnedSlugs.has(badge.slug) ? 'text-yellow-300' : 'text-gray-500'"
      >
        {{ badge.name }}
      </span>
      <span v-if="!earnedSlugs.has(badge.slug)" class="text-[9px] text-gray-600">🔒</span>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Commit**

```bash
git add app/components/BadgeGrid.vue
git commit -m "feat: add BadgeGrid component"
```

---

## Task 5: Componente GamificationWidget (Dashboard)

**Files:**
- Create: `app/components/GamificationWidget.vue`

Widget expansível do dashboard: compacto mostra pontos e nível, expandido mostra ranking e progresso.

- [ ] **Step 1: Criar o componente**

```vue
<!-- app/components/GamificationWidget.vue -->
<script setup lang="ts">
interface Level {
  level: number
  name: string
  minPoints: number
  nextLevelPoints: number | null
  progress: number
}

interface RankingRow {
  user_id: string
  user_name: string
  avatar_url: string | null
  total_points: number
  rank_position: number
}

interface Props {
  totalPoints: number
  userLevel: Level
  groupRanking: RankingRow[]
  currentUserId: string
  nextBadge: { name: string; icon_url: string | null } | null
}
const props = defineProps<Props>()

const expanded = ref(false)

const userRank = computed(
  () => props.groupRanking.find(r => r.user_id === props.currentUserId)?.rank_position ?? null
)

const MEDAL: Record<number, string> = { 1: '🥇', 2: '🥈', 3: '🥉' }
</script>

<template>
  <div
    class="mb-10 rounded-3xl border border-white/10 bg-white/[0.03] backdrop-blur-xl overflow-hidden transition-all duration-300"
    :class="expanded ? 'p-6' : 'p-4'"
  >
    <!-- Linha compacta sempre visível -->
    <button
      class="w-full flex items-center justify-between gap-4"
      @click="expanded = !expanded"
    >
      <div class="flex items-center gap-4">
        <!-- Ícone de nível -->
        <div class="w-10 h-10 rounded-xl bg-purple-500/20 border border-purple-500/30 flex items-center justify-center text-xl">
          {{ userLevel.level === 1 ? '🌱' : userLevel.level === 2 ? '🔭' : userLevel.level === 3 ? '⚙️' : userLevel.level === 4 ? '💡' : '👑' }}
        </div>
        <div class="text-left">
          <p class="text-xs text-gray-500 uppercase tracking-widest font-bold">{{ userLevel.name }}</p>
          <p class="text-lg font-black text-white">{{ totalPoints.toLocaleString('pt-BR') }} pts</p>
        </div>
      </div>
      <div class="flex items-center gap-3">
        <div v-if="userRank" class="text-right">
          <p class="text-xs text-gray-500 uppercase tracking-widest">Ranking</p>
          <p class="text-sm font-bold text-purple-300">#{{ userRank }} no grupo</p>
        </div>
        <svg
          xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24"
          fill="none" stroke="currentColor" stroke-width="2"
          class="text-gray-500 transition-transform duration-300"
          :class="expanded ? 'rotate-180' : ''"
        >
          <polyline points="6 9 12 15 18 9"/>
        </svg>
      </div>
    </button>

    <!-- Conteúdo expandido -->
    <Transition name="expand">
      <div v-if="expanded" class="mt-6 space-y-6">
        <!-- Barra de progresso de nível -->
        <div>
          <div class="flex justify-between text-xs text-gray-500 mb-2">
            <span>Nível {{ userLevel.level }} — {{ userLevel.name }}</span>
            <span v-if="userLevel.nextLevelPoints">
              {{ totalPoints }} / {{ userLevel.nextLevelPoints }} pts
            </span>
            <span v-else>Nível máximo!</span>
          </div>
          <div class="w-full h-2 bg-white/5 rounded-full overflow-hidden">
            <div
              class="h-full bg-gradient-to-r from-purple-500 to-blue-500 rounded-full transition-all duration-1000"
              :style="{ width: `${userLevel.progress}%` }"
            />
          </div>
        </div>

        <!-- Próximo badge -->
        <div v-if="nextBadge" class="flex items-center gap-3 p-3 rounded-2xl bg-yellow-500/5 border border-yellow-500/10">
          <span class="text-2xl">{{ nextBadge.icon_url ?? '🏅' }}</span>
          <div>
            <p class="text-[10px] text-yellow-500/70 uppercase tracking-widest">Próxima conquista</p>
            <p class="text-sm font-semibold text-yellow-300">{{ nextBadge.name }}</p>
          </div>
        </div>

        <!-- Ranking top 5 do grupo -->
        <div v-if="groupRanking.length > 0">
          <h4 class="text-xs text-gray-500 uppercase tracking-widest font-bold mb-3">Ranking do Grupo</h4>
          <div class="space-y-2">
            <div
              v-for="entry in groupRanking.slice(0, 5)"
              :key="entry.user_id"
              class="flex items-center gap-3 p-2 rounded-xl transition-colors"
              :class="entry.user_id === currentUserId ? 'bg-purple-500/10 border border-purple-500/20' : ''"
            >
              <span class="w-6 text-center text-sm">
                {{ MEDAL[entry.rank_position] ?? `#${entry.rank_position}` }}
              </span>
              <img
                v-if="entry.avatar_url"
                :src="entry.avatar_url"
                class="w-7 h-7 rounded-full object-cover border border-white/10"
              />
              <div
                v-else
                class="w-7 h-7 rounded-full bg-white/10 border border-white/10 flex items-center justify-center text-xs text-gray-400"
              >
                {{ entry.user_name?.[0]?.toUpperCase() }}
              </div>
              <span class="flex-1 text-sm" :class="entry.user_id === currentUserId ? 'text-white font-semibold' : 'text-gray-400'">
                {{ entry.user_name }}
              </span>
              <span class="text-xs font-bold text-purple-300">{{ entry.total_points.toLocaleString('pt-BR') }}</span>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.expand-enter-active,
.expand-leave-active {
  transition: all 0.3s ease;
  overflow: hidden;
}
.expand-enter-from,
.expand-leave-to {
  opacity: 0;
  max-height: 0;
}
.expand-enter-to,
.expand-leave-from {
  max-height: 400px;
}
</style>
```

- [ ] **Step 2: Commit**

```bash
git add app/components/GamificationWidget.vue
git commit -m "feat: add GamificationWidget expandable dashboard component"
```

---

## Task 6: Integrar Gamificação no Dashboard (/)

**Files:**
- Modify: `app/pages/index.vue`

- [ ] **Step 1: Adicionar useGamification e carregar dados no script**

No bloco `<script setup>` de `app/pages/index.vue`, logo após as declarações existentes de `supabase` e `user`, adicionar:

```typescript
const gamification = useGamification()

// Carregar dados de gamificação quando o usuário estiver disponível
watch(user, async (u) => {
  if (u?.id) {
    await gamification.loadUserData()
    await gamification.loadGroupRanking()
  }
}, { immediate: true })

// Próximo badge ainda não conquistado
const nextBadge = computed(() => {
  return gamification.allBadgesData.value.find(
    b => !gamification.earnedBadgeSlugs.value.has(b.slug)
  ) ?? null
})
```

- [ ] **Step 2: Adicionar o widget no template**

No template de `app/pages/index.vue`, dentro de `<main>`, logo antes da `<section>` de cursos (antes de `<section>`), adicionar:

```html
<GamificationWidget
  v-if="user && gamification.groupId.value"
  :total-points="gamification.totalPoints.value"
  :user-level="gamification.userLevel.value"
  :group-ranking="gamification.groupRankingData.value"
  :current-user-id="user.id"
  :next-badge="nextBadge"
/>
```

- [ ] **Step 3: Testar no browser**

```bash
npm run dev
```

Navegar para `/` e verificar que o widget aparece compacto e expande ao clicar.

- [ ] **Step 4: Commit**

```bash
git add app/pages/index.vue
git commit -m "feat: integrate GamificationWidget into dashboard"
```

---

## Task 7: Integrar Gamificação na Página da Aula (/lesson/[id])

**Files:**
- Modify: `app/pages/lesson/[id].vue`

- [ ] **Step 1: Adicionar useGamification e PointToast no script**

No bloco `<script setup>` de `app/pages/lesson/[id].vue`, após as declarações existentes, adicionar:

```typescript
const gamification = useGamification()

watch(user, async (u) => {
  if (u?.id) await gamification.loadUserData()
}, { immediate: true })
```

- [ ] **Step 2: Modificar markAsFinishedAuto para disparar evento de pontos**

Localizar a função `markAsFinishedAuto` (linha ~111) e adicionar o trackEvent após o upsert bem-sucedido:

```typescript
async function markAsFinishedAuto() {
  if (isCompleted.value || autoMarked.value || isTogglingProgress.value) return
  
  autoMarked.value = true 
  isTogglingProgress.value = true
  
  try {
    const { error } = await supabase.from('user_progress').upsert({
      content_id: contentId.value
    }, { onConflict: 'user_id,content_id' })
    
    if (!error) {
      await refreshProgress()
      // Gamificação: vídeo assistido (90%+)
      await gamification.trackEvent('video_watched', contentId.value)
    }
  } catch (err) {
    console.error('Erro ao marcar progresso automático:', err)
  } finally {
    isTogglingProgress.value = false
  }
}
```

- [ ] **Step 3: Modificar toggleCompletion para disparar video_completed**

Localizar a função `toggleCompletion` (linha ~79) e adicionar o trackEvent quando marcar como concluído (não ao desmarcar):

```typescript
async function toggleCompletion() {
  if (!user.value || isTogglingProgress.value) return
  isTogglingProgress.value = true

  try {
    if (isCompleted.value) {
      await supabase
        .from('user_progress')
        .delete()
        .eq('user_id', user.value?.id)
        .eq('content_id', contentId.value)
    } else {
      await supabase
        .from('user_progress')
        .insert({ content_id: contentId.value })
      // Gamificação: aula concluída manualmente
      await gamification.trackEvent('video_completed', contentId.value)
    }
    await refreshProgress()
  } catch (err) {
    console.error('Erro ao alternar progresso:', err)
  } finally {
    isTogglingProgress.value = false
  }
}
```

- [ ] **Step 4: Modificar postComment para disparar evento de pontos**

Localizar a função `postComment` (linha ~172) e adicionar trackEvent após o insert bem-sucedido:

```typescript
async function postComment(parentId: string | null = null) {
  const text = parentId ? replyText.value : newComment.value
  if (!text.trim() || isPostingComment.value || !user.value) return

  isPostingComment.value = true
  try {
    const { data: inserted, error } = await supabase.from('comments').insert({
      content_id: contentId.value,
      comment_text: text,
      ...(parentId ? { parent_id: parentId } : {})
    }).select('id').single()

    if (error) throw error

    // Gamificação: pontos por comentário
    if (inserted?.id) {
      await gamification.trackEvent(
        parentId ? 'comment_replied' : 'comment_posted',
        inserted.id
      )
    }

    if (parentId) {
      replyText.value = ''
    } else {
      newComment.value = ''
    }
    replyingTo.value = null
    await refreshComments()
  } catch (err) {
    alert('Erro ao postar comentário. Verifique o console.')
    console.error(err)
  } finally {
    isPostingComment.value = false
  }
}
```

- [ ] **Step 5: Adicionar PointToast no template**

No template de `app/pages/lesson/[id].vue`, antes do fechamento `</div>` final do `<template>`, adicionar:

```html
<PointToast
  :points="gamification.lastPointsEarned.value?.points ?? null"
  :label="gamification.lastPointsEarned.value?.label ?? null"
  :badge="gamification.newlyEarnedBadge.value"
  @close="gamification.clearToasts()"
/>
```

- [ ] **Step 6: Testar no browser**

```bash
npm run dev
```

- Navegar para uma aula com vídeo e assistir até 90% → verificar toast "+10 pts"
- Clicar "Marcar como Concluída" → verificar toast "+20 pts"
- Postar um comentário → verificar toast "+5 pts"

- [ ] **Step 7: Commit**

```bash
git add app/pages/lesson/[id].vue
git commit -m "feat: track gamification events in lesson page"
```

---

## Task 8: Integrar comment_replied no CommentItem

**Files:**
- Modify: `app/components/CommentItem.vue`

O evento `comment_replied` para respostas postadas dentro do `CommentItem` já é tratado pelo `postComment` que é fornecido via `provide` do `lesson/[id].vue`. Verificar se o `CommentItem` usa a mesma função `postComment`.

- [ ] **Step 1: Ler o CommentItem para confirmar o fluxo**

```bash
cat app/components/CommentItem.vue
```

Confirmar que usa `inject('postComment')`. Se sim, nenhuma alteração necessária pois o `postComment` já foi atualizado na Task 7.

- [ ] **Step 2: Commit (apenas se houver mudança)**

Se não houver mudança:
```bash
git commit --allow-empty -m "chore: verify CommentItem uses injected postComment (no change needed)"
```

---

## Task 9: Integrar Gamificação no Perfil (/profile)

**Files:**
- Modify: `app/pages/profile.vue`

- [ ] **Step 1: Adicionar useGamification no script do profile**

No bloco `<script setup>` de `app/pages/profile.vue`, após as declarações existentes, adicionar:

```typescript
const gamification = useGamification()

watch(user, async (u) => {
  if (u?.id) {
    await gamification.loadUserData()
    await gamification.loadGroupRanking()
  }
}, { immediate: true })

const userRank = computed(
  () => gamification.groupRankingData.value.find(
    r => r.user_id === user.value?.id
  )?.rank_position ?? null
)
```

- [ ] **Step 2: Adicionar card de pontos/nível no template**

Localizar no template de `app/pages/profile.vue` a seção principal de conteúdo e adicionar antes do formulário de perfil existente:

```html
<!-- Card de Gamificação -->
<div v-if="gamification.userPointsData.value" class="mb-8 p-6 rounded-3xl bg-white/[0.03] border border-white/10">
  <div class="flex items-center justify-between mb-4">
    <div class="flex items-center gap-3">
      <div class="w-10 h-10 rounded-xl bg-purple-500/20 border border-purple-500/30 flex items-center justify-center text-xl">
        {{ gamification.userLevel.value.level === 1 ? '🌱' : gamification.userLevel.value.level === 2 ? '🔭' : gamification.userLevel.value.level === 3 ? '⚙️' : gamification.userLevel.value.level === 4 ? '💡' : '👑' }}
      </div>
      <div>
        <p class="text-xs text-gray-500 uppercase tracking-widest font-bold">{{ gamification.userLevel.value.name }}</p>
        <p class="text-2xl font-black text-white">{{ gamification.totalPoints.value.toLocaleString('pt-BR') }} pts</p>
      </div>
    </div>
    <div v-if="userRank" class="text-right">
      <p class="text-xs text-gray-500 uppercase tracking-widest">Ranking do Grupo</p>
      <p class="text-xl font-bold text-purple-300">#{{ userRank }}</p>
    </div>
  </div>
  <!-- Barra de progresso -->
  <div>
    <div class="flex justify-between text-xs text-gray-500 mb-1">
      <span>Progresso para {{ gamification.userLevel.value.nextLevelPoints ? 'próximo nível' : 'nível máximo' }}</span>
      <span>{{ gamification.userLevel.value.progress }}%</span>
    </div>
    <div class="w-full h-2 bg-white/5 rounded-full overflow-hidden">
      <div
        class="h-full bg-gradient-to-r from-purple-500 to-blue-500 rounded-full"
        :style="{ width: `${gamification.userLevel.value.progress}%` }"
      />
    </div>
  </div>
</div>

<!-- Grid de Badges -->
<div v-if="gamification.allBadgesData.value.length" class="mb-8">
  <h3 class="text-sm font-bold uppercase tracking-widest text-gray-500 mb-4">Conquistas</h3>
  <BadgeGrid
    :all-badges="gamification.allBadgesData.value"
    :earned-slugs="gamification.earnedBadgeSlugs.value"
  />
</div>
```

- [ ] **Step 3: Testar no browser**

```bash
npm run dev
```

Navegar para `/profile` e verificar card de pontos, barra de progresso e grid de badges.

- [ ] **Step 4: Commit**

```bash
git add app/pages/profile.vue
git commit -m "feat: add gamification card and badge grid to profile page"
```

---

## Task 10: Página Admin de Gamificação

**Files:**
- Create: `app/pages/admin/gamification.vue`

- [ ] **Step 1: Criar a página admin**

```vue
<!-- app/pages/admin/gamification.vue -->
<script setup lang="ts">
const supabase = useSupabaseClient()

// Point Rules
const { data: rules, refresh: refreshRules } = await useAsyncData('point-rules', async () => {
  const { data } = await supabase.from('point_rules').select('*').order('event_type')
  return data
})

async function updateRule(id: string, points: number) {
  await supabase.from('point_rules').update({ points }).eq('id', id)
  await refreshRules()
}

// Ranking por grupo
const { data: ranking } = await useAsyncData('admin-ranking', async () => {
  const { data } = await supabase
    .from('group_ranking_view')
    .select('user_id, user_name, total_points, rank_position, group_id')
    .order('group_id')
    .order('rank_position')
    .limit(50)
  return data
})

// Badges + usuários para concessão manual
const { data: badges } = await useAsyncData('all-badges', async () => {
  const { data } = await supabase.from('badges').select('id, slug, name')
  return data
})

const manualUserId = ref('')
const manualBadgeId = ref('')
const manualGranting = ref(false)

async function grantBadgeManually() {
  if (!manualUserId.value || !manualBadgeId.value || manualGranting.value) return
  manualGranting.value = true
  await supabase.from('user_badges').insert({
    user_id: manualUserId.value,
    badge_id: manualBadgeId.value,
  })
  manualGranting.value = false
  manualUserId.value = ''
  manualBadgeId.value = ''
}

const EVENT_LABELS: Record<string, string> = {
  video_watched:   'Vídeo assistido (90%)',
  video_completed: 'Aula concluída',
  comment_posted:  'Comentário postado',
  comment_replied: 'Resposta publicada',
}
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white p-8">
    <h1 class="text-2xl font-bold mb-10">Gamificação — Admin</h1>

    <!-- Pontos por ação -->
    <section class="mb-12">
      <h2 class="text-lg font-semibold mb-4 text-gray-300">Pontos por Ação</h2>
      <div class="space-y-3">
        <div
          v-for="rule in rules"
          :key="rule.id"
          class="flex items-center justify-between p-4 rounded-2xl bg-white/[0.03] border border-white/10"
        >
          <span class="text-sm text-gray-300">{{ EVENT_LABELS[rule.event_type] ?? rule.event_type }}</span>
          <div class="flex items-center gap-3">
            <input
              type="number"
              :value="rule.points"
              min="0"
              class="w-20 bg-white/5 border border-white/10 rounded-xl px-3 py-1 text-center text-white text-sm focus:border-purple-500/50 outline-none"
              @change="updateRule(rule.id, Number(($event.target as HTMLInputElement).value))"
            />
            <span class="text-xs text-gray-500">pts</span>
          </div>
        </div>
      </div>
    </section>

    <!-- Ranking geral -->
    <section class="mb-12">
      <h2 class="text-lg font-semibold mb-4 text-gray-300">Ranking por Grupo (Top 50)</h2>
      <div class="rounded-2xl border border-white/10 overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-white/[0.03] text-gray-500 uppercase text-xs tracking-widest">
            <tr>
              <th class="p-3 text-left">Pos.</th>
              <th class="p-3 text-left">Aluno</th>
              <th class="p-3 text-right">Pontos</th>
              <th class="p-3 text-left">Grupo</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="entry in ranking" :key="`${entry.group_id}-${entry.user_id}`" class="border-t border-white/5 hover:bg-white/[0.02]">
              <td class="p-3 text-gray-400">#{{ entry.rank_position }}</td>
              <td class="p-3 text-gray-200">{{ entry.user_name }}</td>
              <td class="p-3 text-right font-bold text-purple-300">{{ entry.total_points }}</td>
              <td class="p-3 text-gray-500 text-xs">{{ entry.group_id }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Concessão manual de badge -->
    <section>
      <h2 class="text-lg font-semibold mb-4 text-gray-300">Conceder Badge Manualmente</h2>
      <div class="flex items-end gap-4 p-6 rounded-2xl bg-white/[0.03] border border-white/10">
        <div class="flex-1">
          <label class="block text-xs text-gray-500 uppercase tracking-widest mb-2">User ID</label>
          <input
            v-model="manualUserId"
            type="text"
            placeholder="uuid do usuário"
            class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2 text-sm text-white focus:border-purple-500/50 outline-none"
          />
        </div>
        <div class="flex-1">
          <label class="block text-xs text-gray-500 uppercase tracking-widest mb-2">Badge</label>
          <select
            v-model="manualBadgeId"
            class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-2 text-sm text-white focus:border-purple-500/50 outline-none"
          >
            <option value="" disabled>Selecionar badge...</option>
            <option v-for="b in badges" :key="b.id" :value="b.id">{{ b.name }} ({{ b.slug }})</option>
          </select>
        </div>
        <button
          @click="grantBadgeManually"
          :disabled="manualGranting || !manualUserId || !manualBadgeId"
          class="px-6 py-2 rounded-xl bg-purple-600 text-white text-xs font-bold hover:bg-purple-500 disabled:opacity-40 transition-all"
        >
          Conceder
        </button>
      </div>
    </section>
  </div>
</template>
```

- [ ] **Step 2: Testar no browser**

```bash
npm run dev
```

Navegar para `/admin/gamification` (usuário admin) e verificar as três seções.

- [ ] **Step 3: Commit**

```bash
git add app/pages/admin/gamification.vue
git commit -m "feat: add admin gamification management page"
```

---

## Task 11: Atualizar database.types.ts

**Files:**
- Modify: `app/types/database.types.ts`

Os tipos TypeScript precisam refletir as novas tabelas para que o `useSupabaseClient()` seja fortemente tipado.

- [ ] **Step 1: Regenerar os tipos via Supabase CLI**

```bash
supabase gen types typescript --local > app/types/database.types.ts
```

Ou, se usar o projeto remoto:
```bash
supabase gen types typescript --project-id <PROJECT_ID> > app/types/database.types.ts
```

- [ ] **Step 2: Verificar que as tabelas aparecem**

Confirmar que `point_events`, `user_points`, `badges`, `user_badges`, `point_rules`, `user_streaks` estão presentes no arquivo gerado.

- [ ] **Step 3: Commit**

```bash
git add app/types/database.types.ts
git commit -m "chore: regenerate database types with gamification tables"
```

---

## Task 12: Verificação Final

- [ ] **Step 1: Testar fluxo completo como aluno**

1. Logar como aluno que está em um grupo
2. Ir ao dashboard `/` → confirmar widget aparece
3. Abrir uma aula com vídeo → assistir até 90% → confirmar toast "+10 pts"
4. Clicar "Marcar como Concluída" → confirmar toast "+20 pts"
5. Postar um comentário → confirmar toast "+5 pts"
6. Responder um comentário → confirmar toast "+3 pts"
7. Ir ao `/profile` → confirmar card de pontos e badges

- [ ] **Step 2: Testar que duplicatas não geram pontos duplos**

1. Navegar para a mesma aula assistida anteriormente
2. Assistir novamente até 90% → confirmar que NÃO aparece novo toast de pontos

- [ ] **Step 3: Testar página admin**

1. Logar como admin
2. Ir para `/admin/gamification`
3. Alterar pontos de uma ação → confirmar que salva
4. Conceder badge manualmente a um usuário

- [ ] **Step 4: Commit final**

```bash
git commit --allow-empty -m "chore: gamification system complete and verified"
```
