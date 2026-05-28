<script setup lang="ts">
definePageMeta({
  layout: false,
})

const supabase = useSupabaseClient()
const email = ref('')
const password = ref('')
const loading = ref(false)
const errorMsg = ref('')
const usuarioLogado = useState('usuarioLogado')

const showForgotModal = ref(false)
const forgotEmail = ref('')
const forgotLoading = ref(false)
const forgotMsg = ref('')
const forgotError = ref('')

function openForgotModal() {
  forgotEmail.value = email.value
  forgotMsg.value = ''
  forgotError.value = ''
  showForgotModal.value = true
}

async function handleForgotPassword() {
  if (!forgotEmail.value.trim()) {
    forgotError.value = 'Informe seu e-mail para continuar.'
    return
  }
  try {
    forgotLoading.value = true
    forgotError.value = ''
    const { error } = await supabase.auth.resetPasswordForEmail(forgotEmail.value.trim())
    if (error) throw error
    forgotMsg.value = 'Verifique seu e-mail! Enviamos um link para redefinir sua senha.'
  } catch (err: any) {
    forgotError.value = err.message || 'Erro ao enviar e-mail de recuperação'
  } finally {
    forgotLoading.value = false
  }
}
function camposValidos() {
  if (!email.value.trim() || !password.value.trim()) {
    errorMsg.value = 'Preencha o e-mail e a senha para continuar.'
    return false
  }
  return true
}

async function handleLogin() {
  if (!camposValidos()) return
  try {
    loading.value = true
    errorMsg.value = ''
    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.value,
      password: password.value,
    })
    if (error) throw error
    usuarioLogado.value = data.user;
    navigateTo('/')
  } catch (err: any) {
    errorMsg.value = err.message || 'Erro ao fazer login'
  } finally {
    loading.value = false
  }
}

async function handleSignUp() {
  if (!camposValidos()) return
  try {
    loading.value = true
    errorMsg.value = ''
    const { error } = await supabase.auth.signUp({
      email: email.value,
      password: password.value,
    })
    if (error) throw error
    errorMsg.value = 'Confirme seu e-mail para continuar!'
  } catch (err: any) {
    errorMsg.value = err.message || 'Erro ao cadastrar'
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="min-h-screen bg-[#050505] text-white font-sans flex items-center justify-center p-6 selection:bg-[#FAA407]/30">
    <!-- Background Glows -->
    <div class="fixed inset-0 overflow-hidden pointer-events-none">
      <div class="absolute top-[20%] left-[20%] w-[50%] h-[50%] bg-[#006E46]/10 blur-[120px] rounded-full"></div>
      <div class="absolute bottom-[20%] right-[20%] w-[40%] h-[40%] bg-[#FAA407]/10 blur-[100px] rounded-full"></div>
    </div>

    <div class="relative z-10 w-full max-w-md">
      <div class="glass-card p-8 rounded-3xl border border-white/10 bg-white/5 backdrop-blur-2xl shadow-2xl">
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold bg-gradient-to-r from-white to-gray-400 bg-clip-text text-transparent">
            Bem-vindo
          </h1>
          <p class="text-gray-400 mt-2 text-sm italic">Inovação Academy</p>
        </div>

        <form @submit.prevent="handleLogin" class="space-y-6">
          <div class="space-y-2">
            <label class="text-xs font-medium text-gray-400 uppercase tracking-wider">E-mail</label>
            <input 
              v-model="email"
              type="email" 
              required
              placeholder="seu@email.com"
              class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-[#FAA407]/50 focus:bg-white/[0.08] transition-all"
            />
          </div>

          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <label class="text-xs font-medium text-gray-400 uppercase tracking-wider">Senha</label>
              <button
                type="button"
                @click="openForgotModal"
                class="text-xs text-[#FAA407]/70 hover:text-[#FAA407] transition-colors"
              >
                Esqueci minha senha
              </button>
            </div>
            <input
              v-model="password"
              type="password"
              required
              placeholder="••••••••"
              class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-[#FAA407]/50 focus:bg-white/[0.08] transition-all"
            />
          </div>

          <div v-if="errorMsg" class="p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 text-xs text-center">
            {{ errorMsg }}
          </div>

          <div class="flex flex-col gap-3 pt-2">
            <button 
              type="submit"
              :disabled="loading"
              class="w-full bg-white text-black font-bold py-3 rounded-xl hover:bg-gray-200 active:scale-[0.98] transition-all disabled:opacity-50 disabled:scale-100"
            >
              {{ loading ? 'Entrando...' : 'Entrar' }}
            </button>
            <button 
              @click.prevent="handleSignUp"
              :disabled="loading"
              class="w-full bg-white/5 border border-white/10 text-white font-medium py-3 rounded-xl hover:bg-white/10 active:scale-[0.98] transition-all"
            >
              Criar Conta
            </button>
          </div>
        </form>

        <p class="mt-8 text-center text-xs text-gray-500">
          Acesso exclusivo para membros da Inovação Academy.
        </p>
      </div>
    </div>
  </div>

  <!-- Modal Recuperação de Senha -->
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="showForgotModal"
        class="fixed inset-0 z-50 flex items-center justify-center p-6"
        @click.self="showForgotModal = false"
      >
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm"></div>
        <div class="relative z-10 w-full max-w-sm bg-[#0d0d0d] border border-white/10 rounded-3xl p-8 shadow-2xl">
          <div class="flex items-center justify-between mb-6">
            <h2 class="text-lg font-bold text-white">Recuperar senha</h2>
            <button
              type="button"
              @click="showForgotModal = false"
              class="text-gray-500 hover:text-white transition-colors text-xl leading-none"
            >
              ×
            </button>
          </div>

          <div v-if="!forgotMsg" class="space-y-4">
            <p class="text-sm text-gray-400">Informe seu e-mail e enviaremos um link para redefinir sua senha.</p>
            <div class="space-y-2">
              <label class="text-xs font-medium text-gray-400 uppercase tracking-wider">E-mail</label>
              <input
                v-model="forgotEmail"
                type="email"
                placeholder="seu@email.com"
                class="w-full bg-white/5 border border-white/10 rounded-xl px-4 py-3 outline-none focus:border-[#FAA407]/50 focus:bg-white/[0.08] transition-all text-white"
                @keyup.enter="handleForgotPassword"
              />
            </div>
            <div v-if="forgotError" class="p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 text-xs text-center">
              {{ forgotError }}
            </div>
            <button
              type="button"
              :disabled="forgotLoading"
              @click="handleForgotPassword"
              class="w-full bg-[#FAA407] text-black font-bold py-3 rounded-xl hover:bg-[#FAA407]/90 active:scale-[0.98] transition-all disabled:opacity-50 disabled:scale-100"
            >
              {{ forgotLoading ? 'Enviando...' : 'Enviar link' }}
            </button>
          </div>

          <div v-else class="text-center space-y-4">
            <div class="text-4xl">✉️</div>
            <p class="text-sm text-gray-300">{{ forgotMsg }}</p>
            <button
              type="button"
              @click="showForgotModal = false"
              class="w-full bg-white/5 border border-white/10 text-white font-medium py-3 rounded-xl hover:bg-white/10 transition-all"
            >
              Fechar
            </button>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.glass-card {
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.5);
}

.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.2s ease;
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}
</style>
