# Inovação Academy — Transcription Worker

Worker em Node.js + Python que transcreve vídeos do Inovação Academy via `faster-whisper`, gera embeddings com OpenAI e popula `content_transcriptions` / `content_chunks` no Supabase para busca semântica (RAG).

Veja o PRD completo em [`docs/PRD-transcricao-rag.md`](../../docs/PRD-transcricao-rag.md).

## Fluxo

1. Serviço externo extrai MP3 do vídeo e atualiza `contents.status = 'processed'`.
2. Database Webhook do Supabase chama `POST /webhook/content-processed`.
3. Worker enfileira o job; baixa o MP3, transcreve, chunka, embute e persiste.
4. `contents.status` vira `indexed`. Front pode usar `rpc('search_transcripts', …)`.

## Setup local

### 1. Dependências do sistema

- Node.js ≥ 20
- Python 3.10+ com `pip`
- (GPU) Driver NVIDIA + CUDA 12 + cuDNN 8 — necessário para `compute_type=float16`. Em CPU, use `WHISPER_DEVICE=cpu` e `WHISPER_COMPUTE_TYPE=int8`.

### 2. Instalar

```bash
cd services/transcription-worker
cp .env.example .env   # preencher SUPABASE_SERVICE_ROLE_KEY, OPENAI_API_KEY, WORKER_WEBHOOK_SECRET
npm install
python -m venv .venv && . .venv/Scripts/activate   # ou .venv/bin/activate no Linux
pip install -r python/requirements.txt
```

Aponte `WHISPER_PYTHON` no `.env` para o binário do venv (ex.: `.venv/Scripts/python.exe`).

### 3. Aplicar a migration no Supabase

```bash
# Da raiz do projeto:
supabase db push   # ou aplicar manualmente via SQL Editor
```

A migration `supabase/migrations/20260520000000_transcription_rag.sql` cria a extensão `vector`, as tabelas, o índice HNSW e a RPC `search_transcripts`.

### 4. Configurar o Database Webhook

No painel do Supabase: **Database → Webhooks → New Hook**

- Table: `contents`
- Events: `UPDATE`
- HTTP method: `POST`
- URL: `https://<seu-worker>/webhook/content-processed`
- HTTP Headers: `Authorization: Bearer <WORKER_WEBHOOK_SECRET>`

O worker já valida transição (`status = 'processed'` & não estava `processed` antes) e idempotência.

### 5. Rodar

```bash
npm run dev      # desenvolvimento (hot reload)
npm run build && npm start   # produção
```

Healthcheck:

```bash
curl http://localhost:8787/health
```

## Disparo manual (admin/teste)

```bash
curl -X POST http://localhost:8787/jobs/transcribe/<contentId> \
  -H "Authorization: Bearer $WORKER_WEBHOOK_SECRET"
```

## Docker (GPU)

```bash
docker build -t ia-transcription-worker .
docker run --rm --gpus all -p 8787:8787 --env-file .env ia-transcription-worker
```

Para CPU, troque a base do Dockerfile para `node:20-bookworm` e ajuste `WHISPER_DEVICE=cpu` / `WHISPER_COMPUTE_TYPE=int8`.

## Exemplo de uso da busca no front (Nuxt)

```ts
const supabase = useSupabaseClient();

// 1. Embute a query no servidor (proteja a OPENAI_API_KEY!) — ex.: /server/api/search.post.ts
//    devolvendo o vetor de 1536 dims.
const { data: embedding } = await $fetch('/api/search', { method: 'POST', body: { q } });

// 2. Chama a RPC com o vetor pronto
const { data, error } = await supabase.rpc('search_transcripts', {
  query_embedding: embedding,
  match_count: 10,
  course_filter: courseId ?? null,
  min_similarity: 0.5,
});

// data: [{ chunk_id, content_id, content_title, course_title, chunk_text, start_time, similarity }, ...]
// Deep-link para o player: /lesson/{content_id}?t={start_time}
```

> **Importante:** nunca exponha a `OPENAI_API_KEY` no cliente. A geração do embedding da query deve acontecer no backend (server route do Nuxt ou Edge Function).

## Decisões e limites conhecidos

- **Concorrência = 1 por padrão**: 1 GPU não roda dois `faster-whisper` simultâneos sem disputa. Aumente `JOB_CONCURRENCY` apenas se tiver hardware sobrando.
- **Idempotência**: já tem transcrição? Skip. Disparo manual via `/jobs/transcribe/:id` deleta os chunks antigos antes de reinserir.
- **Pinning de modelo de embedding**: a coluna `embedding_model` em `content_chunks` permite identificar conteúdo gerado por modelos antigos quando você quiser re-embedar.
- **Webhook secret**: o Supabase manda no header `Authorization` exatamente o que você configurar. Use uma string forte.
