# Force Transcription Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar botão "Forçar Transcrição" na listagem de conteúdos do admin (`/admin/courses/[id]`), visível apenas para vídeos, que limpa dados existentes e re-enfileira o job no worker.

**Architecture:** O front-end (admin autenticado) limpa `content_transcriptions` e `content_chunks` via Supabase client, atualiza `status = 'processed'`, então chama um endpoint Nuxt server-side (`/api/admin/transcribe/:contentId`) que valida a role de admin e repassa o disparo ao worker via HTTP com bearer token. O secret do worker nunca é exposto ao cliente.

**Tech Stack:** Nuxt 4, Vue 3, TypeScript, Supabase (RLS + `has_role()`), Worker Express (`POST /jobs/transcribe/:contentId`)

---

## File Map

| Ação | Arquivo |
|------|---------|
| Modify | `app/types/database.types.ts` — adicionar `status` ao tipo `contents` |
| Create | `server/api/admin/transcribe/[contentId].post.ts` — endpoint proxy para o worker |
| Modify | `nuxt.config.ts` — adicionar `workerUrl` e `workerSecret` em `runtimeConfig` |
| Modify | `.env` — adicionar `WORKER_URL` e `WORKER_SECRET` |
| Modify | `app/pages/admin/courses/[id].vue` — badge de status + botão + função |

---

### Task 1: Atualizar tipos do banco para incluir `status` em `contents`

**Files:**
- Modify: `app/types/database.types.ts`

- [ ] **Step 1: Adicionar `status` ao tipo `contents` no Row, Insert e Update**

Abra `app/types/database.types.ts`. Localize o bloco `contents:` (em torno da linha 56). Adicione `status` nas três seções:

```ts
contents: {
  Row: {
    body_text: string | null
    content_type: string
    created_at: string
    file_url: string | null
    id: string
    module_id: string
    order_index: number | null
    status: 'uploaded' | 'processed' | 'transcribing' | 'indexed' | 'failed' | null
    title: string
    video_url: string | null
  }
  Insert: {
    body_text?: string | null
    content_type: string
    created_at?: string
    file_url?: string | null
    id?: string
    module_id: string
    order_index?: number | null
    status?: 'uploaded' | 'processed' | 'transcribing' | 'indexed' | 'failed' | null
    title: string
    video_url?: string | null
  }
  Update: {
    body_text?: string | null
    content_type?: string
    created_at?: string
    file_url?: string | null
    id?: string
    module_id?: string
    order_index?: number | null
    status?: 'uploaded' | 'processed' | 'transcribing' | 'indexed' | 'failed' | null
    title?: string
    video_url?: string | null
  }
  // ... Relationships inalterado
```

- [ ] **Step 2: Verificar que o TypeScript não reclama**

```powershell
npx nuxi typecheck
```

Esperado: sem erros relacionados a `contents.status`. Se houver outros erros pré-existentes, ignore — o objetivo é confirmar que `status` foi aceito.

- [ ] **Step 3: Commit**

```powershell
git add app/types/database.types.ts
git commit -m "chore: add status field to contents database types"
```

---

### Task 2: Adicionar variáveis de ambiente do worker ao Nuxt

**Files:**
- Modify: `nuxt.config.ts`
- Modify: `.env`

- [ ] **Step 1: Adicionar WORKER_URL e WORKER_SECRET ao `.env`**

Abra `.env` e acrescente no final:

```
WORKER_URL=http://localhost:8787
WORKER_SECRET=trocar-isto
```

> Substitua `trocar-isto` pelo mesmo valor de `WORKER_WEBHOOK_SECRET` do arquivo `services/transcription-worker/.env`.

- [ ] **Step 2: Registrar as variáveis no runtimeConfig do Nuxt**

Abra `nuxt.config.ts`. Localize o bloco `runtimeConfig` e adicione `workerUrl` e `workerSecret` (server-only — sem `public`):

```ts
runtimeConfig: {
  openaiApiKey: process.env.OPENAI_API_KEY,
  workerUrl: process.env.WORKER_URL,
  workerSecret: process.env.WORKER_SECRET,
},
```

- [ ] **Step 3: Commit**

```powershell
git add nuxt.config.ts .env
git commit -m "chore: add worker URL and secret to Nuxt runtimeConfig"
```

---

### Task 3: Criar endpoint Nuxt server-side para proxy do worker

**Files:**
- Create: `server/api/admin/transcribe/[contentId].post.ts`

- [ ] **Step 1: Criar o diretório se não existir**

```powershell
New-Item -ItemType Directory -Force "server/api/admin/transcribe"
```

- [ ] **Step 2: Criar o arquivo do endpoint**

Crie `server/api/admin/transcribe/[contentId].post.ts` com o conteúdo:

```ts
import { serverSupabaseClient } from '#supabase/server'

export default defineEventHandler(async (event) => {
  const { contentId } = getRouterParams(event)

  if (!/^[0-9a-f-]{36}$/i.test(contentId)) {
    throw createError({ statusCode: 400, message: 'contentId inválido' })
  }

  const supabase = await serverSupabaseClient(event)

  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError || !user) {
    throw createError({ statusCode: 401, message: 'Não autenticado' })
  }

  const { data: isAdmin, error: roleError } = await supabase
    .rpc('has_role', { roles: ['admin', 'publicador'] })
  if (roleError || !isAdmin) {
    throw createError({ statusCode: 403, message: 'Acesso negado' })
  }

  const config = useRuntimeConfig()
  if (!config.workerUrl || !config.workerSecret) {
    throw createError({ statusCode: 503, message: 'Worker não configurado' })
  }

  const workerRes = await fetch(
    `${config.workerUrl}/jobs/transcribe/${contentId}`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.workerSecret}` },
    }
  )

  if (!workerRes.ok) {
    const body = await workerRes.text()
    throw createError({ statusCode: workerRes.status, message: `Worker error: ${body}` })
  }

  return { accepted: true, contentId }
})
```

- [ ] **Step 3: Verificar que o TypeScript compila o novo arquivo**

```powershell
npx nuxi typecheck
```

Esperado: sem erros no arquivo recém-criado.

- [ ] **Step 4: Commit**

```powershell
git add server/api/admin/transcribe/[contentId].post.ts
git commit -m "feat: add server-side proxy endpoint for force transcription"
```

---

### Task 4: Adicionar badge de status e botão "Forçar Transcrição" na UI

**Files:**
- Modify: `app/pages/admin/courses/[id].vue`

Esta task tem duas partes: estado reativo + função no `<script>`, depois markup no `<template>`.

#### Parte A — Script

- [ ] **Step 1: Adicionar estado reativo `transcribingIds` no `<script setup>`**

Localize a seção de declaração de refs no script (após as declarações de `isCreatingModule`, `editingModuleId`, etc.). Adicione:

```ts
const transcribingIds = ref<Set<string>>(new Set())
```

- [ ] **Step 2: Adicionar a função `forceTranscribe`**

Adicione esta função após `deleteModule`:

```ts
async function forceTranscribe(content: any) {
  if (!confirm(`Forçar nova transcrição para "${content.title}"?\nOs dados de transcrição existentes serão apagados.`)) return

  transcribingIds.value = new Set([...transcribingIds.value, content.id])

  try {
    const { error: delTranscription } = await supabase
      .from('content_transcriptions')
      .delete()
      .eq('content_id', content.id)
    if (delTranscription) throw new Error(delTranscription.message)

    const { error: delChunks } = await supabase
      .from('content_chunks')
      .delete()
      .eq('content_id', content.id)
    if (delChunks) throw new Error(delChunks.message)

    const { error: statusErr } = await supabase
      .from('contents')
      .update({ status: 'processed' })
      .eq('id', content.id)
    if (statusErr) throw new Error(statusErr.message)

    await $fetch(`/api/admin/transcribe/${content.id}`, { method: 'POST' })

    content.status = 'transcribing'
  } catch (err: any) {
    alert('Erro ao forçar transcrição: ' + err.message)
  } finally {
    const next = new Set(transcribingIds.value)
    next.delete(content.id)
    transcribingIds.value = next
  }
}
```

#### Parte B — Template

- [ ] **Step 3: Adicionar badge de status**

Localize o bloco de badges no template, dentro do loop `v-for="content in mod.contents"`. O trecho atual é:

```html
<span v-if="content.file_url" class="text-xs bg-blue-500/20 text-blue-300 px-2 py-0.5 rounded-full">Anexo</span>
```

Adicione o badge de status **depois** do badge de Anexo:

```html
<span v-if="content.file_url" class="text-xs bg-blue-500/20 text-blue-300 px-2 py-0.5 rounded-full">Anexo</span>
<template v-if="content.content_type === 'video' && (content as any).status">
  <span
    v-if="(content as any).status === 'indexed'"
    class="text-xs bg-green-500/20 text-green-400 px-2 py-0.5 rounded-full"
  >Indexado</span>
  <span
    v-else-if="(content as any).status === 'transcribing'"
    class="text-xs bg-yellow-500/20 text-yellow-400 px-2 py-0.5 rounded-full animate-pulse"
  >Transcrevendo</span>
  <span
    v-else-if="(content as any).status === 'failed'"
    class="text-xs bg-red-500/20 text-red-400 px-2 py-0.5 rounded-full"
  >Falhou</span>
  <span
    v-else
    class="text-xs bg-white/10 text-gray-400 px-2 py-0.5 rounded-full"
  >Não indexado</span>
</template>
```

- [ ] **Step 4: Adicionar botão "Forçar Transcrição"**

No mesmo loop de conteúdos, localize a `div` com os botões de editar e excluir:

```html
<div class="flex items-center gap-2">
  <div class="text-xs text-gray-600 mr-2">Ordem: {{ content.order_index }}</div>
  <button 
    @click="startEditContent(mod.id, content)"
    ...
  >
```

Adicione o botão de transcrição **entre** o `div` de ordem e o botão de editar:

```html
<button
  v-if="content.content_type === 'video'"
  @click="forceTranscribe(content)"
  :disabled="transcribingIds.has(content.id) || isUploading"
  class="p-2 rounded-lg bg-white/5 hover:bg-blue-500/20 text-gray-400 hover:text-blue-400 transition-all opacity-0 group-hover/item:opacity-100 disabled:opacity-30"
  title="Forçar Transcrição"
>
  <svg v-if="!transcribingIds.has(content.id)" xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
    <path d="M3 12a9 9 0 0 1 9-9 9.75 9.75 0 0 1 6.74 2.74L21 8"/>
    <path d="M21 3v5h-5"/>
    <path d="M21 12a9 9 0 0 1-9 9 9.75 9.75 0 0 1-6.74-2.74L3 16"/>
    <path d="M8 16H3v5"/>
  </svg>
  <svg v-else xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="animate-spin">
    <path d="M21 12a9 9 0 1 1-6.219-8.56"/>
  </svg>
</button>
```

- [ ] **Step 5: Verificar no browser**

Com o dev server rodando (`npm run dev`), acesse `/admin/courses/:id`. Verifique:
1. Badge de status aparece para conteúdos de vídeo
2. Botão de refresh aparece no hover para vídeos (não para documentos)
3. Botão exibe spinner ao clicar e desabilita durante o processo
4. Após conclusão, o badge muda para "Transcrevendo"

- [ ] **Step 6: Commit**

```powershell
git add app/pages/admin/courses/[id].vue
git commit -m "feat: add force transcription button and status badge for video contents"
```

---

## Verificação final

Após todas as tasks, o fluxo completo deve funcionar:

1. Abrir `/admin/courses/:id` como admin
2. Hover em um conteúdo de vídeo — botão de refresh aparece
3. Clicar → confirm dialog
4. Badge muda para "Transcrevendo" (amarelo pulsante)
5. No worker, `GET /health` deve mostrar a fila com o job enfileirado

Se o worker não estiver rodando localmente, a chamada ao endpoint retornará erro 503 ou de rede — comportamento esperado e tratado pelo `alert`.
