# Inovação Academy — LMS

Sistema de gerenciamento de aprendizado (LMS) construído com Nuxt 4 + Supabase.

## Stack

- **Frontend:** Nuxt 4 (Vue 3), TypeScript, Tailwind CSS v4
- **Backend:** Supabase (PostgreSQL, Auth, Storage)
- **Serviços:** transcoder-worker (Node/FFmpeg), transcription-worker (Node + Python/Whisper + CUDA)

---

## Pré-requisitos

- Node.js 22+
- npm 10+
- Docker e Docker Compose
- Supabase CLI (`npm install -g supabase`)
- (Opcional) GPU NVIDIA com drivers CUDA para o transcription-worker

---

## 1. Variáveis de Ambiente

Cada componente tem seu próprio `.env`. Copie os exemplos e preencha os valores:

```bash
# Frontend
cp .env.example .env

# transcoder-worker
cp services/transcoder-worker/.env.example services/transcoder-worker/.env

# transcription-worker
cp services/transcription-worker/.env.example services/transcription-worker/.env
```

### Frontend (`.env`)

| Variável | Descrição |
|---|---|
| `NUXT_PUBLIC_SUPABASE_URL` | URL do projeto Supabase |
| `NUXT_PUBLIC_SUPABASE_KEY` | Chave anon/public do Supabase |
| `NUXT_OPENAI_API_KEY` | Chave da API OpenAI |
| `NUXT_WORKER_URL` | URL do transcription-worker |
| `NUXT_WORKER_SECRET` | Secret compartilhado com o worker |
| `NUXT_COOKIE_SECURE` | `false` para HTTP (staging), `true` para HTTPS (produção) |

---

## 2. Banco de Dados (Supabase Migrations)

### Usando Supabase Cloud (remoto)

Vincule seu projeto local ao projeto remoto e aplique todas as migrations:

```bash
# Faça login na CLI do Supabase
supabase login

# Vincule ao projeto remoto (use o Project ID do painel do Supabase)
supabase link --project-ref SEU_PROJECT_ID

# Aplique todas as migrations
supabase db push
```

### Usando Supabase local (desenvolvimento)

```bash
# Inicie o stack local do Supabase (Docker necessário)
supabase start

# As migrations são aplicadas automaticamente ao iniciar
# Para reaplicar do zero:
supabase db reset
```

As migrations estão em `supabase/migrations/` e devem ser aplicadas em ordem:

| Arquivo | Descrição |
|---|---|
| `20260513000000_initial_schema.sql` | Schema inicial — tabelas e RLS |
| `20260520000000_transcription_rag.sql` | RAG para transcrições |
| `20260520100000_search_functions.sql` | Funções de busca semântica |
| `20260520200000_course_access_control.sql` | Controle de acesso a cursos |
| `20260521000000_comment_replies.sql` | Respostas em comentários |
| `20260521100000_gamification.sql` | Sistema de gamificação |
| `20260521200000_fix_comments_and_private_notes.sql` | Correções em comentários e notas |
| `20260521300000_fix_views_security_invoker.sql` | Segurança das views |
| `20260526000000_fix_rls_policies.sql` | Correções nas políticas RLS |
| `20260526000001_fix_views_security_invoker.sql` | Correções adicionais de segurança nas views |
| `20260526000002_default_group_for_ungrouped_users.sql` | Grupo padrão para usuários sem grupo |
| `20260527141907_add_thumbnail_url_to_contents.sql` | Adiciona thumbnail_url aos conteúdos |

---

### Carregando as imagens docker

```bash
# Carrega o front-end
docker load < inovacao-academy.tar
# Carrega o transcodificador
docker load < transcoder-worker.tar
# Carrega o transcritor
docker load < transcription-worker.tar

# As migrations são aplicadas automaticamente ao iniciar
# Para reaplicar do zero:
supabase db reset
```

## 3. Frontend

### Desenvolvimento local

```bash
npm install
npm run dev
# Acesse: http://localhost:3000
```

### Build de produção (Docker)

As variáveis de ambiente seguem o padrão `NUXT_*` exigido pelo Nuxt 4 para override de runtime config.
A variável `NUXT_COOKIE_SECURE` é injetada em tempo de **build** (não runtime) pois controla uma opção de módulo.

```bash
# Build da imagem (staging HTTP — cookie sem Secure)
docker build -t inovacao-academy .

# Export da imagem
docker save -o inovacao-academy.tar inovacao-academy

# Build da imagem (produção HTTPS — cookie com Secure)
docker build --build-arg NUXT_COOKIE_SECURE=true -t inovacao-academy .

# Rodar passando as variáveis pelo arquivo env
docker run -p 3000:3000 --env-file .env --restart unless-stopped inovacao-academy
```

### Usando Docker Compose (recomendado)

1. Copie o exemplo e preencha os valores:
   ```bash
   cp .env.example .env
   ```

2. Suba o container:
   ```bash
   docker compose up -d --build
   ```

Para produção com HTTPS, defina `NUXT_COOKIE_SECURE=true` no `.env` antes de buildar.

---

## 4. Serviços

### transcoder-worker

Serviço Node.js responsável por transcodificar vídeos via FFmpeg.

```bash
cd services/transcoder-worker

# Build da imagem
docker build -t transcoder-worker .

# Export da imagem
docker save -o transcoder-worker.tar transcoder-worker

#carregar imagem
docker load < transcoder-worker.tar

# Rodar
docker run --env-file .env --restart unless-stopped transcoder-worker
```

### transcription-worker

Serviço Node.js + Python (faster-whisper) para transcrição de vídeos. Suporta GPU NVIDIA.

```bash
cd services/transcription-worker

# Build da imagem
docker build -t transcription-worker .

# Export da imagem
docker save -o transcription-worker.tar transcription-worker

#carregar imagem
docker load < transcription-worker.tar

# Rodar com GPU NVIDIA
docker run --gpus all --env-file .env -p 8787:8787 transcription-worker

# Rodar sem GPU (CPU)
docker run --env-file .env -p 8787:8787 transcription-worker

# fazer cache dos modelos do whisper windows
docker run --gpus all --env-file .env -v "$(pwd)/cacheModels:/root/.cache"  -p 8787:8787 transcription-worker

# fazer cache dos modelos do whisper linux
docker run --gpus all --env-file .env -v $(pwd)/cacheModels:/root/.cache  -p 8787:8787 --restart unless-stopped transcription-worker
```

---

## Estrutura do Projeto

```
.
├── app/                        # Código Nuxt 4
│   ├── pages/                  # Rotas da aplicação
│   ├── components/             # Componentes Vue
│   ├── composables/            # Composables reutilizáveis
│   └── types/database.types.ts # Tipos gerados pelo Supabase
├── services/
│   ├── transcoder-worker/      # Serviço de transcodificação (Node + FFmpeg)
│   └── transcription-worker/   # Serviço de transcrição (Node + Python/Whisper)
├── supabase/
│   └── migrations/             # Migrations do banco de dados
├── Dockerfile                  # Build do frontend
├── docker-compose.yml          # Compose do frontend
└── .env.example                # Variáveis de ambiente do frontend
```

---

## Regenerar Tipos do Supabase

Após alterações no schema, regenere os tipos TypeScript:

```bash
supabase gen types typescript --project-id SEU_PROJECT_ID > app/types/database.types.ts
```
