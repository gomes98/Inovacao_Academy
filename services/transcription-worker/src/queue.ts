import PQueue from 'p-queue';
import { config } from './config.js';
import { logger } from './logger.js';
import { runTranscriptionJob } from './jobs/transcribe.js';

const queue = new PQueue({ concurrency: config.JOB_CONCURRENCY });

// Evita enfileirar o mesmo contentId duas vezes simultaneamente
const inFlight = new Set<string>();

export function enqueueTranscription(contentId: string) {
  if (inFlight.has(contentId)) {
    logger.info({ contentId }, 'queue:dedup-skip');
    return;
  }
  inFlight.add(contentId);

  queue
    .add(() => runTranscriptionJob(contentId))
    .catch((err) => logger.error({ err, contentId }, 'queue:job-error'))
    .finally(() => inFlight.delete(contentId));

  logger.info({ contentId, size: queue.size, pending: queue.pending }, 'queue:enqueued');
}

export function queueStats() {
  return { size: queue.size, pending: queue.pending, inFlight: inFlight.size };
}
