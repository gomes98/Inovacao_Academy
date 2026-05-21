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
  <div class="w-full bg-black/50 border border-white/10 rounded-xl overflow-hidden focus-within:border-[#FAA407]/50 transition-colors">
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
        :class="isActive ? 'bg-[#006E46] text-white' : 'text-gray-400 hover:bg-white/10 hover:text-white'"
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
        :class="isActive ? 'bg-[#006E46] text-white' : 'text-gray-400 hover:bg-white/10 hover:text-white'"
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
        :class="isActive ? 'bg-[#006E46] text-white' : 'text-gray-400 hover:bg-white/10 hover:text-white'"
      >{{ label }}</button>

      <div class="w-px h-4 bg-white/10 mx-1"></div>

      <button
        type="button"
        @click="setLink"
        class="px-2 py-1 rounded text-xs font-mono transition-colors"
        :class="editor?.isActive('link') ? 'bg-[#006E46] text-white' : 'text-gray-400 hover:bg-white/10 hover:text-white'"
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
