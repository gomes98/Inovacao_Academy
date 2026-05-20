import express from 'express';
import { z } from 'zod';
import { config } from './config.js';
import { logger } from './logger.js';
import { enqueueTranscription, queueStats } from './queue.js';

const app = express();
app.use(express.json({ limit: '1mb' }));

// ----- Auth helper -----
function requireBearer(req: express.Request, res: express.Response): boolean {
  const auth = req.header('authorization') ?? '';
  const expected = `Bearer ${config.WORKER_WEBHOOK_SECRET}`;
  if (auth !== expected) {
    res.status(401).json({ error: 'unauthorized' });
    return false;
  }
  return true;
}

// ----- Health -----
app.get('/health', (_req, res) => {
  res.json({ ok: true, queue: queueStats() });
});

// ----- Webhook do Supabase -----
const webhookSchema = z.object({
  type: z.enum(['INSERT', 'UPDATE', 'DELETE']),
  table: z.string(),
  schema: z.string(),
  record: z
    .object({
      id: z.string().uuid(),
      status: z.string().optional(),
      content_type: z.string().optional(),
    })
    .passthrough(),
  old_record: z
    .object({ status: z.string().optional() })
    .passthrough()
    .nullable()
    .optional(),
});

app.post('/webhook/content-processed', (req, res) => {
  if (!requireBearer(req, res)) return;

  const parsed = webhookSchema.safeParse(req.body);
  if (!parsed.success) {
    logger.warn({ issues: parsed.error.issues }, 'webhook:invalid');
    return res.status(400).json({ error: 'invalid payload' });
  }
  const { type, table, record, old_record } = parsed.data;

  if (table !== 'contents') {
    return res.status(200).json({ ignored: 'table' });
  }
  if (record.content_type && record.content_type !== 'video') {
    return res.status(200).json({ ignored: 'non-video' });
  }
  if (record.status !== 'processed') {
    return res.status(200).json({ ignored: 'status', status: record.status });
  }
  if (type === 'UPDATE' && old_record?.status === 'processed') {
    return res.status(200).json({ ignored: 'no-transition' });
  }

  enqueueTranscription(record.id);
  return res.status(202).json({ accepted: true, contentId: record.id });
});

// ----- Disparo manual (admin) -----
app.post('/jobs/transcribe/:contentId', (req, res) => {
  if (!requireBearer(req, res)) return;
  const { contentId } = req.params;
  if (!/^[0-9a-f-]{36}$/i.test(contentId)) {
    return res.status(400).json({ error: 'invalid contentId' });
  }
  enqueueTranscription(contentId);
  return res.status(202).json({ accepted: true, contentId });
});

app.listen(config.PORT, () => {
  logger.info({ port: config.PORT }, 'worker:listening');
});
