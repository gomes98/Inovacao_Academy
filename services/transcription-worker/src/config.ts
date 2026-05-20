import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  SUPABASE_URL: z.string().url(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(20),
  SUPABASE_STORAGE_BUCKET: z.string().default('courses'),

  WORKER_WEBHOOK_SECRET: z.string().min(8),
  PORT: z.coerce.number().default(8787),

  OPENAI_API_KEY: z.string().min(20),
  EMBEDDING_MODEL: z.string().default('text-embedding-3-small'),

  WHISPER_PYTHON: z.string().default('python3'),
  WHISPER_MODEL: z.string().default('large-v3'),
  WHISPER_DEVICE: z.enum(['cuda', 'cpu']).default('cuda'),
  WHISPER_COMPUTE_TYPE: z.string().default('float16'),
  WHISPER_LANGUAGE: z.string().optional(),

  CHUNK_TARGET_TOKENS: z.coerce.number().default(400),
  CHUNK_OVERLAP_TOKENS: z.coerce.number().default(60),

  JOB_CONCURRENCY: z.coerce.number().default(1),
  LOG_LEVEL: z.string().default('info'),
});

export const config = schema.parse(process.env);
export type Config = typeof config;
