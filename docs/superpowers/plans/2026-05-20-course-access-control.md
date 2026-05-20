# Course Access Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar controle de acesso por curso via RLS no Supabase, com grupos de permissão e configuração individual por aluno gerenciada no painel admin.

**Architecture:** Cinco novas tabelas no banco (`user_access_mode`, `user_course_access`, `permission_groups`, `group_course_access`, `user_groups`) com RLS em `courses` contendo toda a lógica de filtro. A view `course_catalog` herda o RLS automaticamente — o frontend existente não muda. O admin gerencia permissões via extensão do modal de usuário e nova página `/admin/groups`.

**Tech Stack:** Nuxt 4, Vue 3, TypeScript, Supabase (PostgreSQL + RLS), Tailwind CSS v4, `@nuxtjs/supabase`

---

## Mapa de Arquivos

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `supabase/migrations/20260520200000_course_access_control.sql` | Criar | Tabelas, RLS, policies |
| `app/types/database.types.ts` | Regenerar | Tipos TypeScript atualizados |
| `app/pages/admin/groups.vue` | Criar | Página de gestão de grupos |
| `app/pages/admin/users.vue` | Modificar | Adicionar seção de acesso ao modal de edição |

---

## Task 1: Migration SQL — Tabelas e RLS

**Files:**
- Create: `supabase/migrations/20260520200000_course_access_control.sql`

- [ ] **Step 1: Criar o arquivo de migration**

Crie o arquivo `supabase/migrations/20260520200000_course_access_control.sql` com o conteúdo abaixo:

```sql
-- =============================================================================
-- Course Access Control — Tabelas de permissão e RLS
-- =============================================================================

-- ------------------------------------------------------------
-- TABELAS
-- ------------------------------------------------------------

-- Modo geral de acesso do aluno (default: restricted = sem acesso)
CREATE TABLE IF NOT EXISTS public.user_access_mode (
  user_id uuid PRIMARY KEY REFERENCES public.perfis(id) ON DELETE CASCADE,
  mode    text NOT NULL DEFAULT 'restricted'
            CHECK (mode IN ('all_courses', 'restricted'))
);

-- Acesso individual a cursos específicos
CREATE TABLE IF NOT EXISTS public.user_course_access (
  user_id   uuid REFERENCES public.perfis(id)   ON DELETE CASCADE,
  course_id uuid REFERENCES public.courses(id)  ON DELETE CASCADE,
  PRIMARY KEY (user_id, course_id)
);

-- Grupos de permissão
CREATE TABLE IF NOT EXISTS public.permission_groups (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Cursos que um grupo pode acessar
CREATE TABLE IF NOT EXISTS public.group_course_access (
  group_id  uuid REFERENCES public.permission_groups(id) ON DELETE CASCADE,
  course_id uuid REFERENCES public.courses(id)           ON DELETE CASCADE,
  PRIMARY KEY (group_id, course_id)
);

-- Usuários que pertencem a um grupo
CREATE TABLE IF NOT EXISTS public.user_groups (
  user_id  uuid REFERENCES public.perfis(id)           ON DELETE CASCADE,
  group_id uuid REFERENCES public.permission_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, group_id)
);

-- ------------------------------------------------------------
-- RLS — HABILITAR
-- ------------------------------------------------------------

ALTER TABLE public.user_access_mode    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_course_access  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permission_groups   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_course_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_groups         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.courses             ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------
-- POLICIES — user_access_mode
-- ------------------------------------------------------------

CREATE POLICY "user_access_mode_select_own"
  ON public.user_access_mode FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "user_access_mode_admin_all"
  ON public.user_access_mode FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICIES — user_course_access
-- ------------------------------------------------------------

CREATE POLICY "user_course_access_select_own"
  ON public.user_course_access FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "user_course_access_admin_all"
  ON public.user_course_access FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICIES — permission_groups
-- ------------------------------------------------------------

CREATE POLICY "permission_groups_select_authenticated"
  ON public.permission_groups FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "permission_groups_admin_all"
  ON public.permission_groups FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICIES — group_course_access
-- ------------------------------------------------------------

CREATE POLICY "group_course_access_select_authenticated"
  ON public.group_course_access FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "group_course_access_admin_all"
  ON public.group_course_access FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICIES — user_groups
-- ------------------------------------------------------------

CREATE POLICY "user_groups_select_own"
  ON public.user_groups FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "user_groups_admin_all"
  ON public.user_groups FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- ------------------------------------------------------------
-- POLICY — courses SELECT (lógica central de acesso)
-- ------------------------------------------------------------

-- Garante que admins sempre vejam tudo mesmo com RLS ativo
CREATE POLICY "courses_admin_all"
  ON public.courses FOR ALL
  USING (has_role(ARRAY['admin']))
  WITH CHECK (has_role(ARRAY['admin']));

-- Policy de SELECT para todos os usuários autenticados
CREATE POLICY "courses_access"
  ON public.courses FOR SELECT
  USING (
    -- Publicador vê tudo
    has_role(ARRAY['publicador'])

    -- Aluno com mode = 'all_courses'
    OR EXISTS (
      SELECT 1 FROM public.user_access_mode
      WHERE user_id = auth.uid() AND mode = 'all_courses'
    )

    -- Acesso individual ao curso
    OR EXISTS (
      SELECT 1 FROM public.user_course_access
      WHERE user_id = auth.uid() AND course_id = courses.id
    )

    -- Acesso via grupo
    OR EXISTS (
      SELECT 1 FROM public.user_groups ug
      JOIN public.group_course_access gca ON gca.group_id = ug.group_id
      WHERE ug.user_id = auth.uid() AND gca.course_id = courses.id
    )
  );
```

- [ ] **Step 2: Aplicar a migration no Supabase**

Execute via CLI do Supabase:

```bash
supabase db push
```

Saída esperada: `Applying migration 20260520200000_course_access_control.sql... done`

Se não tiver o CLI linkado ao projeto, use o MCP do Supabase via `mcp__supabase__apply_migration` passando o conteúdo SQL acima.

- [ ] **Step 3: Verificar no Supabase Dashboard**

No Table Editor, confirme que as 5 tabelas existem: `user_access_mode`, `user_course_access`, `permission_groups`, `group_course_access`, `user_groups`. Em Authentication > Policies, confirme que `courses` tem as policies `courses_admin_all` e `courses_access`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260520200000_course_access_control.sql
git commit -m "feat: add course access control migration with RLS policies"
```

---

## Task 2: Regenerar Types TypeScript

**Files:**
- Modify: `app/types/database.types.ts`

- [ ] **Step 1: Regenerar os tipos**

```bash
supabase gen types typescript --linked > app/types/database.types.ts
```

Se não tiver o CLI configurado, faça via Dashboard: Settings > API > Generate TypeScript types e substitua o conteúdo de `app/types/database.types.ts`.

- [ ] **Step 2: Verificar que os novos tipos aparecem**

Abra `app/types/database.types.ts` e confirme a presença de:
- `permission_groups` na seção `Tables`
- `user_access_mode` na seção `Tables`
- `user_course_access` na seção `Tables`
- `group_course_access` na seção `Tables`
- `user_groups` na seção `Tables`

- [ ] **Step 3: Commit**

```bash
git add app/types/database.types.ts
git commit -m "chore: regenerate database types with access control tables"
```

---

## Task 3: Página `/admin/groups`

**Files:**
- Create: `app/pages/admin/groups.vue`

Esta página lista todos os grupos e permite criar, editar e excluir grupos. Ao clicar em um grupo, um painel lateral exibe duas abas: Cursos e Membros.

- [ ] **Step 1: Criar o arquivo da página**

Crie `app/pages/admin/groups.vue` com o conteúdo completo abaixo:

```vue
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
```

- [ ] **Step 2: Verificar que a página carrega**

Inicie o servidor de desenvolvimento e acesse `http://localhost:3000/admin/groups` com um usuário admin. Confirme:
- A lista de grupos aparece (vazia inicialmente)
- O botão "Novo Grupo" abre o modal
- Criar um grupo o adiciona à lista
- Clicar no grupo abre o painel com as abas Cursos e Membros

```bash
npm run dev
```

- [ ] **Step 3: Commit**

```bash
git add app/pages/admin/groups.vue
git commit -m "feat: add /admin/groups page for permission group management"
```

---

## Task 4: Extensão do Modal de Usuário — Seção de Acesso a Cursos

**Files:**
- Modify: `app/pages/admin/users.vue`

Adicionar ao modal de edição de usuário uma seção "Acesso a Cursos" visível apenas quando `role === 'aluno'`. A seção tem: seletor de modo (todos / específicos / grupos), checkboxes de cursos quando modo = específicos, e gerenciamento de grupos.

- [ ] **Step 1: Adicionar estado e funções ao `<script setup>`**

No bloco `<script setup lang="ts">` de `app/pages/admin/users.vue`, adicione após a declaração das variáveis existentes (`const roles = [...]`):

```typescript
// ─── Dados para a seção de acesso ────────────────────────────
const allCourses = ref<any[]>([])
const allGroups = ref<any[]>([])

// Estado de acesso do usuário em edição
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

  // Salva o mode
  await supabase.from('user_access_mode').upsert({
    user_id: userId,
    mode: accessMode.value === 'all_courses' ? 'all_courses' : 'restricted',
  })

  // Salva cursos individuais (limpa e reinserir)
  await supabase.from('user_course_access').delete().eq('user_id', userId)
  if (accessMode.value === 'specific' && selectedCourseIds.value.size > 0) {
    const rows = Array.from(selectedCourseIds.value).map(course_id => ({ user_id: userId, course_id }))
    await supabase.from('user_course_access').insert(rows)
  }

  // Salva grupos (limpa e reinserir)
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
```

- [ ] **Step 2: Atualizar `openModal` para carregar dados de acesso**

Localize a função `openModal` existente e substitua-a por:

```typescript
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
```

- [ ] **Step 3: Atualizar `handleSubmit` para salvar o acesso**

Localize `handleSubmit` e adicione a chamada `saveUserAccess` após o sucesso, antes do `alert`:

```typescript
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

    // Salva configurações de acesso ao salvar um aluno editado
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
```

- [ ] **Step 4: Adicionar a seção de acesso ao `<template>` do modal**

No `<template>`, dentro do `<form>`, localize o bloco que contém `<!-- Nível de Acesso -->` (o grid de botões de role) e adicione após ele, antes do `<div class="flex gap-3 pt-4">` dos botões de submit:

```html
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
```

- [ ] **Step 5: Verificar o modal de edição**

Com `npm run dev` rodando, acesse `/admin/users`, edite um aluno e confirme:
- A seção "Acesso a Cursos" aparece
- Os três modos de rádio funcionam
- Selecionar "Cursos específicos" mostra os checkboxes de cursos
- A seção "Grupos" lista os grupos criados
- Salvar persiste no banco (verifique as tabelas `user_access_mode`, `user_course_access`, `user_groups` no Supabase)
- A seção **não** aparece ao editar um admin ou publicador

- [ ] **Step 6: Commit**

```bash
git add app/pages/admin/users.vue
git commit -m "feat: add course access section to user edit modal"
```

---

## Task 5: Verificação end-to-end do RLS

Esta task valida que a segurança no banco funciona corretamente para todos os cenários.

- [ ] **Step 1: Testar aluno sem permissão**

No Supabase Dashboard, crie ou use um aluno existente sem nenhuma entrada em `user_access_mode`, `user_course_access` ou `user_groups`. Faça login com ele e acesse `/`. Resultado esperado: nenhum curso visível, mensagem "Nenhum curso disponível".

- [ ] **Step 2: Testar aluno com `all_courses`**

No modal de edição do aluno, selecione "Todos os cursos" e salve. Faça login com ele. Resultado esperado: todos os cursos visíveis.

- [ ] **Step 3: Testar acesso individual**

Mude o aluno para "Cursos específicos" e selecione apenas um curso. Faça login. Resultado esperado: apenas o curso selecionado aparece.

- [ ] **Step 4: Testar acesso via grupo**

Em `/admin/groups`, crie um grupo, adicione um curso diferente do Step 3, e adicione o aluno como membro. Volte ao modal do aluno e mude para "Somente via grupos". Faça login. Resultado esperado: apenas o curso do grupo aparece.

- [ ] **Step 5: Testar acesso aditivo (individual + grupo)**

Mude o aluno de volta para "Cursos específicos" com o curso do Step 3 selecionado, e mantenha ele no grupo do Step 4. Faça login. Resultado esperado: os dois cursos aparecem (união).

- [ ] **Step 6: Confirmar que admin e publicador não são afetados**

Faça login com um admin e um publicador. Ambos devem ver todos os cursos sem nenhuma configuração adicional.

- [ ] **Step 7: Commit final**

```bash
git add .
git commit -m "feat: complete course access control system"
```

---

## Referência rápida de tipos usados

| Variável | Tipo |
|----------|------|
| `accessMode` | `'all_courses' \| 'specific' \| 'groups_only'` |
| `selectedCourseIds` | `Set<string>` |
| `selectedGroupIds` | `Set<string>` |
| `groupCourseIds` | `Set<string>` |
| `groupMemberIds` | `Set<string>` |
| `allCourses` | `{ id: string, title: string }[]` |
| `allGroups` | `{ id: string, name: string }[]` |
| `groups` | `any[]` (inclui contagens via relacionamento) |
