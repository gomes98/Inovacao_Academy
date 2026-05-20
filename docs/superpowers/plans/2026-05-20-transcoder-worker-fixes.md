# Transcoder Worker — Correções e Melhorias

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corrigir bugs críticos, race conditions, resource leaks e problemas de robustez no serviço `services/transcoder-worker`.

**Architecture:** O worker é um processo Node.js (CommonJS) standalone que monitora a tabela `contents` do Supabase via Realtime + polling, baixa vídeos do Storage, processa com ffmpeg (HLS multi-bitrate + thumbnail + MP3) e faz upload dos resultados. As correções são aplicadas em camadas: configuração/startup → fila/concorrência → processamento/limpeza → ffmpeg.

**Tech Stack:** Node.js (CommonJS), `@supabase/supabase-js`, `dotenv`, ffmpeg/ffprobe (binários do sistema), sem framework de testes (usar `node --test` nativo).

---

## Mapa de Arquivos

| Arquivo | Responsabilidade |
|---------|-----------------|
| `services/transcoder-worker/index.js` | Entry point, fila, realtime, polling, processamento, upload |
| `services/transcoder-worker/src/queue/videoQueue.js` | Estrutura da fila em memória |
| `services/transcoder-worker/src/ffmpeg/run-ffmpeg.js` | Wrapper async do processo ffmpeg |
| `services/transcoder-worker/src/ffmpeg/video-processor.js` | Orquestração: HLS, MP3, thumbnail, master playlist |
| `services/transcoder-worker/Dockerfile` | *(criar)* Imagem com ffmpeg instalado |

---

## Task 1: Validação de variáveis de ambiente e logging de startup

**Problema:** O worker inicia silenciosamente mesmo sem `SUPABASE_URL` ou `SUPABASE_SERVICE_ROLE_KEY` definidos, causando erros crípticos em runtime.

**Files:**
- Modify: `services/transcoder-worker/index.js:1-14`

- [ ] **Step 1: Adicionar validação de env vars no topo de `index.js`**

  Substitua as linhas 1–14 por:

  ```js
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
  ```

- [ ] **Step 2: Verificar manualmente que o arquivo ficou correto**

  ```bash
  node -e "require('./services/transcoder-worker/index.js')" 2>&1 | head -5
  ```
  Sem `SUPABASE_URL` no ambiente deve imprimir a mensagem FATAL e sair com código 1.

- [ ] **Step 3: Commit**

  ```bash
  git add services/transcoder-worker/index.js
  git commit -m "fix: validate required env vars at startup in transcoder-worker"
  ```

---

## Task 2: Corrigir bug na lógica de "próximo da fila" no `finally`

**Problema:** O bloco `finally` de `runNextInQueue` chama `queue.dequeue()` duas vezes para tentar pegar o próximo item — uma para buscar no cache e outra se não encontrar. Isso descarta IDs silenciosamente, podendo perder vídeos da fila.

**Files:**
- Modify: `services/transcoder-worker/index.js:50-64`

- [ ] **Step 1: Reescrever o bloco `finally` de `runNextInQueue`**

  Substitua o bloco `finally` atual (linhas 50–64):

  ```js
  } finally {
    queue.clearProcessing()

    const nextId = queue.peek()
    if (!nextId) return

    const cached = videoCache.get(nextId)
    if (cached) {
      runNextInQueue(cached)
    } else {
      fetchAndEnqueue(queue.dequeue())
    }
  }
  ```

- [ ] **Step 2: Adicionar o método `peek` em `videoQueue.js`**

  Abra `services/transcoder-worker/src/queue/videoQueue.js` e adicione após `size()`:

  ```js
  function peek() {
    return queue[0] ?? null
  }
  ```

  E inclua `peek` no `module.exports`:

  ```js
  module.exports = { enqueue, dequeue, peek, setProcessing, clearProcessing, getProcessingId, size }
  ```

- [ ] **Step 3: Corrigir `fetchAndEnqueue` para não re-enfileirar ID já na fila**

  Substitua a função `fetchAndEnqueue` (linhas 67–82):

  ```js
  async function fetchAndEnqueue(videoId) {
    if (!videoId) return

    const { data, error } = await supabase
      .from('contents')
      .select('*')
      .eq('id', videoId)
      .single()

    if (error || !data) {
      console.error(`[queue] Não foi possível buscar vídeo ${videoId}:`, error)
      // ID já foi removido da fila pelo dequeue() no finally — não re-enfileirar
      return
    }

    videoCache.set(data.id, data)
    const added = queue.enqueue(data.id)
    if (added) runNextInQueue(data)
  }
  ```

- [ ] **Step 4: Verificar sintaxe**

  ```bash
  node --check services/transcoder-worker/index.js && node --check services/transcoder-worker/src/queue/videoQueue.js
  ```
  Esperado: nenhum output (sem erros).

- [ ] **Step 5: Commit**

  ```bash
  git add services/transcoder-worker/index.js services/transcoder-worker/src/queue/videoQueue.js
  git commit -m "fix: correct queue next-item logic and add peek() to avoid double-dequeue"
  ```

---

## Task 3: Corrigir `subscribe` callback — async não tratado

**Problema:** `.subscribe((status) => { checkPendencias() })` não aguarda a Promise e silencia erros.

**Files:**
- Modify: `services/transcoder-worker/index.js:122-125`

- [ ] **Step 1: Transformar callback em async com try/catch**

  Substitua as linhas 122–125:

  ```js
  .subscribe(async (status) => {
    console.log('[realtime] Status:', status)
    try {
      await checkPendencias()
    } catch (err) {
      console.error('[realtime] Erro em checkPendencias:', err)
    }
  })
  ```

- [ ] **Step 2: Verificar sintaxe**

  ```bash
  node --check services/transcoder-worker/index.js
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add services/transcoder-worker/index.js
  git commit -m "fix: await checkPendencias in subscribe callback and handle errors"
  ```

---

## Task 4: Substituir `setInterval` por `setTimeout` recursivo no polling

**Problema:** `setInterval` com função async pode acumular execuções concorrentes se `checkPendencias()` demorar mais que 30 s.

**Files:**
- Modify: `services/transcoder-worker/index.js:235-237`

- [ ] **Step 1: Substituir `setInterval` pelo padrão `setTimeout` recursivo**

  Substitua as linhas 235–237:

  ```js
  ;(async function schedulePoll() {
    try {
      await checkPendencias()
    } catch (err) {
      console.error('[polling] Erro inesperado:', err)
    } finally {
      setTimeout(schedulePoll, 30_000)
    }
  })()
  ```

- [ ] **Step 2: Verificar sintaxe**

  ```bash
  node --check services/transcoder-worker/index.js
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add services/transcoder-worker/index.js
  git commit -m "fix: replace setInterval with recursive setTimeout to prevent concurrent polls"
  ```

---

## Task 5: Garantir limpeza de arquivos temporários em caso de erro

**Problema:** Se `processVideo` lança exceção antes do cleanup (linhas 200–202), os arquivos em `./temp/` ficam para sempre no disco.

**Files:**
- Modify: `services/transcoder-worker/index.js:131-205`

- [ ] **Step 1: Reestruturar `processVideo` para cleanup em `finally`**

  Substitua a função `processVideo` inteira (linhas 131–206):

  ```js
  async function processVideo(video) {
    console.log(`\n[worker] Iniciando processamento: ${video.id}`)

    await setStatus(video.id, 'processing')

    const { bucket, pathString } = parseSupabaseStorageUrl(video.video_url)
    const extensao = getFileExtension(video.video_url)
    const baseName = getFileNameWithoutExtension(video.video_url)

    await fs.promises.mkdir('./temp', { recursive: true })

    const localFilePath = path.join('./temp', baseName + extensao)
    const outputDir = path.join('./temp', baseName)

    try {
      if (await fs.promises.access(localFilePath).then(() => true).catch(() => false)) {
        console.log('[worker] Arquivo já existe localmente, pulando download...')
      } else {
        console.log('[worker] Baixando vídeo...')
        const { data, error } = await supabase.storage.from(bucket).download(pathString)
        if (error) throw new Error(`Erro ao baixar vídeo: ${error.message}`)
        const arrayBuffer = await data.arrayBuffer()
        await fs.promises.writeFile(localFilePath, Buffer.from(arrayBuffer))
        console.log('[worker] Download concluído.')
      }

      const { duration } = await processVideoMAIN(localFilePath)

      const storageBasePath = path.dirname(pathString)

      console.log('[worker] Iniciando upload dos arquivos processados...')
      await uploadDirRecursive(bucket, outputDir, storageBasePath)

      const masterStoragePath = path.posix.join(storageBasePath, `${baseName}.m3u8`)
      const thumbnailStoragePath = path.posix.join(storageBasePath, `${baseName}.jpg`)

      const { data: publicUrlData } = supabase.storage.from(bucket).getPublicUrl(masterStoragePath)
      const { data: thumbnailUrlData } = supabase.storage.from(bucket).getPublicUrl(thumbnailStoragePath)

      const updatePayload = {
        status: 'processed',
        video_url: publicUrlData.publicUrl,
        thumbnail_url: thumbnailUrlData.publicUrl
      }
      if (duration !== null) updatePayload.duration = duration

      const { error: updateError } = await supabase
        .from('contents')
        .update(updatePayload)
        .eq('id', video.id)

      if (updateError) {
        console.error('[db] Erro ao atualizar video_url:', updateError.message)
      }

      const { error: removeError } = await supabase.storage.from(bucket).remove([pathString])
      if (removeError) {
        console.error('[storage] Erro ao remover arquivo original:', removeError.message)
      } else {
        console.log(`[storage] Arquivo original removido: ${pathString}`)
      }

      console.log(`[worker] Processamento concluído: ${video.id}`)
      console.log(`[worker] video_url atualizado: ${publicUrlData.publicUrl}`)

    } finally {
      // Sempre limpa arquivos temporários, mesmo em caso de erro
      await fs.promises.rm(localFilePath, { force: true }).catch(() => {})
      await fs.promises.rm(outputDir, { recursive: true, force: true }).catch(() => {})
      console.log('[worker] Pasta temp limpa.')
    }
  }
  ```

- [ ] **Step 2: Verificar sintaxe**

  ```bash
  node --check services/transcoder-worker/index.js
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add services/transcoder-worker/index.js
  git commit -m "fix: always clean temp files in finally block, use async fs ops"
  ```

---

## Task 6: Corrigir `uploadDirRecursive` — verificar existência do diretório

**Problema:** `fs.readdirSync` lança exceção não capturada se o diretório não existe.

**Files:**
- Modify: `services/transcoder-worker/index.js` (função `uploadDirRecursive`)

- [ ] **Step 1: Substituir `uploadDirRecursive` pela versão async com verificação**

  Substitua a função `uploadDirRecursive` (linhas 208–229):

  ```js
  async function uploadDirRecursive(bucket, localDir, storageBasePath) {
    const exists = await fs.promises.access(localDir).then(() => true).catch(() => false)
    if (!exists) {
      console.error(`[upload] Diretório não encontrado, pulando: ${localDir}`)
      return
    }

    const entries = await fs.promises.readdir(localDir, { withFileTypes: true })

    for (const entry of entries) {
      const localPath = path.join(localDir, entry.name)
      const storagePath = path.posix.join(storageBasePath, entry.name)

      if (entry.isDirectory()) {
        await uploadDirRecursive(bucket, localPath, storagePath)
      } else {
        console.log(`[upload] ${localPath} → ${storagePath}`)
        const fileBuffer = await fs.promises.readFile(localPath)
        const { error } = await supabase.storage
          .from(bucket)
          .upload(storagePath, fileBuffer, { upsert: true, contentType: getContentType(entry.name) })

        if (error) {
          console.error(`[upload] Erro ao enviar ${entry.name}:`, error.message)
        }
      }
    }
  }

  function getContentType(filename) {
    const ext = path.extname(filename).toLowerCase()
    const map = { '.m3u8': 'application/vnd.apple.mpegurl', '.ts': 'video/mp2t', '.mp3': 'audio/mpeg', '.jpg': 'image/jpeg' }
    return map[ext] ?? 'application/octet-stream'
  }
  ```

  > **Por que usar `readFile` em vez de `createReadStream`?** O Supabase JS v2 espera `Uint8Array | ArrayBuffer | Blob | File | FormData | ReadableStream | string` — `Buffer` (subclasse de `Uint8Array`) funciona corretamente; streams precisam de tratamento adicional e não têm os mesmos Content-Type automáticos.

- [ ] **Step 2: Verificar sintaxe**

  ```bash
  node --check services/transcoder-worker/index.js
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add services/transcoder-worker/index.js
  git commit -m "fix: make uploadDirRecursive async, check dir existence, add content-type"
  ```

---

## Task 7: Adicionar timeout no ffmpeg

**Problema:** Se o ffmpeg travar (arquivo corrompido, bug de codec), o worker fica bloqueado para sempre.

**Files:**
- Modify: `services/transcoder-worker/src/ffmpeg/run-ffmpeg.js`

- [ ] **Step 1: Reescrever `runFfmpeg` com suporte a timeout**

  Substitua todo o conteúdo de `run-ffmpeg.js`:

  ```js
  const { spawn } = require('child_process')

  const DEFAULT_TIMEOUT_MS = 10 * 60 * 1000 // 10 minutos

  async function runFfmpeg(args, timeoutMs = DEFAULT_TIMEOUT_MS) {
    return new Promise((resolve, reject) => {
      const ffmpeg = spawn('ffmpeg', args)
      let stdout = ''
      let stderr = ''

      const timer = setTimeout(() => {
        ffmpeg.kill('SIGKILL')
        reject(new Error(`ffmpeg timeout após ${timeoutMs}ms`))
      }, timeoutMs)

      ffmpeg.stdout.on('data', (data) => { stdout += data.toString() })
      ffmpeg.stderr.on('data', (data) => { stderr += data.toString() })

      ffmpeg.on('close', (code) => {
        clearTimeout(timer)
        if (code === 0) {
          resolve({ stdout, stderr })
        } else {
          const error = new Error(`ffmpeg exited with code ${code}`)
          error.code = code
          error.stdout = stdout
          error.stderr = stderr
          reject(error)
        }
      })

      ffmpeg.on('error', (err) => {
        clearTimeout(timer)
        reject(err)
      })
    })
  }

  module.exports = { runFfmpeg }
  ```

- [ ] **Step 2: Verificar sintaxe**

  ```bash
  node --check services/transcoder-worker/src/ffmpeg/run-ffmpeg.js
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add services/transcoder-worker/src/ffmpeg/run-ffmpeg.js
  git commit -m "fix: add timeout to ffmpeg process to prevent worker deadlock"
  ```

---

## Task 8: Corrigir thumbnail para vídeos curtos

**Problema:** `-ss 00:00:05` faz o ffmpeg falhar silenciosamente se o vídeo tiver menos de 5 segundos.

**Files:**
- Modify: `services/transcoder-worker/src/ffmpeg/video-processor.js:115-137`

- [ ] **Step 1: Atualizar `generateThumbnail` para aceitar duração e calcular offset seguro**

  Substitua a função `generateThumbnail` (linhas 115–137):

  ```js
  async function generateThumbnail(inputPath, outputDir, baseName, duration) {
    const output = path.join(outputDir, `${baseName}.jpg`)

    // Usa 15% da duração ou 5s, o que for menor; mínimo 0s
    const safeOffset = duration ? Math.max(0, Math.min(5, Math.floor(duration * 0.15))) : 0
    const timestamp = new Date(safeOffset * 1000).toISOString().substring(11, 19) // HH:MM:SS

    const args = [
      '-i', inputPath,
      '-ss', timestamp,
      '-vframes', '1',
      '-q:v', '2',
      output
    ]

    console.log('\nGerando thumbnail...')
    await runFfmpeg(args)

    return output
  }
  ```

- [ ] **Step 2: Atualizar a chamada de `generateThumbnail` em `processVideo` para passar `duration`**

  Localize a chamada (próximo de linha 307):
  ```js
  await generateThumbnail(inputPath, outputDir, baseName)
  ```
  Substitua por:
  ```js
  await generateThumbnail(inputPath, outputDir, baseName, duration)
  ```

- [ ] **Step 3: Verificar sintaxe**

  ```bash
  node --check services/transcoder-worker/src/ffmpeg/video-processor.js
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add services/transcoder-worker/src/ffmpeg/video-processor.js
  git commit -m "fix: use duration-aware thumbnail offset to handle short videos"
  ```

---

## Task 9: Criar Dockerfile com ffmpeg

**Problema:** Não há Dockerfile — o worker depende de `ffmpeg`/`ffprobe` no PATH mas esses binários não estão documentados nem instalados automaticamente.

**Files:**
- Create: `services/transcoder-worker/Dockerfile`

- [ ] **Step 1: Criar o Dockerfile**

  ```dockerfile
  FROM node:22-alpine

  # ffmpeg inclui ffprobe
  RUN apk add --no-cache ffmpeg

  WORKDIR /app

  COPY package*.json ./
  RUN npm ci --omit=dev

  COPY . .

  CMD ["node", "index.js"]
  ```

- [ ] **Step 2: Criar `.dockerignore`**

  ```
  node_modules
  .env
  temp/
  ```

- [ ] **Step 3: Verificar que o build funciona (se Docker disponível)**

  ```bash
  docker build -t transcoder-worker services/transcoder-worker
  ```
  Esperado: `Successfully built <id>` sem erros.

- [ ] **Step 4: Commit**

  ```bash
  git add services/transcoder-worker/Dockerfile services/transcoder-worker/.dockerignore
  git commit -m "feat: add Dockerfile with ffmpeg for transcoder-worker"
  ```

---

## Revisão do plano

### Cobertura dos problemas originais

| Problema original | Task |
|-------------------|------|
| Sem validação de env vars | Task 1 |
| Bug de double-dequeue na fila | Task 2 |
| ID de vídeo perdido em fetch failure | Task 2 (fetchAndEnqueue) |
| Async não tratado no subscribe | Task 3 |
| setInterval com async concorrente | Task 4 |
| Sem cleanup de temp em caso de erro | Task 5 |
| I/O síncrono bloqueando event loop | Task 5 + Task 6 |
| Sem verificação de existência de diretório | Task 6 |
| Sem timeout no ffmpeg | Task 7 |
| Thumbnail hardcoded em 5s | Task 8 |
| ffmpeg/ffprobe ausentes | Task 9 |
| `await` faltando em `runNextInQueue(data)` | Task 2 (abordado com reestruturação da lógica) |

### Race condition no `videoCache`

O `videoCache` ainda é acessado de múltiplos contextos async, mas como Node.js é single-threaded (sem paralelismo real entre callbacks síncronos), o risco prático é baixo. A solução definitiva seria eliminar o cache e sempre buscar no banco — mas isso aumenta latência e queries. A reestruturação da fila (Task 2) já reduz a janela de inconsistência significativamente.
