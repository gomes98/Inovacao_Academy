import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { chunkSegments } from '../lib/chunker.js';
import { embedTexts } from '../lib/embeddings.js';
import { deriveMp3Path } from '../lib/storage-path.js';
import {
  downloadFromStorage,
  getContent,
  hasTranscription,
  setContentStatus,
  supabase,
} from '../lib/supabase.js';
import { transcribe } from '../lib/whisper.js';

export async function runTranscriptionJob(contentId: string) {
  const log = logger.child({ contentId, job: 'transcribe' });
  log.info('job:start');

  const content = await getContent(contentId);

  if (content.content_type !== 'video') {
    log.warn({ type: content.content_type }, 'job:skip-non-video');
    return;
  }
  if (!content.video_url) {
    throw new Error('contents.video_url está vazio');
  }
  if (await hasTranscription(contentId)) {
    log.info('job:skip-already-indexed');
    return;
  }

  await setContentStatus(contentId, 'transcribing');

  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'ia-whisper-'));
  const audioPath = path.join(tmpDir, 'audio.mp3');

  try {
    // 1. Download MP3
    const mp3Path = deriveMp3Path(content.video_url, config.SUPABASE_STORAGE_BUCKET);
    log.info({ mp3Path }, 'job:download');
    const blob = await downloadFromStorage(mp3Path);
    const buf = Buffer.from(await blob.arrayBuffer());
    await fs.writeFile(audioPath, buf);

    // 2. Transcrever
    log.info('job:whisper');
    const result = await transcribe(audioPath);
    log.info(
      { language: result.language, duration: result.duration, segments: result.segments.length },
      'job:whisper-done',
    );

    // 3. Persistir transcrição completa
    {
      const { error } = await supabase
        .from('content_transcriptions')
        .upsert({
          content_id: contentId,
          language: result.language,
          full_text: result.full_text,
          segments_json: result.segments,
          model: result.model,
          duration_sec: result.duration,
        });
      if (error) throw new Error(`upsert content_transcriptions: ${error.message}`);
    }

    // 4. Chunkar
    const chunks = chunkSegments(
      result.segments,
      config.CHUNK_TARGET_TOKENS,
      config.CHUNK_OVERLAP_TOKENS,
    );
    log.info({ chunks: chunks.length }, 'job:chunks');

    if (chunks.length === 0) {
      log.warn('job:no-chunks');
      await setContentStatus(contentId, 'indexed');
      return;
    }

    // 5. Embeddings
    log.info('job:embeddings');
    const embeddings = await embedTexts(chunks.map((c) => c.text));

    // 6. Upsert chunks (limpa antigos primeiro p/ ser idempotente)
    {
      const { error: delErr } = await supabase
        .from('content_chunks')
        .delete()
        .eq('content_id', contentId);
      if (delErr) throw new Error(`limpar chunks antigos: ${delErr.message}`);
    }

    const rows = chunks.map((c, i) => ({
      content_id: contentId,
      chunk_index: c.index,
      text: c.text,
      start_time: c.start,
      end_time: c.end,
      token_count: c.tokenCount,
      embedding: embeddings[i],
      embedding_model: config.EMBEDDING_MODEL,
    }));

    // Insere em lotes para evitar payload gigante
    const BATCH = 200;
    for (let i = 0; i < rows.length; i += BATCH) {
      const slice = rows.slice(i, i + BATCH);
      const { error } = await supabase.from('content_chunks').insert(slice);
      if (error) throw new Error(`insert content_chunks: ${error.message}`);
    }

    await setContentStatus(contentId, 'indexed');
    log.info('job:done');
  } catch (err) {
    log.error({ err }, 'job:failed');
    await setContentStatus(contentId, 'failed').catch(() => {});
    throw err;
  } finally {
    await fs.rm(tmpDir, { recursive: true, force: true }).catch(() => {});
  }
}
