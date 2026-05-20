import { encoding_for_model } from 'tiktoken';
import type { WhisperSegment } from './whisper.js';

export interface Chunk {
  index: number;
  text: string;
  start: number;
  end: number;
  tokenCount: number;
}

/**
 * Agrupa segmentos do Whisper em chunks de ~targetTokens, respeitando
 * bordas de frase (não corta no meio de um segmento) e aplicando overlap
 * em tokens entre chunks consecutivos para preservar contexto na busca.
 */
export function chunkSegments(
  segments: WhisperSegment[],
  targetTokens: number,
  overlapTokens: number,
): Chunk[] {
  if (segments.length === 0) return [];

  const enc = encoding_for_model('text-embedding-3-small');
  const tokenize = (s: string) => enc.encode(s).length;

  try {
    const chunks: Chunk[] = [];
    let buffer: WhisperSegment[] = [];
    let bufferTokens = 0;
    let chunkIndex = 0;

    const flush = () => {
      if (buffer.length === 0) return;
      const text = buffer.map((s) => s.text.trim()).join(' ').replace(/\s+/g, ' ').trim();
      chunks.push({
        index: chunkIndex++,
        text,
        start: buffer[0].start,
        end: buffer[buffer.length - 1].end,
        tokenCount: bufferTokens,
      });
    };

    for (const seg of segments) {
      const segTokens = tokenize(seg.text);

      if (bufferTokens + segTokens > targetTokens && buffer.length > 0) {
        flush();
        // Overlap: mantém os últimos N tokens (em segmentos completos) no próximo chunk
        const overlapBuf: WhisperSegment[] = [];
        let overlapSum = 0;
        for (let i = buffer.length - 1; i >= 0 && overlapSum < overlapTokens; i--) {
          overlapBuf.unshift(buffer[i]);
          overlapSum += tokenize(buffer[i].text);
        }
        buffer = overlapBuf;
        bufferTokens = overlapSum;
      }

      buffer.push(seg);
      bufferTokens += segTokens;
    }

    flush();
    return chunks;
  } finally {
    enc.free();
  }
}
