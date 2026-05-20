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
