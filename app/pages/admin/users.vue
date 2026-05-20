<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()

// State
const users = ref<any[]>([])
const loading = ref(true)
const isModalOpen = ref(false)
const modalAction = ref<'create' | 'edit' | 'invite'>('create')
const selectedUser = ref<any>(null)

// Form state
const form = ref({
  id: '',
  name: '',
  email: '',
  password: '',
  role: 'aluno'
})

const roles = [
  { value: 'admin', label: 'Administrador' },
  { value: 'publicador', label: 'Publicador' },
  { value: 'aluno', label: 'Aluno' },
  { value: 'disabled', label: 'Desativado' }
]

// ─── Dados para a seção de acesso ────────────────────────────
const allCourses = ref<any[]>([])
const allGroups = ref<any[]>([])

const accessMode = ref<'all_courses' | 'specific' | 'groups_only'>('groups_only')
const selectedCourseIds = ref<Set<string>>(new Set())
const selectedGroupIds = ref<Set<string>>(new Set())

async function fetchAccessData() {
  const [{ data: courses }, { data: groups }] = await Promise.all([
    useSupabaseClient().from('courses').select('id, title').order('title'),
    useSupabaseClient().from('permission_groups').select('id, name').order('name'),
  ])
  allCourses.value = courses ?? []
  allGroups.value = groups ?? []
}

async function fetchUserAccess(userId: string) {
  const supabase = useSupabaseClient()
  const [{ data: uam }, { data: uca }, { data: ug }] = await Promise.all([
    supabase.from('user_access_mode').select('mode').eq('user_id', userId).maybeSingle(),
    supabase.from('user_course_access').select('course_id').eq('user_id', userId),
    supabase.from('user_groups').select('group_id').eq('user_id', userId),
  ])

  if (uam?.mode === 'all_courses') {
    accessMode.value = 'all_courses'
  } else if ((uca ?? []).length > 0) {
    accessMode.value = 'specific'
  } else {
    accessMode.value = 'groups_only'
  }

  selectedCourseIds.value = new Set((uca ?? []).map((r: any) => r.course_id))
  selectedGroupIds.value = new Set((ug ?? []).map((r: any) => r.group_id))
}

async function saveUserAccess(userId: string) {
  const supabase = useSupabaseClient()

  await supabase.from('user_access_mode').upsert({
    user_id: userId,
    mode: accessMode.value === 'all_courses' ? 'all_courses' : 'restricted',
  })

  await supabase.from('user_course_access').delete().eq('user_id', userId)
  if (accessMode.value === 'specific' && selectedCourseIds.value.size > 0) {
    const rows = Array.from(selectedCourseIds.value).map(course_id => ({ user_id: userId, course_id }))
    await supabase.from('user_course_access').insert(rows)
  }

  await supabase.from('user_groups').delete().eq('user_id', userId)
  if (selectedGroupIds.value.size > 0) {
    const rows = Array.from(selectedGroupIds.value).map(group_id => ({ user_id: userId, group_id }))
    await supabase.from('user_groups').insert(rows)
  }
}

function toggleCourseId(courseId: string) {
  if (selectedCourseIds.value.has(courseId)) selectedCourseIds.value.delete(courseId)
  else selectedCourseIds.value.add(courseId)
  selectedCourseIds.value = new Set(selectedCourseIds.value)
}

function toggleGroupId(groupId: string) {
  if (selectedGroupIds.value.has(groupId)) selectedGroupIds.value.delete(groupId)
  else selectedGroupIds.value.add(groupId)
  selectedGroupIds.value = new Set(selectedGroupIds.value)
}

// Fetch data
async function fetchUsers() {
  loading.value = true
  const { data, error } = await supabase
    .from('perfis')
    .select('*')
    .order('created_at', { ascending: false })
  
  if (error) {
    console.error('Erro ao buscar usuários:', error)
  } else {
    users.value = data
  }
  loading.value = false
}

// Actions
async function handleSubmit() {
  loading.value = true
  try {
    let action = modalAction.value
    let payload: any = {
      action,
      email: form.value.email,
      name: form.value.name,
      role: form.value.role
    }

    if (action === 'create') {
      payload.password = form.value.password
    } else if (action === 'edit') {
      payload.action = 'update_user'
      payload.userId = form.value.id
    }

    const { data, error } = await supabase.functions.invoke('manage-users', {
      body: payload
    })

    if (error) throw error
    if (data.error) throw new Error(data.error)

    if (action === 'edit' && form.value.role === 'aluno') {
      await saveUserAccess(form.value.id)
    }

    alert(action === 'edit' ? 'Usuário atualizado!' : 'Operação realizada com sucesso!')
    isModalOpen.value = false
    await fetchUsers()
  } catch (err: any) {
    alert('Erro: ' + err.message)
  } finally {
    loading.value = false
  }
}

async function deleteUser(userId: string) {
  if (!confirm('Tem certeza que deseja excluir este usuário? Esta ação é irreversível e removerá o acesso dele ao sistema.')) return
  
  loading.value = true
  try {
    const { data, error } = await supabase.functions.invoke('manage-users', {
      body: { action: 'delete', userId }
    })

    if (error) throw error
    if (data.error) throw new Error(data.error)

    await fetchUsers()
  } catch (err: any) {
    alert('Erro ao excluir usuário: ' + err.message)
  } finally {
    loading.value = false
  }
}

async function openModal(action: 'create' | 'edit' | 'invite', userData?: any) {
  modalAction.value = action
  if (action === 'edit' && userData) {
    selectedUser.value = userData
    form.value = {
      id: userData.id,
      name: userData.name,
      email: userData.email,
      password: '',
      role: userData.role
    }
    if (userData.role === 'aluno') {
      await fetchAccessData()
      await fetchUserAccess(userData.id)
    }
  } else {
    selectedUser.value = null
    form.value = { id: '', name: '', email: '', password: '', role: 'aluno' }
    accessMode.value = 'groups_only'
    selectedCourseIds.value = new Set()
    selectedGroupIds.value = new Set()
  }
  isModalOpen.value = true
}

onMounted(() => {
  fetchUsers()
})
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white font-sans selection:bg-purple-500/30">
    <!-- Background Glows -->
    <div class="fixed inset-0 overflow-hidden pointer-events-none">
      <div class="absolute -top-[10%] -left-[10%] w-[40%] h-[40%] bg-purple-600/20 blur-[120px] rounded-full"></div>
      <div class="absolute bottom-[10%] -right-[10%] w-[30%] h-[30%] bg-blue-600/10 blur-[100px] rounded-full"></div>
    </div>

    <main class="relative z-10 max-w-7xl mx-auto p-8 pt-12">
      <div class="mb-12 flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div>
          <h1 class="text-4xl font-bold tracking-tight bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">
            Gestão de Usuários
          </h1>
          <p class="text-gray-400 mt-2">Gerencie permissões, crie novas contas ou convide membros.</p>
        </div>
        
        <div class="flex gap-3">
          <button 
            @click="openModal('invite')"
            class="px-5 py-2.5 rounded-xl bg-white/5 border border-white/10 hover:bg-white/10 text-white font-medium transition-all flex items-center gap-2"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>
            Convidar por E-mail
          </button>
          <button 
            @click="openModal('create')"
            class="px-5 py-2.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-medium transition-all shadow-[0_0_20px_-5px_rgba(168,85,247,0.4)] flex items-center gap-2"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
            Novo Usuário
          </button>
        </div>
      </div>

      <!-- Users List -->
      <div class="glass-card rounded-3xl border border-white/10 bg-white/5 backdrop-blur-xl overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="border-b border-white/10 bg-white/[0.02]">
                <th class="px-6 py-4 text-xs font-bold tracking-widest uppercase text-gray-500">Usuário</th>
                <th class="px-6 py-4 text-xs font-bold tracking-widest uppercase text-gray-500">E-mail</th>
                <th class="px-6 py-4 text-xs font-bold tracking-widest uppercase text-gray-500">Role</th>
                <th class="px-6 py-4 text-xs font-bold tracking-widest uppercase text-gray-500 text-right">Ações</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/5">
              <tr v-if="loading && users.length === 0" v-for="i in 5" :key="i" class="animate-pulse">
                <td colspan="4" class="px-6 py-4 h-16 bg-white/[0.01]"></td>
              </tr>
              
              <tr v-else-if="users.length === 0">
                <td colspan="4" class="px-6 py-12 text-center text-gray-500 italic">Nenhum usuário encontrado.</td>
              </tr>

              <tr v-for="u in users" :key="u.id" class="group hover:bg-white/[0.02] transition-colors">
                <td class="px-6 py-4">
                  <div class="flex items-center gap-3">
                    <div class="w-10 h-10 rounded-full bg-gradient-to-br from-purple-500/20 to-blue-500/20 border border-white/10 flex items-center justify-center shrink-0">
                      <img v-if="u.avatar_url" :src="u.avatar_url" class="w-full h-full rounded-full object-cover">
                      <span v-else class="text-sm font-bold text-purple-300">{{ u.name?.[0]?.toUpperCase() }}</span>
                    </div>
                    <div>
                      <div class="font-medium text-white">{{ u.name }}</div>
                      <div class="text-xs text-gray-500">ID: {{ u.id.slice(0, 8) }}...</div>
                    </div>
                  </div>
                </td>
                <td class="px-6 py-4 text-gray-300 text-sm">
                  {{ u.email }}
                </td>
                <td class="px-6 py-4">
                  <span 
                    class="px-2.5 py-1 rounded-full text-[10px] font-bold tracking-wider uppercase border"
                    :class="{
                      'bg-purple-500/10 border-purple-500/30 text-purple-400': u.role === 'admin',
                      'bg-blue-500/10 border-blue-500/30 text-blue-400': u.role === 'publicador',
                      'bg-gray-500/10 border-white/20 text-gray-400': u.role === 'aluno',
                      'bg-red-500/10 border-red-500/30 text-red-400': u.role === 'disabled'
                    }"
                  >
                    {{ u.role }}
                  </span>
                </td>
                <td class="px-6 py-4 text-right">
                  <div class="flex justify-end gap-2">
                    <button 
                      @click="openModal('edit', u)"
                      class="p-2 rounded-lg bg-white/5 border border-white/5 hover:border-white/20 hover:bg-white/10 text-gray-400 hover:text-white transition-all"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
                    </button>
                    <button 
                      v-if="u.id !== user?.id"
                      @click="deleteUser(u.id)"
                      class="p-2 rounded-lg bg-red-500/5 border border-red-500/10 hover:border-red-500/30 hover:bg-red-500/20 text-red-500/50 hover:text-red-500 transition-all"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </main>

    <!-- Modal -->
    <div v-if="isModalOpen" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/80 backdrop-blur-sm" @click="isModalOpen = false"></div>
      
      <div class="relative w-full max-w-md glass-card rounded-3xl border border-white/10 bg-[#0c0c0c] p-8 shadow-2xl">
        <h2 class="text-2xl font-bold mb-6 bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">
          {{ modalAction === 'create' ? 'Novo Usuário' : (modalAction === 'invite' ? 'Convidar Usuário' : 'Editar Usuário') }}
        </h2>
        
        <form @submit.prevent="handleSubmit" class="space-y-5">
          <div v-if="modalAction !== 'invite'">
            <label class="block text-[10px] font-bold tracking-widest uppercase text-gray-500 ml-1 mb-2">Nome Completo</label>
            <input 
              v-model="form.name"
              type="text"
              required
              class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white outline-none focus:border-purple-500/50 transition-all"
              placeholder="Ex: João Silva"
            >
          </div>

          <div>
            <label class="block text-[10px] font-bold tracking-widest uppercase text-gray-500 ml-1 mb-2">E-mail</label>
            <input 
              v-model="form.email"
              type="email"
              required
              class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white outline-none focus:border-purple-500/50 transition-all"
              placeholder="email@exemplo.com"
            >
          </div>

          <div v-if="modalAction === 'create'">
            <label class="block text-[10px] font-bold tracking-widest uppercase text-gray-500 ml-1 mb-2">Senha Provisória</label>
            <input 
              v-model="form.password"
              type="password"
              required
              minlength="6"
              class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white outline-none focus:border-purple-500/50 transition-all"
              placeholder="No mínimo 6 caracteres"
            >
          </div>

          <div>
            <label class="block text-[10px] font-bold tracking-widest uppercase text-gray-500 ml-1 mb-2">Nível de Acesso</label>
            <div class="grid grid-cols-2 gap-2">
              <button 
                v-for="r in roles" 
                :key="r.value"
                type="button"
                @click="form.role = r.value"
                class="px-3 py-2 rounded-xl border text-xs font-medium transition-all"
                :class="form.role === r.value ? 'bg-purple-600/20 border-purple-500 text-purple-300' : 'bg-white/5 border-white/10 text-gray-500 hover:border-white/20'"
              >
                {{ r.label }}
              </button>
            </div>
          </div>

          <!-- Acesso a Cursos — visível apenas para alunos em edição -->
          <div v-if="modalAction === 'edit' && form.role === 'aluno'" class="space-y-4 pt-2 border-t border-white/5">
            <p class="text-[10px] font-bold tracking-widest uppercase text-gray-500 mt-4">Acesso a Cursos</p>

            <!-- Modo de acesso -->
            <div class="space-y-2">
              <label
                v-for="opt in [
                  { value: 'all_courses', label: 'Todos os cursos' },
                  { value: 'specific', label: 'Cursos específicos' },
                  { value: 'groups_only', label: 'Somente via grupos' }
                ]"
                :key="opt.value"
                class="flex items-center gap-3 px-3 py-2.5 rounded-xl border cursor-pointer transition-all"
                :class="accessMode === opt.value ? 'border-purple-500/50 bg-purple-500/10' : 'border-white/5 hover:border-white/10'"
              >
                <input type="radio" :value="opt.value" v-model="accessMode" class="accent-purple-500" />
                <span class="text-sm text-gray-200">{{ opt.label }}</span>
              </label>
            </div>

            <!-- Checkboxes de cursos específicos -->
            <div v-if="accessMode === 'specific'" class="space-y-1.5 max-h-40 overflow-y-auto pr-1">
              <label
                v-for="course in allCourses"
                :key="course.id"
                class="flex items-center gap-3 px-3 py-2 rounded-xl border border-white/5 hover:border-white/10 cursor-pointer transition-all"
              >
                <input
                  type="checkbox"
                  :checked="selectedCourseIds.has(course.id)"
                  @change="toggleCourseId(course.id)"
                  class="w-4 h-4 accent-purple-500"
                />
                <span class="text-xs text-gray-300">{{ course.title }}</span>
              </label>
            </div>

            <!-- Grupos -->
            <div>
              <p class="text-[10px] font-bold tracking-widest uppercase text-gray-500 mb-2">Grupos</p>
              <div class="space-y-1.5 max-h-32 overflow-y-auto pr-1">
                <label
                  v-for="group in allGroups"
                  :key="group.id"
                  class="flex items-center gap-3 px-3 py-2 rounded-xl border border-white/5 hover:border-white/10 cursor-pointer transition-all"
                >
                  <input
                    type="checkbox"
                    :checked="selectedGroupIds.has(group.id)"
                    @change="toggleGroupId(group.id)"
                    class="w-4 h-4 accent-purple-500"
                  />
                  <span class="text-xs text-gray-300">{{ group.name }}</span>
                </label>
              </div>
              <p v-if="allGroups.length === 0" class="text-xs text-gray-600 italic mt-2">Nenhum grupo criado ainda.</p>
            </div>
          </div>

          <div class="flex gap-3 pt-4">
            <button
              type="button"
              @click="isModalOpen = false"
              class="flex-1 py-3 rounded-xl bg-white/5 hover:bg-white/10 text-white font-bold text-xs tracking-widest uppercase transition-all"
            >
              Cancelar
            </button>
            <button
              type="submit"
              :disabled="loading"
              class="flex-1 py-3 rounded-xl bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-500 hover:to-blue-500 text-white font-bold text-xs tracking-widest uppercase transition-all disabled:opacity-50"
            >
              {{ loading ? 'Processando...' : (modalAction === 'edit' ? 'Salvar' : 'Confirmar') }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<style scoped>
.glass-card {
  box-shadow: 0 40px 100px -20px rgba(0, 0, 0, 0.7);
}
</style>
