<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()
const router = useRouter()

const isDropdownOpen = ref(false)
const profile = ref({
  name: '',
  avatar_url: '',
  role: '',
})

async function fetchProfile() {
  const userId = user.value?.id || user.value?.sub
  if (!userId) return
  
  try {
    const { data, error } = await supabase
      .from('perfis')
      .select('name, avatar_url, role')
      .eq('id', userId)
      .single()

    if (data) {
      profile.value.name = data.name || user?.value?.email?.split('@')[0] || 'Usuário'
      profile.value.avatar_url = data.avatar_url || ''
      profile.value.role = data.role || 'user'
    }
  } catch (err) {
    console.error('Erro ao buscar perfil no AppBar:', err)
  }
}

async function handleLogout() {
  await supabase.auth.signOut()
  router.push('/login')
}

function toggleDropdown() {
  isDropdownOpen.value = !isDropdownOpen.value
}

// Close dropdown when clicking outside
if (process.client) {
  window.addEventListener('click', (e) => {
    const target = e.target as HTMLElement
    if (!target.closest('.profile-dropdown-container')) {
      isDropdownOpen.value = false
    }
  })
}

watch(user, (newUser) => {
  if (newUser) fetchProfile()
}, { immediate: true })

onMounted(() => {
  if (user.value) fetchProfile()
})
</script>

<template>
  <nav class="app-bar">
    <div class="app-bar-container">
      <NuxtLink to="/" class="brand">
        <span class="brand-text">Inovação Academy</span>
      </NuxtLink>

      <!-- Busca: só para usuários autenticados -->
      <SearchBar v-if="user" />

      <div v-if="user" class="profile-dropdown-container">
        <button class="profile-trigger" @click.stop="toggleDropdown">
          <div class="user-info">
            <span class="user-name">{{ profile.name }}</span>
            <div class="avatar-wrapper">
              <img v-if="profile.avatar_url" :src="profile.avatar_url" alt="Avatar" class="avatar-img">
              <div v-else class="avatar-placeholder">
                <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
              </div>
            </div>
          </div>
          <svg class="chevron" :class="{ 'rotate': isDropdownOpen }" xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>
        </button>

        <Transition name="dropdown">
          <div v-if="isDropdownOpen" class="dropdown-menu">
            <div class="user-details-mobile">
              <span class="user-email">{{ user?.email }}</span>
            </div>
            
            <NuxtLink to="/profile" class="dropdown-item" @click="isDropdownOpen = false">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
              Meu Perfil
            </NuxtLink>

            <div class="dropdown-divider" v-if="profile.role == 'admin' || profile.role == 'publicador'"></div>
            <div class="dropdown-section-title" v-if="profile.role == 'admin' || profile.role == 'publicador'">Navegação</div>
            <NuxtLink to="/admin/courses" class="dropdown-item" v-if="profile.role == 'admin' || profile.role == 'publicador'" @click="isDropdownOpen = false">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1-2.5-2.5Z"/></svg>
              Gerenciar Cursos
            </NuxtLink>
            <NuxtLink to="/admin/users" class="dropdown-item" v-if="profile.role == 'admin'" @click="isDropdownOpen = false">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
              Gerenciar Usuários
            </NuxtLink>
            <NuxtLink to="/admin/groups" class="dropdown-item" v-if="profile.role == 'admin'" @click="isDropdownOpen = false">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="17" cy="15" r="3"/><circle cx="7" cy="15" r="3"/><path d="M10 15h4"/><circle cx="12" cy="7" r="3"/><path d="M7.5 12.5 6 15"/><path d="M16.5 12.5 18 15"/></svg>
              Gerenciar Grupos
            </NuxtLink>

            <div class="dropdown-divider"></div>
            <button class="dropdown-item logout" @click="handleLogout">
              <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/></svg>
              Sair
            </button>
          </div>
        </Transition>
      </div>
      
      <div v-else>
        <NuxtLink to="/login" class="login-btn">Entrar</NuxtLink>
      </div>
    </div>
  </nav>
</template>

<style scoped>
.app-bar {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: 72px;
  background: rgba(5, 5, 5, 0.8);
  backdrop-filter: blur(12px);
  border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  z-index: 1000;
  display: flex;
  align-items: center;
}

.app-bar-container {
  max-width: 1200px;
  width: 100%;
  margin: 0 auto;
  padding: 0 24px;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.brand {
  text-decoration: none;
  display: flex;
  align-items: center;
  gap: 12px;
  transition: transform 0.2s ease;
}

.brand:hover {
  transform: translateY(-1px);
}

.brand-text {
  font-size: 1.25rem;
  font-weight: 700;
  background: linear-gradient(135deg, #fff 0%, #a855f7 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  letter-spacing: -0.02em;
}

.profile-dropdown-container {
  position: relative;
}

.profile-trigger {
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  padding: 6px 12px 6px 16px;
  border-radius: 99px;
  display: flex;
  align-items: center;
  gap: 12px;
  cursor: pointer;
  transition: all 0.2s ease;
  color: white;
}

.profile-trigger:hover {
  background: rgba(255, 255, 255, 0.1);
  border-color: rgba(255, 255, 255, 0.2);
}

.user-info {
  display: flex;
  align-items: center;
  gap: 10px;
}

.user-name {
  font-size: 0.9rem;
  font-weight: 500;
  max-width: 120px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.avatar-wrapper {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  overflow: hidden;
  background: rgba(255, 255, 255, 0.1);
  border: 1px solid rgba(255, 255, 255, 0.1);
  display: flex;
  align-items: center;
  justify-content: center;
}

.avatar-img {
  width: 100%;
  height: 100%;
  object-cover: cover;
}

.avatar-placeholder {
  color: rgba(255, 255, 255, 0.5);
}

.chevron {
  transition: transform 0.2s ease;
  color: rgba(255, 255, 255, 0.5);
}

.chevron.rotate {
  transform: rotate(180deg);
}

.dropdown-menu {
  position: absolute;
  top: calc(100% + 12px);
  right: 0;
  width: 240px;
  background: #111;
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 16px;
  padding: 8px;
  box-shadow: 0 20px 40px rgba(0, 0, 0, 0.4);
  transform-origin: top right;
}

.user-details-mobile {
  padding: 12px;
  display: flex;
  flex-direction: column;
}

.user-email {
  font-size: 0.75rem;
  color: rgba(255, 255, 255, 0.4);
}

.dropdown-section-title {
  font-size: 0.65rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: rgba(255, 255, 255, 0.3);
  padding: 8px 12px 4px;
}

.dropdown-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  border-radius: 10px;
  color: #ccc;
  text-decoration: none;
  font-size: 0.9rem;
  transition: all 0.2s ease;
  width: 100%;
  border: none;
  background: transparent;
  cursor: pointer;
  text-align: left;
}

.dropdown-item:hover {
  background: rgba(255, 255, 255, 0.05);
  color: white;
}

.dropdown-item.logout:hover {
  background: rgba(239, 68, 68, 0.1);
  color: #ef4444;
}

.dropdown-divider {
  height: 1px;
  background: rgba(255, 255, 255, 0.05);
  margin: 8px;
}

.login-btn {
  background: white;
  color: black;
  padding: 8px 20px;
  border-radius: 99px;
  text-decoration: none;
  font-weight: 600;
  font-size: 0.9rem;
  transition: all 0.2s ease;
}

.login-btn:hover {
  transform: scale(1.05);
  background: #f0f0f0;
}

/* Transitions */
.dropdown-enter-active,
.dropdown-leave-active {
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

.dropdown-enter-from,
.dropdown-leave-to {
  opacity: 0;
  transform: translateY(-10px) scale(0.95);
}
</style>
