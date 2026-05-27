// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  modules: ['@nuxtjs/supabase', '@nuxtjs/tailwindcss'],
  app: {
    head: {
      title: 'Inovation Academy',
    }
  },
  runtimeConfig: {
    openaiApiKey: '',
    workerUrl: '',
    workerSecret: '',
  },
  supabase: {
    redirect: true,
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      exclude: [],
    },
    cookieOptions: {
      // Set NUXT_COOKIE_SECURE=true at build time when HTTPS is configured
      secure: process.env.NUXT_COOKIE_SECURE === 'true',
      sameSite: 'lax',
    },
  },
  build: {
    transpile: [
      'videojs-vimeo',
      'videojs-youtube',
      'videojs-contrib-quality-levels',
      'videojs-hls-quality-selector'
    ]
  },
  css: [
    'video.js/dist/video-js.css'
  ],
  vite: {
    optimizeDeps: {
      include: [
        'video.js',
        'videojs-youtube',
        'videojs-vimeo',
        'videojs-contrib-quality-levels',
        'videojs-hls-quality-selector'
      ]
    }
  }
})
