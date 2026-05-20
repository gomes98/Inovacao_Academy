# Design: Sistema de Controle de Acesso a Cursos

**Data:** 2026-05-20  
**Status:** Aprovado

## Visão Geral

Implementar um sistema de permissões por curso na Inovação Academy. Atualmente todos os alunos autenticados veem todos os cursos. O objetivo é permitir que admins controlem quais cursos cada aluno pode acessar — via configuração individual, via grupos de permissão, ou ambos de forma aditiva.

## Regras de Negócio

- **Admin** → vê todos os cursos sempre (sem necessidade de permissão explícita)
- **Publicador** → vê todos os cursos sempre (sem necessidade de permissão explícita)
- **Aluno** → vê apenas os cursos permitidos, conforme configuração abaixo:
  - `mode = 'all_courses'` → vê todos os cursos
  - `mode = 'restricted'` (padrão) → vê a **união** de:
    - Cursos com acesso individual (`user_course_access`)
    - Cursos dos grupos que pertence (`user_groups` + `group_course_access`)
- Permissões são **aditivas** — grupo e individual se somam, nunca se sobrescrevem
- Usuário sem nenhuma configuração (`mode = 'restricted'` e sem cursos/grupos) não vê nenhum curso

## Modelo de Dados

### Novas tabelas

```sql
-- Modo geral de acesso do usuário (default: restricted)
CREATE TABLE user_access_mode (
  user_id uuid PRIMARY KEY REFERENCES perfis(id) ON DELETE CASCADE,
  mode text NOT NULL DEFAULT 'restricted' CHECK (mode IN ('all_courses', 'restricted'))
);

-- Acesso individual a cursos específicos
CREATE TABLE user_course_access (
  user_id uuid REFERENCES perfis(id) ON DELETE CASCADE,
  course_id uuid REFERENCES courses(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, course_id)
);

-- Grupos de permissão
CREATE TABLE permission_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  created_at timestamptz DEFAULT now()
);

-- Cursos que um grupo acessa
CREATE TABLE group_course_access (
  group_id uuid REFERENCES permission_groups(id) ON DELETE CASCADE,
  course_id uuid REFERENCES courses(id) ON DELETE CASCADE,
  PRIMARY KEY (group_id, course_id)
);

-- Usuários que pertencem a um grupo
CREATE TABLE user_groups (
  user_id uuid REFERENCES perfis(id) ON DELETE CASCADE,
  group_id uuid REFERENCES permission_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, group_id)
);
```

### Tabelas existentes afetadas

- `courses` — recebe policy RLS de SELECT
- `course_catalog` (view) — herda automaticamente o RLS de `courses`, sem alteração

## Segurança — Row Level Security

Toda a lógica de filtro fica no banco. O frontend não precisa de nenhuma lógica de permissão.

### Policy SELECT em `courses`

```sql
CREATE POLICY "course_access" ON courses
FOR SELECT USING (
  -- Admin e publicador veem tudo
  has_role(auth.uid(), 'admin')
  OR has_role(auth.uid(), 'publicador')

  -- Aluno com mode = 'all_courses'
  OR EXISTS (
    SELECT 1 FROM user_access_mode
    WHERE user_id = auth.uid() AND mode = 'all_courses'
  )

  -- Acesso individual ao curso
  OR EXISTS (
    SELECT 1 FROM user_course_access
    WHERE user_id = auth.uid() AND course_id = courses.id
  )

  -- Acesso via grupo
  OR EXISTS (
    SELECT 1 FROM user_groups ug
    JOIN group_course_access gca ON gca.group_id = ug.group_id
    WHERE ug.user_id = auth.uid() AND gca.course_id = courses.id
  )
);
```

### Policies nas novas tabelas

Todas as novas tabelas seguem o padrão:
- `SELECT`: usuário autenticado pode ler suas próprias linhas (necessário para a policy de `courses` funcionar via `auth.uid()`)
- `INSERT/UPDATE/DELETE`: apenas admins (`has_role(auth.uid(), 'admin')`)

## Interface Admin

### Página `/admin/groups` (nova)

- Lista todos os grupos com: nome, descrição, contagem de cursos, contagem de membros
- Ações: criar grupo, editar grupo, excluir grupo
- Ao abrir um grupo, painel com duas abas:
  - **Cursos** — checkboxes de todos os cursos; marcados = grupo tem acesso
  - **Membros** — lista de usuários do grupo; adicionar/remover membros

### Modal de edição do usuário — `/admin/users` (extensão do existente)

Nova seção **"Acesso a Cursos"** aparece abaixo do campo de role, visível apenas quando `role = 'aluno'`:

**Modo de acesso** (radio):
- `Todos os cursos` → salva `user_access_mode.mode = 'all_courses'`
- `Cursos específicos` → salva `mode = 'restricted'` + mostra checkboxes dos cursos
- `Somente via grupos` → salva `mode = 'restricted'` + sem cursos individuais (herda só dos grupos)

**Grupos** (seção sempre visível quando role = aluno):
- Lista os grupos que o usuário pertence
- Botão para adicionar a um grupo existente
- Opção de remover de um grupo

### Fluxo típico do admin

1. Acessa `/admin/groups` → cria grupo "Time de Vendas" → seleciona os cursos do grupo
2. Acessa `/admin/users` → edita um aluno → define modo "Cursos específicos" → seleciona cursos individuais → adiciona o aluno ao grupo "Time de Vendas"
3. O aluno faz login e vê a união dos cursos individuais + cursos do grupo

## Impacto no Frontend Existente

- **`/` (dashboard)** — nenhuma mudança; `course_catalog` já passa pelo RLS automaticamente
- **`/courses/[id]`** — nenhuma mudança; o RLS bloqueia acesso direto via URL a cursos não permitidos
- **`/lesson/[id]`** — nenhuma mudança; conteúdos só são acessíveis via `course_structure` que herda o RLS
- **`/admin/users`** — modal de edição recebe nova seção de acesso
- **`/admin/groups`** — página nova

## Migrações

Ordem de aplicação:
1. Criar as 5 novas tabelas com constraints e defaults
2. Habilitar RLS nas novas tabelas
3. Criar policies nas novas tabelas
4. Habilitar RLS em `courses` (se não estiver habilitado)
5. Criar policy `course_access` em `courses`
6. Regenerar `database.types.ts` via `supabase gen types typescript`

## Fora do Escopo

- Notificação ao aluno quando recebe acesso a um novo curso
- Expiração de acesso por data
- Histórico de alterações de permissão
- Acesso a nível de módulo ou aula (granularidade é por curso)
