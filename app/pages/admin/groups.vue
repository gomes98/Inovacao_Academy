<script setup lang="ts">
const supabase = useSupabaseClient()

// ─── State ───────────────────────────────────────────────────
const groups = ref<any[]>([])
const allCourses = ref<any[]>([])
const allUsers = ref<any[]>([])
const loading = ref(true)

const selectedGroup = ref<any>(null)
const activeTab = ref<'courses' | 'members'>('courses')
const groupCourseIds = ref<Set<string>>(new Set())
const groupMemberIds = ref<Set<string>>(new Set())
const savingCourses = ref(false)
const savingMembers = ref(false)

const isCreateModalOpen = ref(false)
const newGroup = ref({ name: '', description: '' })
const creatingGroup = ref(false)

// ─── Fetch ────────────────────────────────────────────────────
async function fetchGroups() {
  loading.value = true
  const { data } = await supabase
    .from('permission_groups')
    .select(`
      id, name, description, created_at,
      group_course_access(count),
      user_groups(count)
    `)
    .order('created_at', { ascending: false })
  groups.value = data ?? []
  loading.value = false
}

async function fetchAllCourses() {
  const { data } = await supabase.from('courses').select('id, title').order('title')
  allCourses.value = data ?? []
}

async function fetchAllUsers() {
  const { data } = await supabase
    .from('perfis')
    .select('id, name, email')
    .eq('role', 'aluno')
    .order('name')
  allUsers.value = data ?? []
}

// ─── Selecionar grupo ────────────────────────────────────────
async function selectGroup(group: any) {
  selectedGroup.value = group
  activeTab.value = 'courses'

  const [{ data: gca }, { data: ug }] = await Promise.all([
    supabase.from('group_course_access').select('course_id').eq('group_id', group.id),
    supabase.from('user_groups').select('user_id').eq('group_id', group.id),
  ])
  groupCourseIds.value = new Set((gca ?? []).map((r: any) => r.course_id))
  groupMemberIds.value = new Set((ug ?? []).map((r: any) => r.user_id))
}

// ─── Salvar cursos do grupo ───────────────────────────────────
async function saveCourses() {
  if (!selectedGroup.value) return
  savingCourses.value = true

  await supabase.from('group_course_access').delete().eq('group_id', selectedGroup.value.id)

  if (groupCourseIds.value.size > 0) {
    const rows = Array.from(groupCourseIds.value).map(course_id => ({
      group_id: selectedGroup.value.id,
      course_id,
    }))
    await supabase.from('group_course_access').insert(rows)
  }

  savingCourses.value = false
  await fetchGroups()
}

// ─── Salvar membros do grupo ──────────────────────────────────
async function saveMembers() {
  if (!selectedGroup.value) return
  savingMembers.value = true

  await supabase.from('user_groups').delete().eq('group_id', selectedGroup.value.id)

  if (groupMemberIds.value.size > 0) {
    const rows = Array.from(groupMemberIds.value).map(user_id => ({
      group_id: selectedGroup.value.id,
      user_id,
    }))
    await supabase.from('user_groups').insert(rows)
  }

  savingMembers.value = false
  await fetchGroups()
}

// ─── Criar grupo ──────────────────────────────────────────────
async function createGroup() {
  if (!newGroup.value.name.trim()) return
  creatingGroup.value = true

  await supabase.from('permission_groups').insert({
    name: newGroup.value.name.trim(),
    description: newGroup.value.description.trim() || null,
  })

  newGroup.value = { name: '', description: '' }
  isCreateModalOpen.value = false
  creatingGroup.value = false
  await fetchGroups()
}

// ─── Excluir grupo ────────────────────────────────────────────
async function deleteGroup(groupId: string) {
  if (!confirm('Excluir este grupo? Os usuários perderão o acesso concedido por ele.')) return
  await supabase.from('permission_groups').delete().eq('id', groupId)
  if (selectedGroup.value?.id === groupId) selectedGroup.value = null
  await fetchGroups()
}

// ─── Toggle helpers ───────────────────────────────────────────
function toggleCourse(courseId: string) {
  if (groupCourseIds.value.has(courseId)) groupCourseIds.value.delete(courseId)
  else groupCourseIds.value.add(courseId)
  groupCourseIds.value = new Set(groupCourseIds.value)
}

function toggleMember(userId: string) {
  if (groupMemberIds.value.has(userId)) groupMemberIds.value.delete(userId)
  else groupMemberIds.value.add(userId)
  groupMemberIds.value = new Set(groupMemberIds.value)
}

// ─── Init ─────────────────────────────────────────────────────
onMounted(() => {
  fetchGroups()
  fetchAllCourses()
  fetchAllUsers()
})
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white font-sans selection:bg-purple-500/30">
    <div class="fixed inset-0 overflow-hidden pointer-events-none">
      <div class="absolute -top-[10%] -left-[10%] w-[40%] h-[40%] bg-purple-600/20 blur-[120px] rounded-full"></div>
      <div class="absolute bottom-[10%] -right-[10%] w-[30%] h-[30%] bg-blue-600/10 blur-[100px] rounded-full"></div>
    </div>

    <main class="relative z-10 max-w-7xl mx-auto p-8 pt-12">
      <!-- Header -->
      <div class="mb-10 flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div>
          <h1 class="text-4xl font-bold tracking-tight bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">
            Grupos de Permissão
          </h1>
          <p class="text-gray-400 mt-2">Crie grupos e defina quais cursos cada grupo pode acessar.</p>
        </div>
        <button
          @click="isCreateModalOpen = true"
          class="px-5 py-2.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-medium transition-all shadow-[0_0_20px_-5px_rgba(168,85,247,0.4)] flex items-center gap-2"
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
          Novo Grupo
        </button>
      </div>

      <div class="flex gap-6">
        <!-- Lista de grupos -->
        <div class="w-80 shrink-0 space-y-3">
          <div v-if="loading" v-for="i in 4" :key="i" class="h-20 rounded-2xl bg-white/5 animate-pulse"></div>

          <div v-else-if="groups.length === 0" class="text-center py-12 text-gray-500 italic text-sm">
            Nenhum grupo criado ainda.
          </div>

          <div
            v-for="g in groups"
            :key="g.id"
            @click="selectGroup(g)"
            class="p-4 rounded-2xl border cursor-pointer transition-all"
            :class="selectedGroup?.id === g.id
              ? 'border-purple-500/50 bg-purple-500/10'
              : 'border-white/10 bg-white/5 hover:border-white/20 hover:bg-white/[0.08]'"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="font-semibold text-white truncate">{{ g.name }}</p>
                <p v-if="g.description" class="text-xs text-gray-500 mt-0.5 truncate">{{ g.description }}</p>
                <div class="flex gap-3 mt-2">
                  <span class="text-[10px] text-gray-500">{{ g.group_course_access[0]?.count ?? 0 }} cursos</span>
                  <span class="text-[10px] text-gray-500">{{ g.user_groups[0]?.count ?? 0 }} membros</span>
                </div>
              </div>
              <button
                @click.stop="deleteGroup(g.id)"
                class="p-1.5 rounded-lg text-red-500/40 hover:text-red-500 hover:bg-red-500/10 transition-all shrink-0"
              >
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
              </button>
            </div>
          </div>
        </div>

        <!-- Painel do grupo selecionado -->
        <div v-if="selectedGroup" class="flex-1 rounded-3xl border border-white/10 bg-white/5 backdrop-blur-xl p-6">
          <h2 class="text-xl font-bold mb-1">{{ selectedGroup.name }}</h2>
          <p v-if="selectedGroup.description" class="text-sm text-gray-400 mb-5">{{ selectedGroup.description }}</p>

          <!-- Abas -->
          <div class="flex gap-1 mb-6 bg-white/5 p-1 rounded-xl w-fit">
            <button
              v-for="tab in [{ key: 'courses', label: 'Cursos' }, { key: 'members', label: 'Membros' }]"
              :key="tab.key"
              @click="activeTab = tab.key as 'courses' | 'members'"
              class="px-4 py-1.5 rounded-lg text-sm font-medium transition-all"
              :class="activeTab === tab.key ? 'bg-purple-600 text-white' : 'text-gray-400 hover:text-white'"
            >
              {{ tab.label }}
            </button>
          </div>

          <!-- Aba Cursos -->
          <div v-if="activeTab === 'courses'">
            <p class="text-xs text-gray-500 uppercase tracking-widest font-bold mb-4">Selecione os cursos que este grupo acessa</p>
            <div class="space-y-2 mb-6 max-h-80 overflow-y-auto pr-1">
              <label
                v-for="course in allCourses"
                :key="course.id"
                class="flex items-center gap-3 p-3 rounded-xl border border-white/5 hover:border-white/10 hover:bg-white/5 cursor-pointer transition-all"
              >
                <input
                  type="checkbox"
                  :checked="groupCourseIds.has(course.id)"
                  @change="toggleCourse(course.id)"
                  class="w-4 h-4 accent-purple-500"
                />
                <span class="text-sm text-gray-200">{{ course.title }}</span>
              </label>
            </div>
            <button
              @click="saveCourses"
              :disabled="savingCourses"
              class="px-6 py-2.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-medium text-sm transition-all disabled:opacity-50"
            >
              {{ savingCourses ? 'Salvando...' : 'Salvar Cursos' }}
            </button>
          </div>

          <!-- Aba Membros -->
          <div v-if="activeTab === 'members'">
            <p class="text-xs text-gray-500 uppercase tracking-widest font-bold mb-4">Selecione os alunos membros deste grupo</p>
            <div class="space-y-2 mb-6 max-h-80 overflow-y-auto pr-1">
              <label
                v-for="u in allUsers"
                :key="u.id"
                class="flex items-center gap-3 p-3 rounded-xl border border-white/5 hover:border-white/10 hover:bg-white/5 cursor-pointer transition-all"
              >
                <input
                  type="checkbox"
                  :checked="groupMemberIds.has(u.id)"
                  @change="toggleMember(u.id)"
                  class="w-4 h-4 accent-purple-500"
                />
                <div>
                  <p class="text-sm text-gray-200">{{ u.name }}</p>
                  <p class="text-xs text-gray-500">{{ u.email }}</p>
                </div>
              </label>
            </div>
            <button
              @click="saveMembers"
              :disabled="savingMembers"
              class="px-6 py-2.5 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-medium text-sm transition-all disabled:opacity-50"
            >
              {{ savingMembers ? 'Salvando...' : 'Salvar Membros' }}
            </button>
          </div>
        </div>

        <!-- Placeholder quando nenhum grupo selecionado -->
        <div v-else class="flex-1 rounded-3xl border-2 border-dashed border-white/5 flex items-center justify-center">
          <p class="text-gray-600 text-sm">Selecione um grupo para configurar</p>
        </div>
      </div>
    </main>

    <!-- Modal criar grupo -->
    <div v-if="isCreateModalOpen" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/80 backdrop-blur-sm" @click="isCreateModalOpen = false"></div>
      <div class="relative w-full max-w-md rounded-3xl border border-white/10 bg-[#0c0c0c] p-8 shadow-2xl">
        <h2 class="text-2xl font-bold mb-6 bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">Novo Grupo</h2>
        <form @submit.prevent="createGroup" class="space-y-5">
          <div>
            <label class="block text-[10px] font-bold tracking-widest uppercase text-gray-500 ml-1 mb-2">Nome do Grupo</label>
            <input
              v-model="newGroup.name"
              type="text"
              required
              class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white outline-none focus:border-purple-500/50 transition-all"
              placeholder="Ex: Time de Vendas"
            />
          </div>
          <div>
            <label class="block text-[10px] font-bold tracking-widest uppercase text-gray-500 ml-1 mb-2">Descrição (opcional)</label>
            <input
              v-model="newGroup.description"
              type="text"
              class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 text-white outline-none focus:border-purple-500/50 transition-all"
              placeholder="Ex: Acesso aos cursos de vendas"
            />
          </div>
          <div class="flex gap-3 pt-2">
            <button type="button" @click="isCreateModalOpen = false" class="flex-1 py-3 rounded-xl bg-white/5 hover:bg-white/10 text-white font-bold text-xs tracking-widest uppercase transition-all">Cancelar</button>
            <button type="submit" :disabled="creatingGroup" class="flex-1 py-3 rounded-xl bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-500 hover:to-blue-500 text-white font-bold text-xs tracking-widest uppercase transition-all disabled:opacity-50">
              {{ creatingGroup ? 'Criando...' : 'Criar Grupo' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
