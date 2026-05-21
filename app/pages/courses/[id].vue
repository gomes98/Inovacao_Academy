<script setup lang="ts">
import type { Database } from '~/types/database.types'

const route = useRoute()
const supabase = useSupabaseClient<Database>()

const courseId = route.params.id as string

// Busca a estrutura do curso da view course_structure (inclui progresso)
const user = useSupabaseUser()
const { data: structure, pending, error } = await useAsyncData(`course-structure-${courseId}-${user.value?.id}`, async () => {
  const { data } = await supabase.from('course_structure').select('*').eq('course_id', courseId)

  // Coleta IDs de módulos para buscar video_url dos conteúdos
  const moduleIds = [...new Set(data?.map(item => item.module_id).filter(Boolean) as string[])]
  const videoUrlMap = new Map<string, string | null>()
  if (moduleIds.length) {
    const { data: videoUrls } = await supabase
      .from('contents')
      .select('id, video_url')
      .in('module_id', moduleIds)
    videoUrls?.forEach(v => videoUrlMap.set(v.id, v.video_url ?? null))
  }

  // Agrupa conteúdos por módulo
  const modulesMap = new Map()
  data?.forEach(item => {
    if (item.module_id) {
      if (!modulesMap.has(item.module_id)) {
        modulesMap.set(item.module_id, {
          id: item.module_id,
          title: item.module_title,
          order: item.module_order,
          contents: []
        })
      }
      modulesMap.get(item.module_id).contents.push({
        id: item.content_id,
        title: item.content_title,
        type: item.content_type,
        order: item.content_order,
        is_completed: item.is_completed,
        duration: item.content_duration,
        video_url: videoUrlMap.get(item.content_id ?? '') ?? null
      })
    }
  })

  const modules = Array.from(modulesMap.values()).sort((a, b) => a.order - b.order)
  modules.forEach(m => m.contents.sort((a: { order: number }, b: { order: number }) => a.order - b.order))
  return modules
})

const courseTitle = computed(() => structure.value?.[0]?.title || 'Curso')

const stats = computed(() => {
  const total = structure.value?.reduce((acc, mod) => acc + mod.contents.length, 0) || 0
  const completed = structure.value?.reduce((acc, mod) => acc + mod.contents.filter(c => c.is_completed).length, 0) || 0
  const percent = total > 0 ? Math.round((completed / total) * 100) : 0
  return { total, completed, percent }
})

function formatDuration(seconds: number): string {
  if (!seconds || seconds <= 0) return ''
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
}
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white font-sans selection:bg-[#FAA407]/30">
    <!-- Background Glows -->
    <div class="fixed inset-0 overflow-hidden pointer-events-none">
      <div class="absolute -top-[10%] -right-[10%] w-[40%] h-[40%] bg-[#006E46]/10 blur-[120px] rounded-full"></div>
    </div>

    <main class="relative z-10 max-w-4xl mx-auto p-8 pt-12">
      <header class="mb-12">
        <div class="flex flex-col md:flex-row md:items-end justify-between gap-6 mb-8">
          <div>
            <h1 class="text-4xl font-bold tracking-tight bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">
              {{ structure?.[0]?.course_title || 'Detalhes do Curso' }}
            </h1>
            <p class="text-gray-500 mt-2 uppercase tracking-widest text-xs font-medium">Progresso do Aluno</p>
          </div>
          
          <div class="flex flex-col items-end gap-2">
             <div class="text-2xl font-black text-[#FAA407]">{{ stats.percent }}%</div>
             <div class="text-[10px] text-gray-600 uppercase tracking-tighter">{{ stats.completed }} de {{ stats.total }} aulas concluídas</div>
          </div>
        </div>

        <!-- Progress Bar -->
        <div class="w-full h-2 bg-white/5 rounded-full overflow-hidden border border-white/5">
          <div 
            class="h-full bg-gradient-to-r from-[#006E46] to-[#FAA407] transition-all duration-1000 ease-out shadow-[0_0_20px_rgba(0,110,70,0.3)]"
            :style="{ width: `${stats.percent}%` }"
          ></div>
        </div>
      </header>

      <section v-if="pending" class="space-y-6">
        <div v-for="i in 3" :key="i" class="h-24 bg-white/5 rounded-3xl animate-pulse border border-white/10"></div>
      </section>

      <section v-else-if="error" class="p-6 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-400 text-sm">
        Erro ao carregar estrutura: {{ error.message }}
      </section>

      <section v-else-if="structure?.length" class="space-y-8">
        <div v-for="mod in structure" :key="mod.id" class="glass-card rounded-3xl border border-white/10 bg-white/5 backdrop-blur-xl overflow-hidden">
          <div class="p-6 border-b border-white/5 bg-white/[0.02] flex justify-between items-center">
            <h2 class="text-lg font-semibold flex items-center gap-3">
              <span class="w-2 h-2 rounded-full transition-colors" :class="[mod.contents.every(c => c.is_completed) ? 'bg-emerald-500 shadow-[0_0_8px_rgba(16,185,129,0.5)]' : 'bg-[#FAA407]']"></span>
              {{ mod.title }}
              <svg v-if="mod.contents.every(c => c.is_completed)" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" class="text-emerald-500"><polyline points="20 6 9 17 4 12"/></svg>
            </h2>
            <span class="text-xs text-gray-500 uppercase tracking-widest font-medium">{{ mod.contents.filter(c => c.is_completed).length }} / {{ mod.contents.length }} concluídas</span>
          </div>
          
          <div class="divide-y divide-white/5">
            <NuxtLink 
              v-for="content in mod.contents" 
              :key="content.id"
              :to="`/lesson/${content.id}`"
              class="flex items-center gap-4 p-4 hover:bg-white/[0.03] transition-all group"
            >
              <div class="w-10 h-10 rounded-xl bg-white/5 flex items-center justify-center text-gray-500 group-hover:text-[#FAA407] group-hover:bg-[#FAA407]/10 transition-all border border-white/5 relative overflow-hidden flex-shrink-0">
                <template v-if="content.type === 'video' && content.video_url">
                  <img
                    :src="content.video_url.replace(/\.[^.]+$/, '.jpg')"
                    class="w-full h-full object-cover rounded-xl"
                    @error="(e) => { (e.target as HTMLElement).style.display = 'none'; (e.target as HTMLElement).nextElementSibling?.removeAttribute('style') }"
                  />
                  <svg style="display:none" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                  <div class="absolute inset-0 flex items-center justify-center bg-black/30 rounded-xl">
                    <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="white" stroke="none"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                  </div>
                </template>
                <svg v-else-if="content.type === 'video'" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                <svg v-else xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>

                <!-- Completion Badge -->
                <div v-if="content.is_completed" class="absolute -top-1.5 -right-1.5 w-5 h-5 bg-emerald-500 rounded-full flex items-center justify-center border-2 border-[#050505] shadow-lg">
                  <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" class="text-white"><polyline points="20 6 9 17 4 12"/></svg>
                </div>
              </div>
              <div class="flex-1">
                <h3 class="text-sm font-medium text-gray-300 group-hover:text-white transition-colors">{{ content.title }}</h3>
                <p class="text-xs text-gray-600 mt-0.5 capitalize flex items-center gap-2">
                  {{ content.type }}
                  <span v-if="content.type === 'video' && formatDuration(content.duration)" class="text-gray-500">{{ formatDuration(content.duration) }}</span>
                </p>
              </div>
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-gray-700 group-hover:text-[#FAA407] group-hover:translate-x-1 transition-all"><path d="m9 18 6-6-6-6"/></svg>
            </NuxtLink>
          </div>
        </div>
      </section>

      <section v-else class="text-center py-20 border-2 border-dashed border-white/5 rounded-3xl">
        <p class="text-gray-500">Nenhum módulo cadastrado para este curso.</p>
      </section>
    </main>
  </div>
</template>

<style scoped>
.glass-card {
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
}
</style>
