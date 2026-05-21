# Comment Replies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar suporte a respostas aninhadas em comentários na tela de aula, com múltiplos níveis, exibição mista e @menção automática.

**Architecture:** Adiciona coluna `parent_id` na tabela `comments` via migration Supabase, recria a view `content_comments_view` para expor o campo, cria componente recursivo `CommentItem.vue` e atualiza `lesson/[id].vue` para montar a árvore de comentários via `computed` e gerenciar estado de resposta via `provide/inject`.

**Tech Stack:** Nuxt 4, Vue 3 (Composition API, auto-imports), TypeScript, Supabase (PostgreSQL), Tailwind CSS v4

---

## Mapa de Arquivos

| Arquivo | Ação | Responsabilidade |
|---|---|---|
| `supabase/migrations/20260521000000_comment_replies.sql` | Criar | Migration: `parent_id` + recriar view |
| `app/types/database.types.ts` | Modificar | Adicionar `parent_id` ao tipo `comments` e à view |
| `app/components/CommentItem.vue` | Criar | Componente recursivo de comentário com respostas |
| `app/pages/lesson/[id].vue` | Modificar | Montar árvore, estado de resposta, `provide`, `postComment` atualizado |

---

## Task 1: Migration do banco de dados

**Files:**
- Create: `supabase/migrations/20260521000000_comment_replies.sql`

- [ ] **Step 1: Criar o arquivo de migration**

Crie o arquivo `supabase/migrations/20260521000000_comment_replies.sql` com o conteúdo:

```sql
-- Adiciona suporte a respostas aninhadas em comentários
ALTER TABLE comments ADD COLUMN parent_id uuid REFERENCES comments(id) ON DELETE CASCADE;

-- Recria a view para expor parent_id
DROP VIEW IF EXISTS content_comments_view;
CREATE VIEW content_comments_view AS
  SELECT
    c.id        AS comment_id,
    c.content_id,
    c.comment_text,
    c.created_at,
    c.user_id,
    c.parent_id,
    p.full_name AS user_name
  FROM comments c
  LEFT JOIN perfis p ON p.id = c.user_id;
```

- [ ] **Step 2: Aplicar a migration no Supabase**

Execute via MCP Supabase (`mcp__supabase__apply_migration`) ou via CLI:

```bash
npx supabase db push
```

Verifique no painel do Supabase que a coluna `parent_id` aparece na tabela `comments` e que a view `content_comments_view` foi recriada com o campo `parent_id`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260521000000_comment_replies.sql
git commit -m "feat: add parent_id to comments and update view for nested replies"
```

---

## Task 2: Atualizar tipos TypeScript

**Files:**
- Modify: `app/types/database.types.ts`

> Os tipos são gerados automaticamente pelo Supabase CLI. O jeito correto é regenerar. Se não for possível regenerar agora, faça a edição manual descrita abaixo.

- [ ] **Step 1: Regenerar os tipos (preferido)**

```bash
npx supabase gen types typescript --local > app/types/database.types.ts
```

Se o ambiente local não estiver disponível, vá para o Step 2 (edição manual).

- [ ] **Step 2: (Alternativa) Editar manualmente `app/types/database.types.ts`**

Encontre a seção `comments` dentro de `Tables` e adicione `parent_id` nas três sub-seções (`Row`, `Insert`, `Update`):

```ts
// Em comments.Row (linha ~63):
parent_id: string | null  // adicionar após created_at

// Em comments.Insert:
parent_id?: string | null  // adicionar após created_at

// Em comments.Update:
parent_id?: string | null  // adicionar após created_at
```

Encontre a seção `content_comments_view` dentro de `Views` e adicione `parent_id` em `Row`:

```ts
// Em content_comments_view.Row (linha ~594):
parent_id: string | null  // adicionar após created_at
```

- [ ] **Step 3: Commit**

```bash
git add app/types/database.types.ts
git commit -m "chore: add parent_id to comments types"
```

---

## Task 3: Criar componente `CommentItem.vue`

**Files:**
- Create: `app/components/CommentItem.vue`

Este componente é recursivo: renderiza um comentário e seus filhos, chamando a si mesmo para cada filho.

- [ ] **Step 1: Criar `app/components/CommentItem.vue`**

```vue
<script setup lang="ts">
type CommentNode = {
  comment_id: string
  parent_id: string | null
  comment_text: string | null
  user_name: string | null
  created_at: string | null
  children: CommentNode[]
}

const props = defineProps<{
  comment: CommentNode
  depth: number
}>()

// Estado injetado do [id].vue pai
const replyingTo = inject<Ref<string | null>>('replyingTo')!
const replyText = inject<Ref<string>>('replyText')!
const postComment = inject<(parentId: string | null) => Promise<void>>('postComment')!

// Controla expansão de filhos colapsados (depth >= 2)
const showChildren = ref(false)

function startReply() {
  replyText.value = `@${props.comment.user_name} `
  replyingTo.value = props.comment.comment_id
}

function cancelReply() {
  replyingTo.value = null
  replyText.value = ''
}

const isReplying = computed(() => replyingTo.value === props.comment.comment_id)
const hasChildren = computed(() => props.comment.children.length > 0)
const childrenAlwaysVisible = computed(() => props.depth < 2)
</script>

<template>
  <div class="flex gap-4">
    <!-- Avatar -->
    <div class="w-8 h-8 flex-shrink-0 rounded-full bg-gradient-to-br from-purple-500/20 to-blue-500/20 border border-white/10 flex items-center justify-center font-bold text-xs">
      {{ comment.user_name?.charAt(0) || 'U' }}
    </div>

    <div class="flex-1 min-w-0">
      <!-- Cabeçalho -->
      <div class="flex items-center gap-2 mb-1">
        <span class="text-sm font-bold text-white">{{ comment.user_name }}</span>
        <span class="text-[10px] text-gray-600 uppercase tracking-widest">
          {{ comment.created_at ? new Date(comment.created_at).toLocaleDateString() : '' }}
        </span>
      </div>

      <!-- Texto com @menção em roxo -->
      <p class="text-sm text-gray-400 leading-relaxed">
        <template v-for="(part, i) in comment.comment_text?.split(/(@\S+)/g)" :key="i">
          <span v-if="part.startsWith('@')" class="text-purple-400">{{ part }}</span>
          <span v-else>{{ part }}</span>
        </template>
      </p>

      <!-- Botão Responder -->
      <button
        @click="startReply"
        class="mt-2 text-[11px] text-gray-500 hover:text-purple-400 transition-colors font-medium uppercase tracking-widest"
      >
        Responder
      </button>

      <!-- Formulário inline de resposta -->
      <div v-if="isReplying" class="mt-3 p-4 rounded-2xl bg-white/[0.02] border border-white/5">
        <textarea
          v-model="replyText"
          class="w-full bg-transparent border-none focus:ring-0 text-sm text-white placeholder-gray-600 min-h-[60px] resize-none outline-none"
          placeholder="Escreva sua resposta..."
          autofocus
        ></textarea>
        <div class="flex justify-end gap-3 mt-3 pt-3 border-t border-white/5">
          <button
            @click="cancelReply"
            class="px-4 py-2 rounded-xl text-xs font-bold text-gray-500 hover:text-gray-300 transition-colors uppercase tracking-widest"
          >
            Cancelar
          </button>
          <button
            @click="postComment(comment.comment_id)"
            :disabled="!replyText.trim()"
            class="px-5 py-2 rounded-xl bg-purple-600 text-white text-xs font-bold hover:bg-purple-500 disabled:opacity-50 transition-all uppercase tracking-widest"
          >
            Responder
          </button>
        </div>
      </div>

      <!-- Filhos sempre visíveis (depth < 2) -->
      <div v-if="hasChildren && childrenAlwaysVisible" class="mt-4 space-y-4 pl-4 border-l border-white/5">
        <CommentItem
          v-for="child in comment.children"
          :key="child.comment_id"
          :comment="child"
          :depth="depth + 1"
        />
      </div>

      <!-- Filhos colapsados (depth >= 2) -->
      <div v-else-if="hasChildren && !childrenAlwaysVisible" class="mt-3">
        <button
          v-if="!showChildren"
          @click="showChildren = true"
          class="text-[11px] text-purple-400 hover:text-purple-300 transition-colors font-medium uppercase tracking-widest"
        >
          Ver {{ comment.children.length }} {{ comment.children.length === 1 ? 'resposta' : 'respostas' }}
        </button>
        <div v-else class="mt-4 space-y-4 pl-4 border-l border-white/5">
          <CommentItem
            v-for="child in comment.children"
            :key="child.comment_id"
            :comment="child"
            :depth="depth + 1"
          />
        </div>
      </div>
    </div>
  </div>
</template>
```

- [ ] **Step 2: Commit**

```bash
git add app/components/CommentItem.vue
git commit -m "feat: add recursive CommentItem component with reply support"
```

---

## Task 4: Atualizar `lesson/[id].vue`

**Files:**
- Modify: `app/pages/lesson/[id].vue`

Quatro mudanças neste arquivo:
1. Adicionar tipo `CommentNode` e `commentsTree` computed
2. Adicionar `replyingTo`, `replyText` e `provide`
3. Atualizar `postComment` para aceitar `parentId`
4. Atualizar o template da seção de comentários para usar `CommentItem`

- [ ] **Step 1: Adicionar tipo `CommentNode` após as importações de estado (linha ~139)**

Localize o bloco de estados para interação (linha ~138-142):

```ts
// Estados para interação
const newComment = ref('')
const isPostingComment = ref(false)
const noteText = ref('')
const isSavingNote = ref(false)
```

Substitua por:

```ts
type CommentNode = {
  comment_id: string
  parent_id: string | null
  comment_text: string | null
  user_name: string | null
  created_at: string | null
  children: CommentNode[]
}

// Estados para interação
const newComment = ref('')
const isPostingComment = ref(false)
const noteText = ref('')
const isSavingNote = ref(false)
const replyingTo = ref<string | null>(null)
const replyText = ref('')

// Monta árvore de comentários a partir da lista flat
const commentsTree = computed(() => {
  const flat = (comments.value ?? []) as CommentNode[]
  const map = new Map(flat.map(c => [c.comment_id!, { ...c, children: [] as CommentNode[] }]))
  const roots: CommentNode[] = []
  for (const node of map.values()) {
    if (node.parent_id) map.get(node.parent_id)?.children.push(node)
    else roots.push(node)
  }
  return roots
})

provide('replyingTo', replyingTo)
provide('replyText', replyText)
provide('postComment', postComment)
```

> **Nota:** O `provide('postComment', postComment)` deve ficar **após** a declaração da função `postComment`. Mova esta linha para depois da função (veja Step 3).

- [ ] **Step 2: Atualizar a query de comentários para ordem ascendente**

Localize (linha ~23-26):

```ts
const { data: comments, refresh: refreshComments } = await useAsyncData(() => `comments-${contentId.value}`, async () => {
  const { data } = await supabase.from('content_comments_view').select('*').eq('content_id', contentId.value).order('created_at', { ascending: false })
  return data
}, { watch: [contentId] })
```

Mude `ascending: false` para `ascending: true`:

```ts
const { data: comments, refresh: refreshComments } = await useAsyncData(() => `comments-${contentId.value}`, async () => {
  const { data } = await supabase.from('content_comments_view').select('*').eq('content_id', contentId.value).order('created_at', { ascending: true })
  return data
}, { watch: [contentId] })
```

- [ ] **Step 3: Atualizar a função `postComment` para aceitar `parentId`**

Localize a função `postComment` (linha ~149) e substitua completamente:

```ts
async function postComment(parentId: string | null = null) {
  const text = parentId ? replyText.value : newComment.value
  if (!text.trim() || isPostingComment.value || !user.value) return

  isPostingComment.value = true
  try {
    const { error } = await supabase.from('comments').insert({
      content_id: contentId.value,
      comment_text: text,
      ...(parentId ? { parent_id: parentId } : {})
    })

    if (error) {
      console.error('Erro Supabase (Comentário):', error)
      throw error
    }

    if (parentId) {
      replyText.value = ''
    } else {
      newComment.value = ''
    }
    replyingTo.value = null
    await refreshComments()
  } catch (err) {
    alert('Erro ao postar comentário. Verifique o console.')
    console.error(err)
  } finally {
    isPostingComment.value = false
  }
}

// Expõe postComment via provide para CommentItem (deve ficar após a declaração da função)
provide('postComment', postComment)
```

> Remova o `provide('postComment', postComment)` que foi adicionado no Step 1 (estava como placeholder antes da função existir). Deixe apenas este aqui.

- [ ] **Step 4: Atualizar o template — seção de comentários**

Localize a seção de comentários no template (linha ~396-436). Substitua o bloco `<div class="space-y-6 mb-6">` e seu conteúdo:

**Remova:**
```html
<div class="space-y-6 mb-6">
  <div v-for="com in comments" :key="com.comment_id" class="flex gap-4">
    <div class="w-10 h-10 rounded-full bg-gradient-to-br from-purple-500/20 to-blue-500/20 border border-white/10 flex items-center justify-center font-bold text-xs">
      {{ com.user_name?.charAt(0) || 'U' }}
    </div>
    <div class="flex-1">
      <div class="flex items-center gap-2 mb-1">
        <span class="text-sm font-bold">{{ com.user_name }}</span>
        <span class="text-[10px] text-gray-600 uppercase tracking-widest">{{ new Date(com.created_at).toLocaleDateString() }}</span>
      </div>
      <p class="text-sm text-gray-400 leading-relaxed">{{ com.comment_text }}</p>
    </div>
  </div>
</div>
```

**Substitua por:**
```html
<div class="space-y-6 mb-6">
  <CommentItem
    v-for="com in commentsTree"
    :key="com.comment_id"
    :comment="com"
    :depth="0"
  />
</div>
```

- [ ] **Step 5: Verificar que o app compila sem erros**

```bash
npm run build
```

Esperado: build sem erros de TypeScript ou Vue. Se houver erros de tipo relacionados a `parent_id` não existir no tipo da view, confirme que a Task 2 foi concluída corretamente.

- [ ] **Step 6: Commit**

```bash
git add app/pages/lesson/[id].vue
git commit -m "feat: integrate comment replies tree into lesson page"
```

---

## Task 5: Verificação manual

- [ ] **Step 1: Iniciar o servidor de desenvolvimento**

```bash
npm run dev
```

Acesse `http://localhost:3000` e navegue até uma aula.

- [ ] **Step 2: Testar fluxo de comentário raiz**

1. Escreva um comentário no campo principal e clique em "Comentar"
2. Verifique que o comentário aparece na lista
3. Verifique que o botão "Responder" aparece abaixo do comentário

- [ ] **Step 3: Testar fluxo de resposta (depth 0 → 1)**

1. Clique em "Responder" em um comentário raiz
2. Verifique que o textarea aparece inline com `@nome_usuario ` pré-preenchido
3. Escreva uma resposta e clique em "Responder"
4. Verifique que a resposta aparece indentada (com `ml-10` e borda esquerda) abaixo do pai

- [ ] **Step 4: Testar colapso (depth ≥ 2)**

1. Responda uma resposta (criando depth 2)
2. Verifique que aparece o botão "Ver X respostas" ao invés da resposta visível
3. Clique no botão e verifique que a resposta expande

- [ ] **Step 5: Testar cancelamento**

1. Clique em "Responder", verifique que o textarea abre
2. Clique em "Cancelar", verifique que o textarea fecha e o texto é limpo
3. Clique em "Responder" em outro comentário, verifique que o anterior fecha e o novo abre

- [ ] **Step 6: Commit final**

```bash
git add -A
git commit -m "feat: nested comment replies with inline reply form and collapse support"
```
