# Imagem com CUDA + cuDNN para faster-whisper GPU
# Se o host não tiver GPU, o container funciona em CPU (configure WHISPER_DEVICE=cpu)
FROM nvidia/cuda:12.2.2-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    NODE_ENV=production

# Node 22 (LTS, WebSocket nativo) + Python 3.11 + ffmpeg
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates gnupg ffmpeg python3 python3-pip python3-venv python-is-python3 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# --- Python deps (camadas separadas para cache) ---
COPY python/requirements.txt python/requirements.txt
RUN pip3 install --no-cache-dir -r python/requirements.txt

# --- Node deps (inclui devDeps para o build) ---
COPY package.json package-lock.json* ./
RUN npm install --include=dev

# --- Build TypeScript ---
COPY tsconfig.json ./
COPY src ./src
COPY python ./python

RUN npm run build

# Verificação explícita: falha a imagem se dist/index.js não existir
RUN test -f dist/index.js || (echo "ERRO: dist/index.js nao foi gerado. Verifique o tsc." && exit 1)

# Remove dev deps após build (produção limpa)
RUN npm prune --omit=dev

EXPOSE 8787
CMD ["node", "dist/index.js"]
