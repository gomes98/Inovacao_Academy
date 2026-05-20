# Design: Upload de Imagem de Capa do Curso

**Data:** 2026-05-20  
**Arquivo afetado:** `app/pages/admin/courses/index.vue`

## Contexto

O formulário de criação de curso possui um campo de texto simples para URL da capa (`thumbnail_url`). O objetivo é adicionar uma alternativa de upload direto de imagem, mantendo a opção de digitar uma URL externa.

## UI

O campo "URL da Capa" é substituído por um componente com dois tabs:

- **Tab "URL":** input de texto com placeholder `https://...` (comportamento atual)
- **Tab "Upload":** área clicável para seleção de arquivo com preview da imagem e indicador de carregamento

Ao trocar de tab, o `thumbnail_url` é limpo. O componente é inline no formulário de criação, na mesma posição do campo atual.

## Fluxo de Upload

1. Usuário seleciona o tab "Upload" e escolhe um arquivo de imagem
2. Upload imediato para o bucket `courses` no Supabase Storage
3. Caminho: `thumbnails/{timestamp}.{ext}` (sem ID de curso pois ainda não foi criado)
4. URL pública retornada preenche `thumbnail_url` internamente
5. Preview da imagem é exibido no formulário
6. Ao clicar "Salvar Curso", `createCourse()` usa o `thumbnail_url` já preenchido — sem mudança na lógica de inserção

## Estado Interno

```
coverMode: 'url' | 'upload'   // tab ativo
uploadingCover: boolean        // estado de loading do upload
thumbnail_url: string          // campo existente, preenchido por ambos os modos
```

## Storage

- Bucket: `courses` (existente, usado para arquivos de conteúdo)
- Caminho: `thumbnails/{timestamp}.{ext}`
- Upload com `upsert: true`
- Validação: apenas arquivos `image/*`

## Sem mudanças em

- Lógica de `createCourse()` — continua usando `thumbnail_url` como está
- Schema do banco — `thumbnail_url` já existe na tabela `courses`
- Outros componentes ou páginas
