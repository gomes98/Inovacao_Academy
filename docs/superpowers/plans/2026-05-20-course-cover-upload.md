# Course Cover Image Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adicionar ao formulário de criação de curso a opção de fazer upload de uma imagem de capa, como alternativa a digitar uma URL externa.

**Architecture:** O campo "URL da Capa" em `admin/courses/index.vue` é substituído por um componente inline com dois tabs (URL e Upload). O tab Upload faz upload imediato para o bucket `courses` do Supabase Storage e preenche `thumbnail_url` com a URL pública retornada. A lógica de `createCourse()` não muda.

**Tech Stack:** Nuxt 4, Vue 3 (Composition API, auto-imports), Supabase Storage, Tailwind CSS v4

---

### Task 1: Adicionar estado de controle dos tabs no `<script setup>`

**Files:**
- Modify: `app/pages/admin/courses/index.vue`

- [ ] **Step 1: Adicionar `coverMode` e `uploadingCover` ao estado existente**

Localizar o bloco de estado do `newCourse` (linha ~11) e adicionar logo abaixo:

```ts
const coverMode = ref<'url' | 'upload'>('url')
const uploadingCover = ref(false)
```

- [ ] **Step 2: Adicionar função `switchCoverMode` que limpa `thumbnail_url` ao trocar de tab**

Adicionar após as declarações de estado acima:

```ts
function switchCoverMode(mode: 'url' | 'upload') {
  coverMode.value = mode
  newCourse.value.thumbnail_url = ''
}
```

- [ ] **Step 3: Adicionar função `uploadCovertImage`**

Adicionar após `switchCoverMode`:

```ts
async function uploadCoverImage(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return

  if (!file.type.startsWith('image/')) {
    alert('Por favor, selecione uma imagem.')
    return
  }

  uploadingCover.value = true
  try {
    const fileExt = file.name.split('.').pop()
    const fileName = `thumbnails/${Date.now()}.${fileExt}`

    const { error: uploadError } = await supabase.storage
      .from('courses')
      .upload(fileName, file, { upsert: true })

    if (uploadError) throw uploadError

    const { data: { publicUrl } } = supabase.storage
      .from('courses')
      .getPublicUrl(fileName)

    newCourse.value.thumbnail_url = publicUrl
  } catch (err: any) {
    alert('Erro ao fazer upload da capa: ' + err.message)
  } finally {
    uploadingCover.value = false
  }
}
```

- [ ] **Step 4: Verificar que `isCreating` ao fechar o form limpa `coverMode` também**

Localizar onde `isCreating.value = false` é chamado (linhas ~29 e ~117) e garantir que o reset do `newCourse` esteja assim — já cobre `thumbnail_url`. Adicionar reset de `coverMode` nesses dois pontos:

Em `createCourse()` (após o insert bem-sucedido):
```ts
isCreating.value = false
newCourse.value = { title: '', description: '', thumbnail_url: '' }
coverMode.value = 'url'
```

No botão Cancelar, trocar `@click="isCreating = false"` por uma função inline ou extrair:
```ts
function cancelCreate() {
  isCreating.value = false
  newCourse.value = { title: '', description: '', thumbnail_url: '' }
  coverMode.value = 'url'
}
```

E no template, trocar `@click="isCreating = false"` por `@click="cancelCreate"`.

- [ ] **Step 5: Commit**

```bash
git add app/pages/admin/courses/index.vue
git commit -m "feat: add coverMode state and uploadCoverImage logic to course form"
```

---

### Task 2: Substituir o campo URL pelo componente de tabs no template

**Files:**
- Modify: `app/pages/admin/courses/index.vue` (seção `<template>`)

- [ ] **Step 1: Localizar o campo atual de URL da capa**

No template, encontrar o bloco:
```html
<div>
  <label class="block text-sm text-gray-400 mb-1">URL da Capa (Thumbnail)</label>
  <input v-model="newCourse.thumbnail_url" type="text" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50 transition-colors" placeholder="https://...">
</div>
```

- [ ] **Step 2: Substituir pelo componente de tabs**

Substituir o bloco inteiro pelo seguinte:

```html
<div>
  <label class="block text-sm text-gray-400 mb-2">Capa do Curso</label>

  <!-- Tabs -->
  <div class="flex gap-1 mb-3 bg-black/40 p-1 rounded-xl w-fit border border-white/10">
    <button
      type="button"
      @click="switchCoverMode('url')"
      :class="[
        'px-4 py-1.5 rounded-lg text-sm font-medium transition-all',
        coverMode === 'url'
          ? 'bg-purple-600 text-white shadow'
          : 'text-gray-400 hover:text-white'
      ]"
    >URL</button>
    <button
      type="button"
      @click="switchCoverMode('upload')"
      :class="[
        'px-4 py-1.5 rounded-lg text-sm font-medium transition-all',
        coverMode === 'upload'
          ? 'bg-purple-600 text-white shadow'
          : 'text-gray-400 hover:text-white'
      ]"
    >Upload</button>
  </div>

  <!-- Tab: URL -->
  <div v-if="coverMode === 'url'">
    <input
      v-model="newCourse.thumbnail_url"
      type="text"
      class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50 transition-colors"
      placeholder="https://..."
    >
  </div>

  <!-- Tab: Upload -->
  <div v-else>
    <label
      for="cover-upload"
      class="flex flex-col items-center justify-center w-full h-28 rounded-xl border border-dashed border-white/20 bg-black/30 cursor-pointer hover:border-purple-500/50 hover:bg-purple-500/5 transition-all relative overflow-hidden"
    >
      <!-- Preview -->
      <img
        v-if="newCourse.thumbnail_url && !uploadingCover"
        :src="newCourse.thumbnail_url"
        class="absolute inset-0 w-full h-full object-cover opacity-60"
        alt="Preview"
      >
      <!-- Loading -->
      <div v-if="uploadingCover" class="relative flex flex-col items-center gap-2 text-purple-400">
        <div class="w-6 h-6 border-2 border-purple-500/30 border-t-purple-400 animate-spin rounded-full"></div>
        <span class="text-xs font-medium">Enviando...</span>
      </div>
      <!-- Idle / após upload -->
      <div v-else class="relative flex flex-col items-center gap-1 text-gray-400">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" x2="12" y1="3" y2="15"/></svg>
        <span class="text-xs">{{ newCourse.thumbnail_url ? 'Clique para trocar' : 'Clique para selecionar' }}</span>
      </div>
      <input
        id="cover-upload"
        type="file"
        class="hidden"
        accept="image/*"
        @change="uploadCoverImage"
        :disabled="uploadingCover"
      >
    </label>
    <p v-if="newCourse.thumbnail_url && !uploadingCover" class="text-xs text-green-400 mt-1">
      Imagem carregada com sucesso
    </p>
  </div>
</div>
```

- [ ] **Step 3: Verificar que o botão "Salvar Curso" fica desabilitado durante upload**

Localizar o botão de salvar e adicionar `:disabled="uploadingCover"`:

```html
<button
  @click="createCourse"
  :disabled="uploadingCover"
  class="px-4 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white transition-all disabled:opacity-50 disabled:cursor-not-allowed"
>Salvar Curso</button>
```

- [ ] **Step 4: Testar manualmente o fluxo completo**

1. Rodar `npm run dev`
2. Acessar `/admin/courses`
3. Clicar "Novo Curso"
4. Verificar que os tabs URL e Upload aparecem corretamente
5. Tab URL: digitar uma URL e verificar que o campo aceita o valor
6. Trocar para tab Upload: verificar que `thumbnail_url` é limpo
7. Selecionar uma imagem: verificar o spinner, depois o preview e a mensagem "Imagem carregada com sucesso"
8. Preencher título e clicar "Salvar Curso": verificar que o curso é criado com a thumbnail correta na listagem
9. Cancelar o form: verificar que tudo é resetado ao reabrir

- [ ] **Step 5: Commit**

```bash
git add app/pages/admin/courses/index.vue
git commit -m "feat: replace thumbnail URL field with tabs (URL/Upload) in course creation form"
```
