<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const { data: courses, refresh, pending } = await useAsyncData('admin-courses', async () => {
  const { data } = await supabase.from('courses').select('*').order('created_at', { ascending: false })
  return data
})

const isCreating = ref(false)
const newCourse = ref({
  title: '',
  description: '',
  thumbnail_url: ''
})

async function createCourse() {
  if (!newCourse.value.title) return
  
  const { error } = await supabase.from('courses').insert([
    {
      title: newCourse.value.title,
      description: newCourse.value.description,
      thumbnail_url: newCourse.value.thumbnail_url
    }
  ])

  if (!error) {
    isCreating.value = false
    newCourse.value = { title: '', description: '', thumbnail_url: '' }
    await refresh()
  } else {
    alert('Erro ao criar curso: ' + error.message)
  }
}
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white font-sans selection:bg-purple-500/30">
    <!-- Background Glows -->
    <div class="fixed inset-0 overflow-hidden pointer-events-none">
      <div class="absolute -top-[10%] -left-[10%] w-[40%] h-[40%] bg-purple-600/20 blur-[120px] rounded-full"></div>
      <div class="absolute bottom-[10%] -right-[10%] w-[30%] h-[30%] bg-blue-600/10 blur-[100px] rounded-full"></div>
    </div>

    <main class="relative z-10 max-w-6xl mx-auto p-8 pt-12">
      <div class="mb-12 flex justify-between items-end">
        <div>
          <h1 class="text-4xl font-bold tracking-tight bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">
            Gestão de Cursos
          </h1>
          <p class="text-gray-400 mt-2">Crie e edite o catálogo de cursos.</p>
        </div>
        <button 
          @click="isCreating = true"
          class="px-5 py-2.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-medium transition-all shadow-[0_0_20px_-5px_rgba(168,85,247,0.4)] flex items-center gap-2"
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
          Novo Curso
        </button>
      </div>

      <!-- Create Course Form -->
      <div v-if="isCreating" class="mb-12 p-6 glass-card rounded-3xl border border-purple-500/30 bg-purple-500/5 backdrop-blur-xl">
        <h2 class="text-xl font-semibold mb-4 text-purple-100">Criar Novo Curso</h2>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
          <div>
            <label class="block text-sm text-gray-400 mb-1">Título</label>
            <input v-model="newCourse.title" type="text" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50 transition-colors" placeholder="Ex: Introdução ao Vue 3">
          </div>
          <div>
            <label class="block text-sm text-gray-400 mb-1">URL da Capa (Thumbnail)</label>
            <input v-model="newCourse.thumbnail_url" type="text" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50 transition-colors" placeholder="https://...">
          </div>
          <div class="md:col-span-2">
            <label class="block text-sm text-gray-400 mb-1">Descrição</label>
            <textarea v-model="newCourse.description" rows="3" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50 transition-colors" placeholder="Breve descrição do curso..."></textarea>
          </div>
        </div>
        <div class="flex justify-end gap-3">
          <button @click="isCreating = false" class="px-4 py-2 rounded-xl bg-white/5 hover:bg-white/10 text-white transition-all">Cancelar</button>
          <button @click="createCourse" class="px-4 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white transition-all">Salvar Curso</button>
        </div>
      </div>

      <!-- Courses List -->
      <div v-if="pending" class="space-y-4">
        <div v-for="i in 3" :key="i" class="h-20 bg-white/5 rounded-2xl animate-pulse border border-white/10"></div>
      </div>
      
      <div v-else-if="courses?.length === 0" class="text-center py-20 border-2 border-dashed border-white/5 rounded-3xl">
        <p class="text-gray-500">Nenhum curso encontrado. Crie o seu primeiro curso!</p>
      </div>

      <div v-else class="grid grid-cols-1 gap-4">
        <div v-for="course in courses" :key="course.id" class="glass-card p-4 rounded-2xl border border-white/10 bg-white/5 backdrop-blur-xl flex items-center gap-6">
          <div class="w-32 h-20 bg-black/50 rounded-xl overflow-hidden shrink-0 border border-white/5">
            <img v-if="course.thumbnail_url" :src="course.thumbnail_url" class="w-full h-full object-cover" alt="Thumbnail">
            <div v-else class="w-full h-full flex items-center justify-center text-white/10">
               <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/></svg>
            </div>
          </div>
          <div class="flex-1">
            <h3 class="font-bold text-lg text-white">{{ course.title }}</h3>
            <p class="text-sm text-gray-400 line-clamp-1">{{ course.description || 'Sem descrição' }}</p>
          </div>
          <div class="shrink-0 flex gap-2">
            <NuxtLink :to="`/admin/courses/${course.id}`" class="px-4 py-2 rounded-xl bg-white/10 hover:bg-white/20 text-white text-sm transition-all flex items-center gap-2">
              <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/></svg>
              Gerenciar Módulos
            </NuxtLink>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<style scoped>
.glass-card {
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
}
</style>
