// https://nuxt.com/docs/api/configuration/nuxt-config
export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  modules: ['@nuxtjs/supabase', '@nuxtjs/tailwindcss'],
  runtimeConfig: {
    openaiApiKey: process.env.OPENAI_API_KEY,
  },
  supabase: {
    redirect: true,
    redirectOptions: {
      login: '/login',
      callback: '/confirm',
      exclude: [],
    }
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
