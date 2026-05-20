// video-processor.js

const path = require('path')
const fs = require('fs')
const { spawn } = require('child_process')
const { runFfmpeg } = require('./run-ffmpeg')

const PRESETS = [
  {
    name: '1080p',
    width: 1920,
    height: 1080,
    bitrate: '5000k',
    maxrate: '5350k',
    bufsize: '7500k',
    audioBitrate: '128k',
    bandwidth: 5500000
  },
  {
    name: '720p',
    width: 1280,
    height: 720,
    bitrate: '2500k',
    maxrate: '2675k',
    bufsize: '3750k',
    audioBitrate: '128k',
    bandwidth: 2800000
  },
  {
    name: '480p',
    width: 854,
    height: 480,
    bitrate: '1000k',
    maxrate: '1070k',
    bufsize: '1500k',
    audioBitrate: '96k',
    bandwidth: 1200000
  }
]

async function generateHLS(inputPath, outputDir, baseName, preset) {
  const playlistName = `${baseName}_${preset.name}.m3u8`

  const outputPlaylist = path.join(
    outputDir,
    playlistName
  )

  const segmentPattern = path.join(
    outputDir,
    `${baseName}_${preset.name}_%03d.ts`
  )

  const args = [
    '-i', inputPath,

    '-vf',
    // `scale=w=${preset.width}:h=${preset.height}:force_original_aspect_ratio=decrease`,
    `scale=${preset.width}:-2`,

    '-c:v', 'libx264',
    '-preset', 'medium',
    '-crf', '23',

    '-b:v', preset.bitrate,
    '-maxrate', preset.maxrate,
    '-bufsize', preset.bufsize,

    '-c:a', 'aac',
    '-b:a', preset.audioBitrate,
    '-ar', '48000',
    '-ac', '2',

    '-f', 'hls',
    '-hls_time', '6',
    '-hls_playlist_type', 'vod',

    '-hls_segment_filename',
    segmentPattern,

    outputPlaylist
  ]

  console.log(`\nGerando ${preset.name}...`)
  await runFfmpeg(args)

  return {
    preset,
    playlistName
  }
}

async function generateMP3(inputPath, outputDir, baseName) {
  const output = path.join(
    outputDir,
    `${baseName}.mp3`
  )

  const args = [
    '-i', inputPath,

    '-vn',

    '-c:a', 'libmp3lame',
    '-b:a', '128k',

    output
  ]

  console.log('\nGerando MP3...')
  await runFfmpeg(args)

  return output
}

async function generateThumbnail(inputPath, outputDir, baseName, duration) {
  const output = path.join(outputDir, `${baseName}.jpg`)

  const safeOffset = duration ? Math.max(0, Math.min(5, Math.floor(duration * 0.15))) : 0
  const timestamp = new Date(safeOffset * 1000).toISOString().substring(11, 19)

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

async function generateMasterPlaylist(outputDir, baseName, variants) {
  const masterPath = path.join(
    outputDir,
    `${baseName}.m3u8`
  )

  const lines = [
    '#EXTM3U',
    ''
  ]

  for (const variant of variants) {
    lines.push(
      `#EXT-X-STREAM-INF:BANDWIDTH=${variant.preset.bandwidth},RESOLUTION=${variant.preset.width}x${variant.preset.height}`,
      variant.playlistName,
      ''
    )
  }

  await fs.promises.writeFile(masterPath, lines.join('\n'))

  return masterPath
}


async function getVideoDuration(inputPath) {
  return new Promise((resolve, reject) => {
    const proc = spawn('ffprobe', [
      '-v', 'error',
      '-show_entries', 'format=duration',
      '-of', 'default=noprint_wrappers=1:nokey=1',
      inputPath
    ])

    let output = ''
    proc.stdout.on('data', (d) => { output += d.toString() })
    proc.on('close', (code) => {
      if (code !== 0) return reject(new Error(`ffprobe exited with code ${code}`))
      const seconds = Math.round(parseFloat(output.trim()))
      resolve(isNaN(seconds) ? null : seconds)
    })
    proc.on('error', reject)
  })
}

async function processVideo(inputPath) {
  const accessible = await fs.promises.access(inputPath).then(() => true).catch(() => false)
  if (!accessible) {
    throw new Error('Arquivo não encontrado')
  }

  const inputDir = path.dirname(inputPath)

  const ext = path.extname(inputPath)

  const baseName = path.basename(
    inputPath,
    ext
  )

  const outputDir = path.join(
    inputDir,
    baseName
  )

  await fs.promises.mkdir(outputDir, { recursive: true })

  console.log(`\nProcessando vídeo: ${baseName}\n`)
  console.log(`Saída: ${outputDir}\n`)

  const duration = await getVideoDuration(inputPath)

  const variants = []

  for (const preset of PRESETS) {
    const variant = await generateHLS(
      inputPath,
      outputDir,
      baseName,
      preset
    )

    variants.push(variant)
  }

  await generateMP3(
    inputPath,
    outputDir,
    baseName
  )

  await generateThumbnail(
    inputPath,
    outputDir,
    baseName,
    duration
  )

  await generateMasterPlaylist(
    outputDir,
    baseName,
    variants
  )

  console.log('\nProcessamento finalizado!')

  return { duration }
}

module.exports = {
  processVideoMAIN: processVideo
}