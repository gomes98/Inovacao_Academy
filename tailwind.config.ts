import type { Config } from 'tailwindcss'
import typography from '@tailwindcss/typography'

export default {
  theme: {
    extend: {
      fontFamily: {
        sans: ['Barlow', 'sans-serif'],
        condensed: ['Barlow Condensed', 'sans-serif'],
      },
    },
  },
  plugins: [
    typography,
  ],
} satisfies Config
