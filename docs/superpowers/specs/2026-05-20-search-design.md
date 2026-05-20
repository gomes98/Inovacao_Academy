# Design: Busca de Conteúdo por Transcrição (Full-text + Semântica)

**Data:** 2026-05-20  
**Status:** Aprovado

---

## Visão Geral

Adicionar busca híbrida de conteúdo ao LMS Inovação Academy. A busca opera sobre as transcrições dos vídeos (`content_chunks`), combinando **full-text** (ILIKE) para precisão em termos exatos e **busca semântica** (pgvector + OpenAI embeddings) para encontrar conteúdo por significado — mesmo quando o aluno usa palavras diferentes das que aparecem na transcrição.

A busca é **contextual**:
- Na listagem de cursos (`/`) → busca em **todos os cursos**
- Na página de curso (`/courses/[id]`) → busca **restrita ao curso atual**
- Na página de aula (`/lesson/[id]`) → busca **restrita ao curso da aula atual**

O componente de busca **só é exibido para usuários autenticados**.

---

## Infraestrutura existente

| Recurso | Estado |
|---|---|
| `content_chunks` com campo `embedding` (vector) | ✅ Populado (17 chunks) |
| Modelo usado | `text-embedding-3-small` (OpenAI) |
| Índice HNSW com `vector_cosine_ops` | ✅ Criado |
| `OPENAI_API_KEY` no `.env` | ✅ Disponível |
| Extensão `pgvector` v0.8.0 | ✅ Instalada |

---

## Arquitetura

### Componentes

| Arquivo | Responsabilidade |
|---|---|
| `app/components/AppBar.vue` | Adiciona ícone de lupa + input expansível + `<SearchResults>` |
| `app/components/SearchResults.vue` | Renderiza lista de resultados no dropdown |
| `server/api/search.get.ts` | Endpoint Nuxt: gera embedding da query, executa busca híbrida |
| `app/composables/useCurrentCourseId.ts` | Detecta `courseId` com base na rota atual |
| `app/pages/lesson/[id].vue` | Lê `?t=` da query string e passa `startTime` ao VideoPlayer |

### Fluxo de dados

```
Usuário digita query
  → debounce 400ms
  → GET /api/search?q=<query>&courseId=<id|undefined>
    → [server] gera embedding da query via OpenAI text-embedding-3-small
    → [server] executa busca híbrida no Supabase:
        1. semântica: ORDER BY embedding <=> $queryVector LIMIT 20
        2. full-text: ILIKE '%query%' LIMIT 20
        3. une resultados (UNION), deduplica por chunk_id, limita a 10
    → filtra por course_id quando fornecido
    → retorna top 10 resultados ordenados por relevância
  → SearchResults renderiza dropdown
  → Clique em resultado → navigateTo(/lesson/<id>?t=<start_time>)
  → VideoPlayer recebe startTime e posiciona o vídeo
```

---

## API: `GET /api/search`

**Parâmetros de query:**
- `q` (string, obrigatório) — termo de busca, mínimo 2 caracteres
- `courseId` (string, opcional) — UUID do curso para restringir escopo

**Resposta (array de até 10 itens):**
```typescript
{
  contentId: string
  contentTitle: string
  thumbnailUrl: string | null
  moduleName: string
  courseName: string
  chunkText: string       // trecho onde o assunto foi encontrado
  startTime: number       // segundos (ex: 42.5)
  matchType: 'semantic' | 'fulltext'  // para debug/analytics futuro
}
```

### Lógica de busca híbrida no servidor

```typescript
// 1. Gerar embedding da query
const embeddingRes = await openai.embeddings.create({
  model: 'text-embedding-3-small',
  input: query,
})
const queryVector = embeddingRes.data[0].embedding

// 2. Busca semântica (pgvector cosine similarity)
const semanticSQL = `
  SELECT cc.id AS chunk_id, cc.content_id, cc.text, cc.start_time,
         (cc.embedding <=> $1::vector) AS distance,
         'semantic' AS match_type
  FROM content_chunks cc
  JOIN contents c ON c.id = cc.content_id
  JOIN modules  m ON m.id = c.module_id
  JOIN courses co ON co.id = m.course_id
  WHERE ($2::uuid IS NULL OR co.id = $2::uuid)
  ORDER BY distance ASC
  LIMIT 20
`

// 3. Busca full-text (ILIKE — captura termos exatos)
const fulltextSQL = `
  SELECT cc.id AS chunk_id, cc.content_id, cc.text, cc.start_time,
         0 AS distance,
         'fulltext' AS match_type
  FROM content_chunks cc
  JOIN contents c ON c.id = cc.content_id
  JOIN modules  m ON m.id = c.module_id
  JOIN courses co ON co.id = m.course_id
  WHERE cc.text ILIKE '%' || $1 || '%'
    AND ($2::uuid IS NULL OR co.id = $2::uuid)
  LIMIT 20
`

// 4. União e deduplicação: full-text tem prioridade sobre semântico
// Limite final: 10 resultados
```

O endpoint usa o **client Supabase padrão** (anon key via `@nuxtjs/supabase`). A `OPENAI_API_KEY` é lida via `useRuntimeConfig().openaiApiKey` (server-only). As tabelas acessadas são públicas de conteúdo — nenhum dado sensível é exposto.

### nuxt.config.ts — runtimeConfig necessário

```typescript
runtimeConfig: {
  openaiApiKey: process.env.OPENAI_API_KEY,
}
```

---

## Composable: `useCurrentCourseId()`

```typescript
// app/composables/useCurrentCourseId.ts
export function useCurrentCourseId() {
  const route = useRoute()
  if (route.name === 'courses-id') return route.params.id as string
  if (route.name === 'lesson-id') return useState<string>('currentCourseId').value
  return undefined
}
```

A página `lesson/[id].vue` popula o estado ao carregar:
```typescript
useState('currentCourseId').value = lessonData.value.modules.course_id
```

---

## UI: AppBar

- Ícone de lupa visível apenas quando `useSupabaseUser()` retorna usuário autenticado
- Ao clicar na lupa: input de texto expande com animação (`transition: width 200ms`)
- Ao perder foco (blur) sem texto: input recolhe após 150ms (para permitir clique no resultado)
- Tecla `Escape`: limpa e recolhe
- `courseId` obtido via `useCurrentCourseId()`

---

## UI: SearchResults (dropdown)

Cada item exibe:
```
┌─────────────────────────────────────────────────────────┐
│ [thumb 48x48]  Título da Aula                           │
│                Módulo · Nome do Curso                   │
│                "...trecho encontrado..." ⏱ 0:42         │
└─────────────────────────────────────────────────────────┘
```

- Thumbnail: imagem 48×48 com fallback para ícone de vídeo (SVG inline)
- Trecho (`chunkText`): truncado em 80 caracteres com `…`
- Timestamp: `startTime` convertido para `M:SS` (ex: `1:02`)
- Estado carregando: skeleton de 3 linhas (pulse animation)
- Estado vazio: "Nenhum resultado para «query»"
- Clique fora do dropdown: fecha (usando `@click.outside` ou listener no `document`)

---

## Página de Aula: parâmetro `?t=`

- `lesson/[id].vue` lê `const startTime = Number(route.query.t) || 0`
- Passa `startTime` como prop ao `VideoPlayer`
- `VideoPlayer` faz `player.currentTime(startTime)` após o evento `ready`

---

## Estados de erro

| Situação | Comportamento |
|---|---|
| Query < 2 caracteres | Não dispara request; dropdown fechado |
| Erro OpenAI (embedding) | Fallback silencioso para apenas full-text |
| Erro de rede / API | Mensagem discreta: "Erro ao buscar. Tente novamente." |
| Sem resultados | "Nenhum resultado para «query»" |
| Timeout (> 5s) | Aborta request via `AbortController`, exibe erro |

---

## O que está fora do escopo

- Highlight do termo encontrado no trecho de texto
- Histórico de buscas recentes
- Busca em títulos/descrições de cursos e módulos (apenas transcrições)
- Reranking por modelo de linguagem
