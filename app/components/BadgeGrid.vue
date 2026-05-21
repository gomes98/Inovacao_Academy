<!-- app/components/BadgeGrid.vue -->
<script setup lang="ts">
interface Badge {
  slug: string
  name: string
  description: string
  icon_url: string | null
}

interface Props {
  allBadges: Badge[]
  earnedSlugs: Set<string>
}
defineProps<Props>()

const BADGE_EMOJIS: Record<string, string> = {
  first_video:   '🎬',
  first_comment: '💬',
  video_5:       '🏃',
  comment_10:    '🗣️',
  top3_group:    '🏆',
  streak_7:      '🔥',
}
</script>

<template>
  <div class="grid grid-cols-3 sm:grid-cols-6 gap-4">
    <div
      v-for="badge in allBadges"
      :key="badge.slug"
      class="flex flex-col items-center gap-2 p-3 rounded-2xl border transition-all"
      :class="earnedSlugs.has(badge.slug)
        ? 'bg-yellow-500/10 border-yellow-500/30'
        : 'bg-white/[0.02] border-white/5 opacity-40'"
      :title="badge.description"
    >
      <span class="text-3xl">{{ badge.icon_url ?? BADGE_EMOJIS[badge.slug] ?? '🏅' }}</span>
      <span class="text-[10px] text-center font-semibold leading-tight"
        :class="earnedSlugs.has(badge.slug) ? 'text-yellow-300' : 'text-gray-500'"
      >
        {{ badge.name }}
      </span>
      <span v-if="!earnedSlugs.has(badge.slug)" class="text-[9px] text-gray-600">🔒</span>
    </div>
  </div>
</template>
