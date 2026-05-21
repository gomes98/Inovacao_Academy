// app/composables/useGamification.ts

type EventType = 'video_watched' | 'video_completed' | 'comment_posted' | 'comment_replied'

interface Level {
  level: number
  name: string
  minPoints: number
  nextLevelPoints: number | null
  progress: number
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
  const resolvedGroupId = ref<string | null>(null)

  const totalPoints = computed(() => userPointsData.value?.total_points ?? 0)
  const groupId = computed(() => resolvedGroupId.value)
  const userLevel = computed(() => computeLevel(totalPoints.value))

  const earnedBadgeSlugs = computed(
    () => new Set(userBadgesData.value.map(ub => ub.badges.slug))
  )

  async function loadUserData() {
    if (!user.value?.id) return

    const [pointsRes, badgesRes, allBadgesRes, groupRes] = await Promise.all([
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
      supabase
        .from('user_groups')
        .select('group_id')
        .eq('user_id', user.value.id)
        .maybeSingle(),
    ])

    if (pointsRes.data) userPointsData.value = pointsRes.data as UserPointsRow
    if (badgesRes.data) userBadgesData.value = badgesRes.data as unknown as UserBadgeRow[]
    if (allBadgesRes.data) allBadgesData.value = allBadgesRes.data as BadgeRow[]

    // groupId vem de user_groups (funciona mesmo antes do primeiro evento de pontos)
    // e de user_points como fallback após eventos registrados
    resolvedGroupId.value = groupRes.data?.group_id ?? pointsRes.data?.group_id ?? null
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

    const { error } = await supabase.from('point_events').insert({
      user_id: user.value.id,
      group_id: groupId.value,
      event_type: eventType,
      points: 0, // será sobrescrito pelo trigger fn_validate_point_event no banco
      reference_id: referenceId,
    })

    // código 23505 = unique violation (evento já registrado para este referenceId)
    if (error && error.code !== '23505') {
      console.error('[useGamification] trackEvent error:', error)
      return
    }

    if (!error) {
      // Busca o valor real de pontos para exibir no toast
      const { data: rule } = await supabase
        .from('point_rules')
        .select('points')
        .eq('event_type', eventType)
        .eq('is_active', true)
        .maybeSingle()

      const labels: Record<EventType, string> = {
        video_watched:   'Vídeo assistido!',
        video_completed: 'Aula concluída!',
        comment_posted:  'Comentário postado!',
        comment_replied: 'Resposta publicada!',
      }
      lastPointsEarned.value = { points: rule?.points ?? 0, label: labels[eventType] }

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
