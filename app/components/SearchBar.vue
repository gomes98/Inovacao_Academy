<script setup lang="ts">
const { query, results, isLoading, error, clear } = useSearch()
const isOpen = ref(false)
const inputRef = ref<HTMLInputElement | null>(null)

function open() {
  isOpen.value = true
  nextTick(() => inputRef.value?.focus())
}

function close() {
  isOpen.value = false
  clear()
}

function handleBlur(e: FocusEvent) {
  const container = (e.currentTarget as HTMLElement)
  const relatedTarget = e.relatedTarget as HTMLElement | null
  if (!relatedTarget || !container.contains(relatedTarget)) {
    setTimeout(() => close(), 150)
  }
}

function handleKeydown(e: KeyboardEvent) {
  if (e.key === 'Escape') close()
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60)
  const s = Math.floor(seconds % 60).toString().padStart(2, '0')
  return `${m}:${s}`
}

function truncate(text: string, max = 80): string {
  return text.length > max ? text.slice(0, max) + '…' : text
}

const showDropdown = computed(() =>
  isOpen.value && query.value.length >= 2
)
</script>

<template>
  <div class="search-container" @keydown="handleKeydown">
    <!-- Ícone de lupa (fechado) -->
    <button v-if="!isOpen" class="search-icon-btn" @click="open" aria-label="Buscar">
      <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"
        fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
      </svg>
    </button>

    <!-- Input expandido -->
    <div v-else class="search-expanded" @focusout="handleBlur">
      <svg class="search-icon-inline" xmlns="http://www.w3.org/2000/svg" width="16" height="16"
        viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
        stroke-linecap="round" stroke-linejoin="round">
        <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
      </svg>
      <input
        ref="inputRef"
        v-model="query"
        type="text"
        placeholder="Buscar conteúdo..."
        class="search-input"
      />
      <button class="close-btn" @mousedown.prevent="close" aria-label="Fechar busca">
        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24"
          fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round">
          <path d="M18 6 6 18M6 6l12 12"/>
        </svg>
      </button>

      <!-- Dropdown de resultados -->
      <Transition name="dropdown">
        <div v-if="showDropdown" class="results-dropdown">
          <!-- Carregando -->
          <div v-if="isLoading" class="results-list">
            <div v-for="i in 3" :key="i" class="skeleton-item">
              <div class="skeleton-thumb"></div>
              <div class="skeleton-text">
                <div class="skeleton-line w-3/4"></div>
                <div class="skeleton-line w-1/2"></div>
                <div class="skeleton-line w-full"></div>
              </div>
            </div>
          </div>

          <!-- Erro -->
          <div v-else-if="error" class="results-empty">{{ error }}</div>

          <!-- Sem resultados -->
          <div v-else-if="results.length === 0" class="results-empty">
            Nenhum resultado para «{{ query }}»
          </div>

          <!-- Resultados -->
          <div v-else class="results-list">
            <NuxtLink
              v-for="r in results"
              :key="`${r.contentId}-${r.startTime}`"
              :to="`/lesson/${r.contentId}?t=${Math.floor(r.startTime)}`"
              class="result-item"
              @click="close"
            >
              <!-- Thumbnail -->
              <div class="result-thumb">
                <img v-if="r.thumbnailUrl" :src="r.thumbnailUrl" :alt="r.contentTitle" />
                <div v-else class="thumb-fallback">
                  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"
                    fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
                    <polygon points="5 3 19 12 5 21 5 3"/>
                  </svg>
                </div>
              </div>
              <!-- Texto -->
              <div class="result-text">
                <span class="result-title">{{ r.contentTitle }}</span>
                <span class="result-meta">{{ r.moduleName }} · {{ r.courseName }}</span>
                <span class="result-chunk">
                  "{{ truncate(r.chunkText) }}"
                  <span class="result-time">⏱ {{ formatTime(r.startTime) }}</span>
                </span>
              </div>
            </NuxtLink>
          </div>
        </div>
      </Transition>
    </div>
  </div>
</template>

<style scoped>
.search-container {
  position: relative;
  display: flex;
  align-items: center;
}

.search-icon-btn {
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 99px;
  width: 38px;
  height: 38px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  color: rgba(255,255,255,0.7);
  transition: all 0.2s ease;
}
.search-icon-btn:hover {
  background: rgba(255,255,255,0.1);
  color: white;
}

.search-expanded {
  position: relative;
  display: flex;
  align-items: center;
  gap: 8px;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(168,85,247,0.4);
  border-radius: 99px;
  padding: 6px 12px;
  width: 280px;
  transition: width 0.2s ease;
}

.search-icon-inline {
  color: rgba(255,255,255,0.4);
  flex-shrink: 0;
}

.search-input {
  background: transparent;
  border: none;
  outline: none;
  color: white;
  font-size: 0.875rem;
  width: 100%;
}
.search-input::placeholder {
  color: rgba(255,255,255,0.3);
}

.close-btn {
  background: transparent;
  border: none;
  cursor: pointer;
  color: rgba(255,255,255,0.4);
  display: flex;
  align-items: center;
  flex-shrink: 0;
  padding: 2px;
  transition: color 0.15s;
}
.close-btn:hover { color: white; }

/* Dropdown */
.results-dropdown {
  position: absolute;
  top: calc(100% + 10px);
  left: 50%;
  transform: translateX(-50%);
  width: 420px;
  background: #111;
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 16px;
  padding: 8px;
  box-shadow: 0 20px 40px rgba(0,0,0,0.5);
  z-index: 1100;
  max-height: 440px;
  overflow-y: auto;
}

.results-list {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.results-empty {
  padding: 20px;
  text-align: center;
  color: rgba(255,255,255,0.4);
  font-size: 0.875rem;
}

.result-item {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 10px;
  border-radius: 10px;
  text-decoration: none;
  transition: background 0.15s;
  cursor: pointer;
}
.result-item:hover { background: rgba(255,255,255,0.05); }

.result-thumb {
  width: 48px;
  height: 48px;
  border-radius: 8px;
  overflow: hidden;
  flex-shrink: 0;
  background: rgba(255,255,255,0.05);
  border: 1px solid rgba(255,255,255,0.08);
  display: flex;
  align-items: center;
  justify-content: center;
}
.result-thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.thumb-fallback { color: rgba(255,255,255,0.3); }

.result-text {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.result-title {
  font-size: 0.875rem;
  font-weight: 600;
  color: white;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.result-meta {
  font-size: 0.75rem;
  color: rgba(255,255,255,0.4);
}
.result-chunk {
  font-size: 0.75rem;
  color: rgba(255,255,255,0.55);
  line-height: 1.4;
}
.result-time {
  color: #a855f7;
  font-weight: 600;
  margin-left: 6px;
}

/* Skeletons */
.skeleton-item {
  display: flex;
  gap: 12px;
  padding: 10px;
  align-items: flex-start;
}
.skeleton-thumb {
  width: 48px;
  height: 48px;
  border-radius: 8px;
  background: rgba(255,255,255,0.07);
  flex-shrink: 0;
  animation: pulse 1.5s ease-in-out infinite;
}
.skeleton-text { flex: 1; display: flex; flex-direction: column; gap: 6px; }
.skeleton-line {
  height: 10px;
  border-radius: 4px;
  background: rgba(255,255,255,0.07);
  animation: pulse 1.5s ease-in-out infinite;
}
.w-3\/4 { width: 75%; }
.w-1\/2 { width: 50%; }
.w-full { width: 100%; }

@keyframes pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}

/* Transition dropdown */
.dropdown-enter-active,
.dropdown-leave-active {
  transition: all 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}
.dropdown-enter-from,
.dropdown-leave-to {
  opacity: 0;
  transform: translateX(-50%) translateY(-8px);
}
</style>
