import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { config } from '../config.js';
import { logger } from '../logger.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT_PATH = path.resolve(__dirname, '..', '..', 'python', 'transcribe.py');

export interface WhisperSegment {
  id: number;
  start: number;
  end: number;
  text: string;
}

export interface WhisperResult {
  language: string;
  duration: number;
  model: string;
  segments: WhisperSegment[];
  full_text: string;
}

export async function transcribe(audioPath: string): Promise<WhisperResult> {
  const args = [
    SCRIPT_PATH,
    '--audio', audioPath,
    '--model', config.WHISPER_MODEL,
    '--device', config.WHISPER_DEVICE,
    '--compute-type', config.WHISPER_COMPUTE_TYPE,
  ];
  if (config.WHISPER_LANGUAGE) {
    args.push('--language', config.WHISPER_LANGUAGE);
  }

  logger.info({ audioPath, args }, 'whisper:spawn');

  return new Promise<WhisperResult>((resolve, reject) => {
    const proc = spawn(config.WHISPER_PYTHON, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stdout = '';
    let stderr = '';

    proc.stdout.on('data', (d) => { stdout += d.toString(); });
    proc.stderr.on('data', (d) => {
      const line = d.toString();
      stderr += line;
      // faster-whisper emite progresso no stderr — logamos como debug
      logger.debug({ line: line.trim() }, 'whisper:stderr');
    });

    proc.on('error', reject);
    proc.on('close', (code) => {
      if (code !== 0) {
        return reject(new Error(`whisper exit code ${code}. stderr: ${stderr.slice(-500)}`));
      }
      try {
        const result = JSON.parse(stdout) as WhisperResult;
        resolve(result);
      } catch (err) {
        reject(new Error(`whisper stdout não é JSON válido: ${(err as Error).message}`));
      }
    });
  });
}
