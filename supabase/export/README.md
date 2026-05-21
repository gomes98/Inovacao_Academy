# Exportação para Supabase Self-Hosted

## Arquivos

| Arquivo | Descrição |
|---------|-----------|
| `schema.sql` | Schema completo: extensões, tabelas, funções, views, triggers, RLS, storage |
| `seed.sql` | Dados de referência: `point_rules` e `badges` |

## Pré-requisitos

- Supabase self-hosted rodando (docker compose)
- PostgreSQL 15+ (testado no 17)
- Extensão `pgvector` disponível na imagem

## Como aplicar

### Opção A — via psql

```bash
# Schema
psql -h localhost -p 5432 -U postgres -d postgres -f schema.sql

# Seed
psql -h localhost -p 5432 -U postgres -d postgres -f seed.sql
```

### Opção B — via SQL Editor do Supabase Dashboard

1. Abra o SQL Editor no dashboard do self-hosted
2. Cole e execute `schema.sql`
3. Cole e execute `seed.sql`

## O que NÃO está incluído

- **Usuários auth**: precisam ser recriados via dashboard ou API do Auth
- **Arquivos de storage** (avatars, vídeos, documentos): precisam ser re-uploaded manualmente ou via migração do bucket S3/MinIO
- **Conteúdo dos cursos** (`courses`, `modules`, `contents`): dados de produção — exporte separadamente se necessário via `pg_dump --data-only`
- **Embeddings** (`content_chunks.embedding`): precisam ser regerados pelo pipeline de transcrição/indexação

## Notas importantes

### pgvector
A extensão `vector` precisa estar disponível na imagem Docker.
No `docker-compose.yml` do Supabase self-hosted, use a imagem:
```
supabase/postgres:15.x.x-vector
```
ou verifique se sua versão já inclui o pgvector.

### Variáveis de ambiente do app
Atualize o `.env` do Nuxt para apontar para o self-hosted:
```
SUPABASE_URL=http://localhost:8000
SUPABASE_KEY=<anon key do self-hosted>
```

### Primeiro usuário admin
Após criar o primeiro usuário via Auth:
```sql
UPDATE public.perfis SET role = 'admin' WHERE email = 'seu@email.com';
```
