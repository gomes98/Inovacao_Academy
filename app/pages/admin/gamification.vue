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

// Badges para concessão manual
const { data: badges } = await useAsyncData('all-badges', async () => {
  const { data } = await supabase.from('badges').select('id, slug, name')
  return data
})

const manualUserId = ref('')
const manualBadgeId = ref('')
const manualGranting = ref(false)
const manualGrantError = ref<string | null>(null)

async function grantBadgeManually() {
  if (!manualUserId.value || !manualBadgeId.value || manualGranting.value) return
  manualGranting.value = true
  manualGrantError.value = null
  const { error } = await supabase.from('user_badges').insert({
    user_id: manualUserId.value,
    badge_id: manualBadgeId.value,
  })
  manualGranting.value = false
  if (error) {
    manualGrantError.value = error.message
  } else {
    manualUserId.value = ''
    manualBadgeId.value = ''
  }
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
      <div v-if="manualGrantError" class="mb-3 p-3 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm">
        Erro: {{ manualGrantError }}
      </div>
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
