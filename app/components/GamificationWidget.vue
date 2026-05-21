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

const LEVEL_ICONS: Record<number, string> = { 1: '🌱', 2: '🔭', 3: '⚙️', 4: '💡', 5: '👑' }
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
        <div class="w-10 h-10 rounded-xl bg-purple-500/20 border border-purple-500/30 flex items-center justify-center text-xl">
          {{ LEVEL_ICONS[userLevel.level] ?? '👑' }}
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
