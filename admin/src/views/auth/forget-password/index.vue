<template>
  <div class="flex w-full h-screen">
    <LoginLeftView />

    <div class="relative flex-1">
      <AuthTopBar />

      <div class="auth-right-wrap">
        <div class="form">
          <h3 class="title">{{ $t('forgetPassword.title') }}</h3>
          <p class="sub-title">{{ $t('forgetPassword.subTitle') }}</p>
          <div class="mt-5">
            <ElInput
              class="custom-height"
              :placeholder="$t('forgetPassword.placeholder')"
              v-model.trim="account"
            />
          </div>

          <div class="code-row">
            <ElInput
              class="custom-height"
              maxlength="6"
              :placeholder="$t('forgetPassword.codePlaceholder')"
              v-model.trim="code"
              @keyup.enter="resetPassword"
            />
            <ElButton
              class="custom-height code-button"
              :disabled="countdown > 0 || !account"
              :loading="sendingCode"
              @click="sendCode"
            >
              {{ countdown > 0 ? `${countdown}s` : $t('forgetPassword.sendCode') }}
            </ElButton>
          </div>

          <div style="margin-top: 15px">
            <ElInput
              class="custom-height"
              type="password"
              show-password
              :placeholder="$t('forgetPassword.newPasswordPlaceholder')"
              v-model="newPassword"
            />
          </div>

          <div style="margin-top: 15px">
            <ElInput
              class="custom-height"
              type="password"
              show-password
              :placeholder="$t('forgetPassword.confirmPasswordPlaceholder')"
              v-model="confirmPassword"
              @keyup.enter="resetPassword"
            />
          </div>

          <p v-if="deliveryHint" class="delivery-hint">
            {{ $t('forgetPassword.sentTo') }} {{ deliveryHint }}
          </p>

          <div style="margin-top: 15px">
            <ElButton
              class="w-full custom-height"
              type="primary"
              @click="resetPassword"
              :loading="loading"
              v-ripple
            >
              {{ $t('forgetPassword.submitBtnText') }}
            </ElButton>
          </div>

          <div style="margin-top: 15px">
            <ElButton class="w-full custom-height" plain @click="toLogin">
              {{ $t('forgetPassword.backBtnText') }}
            </ElButton>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import {
    resetAdminPasswordByCode,
    sendAdminPasswordResetCode
  } from '@/api/admin'
  import { useI18n } from 'vue-i18n'

  defineOptions({ name: 'ForgetPassword' })

  const router = useRouter()
  const { t } = useI18n()
  const account = ref('')
  const code = ref('')
  const newPassword = ref('')
  const confirmPassword = ref('')
  const sendingCode = ref(false)
  const loading = ref(false)
  const countdown = ref(0)
  const deliveryHint = ref('')
  let countdownTimer: ReturnType<typeof setInterval> | undefined

  const startCountdown = (seconds: number) => {
    countdown.value = Math.max(1, Math.min(seconds || 60, 60))
    if (countdownTimer) clearInterval(countdownTimer)
    countdownTimer = setInterval(() => {
      countdown.value -= 1
      if (countdown.value <= 0 && countdownTimer) {
        clearInterval(countdownTimer)
        countdownTimer = undefined
      }
    }, 1000)
  }

  const sendCode = async () => {
    if (!account.value) {
      ElMessage.warning(t('forgetPassword.accountRequired'))
      return
    }
    sendingCode.value = true
    try {
      const result = await sendAdminPasswordResetCode({ account: account.value })
      deliveryHint.value = result.delivery_hint || ''
      startCountdown(result.expires_in)
      ElMessage.success(result.message || t('forgetPassword.codeSent'))
    } finally {
      sendingCode.value = false
    }
  }

  const resetPassword = async () => {
    if (!account.value || !/^\d{6}$/.test(code.value)) {
      ElMessage.warning(t('forgetPassword.completeCode'))
      return
    }
    if (newPassword.value.length < 8 || newPassword.value.length > 72) {
      ElMessage.warning(t('forgetPassword.passwordRule'))
      return
    }
    if (newPassword.value !== confirmPassword.value) {
      ElMessage.warning(t('forgetPassword.passwordMismatch'))
      return
    }
    loading.value = true
    try {
      await resetAdminPasswordByCode({
        account: account.value,
        code: code.value,
        new_password: newPassword.value
      })
      ElMessage.success(t('forgetPassword.resetSuccess'))
      router.replace({ name: 'Login' })
    } finally {
      loading.value = false
    }
  }

  onBeforeUnmount(() => {
    if (countdownTimer) clearInterval(countdownTimer)
  })

  const toLogin = () => {
    router.push({ name: 'Login' })
  }
</script>

<style scoped>
  @import '../login/style.css';

  .code-row {
    display: flex;
    gap: 10px;
    margin-top: 15px;
  }

  .code-button {
    flex: 0 0 112px;
  }

  .delivery-hint {
    margin-top: 10px;
    color: var(--el-text-color-secondary);
    font-size: 13px;
  }
</style>
