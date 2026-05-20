# PRD — Transcrição e Busca Semântica (Whisper + RAG)

**Projeto:** Inovação Academy
**Autor:** Mauricio Gomes
**Data:** 2026-05-20
**Status:** Draft

---

## 1. Contexto e motivação

O Inovação Academy hoje é um repositório estruturado de vídeo-aulas e documentos. Para diferenciar a plataforma de um simples "Drive de cursos", precisamos transformar os vídeos em conteúdo **buscável por significado**: o aluno digita uma dúvida em linguagem natural e recebe o **momento exato** do vídeo onde aquele assunto é abordado.

A pipeline de extração de áudio (FFMPEG → MP3 ao lado do vídeo no storage) já é executada por um serviço externo. Quando essa etapa termina, o campo `contents.status` passa para `processed`. A partir desse momento, esta feature assume.

## 2. Objetivo

Construir um pipeline reativo que, para cada conteúdo com `status = 'processed'`:

1. Baixa o MP3 correspondente do Supabase Storage.
2. Transcreve com `faster-whisper` (self-hosted) gerando segmentos com timestamps.
3. Agrupa os segmentos em "chunks" coerentes.
4. Gera embeddings (`text-embedding-3-small`, OpenAI).
5. Persiste tudo em Postgres com `pgvector`.
6. Atualiza `contents.status` para `indexed`.

E expor uma função RPC `search_transcripts(query, course_id?, limit)` que recebe uma pergunta em linguagem natural, embute, faz busca por similaridade de cosseno e retorna `content_id`, trecho de texto e `start_time` em segundos.

## 3. Fora de escopo (v1)

- Re-transcrição automática quando o vídeo é re-uploadado (manual por enquanto).
- Tradução automática entre idiomas.
- Resumo automático de aula / geração de quiz a partir da transcrição.
- Front-end de busca global (será PRD separado, esta entrega cobre apenas a RPC).
- Multi-tenant / múltiplos modelos de embedding simultâneos.

## 4. Decisões de arquitetura

| Decisão | Escolha | Por quê |
|---|---|---|
| Transcrição | `faster-whisper` self-hosted (GPU) | Custo zero por minuto, latência aceitável, modelo `large-v3` em PT-BR. |
| Embeddings | OpenAI `text-embedding-3-small` (1536 dims) | Melhor custo/qualidade para RAG. ~$0.02/1M tokens. |
| Runtime | Worker Node.js standalone em container | Sem timeout, controle de fila, escalável horizontalmente. |
| Disparo | Database webhook do Supabase em `contents` quando `status = 'processed'` | Reativo, desacoplado, sem polling. |
| Vector store | `pgvector` no próprio Supabase | Zero infra adicional, transação atômica com metadados. |
| Index | HNSW (`vector_cosine_ops`) | Performance superior a IVFFlat para datasets pequenos/médios. |
| Chunking | Por janela de tokens com overlap, respeitando bordas de segmento Whisper | Mantém timestamps utilizáveis para deep-link. |

## 5. Modelo de dados

Adições ao schema (migration `20260520000000_transcription_rag.sql`):

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE public.content_transcriptions (
    content_id    uuid PRIMARY KEY REFERENCES public.contents(id) ON DELETE CASCADE,
    language      text,
    full_text     text NOT NULL,
    segments_json jsonb NOT NULL,
    model         text NOT NULL,
    duration_sec  numeric,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.content_chunks (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    content_id   uuid NOT NULL REFERENCES public.contents(id) ON DELETE CASCADE,
    chunk_index  integer NOT NULL,
    text         text NOT NULL,
    start_time   numeric NOT NULL,
    end_time     numeric NOT NULL,
    token_count  integer,
    embedding    vector(1536),
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (content_id, chunk_index)
);

CREATE INDEX content_chunks_embedding_idx
    ON public.content_chunks
    USING hnsw (embedding vector_cosine_ops);
```

E uma RPC para busca:

```sql
search_transcripts(query_embedding vector(1536), match_count int, course_filter uuid)
```

Retornando `content_id`, `course_id`, `chunk_text`, `start_time`, `similarity`.

## 6. Fluxo end-to-end

```
[serviço externo FFMPEG]
        │ grava .mp3 no bucket courses/
        │ atualiza contents.status = 'processed'
        ▼
[Supabase DB Webhook]  ──HTTP POST──▶  [Node Worker /webhook/content-processed]
                                              │
                                              ▼
                                       1. Marca status = 'transcribing'
                                       2. Baixa MP3 do storage
                                       3. Spawn python sidecar (faster-whisper)
                                       4. Recebe JSON com segments[]
                                       5. Chunker agrupa segments → chunks
                                       6. OpenAI embeddings.batch
                                       7. Upsert content_transcriptions + content_chunks
                                       8. Marca status = 'indexed'
                                       9. Em caso de erro → status = 'failed'
                                              │
                                              ▼
                                       [Nuxt front]
                                              │ chama rpc('search_transcripts', ...)
                                              ▼
                                       [Postgres + pgvector HNSW]
```

## 7. API do worker

### `POST /webhook/content-processed`

Recebe o payload padrão de Database Webhook do Supabase.

**Headers:**
- `Authorization: Bearer <WORKER_WEBHOOK_SECRET>`

**Body (Supabase):**
```json
{
  "type": "UPDATE",
  "table": "contents",
  "record": { "id": "...", "status": "processed", "video_url": "..." },
  "old_record": { "status": "uploaded" },
  "schema": "public"
}
```

**Resposta:** `202 Accepted` (job enfileirado, processamento assíncrono).

**Validações:**
- `record.content_type = 'video'`
- `record.status = 'processed'` e `old_record.status != 'processed'` (evita reprocesso)
- Idempotência: se já existe linha em `content_transcriptions` para o `content_id`, ignora.

### `POST /jobs/transcribe/:contentId` (admin)

Disparo manual para reprocessar um conteúdo. Protegido por bearer admin.

### `GET /health`

Healthcheck do worker e do sidecar Python.

## 8. Convenção de paths de MP3

`video_url` na tabela `contents` aponta para o vídeo dentro do bucket `courses`. O MP3 vive ao lado, com mesmo nome e extensão `.mp3`. O worker deriva via `replace(/\.[^.]+$/, '.mp3')`.

## 9. Status do conteúdo (máquina de estados)

| Status | Significado | Quem escreve |
|---|---|---|
| `uploaded` | Vídeo no storage, MP3 ainda não extraído | Admin UI |
| `processed` | MP3 disponível, pronto para transcrição | Serviço FFMPEG |
| `transcribing` | Worker está processando | Worker |
| `indexed` | Transcrição e embeddings prontos, conteúdo buscável | Worker |
| `failed` | Falha no pipeline (ver `transcription_errors` table no log do worker) | Worker |

## 10. Custos estimados (por 1h de vídeo)

| Componente | Custo |
|---|---|
| `faster-whisper` (GPU própria) | ~R$ 0,00 (custo embutido na infra) |
| OpenAI embeddings (~10k tokens) | ~$0,0002 |
| Storage adicional pgvector (~50 chunks × 1536 floats) | desprezível |
| **Total** | **~$0,0002/hora de vídeo** |

## 11. Métricas de sucesso

- 95% dos vídeos `processed` chegam a `indexed` em menos de 2× a duração do vídeo.
- Top-1 hit das primeiras 20 buscas manuais de QA aponta para o momento correto (±10s).
- Zero leak de transcrições de cursos privados em buscas de outros usuários (validar via RLS).

## 12. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Webhook duplicado dispara reprocesso | Idempotência via `content_transcriptions.content_id` UNIQUE + check de status na entrada |
| GPU do worker indisponível | Fila in-memory + retry com backoff; alerta se fila > N |
| Embedding mismatch entre indexação e query | Pinning da versão do modelo na coluna `model` da tabela; check antes de servir |
| Custo OpenAI explode com reembedding em massa | Hard cap configurável `MAX_TOKENS_PER_DAY` no worker |
| Áudio em idioma errado | Whisper auto-detecta; salvamos `language` para inspeção |

## 13. Plano de entrega

1. **Sprint 1** — Migration + RPC + worker básico end-to-end com 1 vídeo.
2. **Sprint 2** — Idempotência, retries, status machine completo, healthcheck.
3. **Sprint 3** — RPC com filtros (curso/módulo), UI de busca no `/courses/[id]`.
4. **Sprint 4** — Deep-link no player Video.js (`?t=<start_time>`), highlights na busca.
