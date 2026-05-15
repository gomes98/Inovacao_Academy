<script setup lang="ts">
import videojs from 'video.js'
import 'video.js/dist/video-js.css'

interface Props {
  src: string
  poster?: string
}

const props = defineProps<Props>()
const emit = defineEmits(['progress-90'])

const videoElement = ref<HTMLVideoElement | null>(null)
let player: any = null
const progressReached90 = ref(false)
const isReady = ref(false)

const isYouTube = computed(() => props.src.includes('youtube.com') || props.src.includes('youtu.be'))
const isVimeo = computed(() => props.src.includes('vimeo.com'))
const isHLS = computed(() => props.src.includes('.m3u8'))

function getPlayerOptions() {
  const options: any = {
    autoplay: false,
    controls: true,
    responsive: true,
    fluid: true,
    playbackRates: [0.5, 1, 1.25, 1.5, 2],
    poster: props.poster,
  }

  if (isYouTube.value) {
    options.techOrder = ['youtube']
    options.sources = [{ type: 'video/youtube', src: props.src }]
    options.youtube = { iv_load_policy: 3, modestbranding: 1, rel: 0, showinfo: 0 }
  } else if (isVimeo.value) {
    options.techOrder = ['vimeo']
    options.sources = [{ type: 'video/vimeo', src: props.src }]
  } else if (isHLS.value) {
    options.sources = [{ src: props.src, type: 'application/x-mpegURL' }]
  } else {
    options.sources = [{ src: props.src, type: props.src.endsWith('.mp4') ? 'video/mp4' : 'video/webm' }]
  }

  return options
}

// Builds a quality MenuButton and inserts it into the control bar.
// Called once when the first quality level is reported by VHS.
function addQualityMenuButton() {
  if (!player) return

  const vjs = (window as any).videojs || videojs
  const ql = player.qualityLevels()
  // console.log('[QS] addQualityMenuButton called, levels:', ql?.length)
  if (!ql || ql.length < 2) { console.warn('[QS] not enough levels:', ql?.length); return }

  const MenuItem = vjs.getComponent('MenuItem')
  const MenuButton = vjs.getComponent('MenuButton')

  if (!vjs.getComponent('QualityMenuItem')) {
    class QualityMenuItem extends MenuItem {
      qualityHeight_: number
      constructor(player: any, options: any) {
        options.selectable = true
        super(player, options)
        this.qualityHeight_ = options.qualityHeight
        this.selected(options.selected || false)
      }
      handleClick() {
        (this.parentComponent_ as any).items?.forEach((item: any) => item.selected(false))
        this.selected(true)
        const height = this.qualityHeight_
        for (let i = 0; i < ql.length; i++) {
          ql[i].enabled = height === -1 || ql[i].height === height
        }
        ql.trigger('change')
      }
    }
    vjs.registerComponent('QualityMenuItem', QualityMenuItem)
  }

  if (!vjs.getComponent('QualityMenuButton')) {
    const QualityMenuItem = vjs.getComponent('QualityMenuItem')
    class QualityMenuButton extends MenuButton {
      constructor(player: any, options: any) {
        // Store levels before super() so createItems() (called by super) can access them
        ;(options as any).__ql = options.qualityLevels
        super(player, options)
        this.addClass('vjs-quality-selector')
      }
      createItems() {
        const qlRef: any = (this.options_ as any).__ql
        if (!qlRef) return []
        const heights = new Set<number>()
        for (let i = 0; i < qlRef.length; i++) {
          // console.log(`[QS] level ${i}:`, qlRef[i].width, 'x', qlRef[i].height, 'bandwidth:', qlRef[i].bandwidth)
          if (qlRef[i].height) heights.add(qlRef[i].height)
        }
        const sorted = Array.from(heights).sort((a: number, b: number) => b - a)
        const items: any[] = [
          new QualityMenuItem(this.player_, { label: 'Auto', qualityHeight: -1, selected: true }),
        ]
        sorted.forEach((h: number) => {
          items.push(new QualityMenuItem(this.player_, { label: `${h}p`, qualityHeight: h }))
        })
        return items
      }
    }
    vjs.registerComponent('QualityMenuButton', QualityMenuButton)
  }

  const controlBar = player.getChild('ControlBar')
  if (!controlBar) return
  if (controlBar.getChild('QualityMenuButton')) return

  controlBar.addChild('QualityMenuButton', { qualityLevels: ql }, controlBar.children().length - 1)
  // console.log('[QS] QualityMenuButton added to control bar')
}

function setupQualityTracking() {
  if (!player) { console.warn('[QS] player not ready'); return }
  if (!player.qualityLevels) { console.warn('[QS] qualityLevels plugin not loaded'); return }

  const ql = player.qualityLevels()
  // console.log('[QS] qualityLevels already present:', ql.length)

  let timer: ReturnType<typeof setTimeout> | null = null

  const tryAdd = () => {
    if (timer) clearTimeout(timer)
    // console.log('[QS] addqualitylevel fired, total:', ql.length)
    // Wait 200ms after the last addqualitylevel to ensure all levels are collected
    timer = setTimeout(() => {
      if (ql.length >= 2) addQualityMenuButton()
    }, 200)
  }

  // If levels already populated, schedule immediately
  if (ql.length >= 1) {
    tryAdd()
  }

  ql.on('addqualitylevel', tryAdd)
}

onMounted(async () => {
  if (import.meta.server) return

  const vjs = (videojs as any).default || videojs
  ;(window as any).videojs = vjs
  ;(globalThis as any).videojs = vjs

  const loadPlugin = async (name: string, fn: () => Promise<any>) => {
    try { await fn() } catch (e) { console.warn(`${name} failed to load:`, e) }
  }

  // await loadPlugin('videojs-youtube', () => import('videojs-youtube'))
  // await loadPlugin('videojs-vimeo', () => import('videojs-vimeo'))
  // await loadPlugin('videojs-contrib-quality-levels', () => import('videojs-contrib-quality-levels'))

  isReady.value = true
})

watch([isReady, () => videoElement.value], ([ready, el]) => {
  if (!ready || !el || player) return

  const vjs = (window as any).videojs || videojs
  player = vjs(el, getPlayerOptions())

  player.on('timeupdate', () => {
    const duration = player.duration()
    if (duration > 0 && !progressReached90.value && player.currentTime() / duration >= 0.9) {
      progressReached90.value = true
      emit('progress-90')
    }
  })

  if (isHLS.value) {
    player.ready(() => setupQualityTracking())
  }
}, { immediate: true })

watch(() => props.src, (newSrc) => {
  if (!player) return

  progressReached90.value = false

  // Remove the old quality button so it can be rebuilt for the new source
  const controlBar = player.getChild('ControlBar')
  const oldBtn = controlBar?.getChild('QualityMenuButton')
  if (oldBtn) controlBar.removeChild(oldBtn)

  if (isYouTube.value) {
    player.src({ type: 'video/youtube', src: newSrc })
  } else if (isVimeo.value) {
    player.src({ type: 'video/vimeo', src: newSrc })
  } else if (isHLS.value) {
    player.src({ type: 'application/x-mpegURL', src: newSrc })
    player.ready(() => setupQualityTracking())
  } else {
    player.src({ src: newSrc })
  }
})

onBeforeUnmount(() => {
  if (player) player.dispose()
})
</script>

<template>
  <div class="video-js-container w-full h-full rounded-[32px] overflow-hidden">
    <div data-vjs-player>
      <video
        ref="videoElement"
        class="video-js vjs-big-play-centered vjs-theme-modern"
        controls="true"
      ></video>
    </div>
  </div>
</template>

<style>
.video-js {
  font-family: 'Inter', sans-serif;
  background-color: #000;
}

.vjs-theme-modern .vjs-big-play-button {
  background-color: rgba(139, 92, 246, 0.8);
  border: none;
  width: 80px;
  height: 80px;
  line-height: 80px;
  border-radius: 50%;
  backdrop-filter: blur(4px);
  transition: all 0.3s ease;
}

.video-js:hover .vjs-big-play-button {
  background-color: rgba(139, 92, 246, 1);
  transform: scale(1.1);
}

.vjs-theme-modern .vjs-control-bar {
  background: linear-gradient(to top, rgba(0,0,0,0.8), transparent);
  height: 60px;
}

.vjs-theme-modern .vjs-play-progress {
  background-color: #8b5cf6;
}

.vjs-theme-modern .vjs-slider {
  background-color: rgba(255, 255, 255, 0.1);
}

.vjs-theme-modern .vjs-load-progress {
  background-color: rgba(255, 255, 255, 0.2);
}

.vjs-theme-modern .vjs-volume-level {
  background-color: #8b5cf6;
}

.video-js video {
  border-radius: 32px;
}

.vjs-youtube .vjs-poster {
  background-size: cover;
}

/* Quality selector button */
.vjs-quality-selector .vjs-icon-placeholder::before {
  content: '\f110';
  font-family: VideoJS;
}

.vjs-quality-selector .vjs-menu .vjs-menu-content {
  bottom: 3em;
}
</style>
