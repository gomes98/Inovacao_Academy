<script setup lang="ts">
const route = useRoute()
const supabase = useSupabaseClient()

const courseId = route.params.id as string

const { data: course, refresh: refreshCourse } = await useAsyncData(`admin-course-${courseId}`, async () => {
  const { data } = await supabase.from('courses').select('*').eq('id', courseId).single()
  return data
})

const { data: modules, refresh: refreshModules } = await useAsyncData(`admin-modules-${courseId}`, async () => {
  const { data } = await supabase.from('modules').select('*, contents(*)').eq('course_id', courseId).order('order_index')
  // Sort contents inside modules
  if (data) {
    data.forEach(m => {
      m.contents.sort((a, b) => a.order_index - b.order_index)
    })
  }
  return data || []
})

// Module Creation & Editing
const isCreatingModule = ref(false)
const editingModuleId = ref<string | null>(null)
const newModule = ref({ title: '', order_index: 0 })

function startEditModule(mod: any) {
  isCreatingModule.value = true
  editingModuleId.value = mod.id
  newModule.value = { title: mod.title, order_index: mod.order_index }
}

async function createModule() {
  if (!newModule.value.title) return
  
  const moduleData = {
    course_id: courseId,
    title: newModule.value.title,
    order_index: newModule.value.order_index
  }

  let error
  if (editingModuleId.value) {
    const { error: err } = await supabase.from('modules').update(moduleData).eq('id', editingModuleId.value)
    error = err
  } else {
    const { error: err } = await supabase.from('modules').insert([moduleData])
    error = err
  }

  if (!error) {
    isCreatingModule.value = false
    editingModuleId.value = null
    newModule.value = { title: '', order_index: (modules.value?.length || 0) + 1 }
    await refreshModules()
  } else {
    alert('Erro: ' + error.message)
  }
}

// Content Creation & Editing
const creatingContentForModule = ref<string | null>(null)
const editingContentId = ref<string | null>(null)
const contentForm = ref({
  title: '',
  content_type: 'video',
  body_text: '',
  video_url: '',
  file_url: '',
  order_index: 0
})
const fileUpload = ref<File | null>(null)
const attachmentsUpload = ref<File[]>([])
const isUploading = ref(false)

function openContentForm(moduleId: string) {
  creatingContentForModule.value = moduleId
  editingContentId.value = null
  const mod = modules.value?.find(m => m.id === moduleId)
  contentForm.value = {
    title: '',
    content_type: 'video',
    body_text: '',
    video_url: '',
    file_url: '',
    order_index: mod?.contents.length || 0
  }
  fileUpload.value = null
  attachmentsUpload.value = []
}

function startEditContent(moduleId: string, content: any) {
  creatingContentForModule.value = moduleId
  editingContentId.value = content.id
  contentForm.value = {
    title: content.title,
    content_type: content.content_type,
    body_text: content.body_text || '',
    video_url: content.video_url || '',
    file_url: content.file_url || '',
    order_index: content.order_index
  }
  fileUpload.value = null
  attachmentsUpload.value = []
}

async function handleFileUpload(event: Event) {
  const target = event.target as HTMLInputElement
  if (target.files?.length) {
    fileUpload.value = target.files[0]
  }
}

async function handleAttachmentsUpload(event: Event) {
  const target = event.target as HTMLInputElement
  if (target.files?.length) {
    attachmentsUpload.value = Array.from(target.files)
  }
}

async function saveContent(moduleId: string) {
  if (!contentForm.value.title) return
  
  isUploading.value = true
  let finalFileUrl = contentForm.value.file_url

  // 1. Upload main file (video or document) if new one selected
  if (fileUpload.value) {
    const fileExt = fileUpload.value.name.split('.').pop()
    const fileName = `${Math.random().toString(36).substring(7)}.${fileExt}`
    const bucketName = 'courses'
    const filePath = `course-${courseId}/${moduleId}/${fileName}`
    
    const { data: uploadData, error: uploadError } = await supabase.storage.from(bucketName).upload(filePath, fileUpload.value)
    
    if (uploadError) {
      alert('Erro no upload principal: ' + uploadError.message)
      isUploading.value = false
      return
    }
    
    const { data: publicUrlData } = supabase.storage.from(bucketName).getPublicUrl(filePath)
    
    if (contentForm.value.content_type === 'video') {
      contentForm.value.video_url = publicUrlData.publicUrl
    } else {
      finalFileUrl = publicUrlData.publicUrl
    }
  }

  const contentPayload = {
    module_id: moduleId,
    title: contentForm.value.title,
    content_type: contentForm.value.content_type,
    body_text: contentForm.value.body_text,
    video_url: contentForm.value.video_url,
    file_url: finalFileUrl,
    order_index: contentForm.value.order_index
  }

  let savedContentId = editingContentId.value

  if (editingContentId.value) {
    // 2a. Update content
    const { error: updateError } = await supabase.from('contents').update(contentPayload).eq('id', editingContentId.value)
    if (updateError) {
      alert('Erro ao atualizar conteúdo: ' + updateError.message)
      isUploading.value = false
      return
    }
  } else {
    // 2b. Insert content
    const { data: insertedContent, error: contentError } = await supabase.from('contents').insert([contentPayload]).select().single()
    if (contentError) {
      alert('Erro ao criar conteúdo: ' + contentError.message)
      isUploading.value = false
      return
    }
    savedContentId = insertedContent.id
  }

  // 3. Upload and insert NEW attachments (optional)
  if (attachmentsUpload.value.length > 0 && savedContentId) {
    for (const file of attachmentsUpload.value) {
      const fileExt = file.name.split('.').pop()
      const fileName = `${Math.random().toString(36).substring(7)}_${file.name}`
      const bucketName = 'files'
      const filePath = `attachments/${savedContentId}/${fileName}`

      const { data: uploadData, error: uploadError } = await supabase.storage.from(bucketName).upload(filePath, file)

      if (!uploadError) {
        const { data: publicUrlData } = supabase.storage.from(bucketName).getPublicUrl(filePath)
        
        await supabase.from('attachments').insert({
          content_id: savedContentId,
          name: file.name,
          file_url: publicUrlData.publicUrl,
          file_type: file.type,
          file_size: file.size
        })
      }
    }
  }

  isUploading.value = false
  creatingContentForModule.value = null
  editingContentId.value = null
  fileUpload.value = null
  attachmentsUpload.value = []
  await refreshModules()
}

function getPathFromUrl(url: string, bucket: string) {
  if (!url || !url.includes('.supabase.co/storage/v1/object/public/')) return null
  const parts = url.split(`/public/${bucket}/`)
  if (parts.length < 2) return null
  const path = parts[1].split('?')[0] // Remove query params if any
  return decodeURI(path)
}

async function deleteContent(content: any) {
  if (!confirm(`Tem certeza que deseja excluir a aula "${content.title}"? Todos os arquivos e dados relacionados serão removidos permanentemente.`)) return

  isUploading.value = true

  try {
    // 1. Get attachments to delete files from storage
    const { data: attachments } = await supabase.from('attachments').select('file_url').eq('content_id', content.id)
    
    if (attachments && attachments.length > 0) {
      const attachmentPaths = attachments.map(a => getPathFromUrl(a.file_url, 'files')).filter(Boolean) as string[]
      if (attachmentPaths.length > 0) {
        await supabase.storage.from('files').remove(attachmentPaths)
      }
    }

    // 2. Delete main files from storage
    const coursesFilesToDelete: string[] = []
    
    // Process video_url
    const videoPath = getPathFromUrl(content.video_url, 'courses')
    if (videoPath) {
      if (videoPath.endsWith('.m3u8')) {
        // HLS: Delete all files with the same prefix in the same folder
        const lastSlashIndex = videoPath.lastIndexOf('/')
        const folderPath = lastSlashIndex !== -1 ? videoPath.substring(0, lastSlashIndex) : ''
        const fileName = videoPath.split('/').pop() || ''
        const baseName = fileName.replace('.m3u8', '')
        
        let allHlsFiles: string[] = []
        let offset = 0
        const limit = 1000
        let hasMore = true
        
        while (hasMore) {
          const { data: files, error: listError } = await supabase.storage.from('courses').list(folderPath, {
            limit,
            offset,
            search: baseName
          })
          
          if (listError) throw listError
          
          if (!files || files.length === 0) {
            hasMore = false
          } else {
            // Filter files that are either the exact m3u8 or variants/segments (nome_1080p..., nome.ts, etc.)
            const hlsFiles = files
              .filter(f => f.name === fileName || f.name.startsWith(baseName + '_') || f.name.startsWith(baseName + '.'))
              .map(f => folderPath ? `${folderPath}/${f.name}` : f.name)
            
            allHlsFiles = [...allHlsFiles, ...hlsFiles]
            offset += limit
            if (files.length < limit) hasMore = false
          }
        }

        // Delete in chunks of 100 (Storage.remove limit)
        if (allHlsFiles.length > 0) {
          for (let i = 0; i < allHlsFiles.length; i += 100) {
            const chunk = allHlsFiles.slice(i, i + 100)
            await supabase.storage.from('courses').remove(chunk)
          }
        }
      } else {
        coursesFilesToDelete.push(videoPath)
      }
    }

    // Process file_url (for documents)
    const filePath = getPathFromUrl(content.file_url, 'courses')
    if (filePath && !coursesFilesToDelete.includes(filePath)) {
      coursesFilesToDelete.push(filePath)
    }

    if (coursesFilesToDelete.length > 0) {
      await supabase.storage.from('courses').remove(coursesFilesToDelete)
    }

    // 3. Delete content record (cascade will handle other tables)
    const { error } = await supabase.from('contents').delete().eq('id', content.id)
    
    if (error) throw error

    await refreshModules()
  } catch (error: any) {
    console.error('Delete error:', error)
    alert('Erro ao excluir conteúdo: ' + error.message)
  } finally {
    isUploading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white font-sans selection:bg-purple-500/30 pb-20">
    <div class="fixed inset-0 overflow-hidden pointer-events-none">
      <div class="absolute top-[20%] right-[10%] w-[30%] h-[30%] bg-purple-600/10 blur-[120px] rounded-full"></div>
    </div>

    <main class="relative z-10 max-w-5xl mx-auto p-8">
      <header class="mb-12">
        <NuxtLink to="/admin/courses" class="text-sm text-gray-500 hover:text-purple-400 flex items-center gap-2 mb-6 transition-colors">
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>
          Voltar para Cursos
        </NuxtLink>
        <div class="flex justify-between items-start">
          <div>
            <h1 class="text-3xl font-bold tracking-tight bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">
              {{ course?.title || 'Carregando...' }}
            </h1>
            <p class="text-gray-400 mt-2">Gerencie os módulos e conteúdos deste curso.</p>
          </div>
          <button 
            @click="isCreatingModule = true"
            class="px-4 py-2 rounded-xl bg-white/10 hover:bg-white/20 text-white font-medium transition-all flex items-center gap-2"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
            Adicionar Módulo
          </button>
        </div>
      </header>

      <!-- Create/Edit Module Form -->
      <div v-if="isCreatingModule" class="mb-10 p-6 glass-card rounded-2xl border border-white/10 bg-white/5 backdrop-blur-xl">
        <h3 class="text-lg font-medium mb-4">{{ editingModuleId ? 'Editar' : 'Novo' }} Módulo</h3>
        <div class="flex gap-4 items-end">
          <div class="flex-1">
            <label class="block text-xs text-gray-400 mb-1">Título do Módulo</label>
            <input v-model="newModule.title" type="text" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50">
          </div>
          <div class="w-24">
            <label class="block text-xs text-gray-400 mb-1">Ordem</label>
            <input v-model="newModule.order_index" type="number" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50">
          </div>
          <button @click="isCreatingModule = false; editingModuleId = null" class="px-4 py-2 rounded-xl bg-transparent text-gray-400 hover:text-white transition-colors">Cancelar</button>
          <button @click="createModule" class="px-4 py-2 rounded-xl bg-purple-600 hover:bg-purple-500 text-white transition-colors">Salvar</button>
        </div>
      </div>

      <!-- Modules List -->
      <div class="space-y-8">
        <div v-for="mod in modules" :key="mod.id" class="glass-card rounded-3xl border border-white/10 bg-white/[0.02] backdrop-blur-xl overflow-hidden group/mod">
          <div class="p-5 border-b border-white/5 bg-white/[0.03] flex justify-between items-center">
            <h2 class="text-xl font-semibold flex items-center gap-3">
              <span class="text-purple-400">{{ mod.order_index }}.</span>
              {{ mod.title }}
              <button @click="startEditModule(mod)" class="p-1.5 rounded-lg hover:bg-white/5 text-gray-600 hover:text-purple-400 transition-all opacity-0 group-hover/mod:opacity-100">
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
              </button>
            </h2>
            <button @click="openContentForm(mod.id)" class="text-sm px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/10 text-white transition-colors flex items-center gap-1">
              <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
              Adicionar Conteúdo
            </button>
          </div>

          <!-- Content Creation/Editing Form -->
          <div v-if="creatingContentForModule === mod.id" class="p-6 bg-purple-900/10 border-b border-purple-500/20">
            <h4 class="text-sm font-medium text-purple-300 mb-4">{{ editingContentId ? 'Editar' : 'Novo' }} Conteúdo para "{{ mod.title }}"</h4>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
              <div>
                <label class="block text-xs text-gray-400 mb-1">Título da Aula/Material</label>
                <input v-model="contentForm.title" type="text" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50">
              </div>
              <div>
                <label class="block text-xs text-gray-400 mb-1">Tipo de Conteúdo</label>
                <select v-model="contentForm.content_type" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50 appearance-none">
                  <option value="video">Vídeo</option>
                  <option value="document">Documento / Texto / Arquivo</option>
                </select>
              </div>

              <div v-if="contentForm.content_type === 'video'" class="md:col-span-2 space-y-4">
                <div>
                  <label class="block text-xs text-gray-400 mb-1">URL do Vídeo (YouTube, Vimeo, etc)</label>
                  <input v-model="contentForm.video_url" type="text" placeholder="https://..." class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50">
                </div>
                <div class="relative">
                  <div class="flex items-center gap-4 mb-2">
                    <div class="h-px flex-1 bg-white/10"></div>
                    <span class="text-[10px] uppercase tracking-widest text-gray-500 font-bold">ou faça upload</span>
                    <div class="h-px flex-1 bg-white/10"></div>
                  </div>
                  <label class="block text-xs text-gray-400 mb-1">Upload de Arquivo de Vídeo (Opcional se já existe)</label>
                  <input type="file" accept="video/*" @change="handleFileUpload" class="block w-full text-sm text-gray-400 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-purple-500/10 file:text-purple-400 hover:file:bg-purple-500/20 transition-all cursor-pointer">
                </div>
                <!-- Attachments for video -->
                <div class="pt-4 border-t border-white/5">
                  <label class="block text-xs text-gray-400 mb-1">Adicionar Anexos para Download</label>
                  <input type="file" multiple @change="handleAttachmentsUpload" class="block w-full text-sm text-gray-400 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-blue-500/10 file:text-blue-400 hover:file:bg-blue-500/20 transition-all cursor-pointer">
                  <p v-if="attachmentsUpload.length" class="mt-2 text-[10px] text-gray-500">
                    {{ attachmentsUpload.length }} novo(s) arquivo(s) selecionado(s)
                  </p>
                </div>
              </div>

              <div v-if="contentForm.content_type === 'document'" class="md:col-span-2 space-y-4">
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Texto (Opcional)</label>
                  <textarea v-model="contentForm.body_text" rows="3" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50"></textarea>
                </div>
                <div>
                  <label class="block text-xs text-gray-400 mb-1">Upload de Arquivo Principal (Opcional se já existe)</label>
                  <input type="file" @change="handleFileUpload" class="block w-full text-sm text-gray-400 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-purple-500/10 file:text-purple-400 hover:file:bg-purple-500/20">
                </div>
                <!-- Attachments for document -->
                <div class="pt-4 border-t border-white/5">
                  <label class="block text-xs text-gray-400 mb-1">Adicionar Anexos Adicionais</label>
                  <input type="file" multiple @change="handleAttachmentsUpload" class="block w-full text-sm text-gray-400 file:mr-4 file:py-2 file:px-4 file:rounded-full file:border-0 file:text-sm file:font-semibold file:bg-blue-500/10 file:text-blue-400 hover:file:bg-blue-500/20 transition-all cursor-pointer">
                </div>
              </div>
              
              <div>
                <label class="block text-xs text-gray-400 mb-1">Ordem</label>
                <input v-model="contentForm.order_index" type="number" class="w-full bg-black/50 border border-white/10 rounded-xl px-4 py-2 text-white outline-none focus:border-purple-500/50">
              </div>
            </div>
            <div class="flex justify-end gap-3 mt-4">
              <button @click="creatingContentForModule = null" class="px-4 py-2 rounded-xl text-sm text-gray-400 hover:text-white transition-colors">Cancelar</button>
              <button @click="saveContent(mod.id)" :disabled="isUploading" class="px-5 py-2 rounded-xl text-sm bg-purple-600 hover:bg-purple-500 text-white transition-colors disabled:opacity-50">
                {{ isUploading ? 'Salvando...' : 'Salvar Alterações' }}
              </button>
            </div>
          </div>

          <!-- Contents List -->
          <div class="divide-y divide-white/5">
            <div v-if="mod.contents.length === 0" class="p-6 text-center text-gray-500 text-sm">
              Nenhum conteúdo adicionado.
            </div>
            <div v-for="content in mod.contents" :key="content.id" class="p-4 flex items-center gap-4 hover:bg-white/[0.02] transition-colors group/item">
              <div class="w-10 h-10 rounded-xl bg-white/5 flex items-center justify-center text-gray-400 border border-white/5">
                <svg v-if="content.content_type === 'video'" xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                <svg v-else xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg>
              </div>
              <div class="flex-1">
                <h4 class="text-sm font-medium text-gray-200">{{ content.title }}</h4>
                <div class="flex items-center gap-2 mt-1">
                  <span class="text-xs text-gray-500 capitalize">{{ content.content_type }}</span>
                  <span v-if="content.file_url" class="text-xs bg-blue-500/20 text-blue-300 px-2 py-0.5 rounded-full">Anexo</span>
                </div>
              </div>
              <div class="flex items-center gap-2">
                <div class="text-xs text-gray-600 mr-2">Ordem: {{ content.order_index }}</div>
                <button 
                  @click="startEditContent(mod.id, content)"
                  class="p-2 rounded-lg bg-white/5 hover:bg-white/10 text-gray-400 hover:text-white transition-all opacity-0 group-hover/item:opacity-100"
                  title="Editar Aula"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
                </button>
                <button 
                  @click="deleteContent(content)"
                  :disabled="isUploading"
                  class="p-2 rounded-lg bg-white/5 hover:bg-red-500/20 text-gray-400 hover:text-red-400 transition-all opacity-0 group-hover/item:opacity-100 disabled:opacity-30"
                  title="Excluir Aula"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/><line x1="10" y1="11" x2="10" y2="17"/><line x1="14" y1="11" x2="14" y2="17"/></svg>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>

<style scoped>
.glass-card {
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
}
</style>
