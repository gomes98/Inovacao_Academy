# Rich Text Body Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Tiptap WYSIWYG HTML editor to the admin content form (available for all content types), and render the saved HTML safely in the student lesson view.

**Architecture:** Install Tiptap with StarterKit + Link extensions. Create a reusable `RichTextEditor.vue` component. In the admin course page, move the `body_text` field outside the `document`-only block and swap the textarea for the new component. In the student lesson page, replace the text interpolation with `v-html` inside a styled `prose` container.

**Tech Stack:** Nuxt 4, Vue 3, Tiptap (@tiptap/vue-3, @tiptap/starter-kit, @tiptap/extension-link), Tailwind CSS v4

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `app/components/RichTextEditor.vue` | Create | WYSIWYG editor component wrapping Tiptap |
| `app/pages/admin/courses/[id].vue` | Modify | Move body_text field, use RichTextEditor |
| `app/pages/lesson/[id].vue` | Modify | Render body_text as HTML with v-html |

---

### Task 1: Install Tiptap dependencies

**Files:**
- Modify: `package.json` (via npm install)

- [ ] **Step 1: Install packages**

```bash
npm install @tiptap/vue-3 @tiptap/starter-kit @tiptap/extension-link
```

Expected output: packages added, no errors.

- [ ] **Step 2: Verify install**

```bash
node -e "require('@tiptap/vue-3'); console.log('ok')"
```

Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore: install tiptap for rich text editor"
```

---

### Task 2: Create RichTextEditor component

**Files:**
- Create: `app/components/RichTextEditor.vue`

This component accepts `modelValue` (HTML string) and emits `update:modelValue`. It renders a toolbar with basic formatting actions and a Tiptap editor area styled to match the dark theme.

- [ ] **Step 1: Create the component**

```vue
<!-- app/components/RichTextEditor.vue -->
<script setup lang="ts">
import { useEditor, EditorContent } from '@tiptap/vue-3'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'

const props = defineProps<{ modelValue: string }>()
const emit = defineEmits<{ 'update:modelValue': [value: string] }>()

const editor = useEditor({
  content: props.modelValue,
  extensions: [
    StarterKit,
    Link.configure({ openOnClick: false }),
  ],
  editorProps: {
    attributes: {
      class: 'min-h-[160px] px-4 py-3 text-sm text-gray-200 focus:outline-none',
    },
  },
  onUpdate({ editor }) {
    emit('update:modelValue', editor.getHTML())
  },
})

watch(() => props.modelValue, (val) => {
  if (editor.value && editor.value.getHTML() !== val) {
    editor.value.commands.setContent(val, false)
  }
})

onBeforeUnmount(() => editor.value?.destroy())

function setLink() {
  const url = window.prompt('URL do link:')
  if (url) editor.value?.chain().focus().setLink({ href: url }).run()
}
</script>

<template>
  <div class="w-full bg-black/50 border border-white/10 rounded-xl overflow-hidden focus-within:border-purple-500/50 transition-colors">
    <!-- Toolbar -->
    <div class="flex flex-wrap items-center gap-1 px-3 py-2 border-b border-white/10 bg-white/[0.02]">
      <button
        v-for="({ action, label, isActive }) in [
          { action: () => editor?.chain().focus().toggleBold().run(), label: 'B', isActive: editor?.isActive('bold') },
          { action: () => editor?.chain().focus().toggleItalic().run(), label: 'I', isActive: editor?.isActive('italic') },
          { action: () => editor?.chain().focus().toggleStrike().run(), label: 'S̶', isActive: editor?.isActive('strike') },
          { action: () => editor?.chain().focus().toggleCode().run(), label: '<>', isActive: editor?.isActive('code') },
        ]"
        :key="label"
        type="button"
        @click="action"
        class="px-2 py-1 rounded text-xs font-mono transition-colors"
        :class="isActive ? 'bg-purple-600 text-white' : 'text-gray-400 hover:bg-white/10 hover:text-white'"
      >{{ label }}</button>

      <div class="w-px h-4 bg-white/10 mx-1"></div>

      <button
        v-for="({ action, label, isActive }) in [
          { action: () => editor?.chain().focus().toggleHeading({ level: 2 }).run(), label: 'H2', isActive: editor?.isActive('heading', { level: 2 }) },
          { action: () => editor?.chain().focus().toggleHeading({ level: 3 }).run(), label: 'H3', isActive: editor?.isActive('heading', { level: 3 }) },
        ]"
        :key="label"
        type="button"
        @click="action"
        class="px-2 py-1 rounded text-xs font-mono transition-colors"
        :class="isActive ? 'bg-purple-600 text-white' : 'text-gray-400 hover:bg-white/10 hover:text-white'"
      >{{ label }}</button>

      <div class="w-px h-4 bg-white/10 mx-1"></div>

      <button
        v-for="({ action, label, isActive }) in [
          { action: () => editor?.chain().focus().toggleBulletList().run(), label: '• List', isActive: editor?.isActive('bulletList') },
          { action: () => editor?.chain().focus().toggleOrderedList().run(), label: '1. List', isActive: editor?.isActive('orderedList') },
          { action: () => editor?.chain().focus().toggleBlockquote().run(), label: '❝', isActive: editor?.isActive('blockquote') },
        ]"
        :key="label"
        type="button"
        @click="action"
        class="px-2 py-1 rounded text-xs font-mono transition-colors"
        :class="isActive ? 'bg-purple-600 text-white' : 'text-gray-400 hover:bg-white/10 hover:text-white'"
      >{{ label }}</button>

      <div class="w-px h-4 bg-white/10 mx-1"></div>

      <button
        type="button"
        @click="setLink"
        class="px-2 py-1 rounded text-xs font-mono transition-colors"
        :class="editor?.isActive('link') ? 'bg-purple-600 text-white' : 'text-gray-400 hover:bg-white/10 hover:text-white'"
      >🔗</button>

      <button
        v-if="editor?.isActive('link')"
        type="button"
        @click="editor?.chain().focus().unsetLink().run()"
        class="px-2 py-1 rounded text-xs font-mono text-red-400 hover:bg-red-500/10 transition-colors"
      >✕ link</button>
    </div>

    <!-- Editor area -->
    <EditorContent :editor="editor" />
  </div>
</template>
```

- [ ] **Step 2: Commit**

```bash
git add app/components/RichTextEditor.vue
git commit -m "feat: add RichTextEditor component with Tiptap"
```

---

### Task 3: Update admin content form

**Files:**
- Modify: `app/pages/admin/courses/[id].vue`

Two changes:
1. Move the `body_text` field out of the `v-if="content_type === 'document'"` block so it appears for all content types.
2. Replace the `<textarea v-model="contentForm.body_text">` with `<RichTextEditor v-model="contentForm.body_text" />`.

- [ ] **Step 1: Move body_text field and replace textarea**

In `app/pages/admin/courses/[id].vue`, find lines 531–535:

```vue
<div v-if="contentForm.content_type === 'document'" class="md:col-span-2 space-y-4">
  <div>
    <label class="block text-xs text-gray-400 mb-1">Texto (Opcional)</label>
    <textarea v-model="contentForm.body_text" rows="3" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50"></textarea>
  </div>
```

Replace **only the body_text `<div>` inside that block** — extract it and place it as a standalone field above the `v-if` blocks, just before the `<div class="w-24">` order field (around line 547). The final structure inside the `grid` should be:

```vue
<!-- body_text — available for all content types -->
<div class="md:col-span-2">
  <label class="block text-xs text-gray-400 mb-1">Descrição / Instruções (HTML)</label>
  <RichTextEditor v-model="contentForm.body_text" />
</div>

<!-- video-specific fields -->
<div v-if="contentForm.content_type === 'video'" class="md:col-span-2 space-y-4">
  ...existing video fields...
</div>

<!-- document-specific fields (remove the body_text div from here) -->
<div v-if="contentForm.content_type === 'document'" class="md:col-span-2 space-y-4">
  ...existing document fields WITHOUT the body_text div...
</div>

<!-- order field -->
<div>
  <label class="block text-xs text-gray-400 mb-1">Ordem</label>
  ...
</div>
```

- [ ] **Step 2: Verify the page compiles (dev server or build)**

```bash
npm run build 2>&1 | tail -20
```

Expected: no TypeScript or template errors.

- [ ] **Step 3: Commit**

```bash
git add app/pages/admin/courses/[id].vue
git commit -m "feat: add body_text rich text editor to all content types in admin"
```

---

### Task 4: Render HTML in student lesson view

**Files:**
- Modify: `app/pages/lesson/[id].vue` (line 361–363)

- [ ] **Step 1: Replace text interpolation with v-html**

Find this block (around line 361):

```vue
<div v-if="content?.body_text" class="prose prose-invert max-w-none text-gray-400 leading-relaxed text-lg mb-8">
  {{ content.body_text }}
</div>
```

Replace with:

```vue
<div
  v-if="content?.body_text"
  class="prose prose-invert prose-headings:text-white prose-a:text-purple-400 prose-strong:text-white prose-code:text-purple-300 prose-blockquote:border-purple-500 max-w-none text-gray-400 leading-relaxed text-lg mb-8"
  v-html="content.body_text"
></div>
```

Note: Tailwind's `prose` classes handle HTML element styling. `v-html` renders the saved Tiptap HTML. The content is admin-authored (not user-supplied), so XSS risk is acceptable — but only admins can write to `body_text` via Supabase RLS.

- [ ] **Step 2: Verify the page compiles**

```bash
npm run build 2>&1 | tail -20
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/pages/lesson/[id].vue
git commit -m "feat: render body_text as HTML in student lesson view"
```

---

### Task 5: Install Tailwind Typography plugin (for prose styles)

The `prose` / `prose-invert` classes require `@tailwindcss/typography`.

- [ ] **Step 1: Check if already installed**

```bash
node -e "require('@tailwindcss/typography'); console.log('already installed')" 2>/dev/null || echo "not installed"
```

- [ ] **Step 2: Install if missing**

```bash
npm install -D @tailwindcss/typography
```

- [ ] **Step 3: Add plugin to Tailwind config**

Check if there is a `tailwind.config.js` or `tailwind.config.ts` at project root. If it exists, add the plugin:

```js
// tailwind.config.js
export default {
  plugins: [
    require('@tailwindcss/typography'),
  ],
}
```

If no config file exists (Tailwind v4 CSS-only config), add to your main CSS file (typically `app/assets/css/main.css` or similar):

```css
@plugin "@tailwindcss/typography";
```

- [ ] **Step 4: Verify prose styles are applied by running dev server and checking lesson page visually**

```bash
npm run dev
```

Open `http://localhost:3000/lesson/<any-id>` with a content that has `body_text`. Confirm formatted HTML renders correctly.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json tailwind.config.* app/assets/
git commit -m "chore: add tailwindcss/typography for prose HTML rendering"
```
