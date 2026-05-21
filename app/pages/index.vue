<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

// Busca o perfil do usuário logado
const { data: profile } = await useAsyncData('user-profile', async () => {
  if (!user.value?.id) return null
  const { data } = await supabase.from('perfis').select('role, name').eq('id', user.value.id).single()
  return data
})

// Busca os cursos da view course_catalog (agora inclui progresso automaticamente)
const { data: courses, pending, error } = await useAsyncData(`course-catalog-${user.value?.id}`, async () => {
  const { data } = await supabase.from('course_catalog').select('*')
  return data
}, { watch: [user] })

function getCoursePercent(course: any) {
  if (!course.total_contents) return 0
  const completed = course.completed_contents || 0
  return Math.round((completed / course.total_contents) * 100)
}

async function handleLogout() {
  await supabase.auth.signOut()
  navigateTo('/login')
}

// Gamification
const {
  totalPoints,
  userLevel,
  groupId,
  groupRankingData,
  allBadgesData,
  earnedBadgeSlugs,
  loadUserData,
  loadGroupRanking,
} = useGamification()

if (import.meta.client) {
  loadUserData().then(() => loadGroupRanking())
}

const nextBadge = computed(() => {
  return allBadgesData.value.find(b => !earnedBadgeSlugs.value.has(b.slug)) ?? null
})
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white font-sans selection:bg-[#FAA407]/30">
    <!-- Background Glows -->
    <div class="fixed inset-0 overflow-hidden pointer-events-none">
      <div class="absolute -top-[10%] -left-[10%] w-[40%] h-[40%] bg-[#006E46]/20 blur-[120px] rounded-full"></div>
      <div class="absolute bottom-[10%] -right-[10%] w-[30%] h-[30%] bg-[#FAA407]/10 blur-[100px] rounded-full"></div>
    </div>

    <main class="relative z-10 max-w-6xl mx-auto p-8 pt-12">
      <div class="mb-12">
        <h1 class="text-3xl font-bold tracking-tight text-white">
          Bem-vindo, <span class="bg-gradient-to-r from-[#FAA407] to-[#008266] bg-clip-text text-transparent">{{ profile?.name }}</span>
        </h1>
        <p class="text-gray-400 mt-2">Continue sua jornada de aprendizado na Inovação Academy.</p>
      </div>

      <ClientOnly>
        <GamificationWidget
          v-if="groupId"
          :total-points="totalPoints"
          :user-level="userLevel"
          :group-ranking="groupRankingData"
          :current-user-id="user?.id ?? ''"
          :next-badge="nextBadge"
        />
      </ClientOnly>

      <!-- Courses Grid -->
      <section>
        <h2 class="text-xl font-semibold mb-8 flex items-center gap-3">
          <span class="w-8 h-8 rounded-lg bg-[#006E46]/20 flex items-center justify-center text-[#FAA407]">
            <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1-2.5-2.5Z"/><path d="M8 7h6"/><path d="M8 11h8"/></svg>
          </span>
          Meus Cursos
        </h2>

        <div v-if="error" class="p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm">
          Erro ao carregar catálogo: {{ error.message }}
        </div>

        <div v-else-if="!courses || courses.length === 0" class="text-center py-20 border-2 border-dashed border-white/5 rounded-3xl">
          <div class="w-16 h-16 bg-white/5 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-gray-500"><path d="M21 12V7a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h7"/><path d="M16 19h6"/><path d="M19 16v6"/><circle cx="9" cy="9" r="2"/></svg>
          </div>
          <p class="text-gray-500">Nenhum curso disponível no momento.</p>
        </div>

        <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          <NuxtLink 
            v-for="course in courses" 
            :key="course.course_id"
            :to="`/courses/${course.course_id}`"
            class="group glass-card p-4 rounded-3xl border border-white/10 bg-white/5 backdrop-blur-xl hover:border-[#FAA407]/50 hover:bg-white/[0.08] transition-all duration-500 block"
          >
            <div class="aspect-video rounded-2xl bg-gradient-to-br from-[#006E46]/40 to-[#004F32]/60 mb-4 overflow-hidden border border-white/5">
              <img v-if="course.thumbnail_url" :src="course.thumbnail_url" class="w-full h-full object-cover group-hover:scale-105 transition-transform duration-700" alt="Thumbnail">
              <div v-else class="w-full h-full flex items-center justify-center">
                <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-white/10"><path d="m16 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="m2 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="M7 21h10"/><path d="M12 3v18"/><path d="M3 7h2c2 0 5-1 7-2 2 1 5 2 7 2h2"/></svg>
              </div>
            </div>
            <h3 class="font-bold text-lg text-gray-100 group-hover:text-white transition-colors">{{ course.course_title }}</h3>
            <p class="text-sm text-gray-500 mt-2 line-clamp-2 h-10">{{ course.course_description }}</p>
            
            <div class="mt-6 pt-4 border-t border-white/5">
               <!-- Progress indicator -->
               <div class="flex items-center justify-between mb-2">
                 <span class="text-[10px] text-gray-500 uppercase tracking-widest font-bold">Progresso</span>
                 <span class="text-[10px] text-[#FAA407] font-bold">{{ getCoursePercent(course) }}%</span>
               </div>
               <div class="w-full h-1 bg-white/5 rounded-full overflow-hidden mb-4">
                 <div class="h-full bg-[#FAA407] transition-all duration-1000" :style="{ width: `${getCoursePercent(course)}%` }"></div>
               </div>

              <div class="flex items-center gap-4">
                <span class="text-xs text-gray-400 flex items-center gap-1">
                  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1-2.5-2.5Z"/></svg>
                  {{ course.total_modules }} Módulos
                </span>
                <span class="text-xs text-gray-400 flex items-center gap-1">
                  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 12m-9 0a9 9 0 1 0 18 0a9 9 0 1 0 -18 0"/><path d="M12 7v5l3 3"/></svg>
                  {{ course.total_contents }} Aulas
                </span>
              </div>
            </div>
          </NuxtLink>
        </div>
      </section>
    </main>
  </div>
</template>

<style scoped>
.glass-card {
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
}
</style>

