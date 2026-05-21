# Design: Respostas em Comentários

**Data:** 2026-05-21  
**Escopo:** `app/pages/lesson/[id].vue` + banco de dados Supabase

---

## Objetivo

Permitir que usuários autenticados respondam comentários na tela de aula, com suporte a múltiplos níveis de aninhamento, exibição mista (primeiros níveis visíveis, níveis mais profundos colapsados) e @menção automática ao autor ao iniciar uma resposta.

---

## Banco de Dados

### Migration

```sql
ALTER TABLE comments ADD COLUMN parent_id uuid REFERENCES comments(id) ON DELETE CASCADE;
```

- `parent_id NULL` = comentário raiz
- `parent_id NOT NULL` = resposta a outro comentário
- `ON DELETE CASCADE` remove respostas filhas ao deletar o pai

### View `content_comments_view`

Recriar para expor `parent_id`:

```sql
DROP VIEW content_comments_view;
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

### RLS

Nenhuma alteração necessária. As policies existentes em `comments` cobrem respostas por serem a mesma tabela.

---

## Frontend

### Busca de dados

Query em `useAsyncData` já existente, com duas mudanças:
1. `select('*')` passa a incluir `parent_id` (exposto pela view)
2. `order('created_at', { ascending: true })` para ordem cronológica correta nas threads

### Tipo

```ts
type CommentNode = {
  comment_id: string
  parent_id: string | null
  comment_text: string | null
  user_name: string | null
  created_at: string | null
  children: CommentNode[]
}
```

### Montagem da árvore

`computed` derivado da lista flat:

```ts
const commentsTree = computed(() => {
  const flat = (comments.value ?? []) as CommentNode[]
  const map = new Map(flat.map(c => [c.comment_id, { ...c, children: [] as CommentNode[] }]))
  const roots: CommentNode[] = []
  for (const node of map.values()) {
    if (node.parent_id) map.get(node.parent_id)?.children.push(node)
    else roots.push(node)
  }
  return roots
})
```

### Estado de resposta

Declarado em `[id].vue` e exposto via `provide` para `CommentItem`:

```ts
const replyingTo = ref<string | null>(null) // comment_id com formulário aberto
const replyText = ref('')
provide('replyingTo', replyingTo)
provide('replyText', replyText)
provide('postComment', postComment)
```

Apenas um formulário inline aberto por vez. Clicar em "Responder" em outro comentário fecha o atual.

### Função `postComment` atualizada

Recebe `parentId: string | null` opcional:

```ts
async function postComment(parentId: string | null = null) {
  const text = parentId ? replyText.value : newComment.value
  if (!text.trim() || isPostingComment.value || !user.value) return
  isPostingComment.value = true
  try {
    await supabase.from('comments').insert({
      content_id: contentId.value,
      comment_text: text,
      parent_id: parentId ?? undefined
    })
    parentId ? replyText.value = '' : newComment.value = ''
    replyingTo.value = null
    await refreshComments()
  } finally {
    isPostingComment.value = false
  }
}
```

---

## Componente `CommentItem.vue`

Componente recursivo novo em `app/components/`.

**Props:**
```ts
defineProps<{
  comment: CommentNode
  depth: number
}>()
```

**Comportamento por profundidade:**
- `depth < 2`: filhos sempre visíveis, indentados com `ml-10`
- `depth >= 2`: filhos colapsados; botão "Ver X respostas" expande via `ref` local `showChildren`

**Botão "Responder":**
- Visível em todos os níveis
- Ao clicar: define `replyingTo` via `provide/inject` (preferido sobre `emit` porque o componente é recursivo e pode ter profundidade arbitrária)
- O textarea abre inline abaixo do comentário com `@nome_do_usuario ` pré-preenchido

**Formulário inline de resposta:**
- Mesmo estilo visual do formulário principal
- `min-h-[60px]`, indentado no mesmo nível do comentário pai
- Botões: "Cancelar" (fecha, limpa `replyingTo`) e "Responder" (chama `postComment(comment_id)`)

---

## UI — Regras Visuais

| Profundidade | Indentação | Filhos visíveis por padrão |
|---|---|---|
| 0 (raiz) | nenhuma | sim |
| 1 | `ml-10` | sim |
| ≥ 2 | `ml-10` por nível | não (colapso com "Ver X respostas") |

- Avatar do autor: inicial do nome, mesmo estilo atual
- `@menção` no texto da resposta: cor `text-purple-400`, sem funcionalidade de link (apenas visual)
- Contagem no cabeçalho: usa `comments.length` (lista flat total)

---

## Fluxo de Dados

```
useAsyncData → comments (flat) → commentsTree (computed) → CommentItem (recursivo)
                                                              ↓
                                                    replyingTo (ref no [id].vue)
                                                    replyText (ref no [id].vue)
                                                    postComment(parentId)
```

---

## Fora do Escopo

- Notificações ao autor do comentário pai
- Edição ou exclusão de comentários
- Paginação de comentários/respostas
- Moderação admin
