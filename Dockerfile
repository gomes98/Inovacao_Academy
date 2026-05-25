# Stage 1: build
FROM node:22-alpine AS builder

WORKDIR /app

ARG NUXT_COOKIE_SECURE=false
ENV NUXT_COOKIE_SECURE=$NUXT_COOKIE_SECURE

COPY package.json package-lock.json ./
RUN npm install

COPY . .
RUN npm run build

# Stage 2: runtime
FROM node:22-alpine AS runner

WORKDIR /app

COPY --from=builder /app/.output ./.output

EXPOSE 3000

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000

CMD ["node", ".output/server/index.mjs"]
