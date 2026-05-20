import { createClient } from '@supabase/supabase-js';
import { config } from '../config.js';

export const supabase = createClient(
  config.SUPABASE_URL,
  config.SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: { persistSession: false, autoRefreshToken: false },
  },
);

export type ContentStatus =
  | 'uploaded'
  | 'processed'
  | 'transcribing'
  | 'indexed'
  | 'failed';

export async function setContentStatus(contentId: string, status: ContentStatus) {
  const { error } = await supabase
    .from('contents')
    .update({ status })
    .eq('id', contentId);
  if (error) throw new Error(`Falha ao atualizar status: ${error.message}`);
}

export async function getContent(contentId: string) {
  const { data, error } = await supabase
    .from('contents')
    .select('id, title, content_type, video_url, status, module_id')
    .eq('id', contentId)
    .single();
  if (error) throw new Error(`Conteúdo não encontrado: ${error.message}`);
  return data;
}

export async function hasTranscription(contentId: string): Promise<boolean> {
  const { count, error } = await supabase
    .from('content_transcriptions')
    .select('content_id', { count: 'exact', head: true })
    .eq('content_id', contentId);
  if (error) throw new Error(`Check transcription falhou: ${error.message}`);
  return (count ?? 0) > 0;
}

/**
 * Baixa o arquivo do bucket de Storage para um path local.
 * `objectPath` é o caminho dentro do bucket (sem o nome do bucket).
 */
export async function downloadFromStorage(objectPath: string): Promise<Blob> {
  const { data, error } = await supabase.storage
    .from(config.SUPABASE_STORAGE_BUCKET)
    .download(objectPath);
  if (error) throw new Error(`Download storage falhou (${objectPath}): ${error.message}`);
  return data;
}
