# Search Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar busca híbrida (full-text + semântica) sobre transcrições de vídeo à AppBar do LMS, com escopo contextual por curso.

**Architecture:** O endpoint `GET /api/search` recebe a query, gera um embedding via OpenAI `text-embedding-3-small`, executa duas queries no Supabase (pgvector cosine similarity + ILIKE), une e deduplica os resultados, retornando os 10 mais relevantes. O componente `SearchBar` na AppBar detecta o curso atual via composable e exibe um dropdown com resultados clicáveis que redirecionam para `/lesson/[id]?t=<segundos>`. O VideoPlayer já existente recebe uma nova prop `startTime` para posicionar o vídeo no timestamp correto.

**Tech Stack:** Nuxt 4, Vue 3, TypeScript, Supabase (pgvector), OpenAI SDK (`openai` npm), Tailwind CSS v4

---

## Mapa de Arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `nuxt.config.ts` | Modificar | Adicionar `runtimeConfig.openaiApiKey` |
| `server/api/search.get.ts` | Criar | Endpoint de busca híbrida |
| `app/composables/useCurrentCourseId.ts` | Criar | Detecta courseId pelo contexto da rota |
| `app/composables/useSearch.ts` | Criar | Lógica de busca com debounce, estado e chamada à API |
| `app/components/SearchBar.vue` | Criar | Input expansível + dropdown de resultados |
| `app/components/AppBar.vue` | Modificar | Incluir `<SearchBar>` quando usuário está autenticado |
| `app/pages/lesson/[id].vue` | Modificar | Popula `useState('currentCourseId')` + passa `startTime` ao VideoPlayer |
| `app/components/VideoPlayer.vue` | Modificar | Aceita prop `startTime` e posiciona o vídeo após `ready` |

---

## Task 1: Configurar runtimeConfig e instalar dependência OpenAI

**Files:**
- Modify: `nuxt.config.ts`
- Modify: `package.json` (via npm install)

- [ ] **Step 1: Instalar o SDK da OpenAI**

```bash
cd c:\DEV\Antigravity\Inovacao_Academy
npm install openai
```

Esperado: `added 1 package` (ou similar) sem erros.

- [ ] **Step 2: Adicionar `runtimeConfig` ao nuxt.config.ts**

Substituir o conteúdo de `nuxt.config.ts` por:

```typescript
// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  modules: ['@nuxtjs/supabase', '@nuxtjs/tailwindcss'],
  runtimeConfig: {
    openaiApiKey: process.env.OPENAI_API_KEY,
  },
  supabase: {
    redirect: true,
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      exclude: [],
    }
  },
  build: {
    transpile: [
      'videojs-vimeo',
      'videojs-youtube',
      'videojs-contrib-quality-levels',
      'videojs-hls-quality-selector'
    ]
  },
  css: [
    'video.js/dist/video-js.css'
  ],
  vite: {
    optimizeDeps: {
      include: [
        'video.js',
        'videojs-youtube',
        'videojs-vimeo',
        'videojs-contrib-quality-levels',
        'videojs-hls-quality-selector'
      ]
    }
  }
})
```

- [ ] **Step 3: Confirmar que `OPENAI_API_KEY` está no `.env`**

Verificar que `.env` já contém a linha (não adicionar a chave no plano por segurança):
```
OPENAI_API_KEY=sk-proj-...
```

- [ ] **Step 4: Commit**

```bash
git add nuxt.config.ts package.json package-lock.json
git commit -m "feat: add openai sdk and runtimeConfig for search endpoint"
```

---

## Task 2: Criar endpoint de busca híbrida

**Files:**
- Create: `server/api/search.get.ts`

Este endpoint recebe `q` (query) e `courseId` (opcional), gera embedding da query via OpenAI, executa busca semântica e full-text no Supabase, une os resultados e retorna os 10 melhores.

- [ ] **Step 1: Criar o arquivo `server/api/search.get.ts`**

```typescript
import OpenAI from 'openai'
import { createClient } from '@supabase/supabase-js'

export interface SearchResult {
  contentId: string
  contentTitle: string
  thumbnailUrl: string | null
  moduleName: string
  courseName: string
  chunkText: string
  startTime: number
  matchType: 'semantic' | 'fulltext'
}

export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig()
  const query = getQuery(event)

  const q = String(query.q || '').trim()
  const courseId = query.courseId ? String(query.courseId) : null

  if (q.length < 2) {
    return []
  }

  const supabaseUrl = process.env.SUPABASE_URL!
  const supabaseKey = process.env.SUPABASE_KEY!
  const supabase = createClient(supabaseUrl, supabaseKey)

  // --- Busca full-text (ILIKE) ---
  const fulltextQuery = supabase.rpc('search_content_fulltext', {
    search_query: q,
    filter_course_id: courseId,
  })

  // --- Busca semântica (pgvector) ---
  let semanticRows: any[] = []
  try {
    const openai = new OpenAI({ apiKey: config.openaiApiKey })
    const embeddingRes = await openai.embeddings.create({
      model: 'text-embedding-3-small',
      input: q,
    })
    const vector = embeddingRes.data[0].embedding

    const { data: semData } = await supabase.rpc('search_content_semantic', {
      query_embedding: vector,
      filter_course_id: courseId,
      match_count: 20,
    })
    semanticRows = semData || []
  } catch {
    // fallback silencioso para apenas full-text se OpenAI falhar
  }

  const { data: fulltextRows } = await fulltextQuery

  // --- União e deduplicação ---
  // full-text tem prioridade: se chunk_id aparece nos dois, fica como 'fulltext'
  const seen = new Set<string>()
  const merged: SearchResult[] = []

  for (const row of (fulltextRows || [])) {
    if (seen.has(row.chunk_id)) continue
    seen.add(row.chunk_id)
    merged.push({
      contentId: row.content_id,
      contentTitle: row.content_title,
      thumbnailUrl: row.thumbnail_url,
      moduleName: row.module_title,
      courseName: row.course_title,
      chunkText: row.chunk_text,
      startTime: Number(row.start_time),
      matchType: 'fulltext',
    })
  }

  for (const row of semanticRows) {
    if (seen.has(row.chunk_id)) continue
    seen.add(row.chunk_id)
    merged.push({
      contentId: row.content_id,
      contentTitle: row.content_title,
      thumbnailUrl: row.thumbnail_url,
      moduleName: row.module_title,
      courseName: row.course_title,
      chunkText: row.chunk_text,
      startTime: Number(row.start_time),
      matchType: 'semantic',
    })
  }

  return merged.slice(0, 10)
})
```

- [ ] **Step 2: Commit**

```bash
git add server/api/search.get.ts
git commit -m "feat: add hybrid search API endpoint (fulltext + semantic)"
```

---

## Task 3: Criar funções SQL no Supabase

As queries de busca são encapsuladas em funções Postgres para reutilização e para evitar SQL dinâmico no servidor.

- [ ] **Step 1: Criar migration com as duas funções**

Criar o arquivo `supabase/migrations/20260520100000_search_functions.sql`:

```sql
-- Busca full-text por transcrições
CREATE OR REPLACE FUNCTION search_content_fulltext(
  search_query text,
  filter_course_id uuid DEFAULT NULL
)
RETURNS TABLE (
  chunk_id    uuid,
  content_id  uuid,
  chunk_text  text,
  start_time  numeric,
  content_title text,
  thumbnail_url text,
  module_title  text,
  course_title  text
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    cc.id          AS chunk_id,
    cc.content_id,
    cc.text        AS chunk_text,
    cc.start_time,
    c.title        AS content_title,
    co.thumbnail_url,
    m.title        AS module_title,
    co.title       AS course_title
  FROM content_chunks cc
  JOIN contents c  ON c.id  = cc.content_id
  JOIN modules  m  ON m.id  = c.module_id
  JOIN courses  co ON co.id = m.course_id
  WHERE cc.text ILIKE '%' || search_query || '%'
    AND (filter_course_id IS NULL OR co.id = filter_course_id)
  ORDER BY co.title, m.order_index, c.order_index, cc.start_time
  LIMIT 20;
$$;

-- Busca semântica por embeddings (pgvector)
CREATE OR REPLACE FUNCTION search_content_semantic(
  query_embedding vector(1536),
  filter_course_id uuid DEFAULT NULL,
  match_count int DEFAULT 20
)
RETURNS TABLE (
  chunk_id    uuid,
  content_id  uuid,
  chunk_text  text,
  start_time  numeric,
  content_title text,
  thumbnail_url text,
  module_title  text,
  course_title  text,
  distance    float
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    cc.id          AS chunk_id,
    cc.content_id,
    cc.text        AS chunk_text,
    cc.start_time,
    c.title        AS content_title,
    co.thumbnail_url,
    m.title        AS module_title,
    co.title       AS course_title,
    (cc.embedding <=> query_embedding) AS distance
  FROM content_chunks cc
  JOIN contents c  ON c.id  = cc.content_id
  JOIN modules  m  ON m.id  = c.module_id
  JOIN courses  co ON co.id = m.course_id
  WHERE cc.embedding IS NOT NULL
    AND (filter_course_id IS NULL OR co.id = filter_course_id)
  ORDER BY distance ASC
  LIMIT match_count;
$$;
```

- [ ] **Step 2: Aplicar a migration ao Supabase**

Via MCP (Supabase tool `apply_migration`) ou via CLI:
```bash
supabase db push
```

Confirmar que as funções foram criadas sem erros.

- [ ] **Step 3: Testar as funções no SQL Editor do Supabase**

```sql
-- Teste full-text
SELECT * FROM search_content_fulltext('git', NULL) LIMIT 3;

-- Teste semântico (substitua o vetor por um real se necessário)
-- SELECT * FROM search_content_semantic('[0.1, 0.2, ...]'::vector(1536), NULL, 5);
```

Esperado: retorno de linhas com `chunk_id`, `content_title`, `start_time`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260520100000_search_functions.sql
git commit -m "feat: add SQL functions for fulltext and semantic content search"
```

---

## Task 4: Criar composable `useCurrentCourseId`

**Files:**
- Create: `app/composables/useCurrentCourseId.ts`

- [ ] **Step 1: Criar o arquivo**

```typescript
// app/composables/useCurrentCourseId.ts
export function useCurrentCourseId(): string | undefined {
  const route = useRoute()

  if (route.name === 'courses-id') {
    return route.params.id as string
  }

  if (route.name === 'lesson-id') {
    return useState<string | undefined>('currentCourseId').value
  }

  return undefined
}
```

- [ ] **Step 2: Commit**

```bash
git add app/composables/useCurrentCourseId.ts
git commit -m "feat: add useCurrentCourseId composable for contextual search scope"
```

---

## Task 5: Criar composable `useSearch`

**Files:**
- Create: `app/composables/useSearch.ts`

Encapsula o estado da busca, debounce de 400ms e chamada à API.

- [ ] **Step 1: Criar o arquivo**

```typescript
// app/composables/useSearch.ts
import type { SearchResult } from '~/server/api/search.get'

export function useSearch() {
  const query = ref('')
  const results = ref<SearchResult[]>([])
  const isLoading = ref(false)
  const error = ref<string | null>(null)
  const courseId = useCurrentCourseId()

  let debounceTimer: ReturnType<typeof setTimeout> | null = null
  let abortController: AbortController | null = null

  async function performSearch(q: string) {
    if (q.length < 2) {
      results.value = []
      return
    }

    isLoading.value = true
    error.value = null

    // Aborta request anterior se ainda estiver em andamento
    abortController?.abort()
    abortController = new AbortController()

    const timeout = setTimeout(() => abortController?.abort(), 5000)

    try {
      const params = new URLSearchParams({ q })
      if (courseId) params.set('courseId', courseId)

      const data = await $fetch<SearchResult[]>(`/api/search?${params}`, {
        signal: abortController.signal,
      })
      results.value = data
    } catch (err: any) {
      if (err?.name !== 'AbortError') {
        error.value = 'Erro ao buscar. Tente novamente.'
      }
      results.value = []
    } finally {
      clearTimeout(timeout)
      isLoading.value = false
    }
  }

  watch(query, (q) => {
    if (debounceTimer) clearTimeout(debounceTimer)
    if (q.length < 2) {
      results.value = []
      isLoading.value = false
      return
    }
    debounceTimer = setTimeout(() => performSearch(q), 400)
  })

  function clear() {
    query.value = ''
    results.value = []
    error.value = null
    abortController?.abort()
  }

  return { query, results, isLoading, error, clear }
}
```

- [ ] **Step 2: Commit**

```bash
git add app/composables/useSearch.ts
git commit -m "feat: add useSearch composable with debounce and abort controller"
```

---

## Task 6: Criar componente `SearchBar`

**Files:**
- Create: `app/components/SearchBar.vue`

Input expansível + dropdown com resultados. Segue o visual dark/glassmorphism do projeto.

- [ ] **Step 1: Criar o arquivo**

```vue
<script setup lang="ts">
const { query, results, isLoading, error, clear } = useSearch()
const isOpen = ref(false)
const inputRef = ref<HTMLInputElement | null>(null)

function open() {
  isOpen.value = true
  nextTick(() => inputRef.value?.focus())
}

function close() {
  isOpen.value = false
  clear()
}

function handleBlur() {
  // Delay para permitir clique nos resultados antes de fechar
  setTimeout(() => {
    if (!query.value) close()
  }, 150)
}

function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') close()
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = Math.floor(seconds % 60).toString().padStart(2, '0')
  return `${m}:${s}`
}

function truncate(text: string, max = 80): string {
  return text.length > max ? text.slice(0, max) + '…' : text
}

const showDropdown = computed(() =>
  isOpen.value && query.value.length >= 2
)
</script>

<template>
  <div class="search-container" @keydown="handleKeydown">
    <!-- Ícone de lupa (fechado) -->
    <button v-if="!isOpen" class="search-icon-btn" @click="open" aria-label="Buscar">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"
        fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
      </svg>
    </button>

    <!-- Input expandido -->
    <div v-else class="search-expanded">
      <svg class="search-icon-inline" xmlns="http://www.w3.org/2000/svg" width="16" height="16"
        viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
        stroke-linecap="round" stroke-linejoin="round">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
      </svg>
      <input
        ref="inputRef"
        v-model="query"
        type="text"
        placeholder="Buscar conteúdo..."
        class="search-input"
        @blur="handleBlur"
      />
      <button class="close-btn" @mousedown.prevent="close" aria-label="Fechar busca">
        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24"
          fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
          <path d="M18 6 6 18M6 6l12 12"/>
        </svg>
      </button>

      <!-- Dropdown de resultados -->
      <Transition name="dropdown">
        <div v-if="showDropdown" class="results-dropdown">
          <!-- Carregando -->
          <div v-if="isLoading" class="results-list">
            <div v-for="i in 3" :key="i" class="skeleton-item">
              <div class="skeleton-thumb"></div>
              <div class="skeleton-text">
                <div class="skeleton-line w-3/4"></div>
                <div class="skeleton-line w-1/2"></div>
                <div class="skeleton-line w-full"></div>
              </div>
            </div>
          </div>

          <!-- Erro -->
          <div v-else-if="error" class="results-empty">{{ error }}</div>

          <!-- Sem resultados -->
          <div v-else-if="results.length === 0" class="results-empty">
            Nenhum resultado para «{{ query }}»
          </div>

          <!-- Resultados -->
          <div v-else class="results-list">
            <NuxtLink
              v-for="r in results"
              :key="`${r.contentId}-${r.startTime}`"
              :to="`/lesson/${r.contentId}?t=${Math.floor(r.startTime)}`"
              class="result-item"
              @click="close"
            >
              <!-- Thumbnail -->
              <div class="result-thumb">
                <img v-if="r.thumbnailUrl" :src="r.thumbnailUrl" :alt="r.contentTitle" />
                <div v-else class="thumb-fallback">
                  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"
                    fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
                    <polygon points="5 3 19 12 5 21 5 3"/>
                  </svg>
                </div>
              </div>
              <!-- Texto -->
              <div class="result-text">
                <span class="result-title">{{ r.contentTitle }}</span>
                <span class="result-meta">{{ r.moduleName }} · {{ r.courseName }}</span>
                <span class="result-chunk">
                  "{{ truncate(r.chunkText) }}"
                  <span class="result-time">⏱ {{ formatTime(r.startTime) }}</span>
                </span>
              </div>
            </NuxtLink>
          </div>
        </div>
      </Transition>
    </div>
  </div>
</template>

<style scoped>
.search-container {
  position: relative;
  display: flex;
  align-items: center;
}

.search-icon-btn {
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 99px;
  width: 38px;
  height: 38px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  color: rgba(255,255,255,0.7);
  transition: all 0.2s ease;
}
.search-icon-btn:hover {
  background: rgba(255,255,255,0.1);
  color: white;
}

.search-expanded {
  position: relative;
  display: flex;
  align-items: center;
  gap: 8px;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(168,85,247,0.4);
  border-radius: 99px;
  padding: 6px 12px;
  width: 280px;
  transition: width 0.2s ease;
}

.search-icon-inline {
  color: rgba(255,255,255,0.4);
  flex-shrink: 0;
}

.search-input {
  background: transparent;
  border: none;
  outline: none;
  color: white;
  font-size: 0.875rem;
  width: 100%;
}
.search-input::placeholder {
  color: rgba(255,255,255,0.3);
}

.close-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: rgba(255,255,255,0.4);
  display: flex;
  align-items: center;
  flex-shrink: 0;
  padding: 2px;
  transition: color 0.15s;
}
.close-btn:hover { color: white; }

/* Dropdown */
.results-dropdown {
  position: absolute;
  top: calc(100% + 10px);
  left: 50%;
  transform: translateX(-50%);
  width: 420px;
  background: #111;
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px;
  padding: 8px;
  box-shadow: 0 20px 40px rgba(0,0,0,0.5);
  z-index: 1100;
  max-height: 440px;
  overflow-y: auto;
}

.results-list {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.results-empty {
  padding: 20px;
  text-align: center;
  color: rgba(255,255,255,0.4);
  font-size: 0.875rem;
}

.result-item {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 10px;
  border-radius: 10px;
  text-decoration: none;
  transition: background 0.15s;
  cursor: pointer;
}
.result-item:hover { background: rgba(255,255,255,0.05); }

.result-thumb {
  width: 48px;
  height: 48px;
  border-radius: 8px;
  overflow: hidden;
  flex-shrink: 0;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.08);
  display: flex;
  align-items: center;
  justify-content: center;
}
.result-thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.thumb-fallback { color: rgba(255,255,255,0.3); }

.result-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.result-title {
  font-size: 0.875rem;
  font-weight: 600;
  color: white;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.result-meta {
  font-size: 0.75rem;
  color: rgba(255,255,255,0.4);
}
.result-chunk {
  font-size: 0.75rem;
  color: rgba(255,255,255,0.55);
  line-height: 1.4;
}
.result-time {
  color: #a855f7;
  font-weight: 600;
  margin-left: 6px;
}

/* Skeletons */
.skeleton-item {
  display: flex;
  gap: 12px;
  padding: 10px;
  align-items: flex-start;
}
.skeleton-thumb {
  width: 48px;
  height: 48px;
  border-radius: 8px;
  background: rgba(255,255,255,0.07);
  flex-shrink: 0;
  animation: pulse 1.5s ease-in-out infinite;
}
.skeleton-text { flex: 1; display: flex; flex-direction: column; gap: 6px; }
.skeleton-line {
  height: 10px;
  border-radius: 4px;
  background: rgba(255,255,255,0.07);
  animation: pulse 1.5s ease-in-out infinite;
}
.w-3\/4 { width: 75%; }
.w-1\/2 { width: 50%; }
.w-full { width: 100%; }

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}

/* Transition dropdown */
.dropdown-enter-active,
.dropdown-leave-active {
  transition: all 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}
.dropdown-enter-from,
.dropdown-leave-to {
  opacity: 0;
  transform: translateX(-50%) translateY(-8px);
}
</style>
```

- [ ] **Step 2: Commit**

```bash
git add app/components/SearchBar.vue
git commit -m "feat: add SearchBar component with results dropdown"
```

---

## Task 7: Integrar `SearchBar` na `AppBar`

**Files:**
- Modify: `app/components/AppBar.vue`

Adicionar `<SearchBar>` entre a marca e o dropdown de perfil, visível apenas quando o usuário está autenticado.

- [ ] **Step 1: Adicionar o `SearchBar` no template da AppBar**

No `app/components/AppBar.vue`, localizar a div `.app-bar-container` e adicionar `<SearchBar>` entre o `.brand` e o `v-if="user"` do perfil:

```html
<div class="app-bar-container">
  <NuxtLink to="/" class="brand">
    <span class="brand-text">Inovação Academy</span>
  </NuxtLink>

  <!-- Busca: só para usuários autenticados -->
  <SearchBar v-if="user" />

  <div v-if="user" class="profile-dropdown-container">
    <!-- ... resto do código existente sem alterações ... -->
  </div>

  <div v-else>
    <NuxtLink to="/login" class="login-btn">Entrar</NuxtLink>
  </div>
</div>
```

- [ ] **Step 2: Commit**

```bash
git add app/components/AppBar.vue
git commit -m "feat: integrate SearchBar into AppBar for authenticated users"
```

---

## Task 8: Adicionar prop `startTime` ao VideoPlayer

**Files:**
- Modify: `app/components/VideoPlayer.vue`

- [ ] **Step 1: Adicionar `startTime` à interface Props**

Localizar a interface `Props` no início do `<script setup>`:

```typescript
interface Props {
  src: string
  poster?: string
  startTime?: number
}
```

- [ ] **Step 2: Aplicar `startTime` após o player estar pronto**

Após a inicialização do player (evento `ready`), adicionar a lógica de seek. Localizar onde o evento `ready` é tratado (ou `isReady.value = true` é atribuído) e acrescentar:

```typescript
player.ready(() => {
  isReady.value = true
  if (props.startTime && props.startTime > 0) {
    player.currentTime(props.startTime)
  }
})
```

Se já existir um handler `ready`, apenas acrescentar o bloco `if (props.startTime ...)` dentro dele.

- [ ] **Step 3: Commit**

```bash
git add app/components/VideoPlayer.vue
git commit -m "feat: add startTime prop to VideoPlayer for deep-link navigation"
```

---

## Task 9: Atualizar página de aula para suportar `?t=` e `currentCourseId`

**Files:**
- Modify: `app/pages/lesson/[id].vue`

Duas mudanças independentes: (1) popular `useState('currentCourseId')` ao carregar o conteúdo; (2) ler `?t=` da URL e passar ao VideoPlayer.

- [ ] **Step 1: Popular `currentCourseId` após carregar o conteúdo**

Logo após o bloco `useAsyncData` que busca o conteúdo (por volta da linha 12), adicionar:

```typescript
// Expõe o courseId para a busca contextual da AppBar
watch(content, (c) => {
  if (c?.modules?.courses?.id) {
    useState('currentCourseId').value = c.modules.courses.id
  }
}, { immediate: true })
```

- [ ] **Step 2: Ler o parâmetro `?t=` da URL**

Após as declarações de `route` e `contentId`, adicionar:

```typescript
const startTime = computed(() => Number(route.query.t) || 0)
```

- [ ] **Step 3: Passar `startTime` ao componente `VideoPlayer` no template**

Localizar onde `<VideoPlayer>` é usado no template e adicionar a prop:

```html
<VideoPlayer
  :src="content.video_url"
  :poster="content.modules?.courses?.thumbnail_url"
  :start-time="startTime"
  @progress-90="handleProgress90"
/>
```

- [ ] **Step 4: Commit**

```bash
git add app/pages/lesson/[id].vue
git commit -m "feat: support ?t= timestamp param and expose currentCourseId in lesson page"
```

---

## Task 10: Verificação manual end-to-end

- [ ] **Step 1: Iniciar o servidor de desenvolvimento**

```bash
npm run dev
```

Abrir `http://localhost:3000` no browser.

- [ ] **Step 2: Testar busca global (dashboard)**

1. Fazer login
2. Estar na página `/` (listagem de cursos)
3. Clicar na lupa na AppBar → input deve expandir
4. Digitar um termo que aparece nas transcrições (ex: "git")
5. Verificar: dropdown aparece com resultados de múltiplos cursos
6. Verificar: cada item mostra thumbnail, título, módulo·curso, trecho e timestamp

- [ ] **Step 3: Testar busca contextual (dentro de um curso)**

1. Navegar para `/courses/[id]` de qualquer curso
2. Buscar o mesmo termo
3. Verificar: resultados são apenas do curso atual (não aparecem outros cursos)

- [ ] **Step 4: Testar navegação por timestamp**

1. Clicar em um resultado da busca
2. Verificar: redireciona para `/lesson/[id]?t=<segundos>`
3. Verificar: o video começa no timestamp correto (não do início)

- [ ] **Step 5: Testar fallback sem OpenAI**

1. Temporariamente remover `OPENAI_API_KEY` do `.env`
2. Buscar um termo
3. Verificar: resultados full-text ainda aparecem (sem erro visível para o usuário)
4. Restaurar a chave

- [ ] **Step 6: Verificar que a lupa NÃO aparece sem login**

1. Fazer logout
2. Verificar: a lupa não aparece na AppBar

- [ ] **Step 7: Commit final de verificação**

```bash
git add -p  # revisar qualquer ajuste feito durante testes
git commit -m "fix: post-verification adjustments for search feature" --allow-empty
```
