import OpenAI from 'openai';
import { config } from '../config.js';

const openai = new OpenAI({ apiKey: config.OPENAI_API_KEY });

const BATCH_SIZE = 100; // OpenAI aceita até 2048 inputs, mas batches menores são mais resilientes

export async function embedTexts(texts: string[]): Promise<number[][]> {
  const out: number[][] = [];

  for (let i = 0; i < texts.length; i += BATCH_SIZE) {
    const batch = texts.slice(i, i + BATCH_SIZE);
    const resp = await openai.embeddings.create({
      model: config.EMBEDDING_MODEL,
      input: batch,
    });
    // resp.data vem na mesma ordem do input
    for (const item of resp.data) {
      out.push(item.embedding);
    }
  }

  return out;
}
