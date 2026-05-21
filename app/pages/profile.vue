<script setup lang="ts">
// Nuxt auto-imports ref, watch, onMounted, useSupabaseClient, etc.
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const loading = ref(false)
const uploading = ref(false)
const profile = ref({
  name: '',
  avatar_url: ''
})

// Função para buscar os dados do perfil
async function fetchProfile() {
  console.log("fetchProfile", user.value?.sub);
  
  if (!user.value?.sub) return
  
  loading.value = true
  try {
    const { data, error } = await supabase
      .from('perfis')
      .select('name, avatar_url')
      .eq('id', user.value.sub)
      .single()    

    if (error && error.code !== 'PGRST116') {
      console.error('Erro Supabase:', error)
      throw error
    }
    
    if (data) {
      profile.value.name = data.name || ''
      profile.value.avatar_url = data.avatar_url || ''
    }
  } catch (err: any) {
    console.error('Erro ao buscar perfil:', err.message)
  } finally {
    loading.value = false
  }
}

// Observa o usuário e busca o perfil quando o ID estiver disponível
watch(user, (newUser) => {
  if (newUser?.sub) {
    fetchProfile()
  }
}, { immediate: true })

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

async function updateProfile() {
  loading.value = true
  
  try {
    // Busca o usuário atual de forma direta para garantir que a sessão está ativa
    const { data: { user: authUser } } = await supabase.auth.getUser()
    
    if (!authUser) {
      alert('Sessão expirada ou usuário não identificado. Por favor, faça login novamente.')
      return
    }
    
    const { error } = await supabase
      .from('perfis')
      .update({
        name: profile.value.name,
        avatar_url: profile.value.avatar_url
      })
      .eq('id', authUser.id)

    if (error) throw error
    alert('Perfil atualizado com sucesso!')
  } catch (err: any) {
    alert('Erro ao atualizar perfil: ' + err.message)
  } finally {
    loading.value = false
  }
}

async function uploadAvatar(event: any) {
  const file = event.target.files[0]
  if (!file) return

  if (!file.type.startsWith('image/')) {
    alert('Por favor, selecione uma imagem.')
    return
  }

  uploading.value = true
  try {
    const { data: { user: authUser } } = await supabase.auth.getUser()
    if (!authUser) throw new Error('Usuário não autenticado.')

    const fileExt = file.name.split('.').pop()
    const fileName = `${authUser.id}/${Date.now()}.${fileExt}`
    
    const { error: uploadError } = await supabase.storage
      .from('avatars')
      .upload(fileName, file, { upsert: true })

    if (uploadError) throw uploadError

    const { data: { publicUrl } } = supabase.storage
      .from('avatars')
      .getPublicUrl(fileName)

    profile.value.avatar_url = publicUrl
    
    // Atualiza o perfil imediatamente
    await supabase
      .from('perfis')
      .update({ avatar_url: publicUrl })
      .eq('id', authUser.id)

  } catch (err: any) {
    alert('Erro ao fazer upload: ' + err.message)
  } finally {
    uploading.value = false
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

    <main class="relative z-10 max-w-2xl mx-auto p-8 pt-20">

      <div class="glass-card p-8 rounded-3xl border border-white/10 bg-white/5 backdrop-blur-xl">
        <header class="mb-12">
          <h1 class="text-3xl font-bold bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">
            Meu Perfil
          </h1>
          <p class="text-gray-500 mt-2">Gerencie suas informações e foto de perfil.</p>
        </header>

        <!-- Loading State -->
        <div v-if="loading && !profile.name" class="flex justify-center py-20">
          <div class="relative w-12 h-12">
            <div class="absolute inset-0 rounded-full border-2 border-purple-500/20"></div>
            <div class="absolute inset-0 rounded-full border-2 border-transparent border-t-purple-500 animate-spin"></div>
          </div>
        </div>

        <!-- Form State -->
        <div v-else class="space-y-12">
          <!-- Avatar Section -->
          <div class="flex flex-col items-center gap-6">
            <div class="relative group">
              <div class="w-40 h-40 rounded-full overflow-hidden border-2 border-white/10 bg-white/5 flex items-center justify-center transition-all group-hover:border-purple-500/50 shadow-2xl">
                <img v-if="profile.avatar_url" :src="profile.avatar_url" class="w-full h-full object-cover" alt="Avatar">
                <div v-else class="w-full h-full flex flex-col items-center justify-center text-gray-600 gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                </div>
              </div>
              
              <label 
                for="avatar-upload" 
                class="absolute inset-0 flex flex-col items-center justify-center bg-black/60 backdrop-blur-sm opacity-0 group-hover:opacity-100 transition-all rounded-full cursor-pointer border-2 border-dashed border-white/20"
              >
                <svg v-if="!uploading" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="mb-1 text-purple-400"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/></svg>
                <div v-else class="w-6 h-6 border-2 border-white/20 border-t-white animate-spin rounded-full mb-1"></div>
                <span class="text-[10px] font-bold tracking-widest uppercase">{{ uploading ? 'Enviando...' : 'Alterar Foto' }}</span>
                <input id="avatar-upload" type="file" class="hidden" accept="image/*" @change="uploadAvatar" :disabled="uploading">
              </label>
            </div>
            <div class="text-center">
              <h3 class="font-semibold text-gray-300">{{ profile.name || 'Sem nome definido' }}</h3>
              <p class="text-xs text-gray-500 mt-1">Recomendado: 400x400px (JPG, PNG)</p>
            </div>
          </div>

          <!-- Gamification Card -->
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

          <!-- Badge Grid -->
          <div v-if="gamification.allBadgesData.value.length" class="mb-8">
            <h3 class="text-sm font-bold uppercase tracking-widest text-gray-500 mb-4">Conquistas</h3>
            <BadgeGrid
              :all-badges="gamification.allBadgesData.value"
              :earned-slugs="gamification.earnedBadgeSlugs.value"
            />
          </div>

          <!-- Form Section -->
          <div class="space-y-8">
            <div class="grid grid-cols-1 gap-6">
              <div class="space-y-2">
                <label class="text-[10px] font-bold tracking-widest uppercase text-gray-500 ml-1">E-mail da Conta</label>
                <div class="w-full px-5 py-4 rounded-2xl bg-white/[0.02] border border-white/5 text-gray-600 flex items-center gap-3 cursor-not-allowed">
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>
                  {{ user?.email }}
                </div>
              </div>

              <div class="space-y-2">
                <label for="name" class="text-[10px] font-bold tracking-widest uppercase text-gray-400 ml-1">Nome de Exibição</label>
                <div class="relative">
                  <input 
                    id="name"
                    v-model="profile.name"
                    type="text"
                    placeholder="Como você quer ser chamado?"
                    class="w-full pl-12 pr-5 py-4 rounded-2xl bg-white/5 border border-white/10 focus:border-purple-500/50 focus:bg-white/[0.08] transition-all outline-none"
                  >
                  <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="absolute left-4 top-1/2 -translate-y-1/2 text-gray-500"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
                </div>
              </div>
            </div>

            <button 
              @click="updateProfile"
              :disabled="loading || uploading"
              class="w-full py-5 rounded-2xl bg-gradient-to-r from-purple-600 to-blue-600 font-bold text-sm tracking-widest uppercase hover:from-purple-500 hover:to-blue-500 transition-all disabled:opacity-50 disabled:cursor-not-allowed shadow-xl shadow-purple-500/20 active:scale-[0.98]"
            >
              <span v-if="!loading">Salvar Alterações</span>
              <span v-else class="flex items-center justify-center gap-2">
                <div class="w-4 h-4 border-2 border-white/20 border-t-white animate-spin rounded-full"></div>
                Salvando...
              </span>
            </button>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<style scoped>
.glass-card {
  box-shadow: 0 40px 100px -20px rgba(0, 0, 0, 0.7);
}

input::placeholder {
  color: rgba(255, 255, 255, 0.2);
}
</style>
