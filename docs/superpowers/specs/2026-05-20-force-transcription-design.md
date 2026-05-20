# Design: Forçar Transcrição por Conteúdo (Admin)

**Data:** 2026-05-20  
**Escopo:** `/admin/courses/[id]` — botão por conteúdo individual do tipo `video`

---

## Contexto

O worker de transcrição (`services/transcription-worker`) já possui o endpoint `POST /jobs/transcribe/:contentId` para disparo manual. Atualmente, o disparo só ocorre automaticamente via Database Webhook quando `contents.status` muda para `processed`. Esta feature expõe o disparo manual para o admin na UI, com limpeza dos dados existentes antes de re-enfileirar.

---

## Arquitetura

```
Browser (admin)
  │  1. DELETE content_transcriptions + content_chunks (Supabase client)
  │  2. UPDATE contents SET status = 'processed'
  │  3. POST /api/admin/transcribe/:contentId
  ▼
Nuxt Server API (server/api/admin/transcribe/[contentId].post.ts)
  │  - Verifica autenticação (Supabase SSR)
  │  - Verifica role admin via has_role()
  │  - POST worker /jobs/transcribe/:contentId
  ▼
Transcription Worker (http://WORKER_URL)
  │  Authorization: Bearer WORKER_SECRET
  └─ enqueueTranscription(contentId)
```

---

## Componentes

### 1. Variáveis de ambiente (Nuxt)

Adicionar ao `.env`:
```
WORKER_URL=http://localhost:8787
WORKER_SECRET=<mesmo valor de WORKER_WEBHOOK_SECRET do worker>
```

Adicionar ao `nuxt.config.ts` em `runtimeConfig` (server-only, nunca `public`):
```ts
runtimeConfig: {
  workerUrl: process.env.WORKER_URL,
  workerSecret: process.env.WORKER_SECRET,
}
```

### 2. Nuxt Server API

**Arquivo:** `server/api/admin/transcribe/[contentId].post.ts`

Responsabilidades:
- Autenticar via `serverSupabaseClient` — rejeitar 401 se não autenticado
- Verificar role: `SELECT has_role(ARRAY['admin','publicador'])` — rejeitar 403 se falso
- `POST ${workerUrl}/jobs/transcribe/${contentId}` com `Authorization: Bearer ${workerSecret}`
- Retornar `{ accepted: true }` em sucesso ou repassar erro do worker

### 3. Tipos — `app/types/database.types.ts`

Adicionar `status` ao tipo `contents`:
```ts
// Row
status: 'uploaded' | 'processed' | 'transcribing' | 'indexed' | 'failed' | null
// Insert / Update
status?: 'uploaded' | 'processed' | 'transcribing' | 'indexed' | 'failed' | null
```

### 4. UI — `app/pages/admin/courses/[id].vue`

**Estado reativo:**
```ts
const transcribingIds = ref<Set<string>>(new Set())
```

**Função `forceTranscribe(contentId)`:**
1. Adiciona `contentId` ao `transcribingIds`
2. `DELETE FROM content_transcriptions WHERE content_id = contentId`
3. `DELETE FROM content_chunks WHERE content_id = contentId`
4. `UPDATE contents SET status = 'processed' WHERE id = contentId`
5. `POST /api/admin/transcribe/${contentId}`
6. Atualiza localmente `content.status = 'transcribing'` (otimista, sem refresh completo)
7. Remove `contentId` de `transcribingIds`
8. Em erro: `alert(...)` + remove de `transcribingIds`

**Badge de status** (visível sempre para vídeos):
| status | estilo |
|--------|--------|
| `indexed` | `bg-green-500/20 text-green-400` — "Indexado" |
| `transcribing` | `bg-yellow-500/20 text-yellow-400 animate-pulse` — "Transcrevendo" |
| `failed` | `bg-red-500/20 text-red-400` — "Falhou" |
| `processed` ou `uploaded` | `bg-white/10 text-gray-400` — "Não indexado" |
| `null` | sem badge |

**Botão "Forçar Transcrição":**
- Visível apenas para `content_type === 'video'`
- Aparece no hover (mesmo padrão: `opacity-0 group-hover/item:opacity-100`)
- Desabilitado quando `transcribingIds.has(content.id)` ou `isUploading`
- Ícone de refresh (SVG inline)
- Cor: azul/roxo (`bg-white/5 hover:bg-blue-500/20 text-gray-400 hover:text-blue-400`)
- Tooltip: `title="Forçar Transcrição"`

---

## Fluxo de dados

```
Admin clica "Forçar Transcrição"
  → UI marca content como transcribingIds (spinner no botão)
  → Supabase client: limpa content_transcriptions + content_chunks
  → Supabase client: status = 'processed'
  → fetch POST /api/admin/transcribe/:id
    → Nuxt server: autentica + verifica role
    → Nuxt server: chama worker
      → Worker: enfileira job
  → UI: otimisticamente seta status local = 'transcribing'
  → UI: remove do transcribingIds
```

---

## Fora do escopo

- Polling de status em tempo real (o admin pode recarregar a página para ver o status atualizado)
- Botão de "cancelar transcrição"
- Transcrição em lote para múltiplos vídeos de uma vez
