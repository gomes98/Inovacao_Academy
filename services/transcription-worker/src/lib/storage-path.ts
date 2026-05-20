/**
 * Deriva o objectPath do MP3 a partir do video_url salvo em contents.video_url.
 *
 * O serviço externo (FFMPEG) salva o MP3 com o mesmo path do .m3u8,
 * apenas com extensão trocada para .mp3.
 *
 * video_url pode ser:
 *   - URL pública completa: https://<proj>.supabase.co/storage/v1/object/public/courses/course-x/mod-y/video.m3u8
 *   - Path relativo no bucket: course-x/mod-y/video.m3u8
 *
 * Retorna o path dentro do bucket (sem o nome do bucket).
 */
export function deriveMp3Path(videoUrl: string, bucket: string): string {
  let path = videoUrl;

  // Se for URL completa, extrai a parte após /<bucket>/
  const marker = `/${bucket}/`;
  const idx = path.indexOf(marker);
  if (idx !== -1) {
    path = path.slice(idx + marker.length);
  }

  // Remove query string se houver
  path = path.split('?')[0];

  // Troca .m3u8 por .mp3
  return path.replace(/\.m3u8$/i, '.mp3');
}
