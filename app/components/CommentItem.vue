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
    <div class="w-8 h-8 flex-shrink-0 rounded-full bg-gradient-to-br from-[#006E46]/20 to-[#FAA407]/20 border border-white/10 flex items-center justify-center font-bold text-xs">
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
          <span v-if="part.startsWith('@')" class="text-[#FAA407]">{{ part }}</span>
          <span v-else>{{ part }}</span>
        </template>
      </p>

      <!-- Botão Responder -->
      <button
        @click="startReply"
        class="mt-2 text-[11px] text-gray-500 hover:text-[#FAA407] transition-colors font-medium uppercase tracking-widest"
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
            class="px-5 py-2 rounded-xl bg-[#006E46] text-white text-xs font-bold hover:bg-[#008266] disabled:opacity-50 transition-all uppercase tracking-widest"
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
          class="text-[11px] text-[#FAA407] hover:text-[#FAA407] transition-colors font-medium uppercase tracking-widest"
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
