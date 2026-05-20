# Design: Busca de Conteúdo por Transcrição

**Data:** 2026-05-20  
**Status:** Aprovado

---

## Visão Geral

Adicionar busca full-text de conteúdo ao LMS Inovação Academy. A busca opera sobre as transcrições dos vídeos (`content_chunks`), permitindo ao aluno encontrar o momento exato dentro de uma aula onde determinado assunto é abordado.

A busca é **contextual**:
- Na listagem de cursos (`/`) → busca em **todos os cursos**
- Na página de curso (`/courses/[id]`) → busca **restrita ao curso atual**
- Na página de aula (`/lesson/[id]`) → busca **restrita ao curso da aula atual**

O componente de busca **só é exibido para usuários autenticados**.

---

## Arquitetura

### Componentes

| Arquivo | Responsabilidade |
|---|---|
| `app/components/AppBar.vue` | Adiciona ícone de lupa + input expansível + `<SearchResults>` |
| `app/components/SearchResults.vue` | Renderiza lista de resultados no dropdown |
| `server/api/search.get.ts` | Endpoint Nuxt que executa SQL no Supabase via service role |
| `app/pages/lesson/[id].vue` | Lê `?t=` da query string e passa `startTime` ao VideoPlayer |

### Fluxo de dados

```
Usuário digita query
  → debounce 300ms
  → GET /api/search?q=<query>&courseId=<id|undefined>
    → SQL: full-text search em content_chunks.text (ILIKE)
    → filtra por course_id quando fornecido
    → retorna top 10 resultados
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
  chunkText: string       // trecho onde o termo foi encontrado
  startTime: number       // segundos (ex: 42.5)
}
```

**SQL executado:**
```sql
SELECT
  cc.content_id,
  cc.text        AS chunk_text,
  cc.start_time,
  c.title        AS content_title,
  co.thumbnail_url,
  m.title        AS module_title,
  co.title       AS course_title,
  co.id          AS course_id
FROM content_chunks cc
JOIN contents  c  ON c.id  = cc.content_id
JOIN modules   m  ON m.id  = c.module_id
JOIN courses   co ON co.id = m.course_id
WHERE cc.text ILIKE '%' || $1 || '%'
  AND ($2::uuid IS NULL OR co.id = $2::uuid)
ORDER BY co.title, m.order_index, c.order_index, cc.start_time
LIMIT 10
```

O endpoint usa o **client Supabase padrão** (anon key via `@nuxtjs/supabase`). A query acessa apenas tabelas públicas de conteúdo (`content_chunks`, `contents`, `modules`, `courses`) — nenhum dado sensível de usuário é exposto. O RLS dessas tabelas deve permitir leitura para usuários autenticados, o que já é o comportamento existente.

---

## UI: AppBar

- Ícone de lupa visível apenas quando `useSupabaseUser()` retorna usuário autenticado
- Ao clicar na lupa: input de texto expande com animação (`transition: width`)
- Ao perder foco (blur) sem texto: input recolhe
- Tecla `Escape`: limpa e recolhe
- O `courseId` é derivado de uma composable `useCurrentCourseId()`:
  - `/courses/[id]` → `route.params.id` diretamente
  - `/lesson/[id]` → lê `useState('currentCourseId')`, que é populado pela página de aula ao carregar o conteúdo (`lessonData.modules.course_id`)
  - Demais rotas → `undefined` (busca global)

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

- Thumbnail: imagem 48×48 com fallback para ícone de vídeo
- Trecho (`chunkText`): truncado em 80 caracteres com `…`
- Timestamp: `startTime` convertido para `MM:SS` (ex: `1:02`)
- Estado vazio: "Nenhum resultado para «query»"
- Estado carregando: skeleton de 3 linhas
- Clique fora do dropdown: fecha

---

## Página de Aula: parâmetro `?t=`

- `lesson/[id].vue` lê `const t = Number(route.query.t) || 0`
- Passa `startTime` como prop ao `VideoPlayer`
- `VideoPlayer` faz `player.currentTime(startTime)` após o `ready` event

---

## Estados de erro

| Situação | Comportamento |
|---|---|
| Query < 2 caracteres | Não dispara request; dropdown fechado |
| Erro de rede / API | Mensagem discreta: "Erro ao buscar. Tente novamente." |
| Sem resultados | "Nenhum resultado para «query»" |
| Timeout (> 5s) | Aborta request, exibe erro |

---

## O que está fora do escopo

- Busca semântica por embeddings (pgvector) — a infra existe mas não é usada aqui
- Highlight do termo no trecho de texto
- Histórico de buscas recentes
- Busca em títulos/descrições de cursos e módulos (apenas transcrições)
