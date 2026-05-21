<script setup lang="ts">
const route = useRoute()
const supabase = useSupabaseClient()
const user = useSupabaseUser()

const gamification = useGamification()

watch(user, async (u) => {
  if (u?.id) await gamification.loadUserData()
}, { immediate: true })

const contentId = computed(() => route.params.id as string)
const startTime = computed(() => Number(route.query.t) || 0)

// 1. Busca os detalhes da aula
const { data: content, error: contentError } = await useAsyncData(() => `content-${contentId.value}`, async () => {
  const { data } = await supabase.from('contents').select('*, modules(title, courses(id, title)), attachments(*)').eq('id', contentId.value).single()
  return data
}, { watch: [contentId] })

// Expõe o courseId para a busca contextual da AppBar
watch(content, (c) => {
  if (c?.modules?.courses?.id) {
    useState('currentCourseId').value = c.modules.courses.id
  }
}, { immediate: true })

// 2. Busca os comentários (via view para pegar nomes)
const { data: comments, refresh: refreshComments } = await useAsyncData(() => `comments-${contentId.value}`, async () => {
  const { data } = await supabase.from('content_comments_view').select('*').eq('content_id', contentId.value).order('created_at', { ascending: true })
  return data
}, { watch: [contentId] })

// 3. Busca a playlist do mesmo módulo
const { data: playlist } = await useAsyncData(() => `playlist-${content.value?.module_id}`, async () => {
  if (!content.value?.module_id) return []
  const { data } = await supabase
    .from('contents')
    .select('id, title, video_url, order_index')
    .eq('module_id', content.value.module_id)
    .order('order_index', { ascending: true })
  return data
}, { watch: [content] })

// 4. Busca a nota privada do usuário (v2 para limpar cache)
const { data: privateNote, refresh: refreshNote } = await useAsyncData(() => `private-note-v2-${user.value?.id}-${contentId.value}`, async () => {
  const userId = user.value?.id
  if (!userId) return null
  
  const { data, error } = await supabase
    .from('private_notes')
    .select('*')
    .eq('content_id', contentId.value)
    .eq('user_id', userId)
    .maybeSingle()
  
  if (error) {
    console.error('Erro ao buscar nota:', error)
    return null
  }
  return data
}, { watch: [user, contentId] })

// 5. Busca o progresso do usuário para os conteúdos da playlist
const { data: userProgress, refresh: refreshProgress } = await useAsyncData(() => `user-progress-${user.value?.id}-${content.value?.module_id}`, async () => {
  const userId = user.value?.id
  if (!userId || !content.value?.module_id) return []
  
  // Pegamos os IDs dos conteúdos da playlist para filtrar o progresso
  const contentIds = playlist.value?.map(p => p.id) || []
  if (contentIds.length === 0) return []

  const { data } = await supabase
    .from('user_progress')
    .select('content_id')
    .eq('user_id', userId)
    .in('content_id', contentIds)
  
  return data?.map(p => p.content_id) || []
}, { watch: [user, playlist] })

const isCompleted = computed(() => userProgress.value?.includes(contentId.value))
const isTogglingProgress = ref(false)

async function toggleCompletion() {
  if (!user.value || isTogglingProgress.value) return
  isTogglingProgress.value = true

  try {
    if (isCompleted.value) {
      // Remover conclusão
      await supabase
        .from('user_progress')
        .delete()
        .eq('user_id', user.value?.id)
        .eq('content_id', contentId.value)
    } else {
      // Marcar como concluído
      // Não passamos user_id para deixar o banco usar o default auth.uid()
      await supabase
        .from('user_progress')
        .insert({
          content_id: contentId.value
        })
      await gamification.trackEvent('video_completed', contentId.value)
    }
    await refreshProgress()
  } catch (err) {
    console.error('Erro ao alternar progresso:', err)
  } finally {
    isTogglingProgress.value = false
  }
}

const autoMarked = ref(false)

// Mark as finished logic remains the same, but triggered by component event
async function markAsFinishedAuto() {
  if (isCompleted.value || autoMarked.value || isTogglingProgress.value) return
  
  autoMarked.value = true 
  isTogglingProgress.value = true
  
  try {
    const { error } = await supabase.from('user_progress').upsert({
      content_id: contentId.value
    }, { onConflict: 'user_id,content_id' })
    
    if (!error) {
      await refreshProgress()
      await gamification.trackEvent('video_watched', contentId.value)
    }
  } catch (err) {
    console.error('Erro ao marcar progresso automático:', err)
  } finally {
    isTogglingProgress.value = false
  }
}

// Reset flag ao mudar de aula
watch(contentId, () => {
  autoMarked.value = false
  noteText.value = ''
})

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

// Sincroniza nota inicial
watch(privateNote, (val) => {
  if (val) noteText.value = val.note_text
}, { immediate: true })

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

    if (error) throw error

    if (parentId) {
      replyText.value = ''
    } else {
      newComment.value = ''
    }
    replyingTo.value = null
    await refreshComments()

    // Rastreia gamificação com o id do comentário recém inserido
    const newest = comments.value?.[comments.value.length - 1]
    if (newest?.comment_id) {
      await gamification.trackEvent(
        parentId ? 'comment_replied' : 'comment_posted',
        newest.comment_id
      )
    }
  } catch (err) {
    alert('Erro ao postar comentário. Verifique o console.')
    console.error(err)
  } finally {
    isPostingComment.value = false
  }
}

provide('replyingTo', replyingTo)
provide('replyText', replyText)
provide('postComment', postComment)

async function saveNote() {
  if (isSavingNote.value || !user.value) return
  
  isSavingNote.value = true
  try {
    // Usamos upsert com o constraint de unicidade (user_id, content_id)
    // O banco já tem o default para user_id (auth.uid()), mas para o upsert 
    // funcionar bem com a restrição unique_user_content_note, 
    // às vezes é melhor ser explícito ou deixar o RLS cuidar.
    const { error } = await supabase
      .from('private_notes')
      .upsert({
        content_id: contentId.value,
        user_id: user.value.id, // Explicitamente passamos aqui para o upsert saber qual linha atualizar
        note_text: noteText.value,
        updated_at: new Date()
      }, {
        onConflict: 'user_id,content_id'
      })

    if (error) {
      console.error('Erro Supabase (Nota):', error)
      throw error
    }

    await refreshNote()
  } catch (err) {
    alert('Erro ao salvar nota. Verifique o console.')
    console.error(err)
  } finally {
    isSavingNote.value = false
  }
}

</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white font-sans selection:bg-purple-500/30 pb-20">
    <div class="fixed inset-0 overflow-hidden pointer-events-none">
      <div class="absolute -bottom-[10%] -left-[10%] w-[40%] h-[40%] bg-purple-600/10 blur-[120px] rounded-full"></div>
    </div>

    <main class="relative z-10 max-w-7xl mx-auto p-6 lg:p-10">
      <!-- Breadcrumbs -->
      <nav class="flex items-center gap-2 text-xs text-gray-500 mb-8 uppercase tracking-widest font-medium">
        <NuxtLink :to="`/courses/${content?.modules?.courses?.id}`" class="hover:text-purple-400 transition-colors">
          {{ content?.modules?.courses?.title }}
        </NuxtLink>
        <span>/</span>
        <span class="text-gray-400">{{ content?.modules?.title }}</span>
      </nav>

      <div class="space-y-12">
        <!-- Main Content (Video + Playlist) -->
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-6 lg:gap-10">
          <div class="lg:col-span-3">
              <div class="aspect-video rounded-[32px] bg-black border border-white/10 overflow-hidden shadow-2xl relative group">
                <template v-if="content?.video_url">
                  <ClientOnly>
                    <VideoPlayer
                      :src="content.video_url"
                      :start-time="startTime"
                      @progress-90="markAsFinishedAuto"
                    />
                  </ClientOnly>
                </template>
                <div v-else class="w-full h-full flex flex-col items-center justify-center bg-gradient-to-br from-white/[0.02] to-white/[0.05]">
                   <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" class="text-white/10 mb-4"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
                   <p class="text-gray-500">Nenhum vídeo disponível para esta aula.</p>
                </div>
              </div>
            </div>

            <!-- Playlist Sidebar -->
            <div class="lg:col-span-1 flex flex-col h-full max-h-[500px] lg:max-h-full">
              <div class="flex-1 rounded-[32px] bg-white/[0.03] border border-white/10 overflow-hidden flex flex-col">
                <div class="p-5 border-b border-white/10 bg-white/[0.02]">
                  <h3 class="text-sm font-bold flex items-center gap-2 uppercase tracking-widest text-gray-400">
                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-purple-400"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M15 3v18"/><path d="M8 8h2"/><path d="M8 12h2"/><path d="M8 16h2"/></svg>
                    Conteúdo
                  </h3>
                </div>
                <div class="flex-1 overflow-y-auto p-2 custom-scrollbar">
                  <div class="space-y-1">
                    <NuxtLink 
                      v-for="(item, idx) in playlist" 
                      :key="item.id"
                      :to="`/lesson/${item.id}`"
                      class="group flex items-center gap-3 p-3 rounded-2xl transition-all hover:bg-white/5"
                      :class="[item.id === contentId ? 'bg-purple-600/20 border border-purple-500/30' : 'border border-transparent']"
                    >
                      <div class="w-8 h-8 flex-shrink-0 rounded-lg flex items-center justify-center text-[10px] font-bold border transition-colors overflow-hidden relative"
                        :class="[item.id === contentId ? 'bg-purple-600 border-purple-400 text-white' : 'bg-white/5 border-white/10 text-gray-500 group-hover:border-white/20 group-hover:text-gray-300']"
                      >
                        <template v-if="item.video_url">
                          <img
                            :src="item.video_url.replace(/\.[^.]+$/, '.jpg')"
                            class="absolute inset-0 w-full h-full object-cover rounded-lg"
                            @error="(e) => { (e.target as HTMLElement).style.display = 'none'; (e.target as HTMLElement).nextElementSibling?.removeAttribute('style') }"
                          />
                          <div class="absolute inset-0 flex items-center justify-center bg-black/30 rounded-lg">
                            <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="white" stroke="none"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                          </div>
                          <span style="display:none" class="relative z-10">{{ idx + 1 }}</span>
                        </template>
                        <span v-else>{{ idx + 1 }}</span>
                      </div>
                      <div class="flex-1 min-w-0">
                        <div class="flex items-center justify-between gap-2">
                          <p class="text-[13px] font-medium truncate transition-colors"
                            :class="[item.id === contentId ? 'text-white' : 'text-gray-400 group-hover:text-gray-200']"
                          >
                            {{ item.title }}
                          </p>
                          <svg v-if="userProgress?.includes(item.id)" xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" class="text-emerald-400"><polyline points="20 6 9 17 4 12"/></svg>
                        </div>
                        <div class="flex items-center gap-1.5 mt-0.5">
                          <svg v-if="item.video_url" xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-purple-400"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                          <svg v-else xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-blue-400"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
                          <span class="text-[9px] uppercase tracking-tighter text-gray-600">{{ item.video_url ? 'Vídeo' : 'Aula' }}</span>
                        </div>
                      </div>
                    </NuxtLink>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="space-y-12">
            <div class="max-w-4xl">
              <div class="flex flex-col md:flex-row md:items-center justify-between gap-6 mb-8">
                <h1 class="text-3xl lg:text-4xl font-bold bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">{{ content?.title }}</h1>
                
                <button 
                  @click="toggleCompletion"
                  :disabled="isTogglingProgress"
                  class="flex-shrink-0 flex items-center justify-center gap-2 px-6 py-3 rounded-2xl font-bold text-xs uppercase tracking-widest transition-all group"
                  :class="[isCompleted ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 hover:bg-emerald-500/20' : 'bg-white text-black hover:bg-gray-200']"
                >
                  <svg v-if="isTogglingProgress" class="animate-spin h-4 w-4" viewBox="0 0 24 24">
                    <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"></circle>
                    <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  <template v-else>
                    <svg v-if="isCompleted" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" class="text-emerald-400"><polyline points="20 6 9 17 4 12"/></svg>
                    <svg v-else xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="group-hover:scale-110 transition-transform"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                    {{ isCompleted ? 'Aula Concluída' : 'Marcar como Concluída' }}
                  </template>
                </button>
              </div>
              
              <div
                v-if="content?.body_text"
                class="prose prose-invert prose-headings:text-white prose-a:text-purple-400 prose-strong:text-white prose-code:text-purple-300 prose-blockquote:border-purple-500 max-w-none text-gray-400 leading-relaxed text-lg mb-8"
                v-html="content.body_text"
              ></div>

              <!-- Attachments Section -->
              <div v-if="content?.attachments?.length" class="mt-8 pt-8 border-t border-white/10">
                <h3 class="text-sm font-bold uppercase tracking-widest text-gray-500 mb-4 flex items-center gap-2">
                  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-blue-400"><path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.51a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>
                  Materiais de Apoio ({{ content.attachments.length }})
                </h3>
                <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <a 
                    v-for="file in content.attachments" 
                    :key="file.id"
                    :href="file.file_url"
                    target="_blank"
                    download
                    class="group flex items-center gap-4 p-4 rounded-2xl bg-white/[0.03] border border-white/5 hover:border-blue-500/30 hover:bg-white/5 transition-all"
                  >
                    <div class="w-10 h-10 rounded-xl bg-blue-500/10 flex items-center justify-center text-blue-400 border border-blue-500/20 group-hover:scale-110 transition-transform">
                      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                    </div>
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium text-gray-200 truncate">{{ file.name }}</p>
                      <p class="text-[10px] text-gray-500 uppercase tracking-tighter">{{ (file.file_size / 1024 / 1024).toFixed(2) }} MB</p>
                    </div>
                    <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-gray-700 group-hover:text-blue-400 transition-colors"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
                  </a>
                </div>
              </div>
            </div>

            <!-- Private Notes Section -->
            <div class="pt-10 border-t border-white/10">
              <div class="glass-card p-8 rounded-[32px] border border-white/10 bg-white/5 backdrop-blur-2xl shadow-[0_32px_64px_-12px_rgba(0,0,0,0.8)]">
                <h3 class="text-lg font-bold mb-6 flex items-center gap-3 text-white">
                  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-yellow-500/80"><path d="M15.5 3H5a2 2 0 0 0-2 2v14c0 1.1.9 2 2 2h14a2 2 0 0 0 2-2V8.5L15.5 3Z"/><path d="M15 3v6h6"/><path d="M8 13h8"/><path d="M8 17h8"/><path d="M8 9h3"/></svg>
                  Minhas Anotações
                </h3>
                <p class="text-xs text-gray-500 mb-6 leading-relaxed">Suas anotações são pessoais e só você pode vê-las. Ótimo para fixar o aprendizado.</p>
                
                <textarea 
                  v-model="noteText"
                  class="w-full bg-white/[0.03] border border-white/5 rounded-2xl p-4 text-sm text-gray-200 placeholder-gray-700 min-h-[200px] focus:border-purple-500/30 transition-all outline-none"
                  placeholder="Digite aqui seus insights sobre esta aula..."
                ></textarea>
                
                <div class="flex items-center justify-between mt-6">
                  <div v-if="privateNote?.updated_at" class="text-[10px] text-gray-600 italic">
                    Última alteração: {{ new Date(privateNote.updated_at).toLocaleString() }}
                  </div>
                  <div v-else></div>
                  
                  <button 
                    @click="saveNote"
                    :disabled="isSavingNote"
                    class="px-8 py-3 rounded-2xl bg-white text-black font-bold text-xs uppercase tracking-widest hover:bg-gray-200 transition-all flex items-center justify-center gap-2"
                  >
                    <svg v-if="isSavingNote" class="animate-spin h-4 w-4" viewBox="0 0 24 24">
                      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"></circle>
                      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                    </svg>
                    {{ isSavingNote ? 'Salvando...' : 'Salvar Anotação' }}
                  </button>
                </div>
              </div>
            </div>

            <!-- Comments Section -->
            <div class="pt-10 border-t border-white/10">
              <h2 class="text-xl font-bold mb-8 flex items-center gap-3">
                <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="text-purple-400"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
                Comentários ({{ comments?.length || 0 }})
              </h2>

              <div class="space-y-6 mb-6">
                <CommentItem
                  v-for="com in commentsTree"
                  :key="com.comment_id"
                  :comment="com"
                  :depth="0"
                />
              </div>

              <div class="mb-10 p-6 rounded-3xl bg-white/[0.02] border border-white/5">
                <textarea 
                  v-model="newComment"
                  placeholder="O que achou dessa aula?"
                  class="w-full bg-transparent border-none focus:ring-0 text-sm text-white placeholder-gray-600 min-h-[80px] resize-none"
                ></textarea>
                <div class="flex justify-end mt-4 pt-4 border-t border-white/5">
                  <button 
                    @click="postComment"
                    :disabled="isPostingComment || !newComment.trim()"
                    class="px-6 py-2 rounded-xl bg-purple-600 text-white text-xs font-bold hover:bg-purple-500 disabled:opacity-50 transition-all"
                  >
                    {{ isPostingComment ? 'Postando...' : 'Comentar' }}
                  </button>
                </div>
              </div>

              
            </div>
        </div>
      </div>
    </main>

    <PointToast
      :points="gamification.lastPointsEarned.value?.points ?? null"
      :label="gamification.lastPointsEarned.value?.label ?? null"
      :badge="gamification.newlyEarnedBadge.value"
      @close="gamification.clearToasts()"
    />
  </div>
</template>

<style scoped>
.glass-card {
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
}

.custom-scrollbar::-webkit-scrollbar {
  width: 4px;
}

.custom-scrollbar::-webkit-scrollbar-track {
  background: transparent;
}

.custom-scrollbar::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.1);
  border-radius: 10px;
}

.custom-scrollbar::-webkit-scrollbar-thumb:hover {
  background: rgba(139, 92, 246, 0.3);
}
</style>
