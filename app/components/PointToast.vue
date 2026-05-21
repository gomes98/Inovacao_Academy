<!-- app/components/PointToast.vue -->
<script setup lang="ts">
interface Props {
  points: number | null
  label: string | null
  badge: { name: string; icon_url: string | null } | null
}
const props = defineProps<Props>()
const emit = defineEmits(['close'])

const visible = ref(false)

watch(
  [() => props.points, () => props.badge],
  ([newPoints, newBadge]) => {
    if (newPoints || newBadge) {
      visible.value = true
      setTimeout(() => {
        visible.value = false
        emit('close')
      }, 3000)
    }
  }
)
</script>

<template>
  <Transition name="toast">
    <div
      v-if="visible && (points || badge)"
      class="fixed bottom-6 right-6 z-50 flex flex-col gap-2"
    >
      <div
        v-if="points && label"
        class="flex items-center gap-3 px-5 py-3 rounded-2xl bg-purple-600/90 backdrop-blur-md border border-purple-400/30 shadow-2xl text-white"
      >
        <span class="text-xl font-black text-yellow-300">+{{ points }}</span>
        <span class="text-sm font-medium">{{ label }}</span>
      </div>
      <div
        v-if="badge"
        class="flex items-center gap-3 px-5 py-3 rounded-2xl bg-yellow-500/20 backdrop-blur-md border border-yellow-400/30 shadow-2xl text-white"
      >
        <span class="text-2xl">{{ badge.icon_url ?? '🏅' }}</span>
        <div>
          <p class="text-xs text-yellow-300 font-bold uppercase tracking-widest">Badge Desbloqueado!</p>
          <p class="text-sm font-semibold">{{ badge.name }}</p>
        </div>
      </div>
    </div>
  </Transition>
</template>

<style scoped>
.toast-enter-active,
.toast-leave-active {
  transition: all 0.3s ease;
}
.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateY(20px);
}
</style>
