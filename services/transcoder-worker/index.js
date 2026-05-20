require('dotenv').config()

const REQUIRED_ENV = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY']
const missing = REQUIRED_ENV.filter((k) => !process.env[k])
if (missing.length) {
  console.error(`[startup] FATAL: variáveis de ambiente ausentes: ${missing.join(', ')}`)
  process.exit(1)
}

console.log('[startup] transcoder-worker iniciando...')
console.log(`[startup] SUPABASE_URL: ${process.env.SUPABASE_URL}`)
console.log(`[startup] SERVICE_ROLE_KEY: ${'*'.repeat(8)}`)

const { createClient } = require('@supabase/supabase-js')
const fs = require('fs')
const path = require('path')
const { processVideoMAIN } = require('./src/ffmpeg/video-processor')
const queue = require('./src/queue/videoQueue')

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
)

// ========================
// FILA DE PROCESSAMENTO
// ========================

function enqueueVideo(video) {
  const added = queue.enqueue(video.id)
  if (added) {
    console.log(`[queue] Vídeo enfileirado: ${video.id} | fila: ${queue.size()}`)
    runNextInQueue(video)
  } else {
    console.log(`[queue] Vídeo já na fila ou em processamento: ${video.id}`)
  }
}

// Armazena os dados do vídeo pelo id para não precisar rebuscar no banco
const videoCache = new Map()

async function runNextInQueue(videoHint) {
  // Se já há um em processamento, não inicia outro
  if (queue.getProcessingId() !== null) return

  const nextId = queue.dequeue()
  if (!nextId) return

  queue.setProcessing(nextId)

  const video = videoCache.get(nextId) ?? videoHint
  videoCache.delete(nextId)

  try {
    await processVideo(video)
  } catch (err) {
    console.error(`[worker] Erro fatal no vídeo ${nextId}:`, err)
    await setStatus(nextId, 'error')
  } finally {
    queue.clearProcessing()
    // Processa o próximo da fila, se houver
    const nextVideo = videoCache.get(queue.dequeue())
    if (nextVideo) {
      queue.enqueue(nextVideo.id)
      runNextInQueue(nextVideo)
    } else if (queue.size() > 0) {
      // Tem IDs na fila mas não temos os dados em cache — busca no banco
      const nextInQueue = queue.dequeue()
      if (nextInQueue) {
        fetchAndEnqueue(nextInQueue)
      }
    }
  }
}

async function fetchAndEnqueue(videoId) {
  const { data, error } = await supabase
    .from('contents')
    .select('*')
    .eq('id', videoId)
    .single()

  if (error || !data) {
    console.error(`[queue] Não foi possível buscar vídeo ${videoId}:`, error)
    return
  }

  videoCache.set(data.id, data)
  queue.enqueue(data.id)
  runNextInQueue(data)
}

// ========================
// MONITORAMENTO REALTIME
// ========================

console.log('Monitorando novos vídeos...')

const channel = supabase
  .channel('videos-monitor')
  .on(
    'postgres_changes',
    {
      event: 'INSERT',
      schema: 'public',
      table: 'contents'
    },
    async (payload) => {
      try {
        const video = payload.new
        console.log('\n[realtime] Novo vídeo detectado:', video.id)

        if (!video.video_url) {
          console.log('[realtime] Vídeo sem URL, ignorando...')
          return
        }

        if (video.status !== 'uploaded') {
          console.log('[realtime] Status inválido:', video.status)
          return
        }

        videoCache.set(video.id, video)
        enqueueVideo(video)

      } catch (err) {
        console.error('[realtime] Erro ao processar evento:', err)
      }
    }
  )
  .subscribe((status) => {
    console.log('[realtime] Status:', status)
    checkPendencias()
  })

// ========================
// PROCESSAMENTO
// ========================

async function processVideo(video) {
  console.log(`\n[worker] Iniciando processamento: ${video.id}`)

  await setStatus(video.id, 'processing')

  const { bucket, pathString } = parseSupabaseStorageUrl(video.video_url)
  const extensao = getFileExtension(video.video_url)
  const baseName = getFileNameWithoutExtension(video.video_url)

  if (!fs.existsSync('./temp')) {
    fs.mkdirSync('./temp')
  }

  const localFilePath = path.join('./temp', baseName + extensao)

  if (fs.existsSync(localFilePath)) {
    console.log('[worker] Arquivo já existe localmente, pulando download...')
  } else {
    console.log('[worker] Baixando vídeo...')
    const { data, error } = await supabase
      .storage
      .from(bucket)
      .download(pathString)

    if (error) {
      throw new Error(`Erro ao baixar vídeo: ${error.message}`)
    }

    const arrayBuffer = await data.arrayBuffer()
    fs.writeFileSync(localFilePath, Buffer.from(arrayBuffer))
    console.log('[worker] Download concluído.')
  }

  const { duration } = await processVideoMAIN(localFilePath)

  const outputDir = path.join('./temp', baseName)
  const storageBasePath = path.dirname(pathString)

  console.log('[worker] Iniciando upload dos arquivos processados...')
  await uploadDirRecursive(bucket, outputDir, storageBasePath)

  // URL pública do master playlist gerado pelo FFmpeg
  const masterStoragePath = path.posix.join(storageBasePath, `${baseName}.m3u8`)
  const { data: publicUrlData } = supabase.storage.from(bucket).getPublicUrl(masterStoragePath)

  const thumbnailStoragePath = path.posix.join(storageBasePath, `${baseName}.jpg`)
  const { data: thumbnailUrlData } = supabase.storage.from(bucket).getPublicUrl(thumbnailStoragePath)

  const updatePayload = { status: 'processed', video_url: publicUrlData.publicUrl, thumbnail_url: thumbnailUrlData.publicUrl }
  if (duration !== null) updatePayload.duration = duration

  const { error: updateError } = await supabase
    .from('contents')
    .update(updatePayload)
    .eq('id', video.id)

  if (updateError) {
    console.error('[db] Erro ao atualizar video_url:', updateError.message)
  }

  // Remove o arquivo original do bucket
  const { error: removeError } = await supabase.storage.from(bucket).remove([pathString])
  if (removeError) {
    console.error('[storage] Erro ao remover arquivo original:', removeError.message)
  } else {
    console.log(`[storage] Arquivo original removido: ${pathString}`)
  }

  // Remove o arquivo fonte e a pasta de output do temp
  fs.rmSync(localFilePath, { force: true })
  fs.rmSync(outputDir, { recursive: true, force: true })
  console.log('[worker] Pasta temp limpa.')

  console.log(`[worker] Processamento concluído: ${video.id}`)
  console.log(`[worker] video_url atualizado: ${publicUrlData.publicUrl}`)
}

// Percorre diretório recursivamente e faz upload de todos os arquivos
async function uploadDirRecursive(bucket, localDir, storageBasePath) {
  const entries = fs.readdirSync(localDir, { withFileTypes: true })

  for (const entry of entries) {
    const localPath = path.join(localDir, entry.name)
    const storagePath = path.posix.join(storageBasePath, entry.name)

    if (entry.isDirectory()) {
      await uploadDirRecursive(bucket, localPath, storagePath)
    } else {
      console.log(`[upload] ${localPath} → ${storagePath}`)
      const { error } = await supabase.storage
        .from(bucket)
        .upload(storagePath, fs.createReadStream(localPath), { upsert: true })

      if (error) {
        console.error(`[upload] Erro ao enviar ${entry.name}:`, error.message)
      }
    }
  }
}

// ========================
// POLLING DE SEGURANÇA
// ========================

setInterval(async () => {
  await checkPendencias()
}, 30000)

async function checkPendencias() {
  try {
    console.log('\n[polling] Verificando pendências...')

    const { data, error } = await supabase
      .from('contents')
      .select('*')
      .eq('status', 'uploaded')
      .limit(10)

    if (error) {
      console.error('[polling] Erro na consulta:', error)
      return
    }

    if (!data.length) {
      console.log('[polling] Nenhuma pendência.')
      return
    }

    for (const video of data) {
      console.log(`[polling] Pendência encontrada: ${video.id}`)
      videoCache.set(video.id, video)
      enqueueVideo(video)
    }

  } catch (err) {
    console.error('[polling] Erro:', err)
  }
}

// ========================
// HELPERS
// ========================

async function setStatus(videoId, status) {
  const { error } = await supabase
    .from('contents')
    .update({ status })
    .eq('id', videoId)

  if (error) {
    console.error(`[db] Erro ao atualizar status para '${status}':`, error.message)
  }
}

function parseSupabaseStorageUrl(url) {
  const marker = '/storage/v1/object/public/'
  const index = url.indexOf(marker)

  if (index === -1) {
    throw new Error('URL inválida do Supabase Storage')
  }

  const filePart = url.substring(index + marker.length)
  const parts = filePart.split('/')
  const bucket = parts.shift()

  return {
    bucket,
    pathString: parts.join('/')
  }
}

function getFileExtension(url) {
  return path.extname(url).toLowerCase()
}

function getFileNameWithoutExtension(url) {
  return path.basename(url, path.extname(url))
}
