#!/usr/bin/env python3
"""
Sidecar de transcricao usando faster-whisper.
E chamado como subprocesso pelo worker Node.js.

Imprime UM unico objeto JSON em stdout. Logs/progresso vao para stderr.
"""
import argparse
import json
import sys
from faster_whisper import WhisperModel


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio", required=True, help="Caminho do arquivo de audio (.mp3)")
    parser.add_argument("--model", default="large-v3")
    parser.add_argument("--device", default="cuda", choices=["cuda", "cpu"])
    parser.add_argument("--compute-type", default="float16")
    parser.add_argument("--language", default=None, help="Idioma forcado (ex: pt). Vazio = auto.")
    parser.add_argument("--beam-size", type=int, default=5)
    parser.add_argument("--vad-filter", action="store_true", default=True)
    args = parser.parse_args()

    print(
        f"[whisper] loading model={args.model} device={args.device} compute={args.compute_type}",
        file=sys.stderr,
    )
    model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)

    segments_iter, info = model.transcribe(
        args.audio,
        language=args.language or None,
        beam_size=args.beam_size,
        vad_filter=args.vad_filter,
        word_timestamps=False,
    )

    print(
        f"[whisper] detected language={info.language} duration={info.duration:.1f}s",
        file=sys.stderr,
    )

    segments = []
    full_text_parts = []
    for seg in segments_iter:
        text = seg.text.strip()
        segments.append(
            {
                "id": seg.id,
                "start": round(seg.start, 3),
                "end": round(seg.end, 3),
                "text": text,
            }
        )
        full_text_parts.append(text)
        if seg.id % 20 == 0:
            print(f"[whisper] segment {seg.id} t={seg.end:.1f}s", file=sys.stderr)

    payload = {
        "language": info.language,
        "duration": round(info.duration, 3),
        "model": args.model,
        "segments": segments,
        "full_text": " ".join(full_text_parts).strip(),
    }
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
