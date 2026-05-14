<script setup lang="ts">
const user = useSupabaseUser()

watch(user, () => {
  if (user.value) {
    return navigateTo('/')
  }
}, { immediate: true })
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white flex items-center justify-center">
    <div class="text-center">
      <div class="w-12 h-12 border-4 border-purple-500 border-t-transparent rounded-full animate-spin mx-auto mb-4"></div>
      <p class="text-gray-400">Confirmando autenticação...</p>
    </div>
  </div>
</template>
