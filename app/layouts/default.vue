<template>
  <div class="layout-wrapper">
    <AppBar />
    <div class="content-container">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.layout-wrapper {
  min-height: 100vh;
  background-color: #050505;
}

.content-container {
  padding-top: 72px; /* Height of the AppBar */
}
</style>
