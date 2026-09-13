<template>
  <main class="login-page">
    <AuthTopBar />

    <section class="brand-stage" aria-labelledby="brand-title">
      <div class="brand-lockup">
        <ArtLogo class="brand-logo" size="54" />
        <div class="brand-name">
          <span>{{ $t('login.consoleLabel') }}</span>
          <strong>{{ displaySystemName }}</strong>
        </div>
      </div>

      <div class="brand-content">
        <div class="brand-sequence" aria-hidden="true">
          <span>01</span>
          <i></i>
          <span>customer IM</span>
        </div>
        <h1 id="brand-title">{{ $t('login.leftView.title') }}</h1>
        <p>{{ $t('login.leftView.subTitle') }}</p>

        <div class="brand-graphic" aria-hidden="true">
          <div class="graphic-index">IM</div>
          <div class="graphic-lines">
            <i></i>
            <i></i>
            <i></i>
          </div>
        </div>
      </div>

      <div class="brand-footer">
        <span class="secure-status">
          <i></i>
          {{ $t('login.securityNote') }}
        </span>
        <span>customer / ADMIN</span>
      </div>
    </section>

    <section class="login-pane" aria-labelledby="login-title">
      <div class="login-form-wrap">
        <header class="form-heading">
          <span class="access-label">{{ $t('login.accessLabel') }}</span>
          <h2 id="login-title">{{ $t('login.title') }}</h2>
          <p>{{ $t('login.subTitle') }}</p>
        </header>

        <ElForm
          ref="formRef"
          class="login-form"
          :model="formData"
          :rules="rules"
          :key="formKey"
          @keyup.enter="handleSubmit"
        >
          <ElFormItem prop="username" class="login-field">
            <div class="field-wrap">
              <label for="admin-username">{{ $t('login.field.username') }}</label>
              <ElInput
                id="admin-username"
                class="login-input"
                :placeholder="$t('login.placeholder.username')"
                v-model.trim="formData.username"
                autocomplete="username"
              >
                <template #prefix>
                  <ArtSvgIcon icon="ri:user-3-line" />
                </template>
              </ElInput>
            </div>
          </ElFormItem>

          <ElFormItem prop="password" class="login-field">
            <div class="field-wrap">
              <label for="admin-password">{{ $t('login.field.password') }}</label>
              <ElInput
                id="admin-password"
                class="login-input"
                :placeholder="$t('login.placeholder.password')"
                v-model.trim="formData.password"
                type="password"
                autocomplete="current-password"
                show-password
              >
                <template #prefix>
                  <ArtSvgIcon icon="ri:lock-2-line" />
                </template>
              </ElInput>
            </div>
          </ElFormItem>

          <ElFormItem v-if="captchaSupported !== false" prop="captchaCode" class="login-field">
            <div class="field-wrap">
              <label for="admin-captcha">{{ $t('login.field.captcha') }}</label>
              <div
                class="captcha-control"
                :class="{
                  'is-focused': captchaFocused,
                  'is-loading': captchaLoading
                }"
              >
                <ElInput
                  id="admin-captcha"
                  class="captcha-input"
                  :class="{ 'has-value': formData.captchaCode }"
                  :placeholder="$t('login.placeholder.captcha')"
                  :model-value="formData.captchaCode"
                  maxlength="4"
                  inputmode="text"
                  autocomplete="off"
                  @input="normalizeCaptchaCode"
                  @focus="captchaFocused = true"
                  @blur="captchaFocused = false"
                />
                <button
                  class="captcha-preview"
                  type="button"
                  :disabled="captchaLoading"
                  :aria-label="$t('login.captchaRefresh')"
                  :title="$t('login.captchaRefresh')"
                  @click="loadCaptcha"
                >
                  <span class="captcha-image-surface">
                    <img v-if="captchaImage" :src="captchaImage" :alt="$t('login.captchaAlt')" />
                    <ArtSvgIcon v-else icon="ri:shield-check-line" class="captcha-empty-icon" />
                  </span>
                  <span class="captcha-refresh-surface">
                    <ArtSvgIcon
                      icon="ri:refresh-line"
                      class="captcha-refresh-icon"
                      :class="{ 'is-loading': captchaLoading }"
                    />
                  </span>
                  <span class="sr-only">{{ $t('login.captchaRefresh') }}</span>
                </button>
              </div>
            </div>
          </ElFormItem>

          <ElFormItem v-if="captchaSupported !== false" prop="totpCode" class="login-field">
            <div class="field-wrap">
              <label for="admin-totp">{{ $t('login.field.totp') }}</label>
              <ElInput
                id="admin-totp"
                class="login-input"
                :placeholder="$t('login.placeholder.totp')"
                v-model.trim="formData.totpCode"
                maxlength="6"
                inputmode="numeric"
                autocomplete="one-time-code"
              >
                <template #prefix>
                  <ArtSvgIcon icon="ri:shield-keyhole-line" />
                </template>
              </ElInput>
            </div>
          </ElFormItem>

          <div class="form-options">
            <ElCheckbox v-model="formData.rememberPassword">
              {{ $t('login.rememberPwd') }}
            </ElCheckbox>
          </div>

          <ElButton
            class="login-submit"
            type="primary"
            @click="handleSubmit"
            :loading="loading"
            v-ripple
          >
            <span>{{ $t('login.btnText') }}</span>
            <ArtSvgIcon v-if="!loading" icon="ri:arrow-right-line" />
          </ElButton>
        </ElForm>

        <footer class="form-footer">
          <ArtSvgIcon icon="ri:shield-check-line" />
          <span>{{ $t('login.securityNote') }}</span>
        </footer>
      </div>
    </section>
  </main>
</template>

<script setup lang="ts">
  import { useUserStore } from '@/store/modules/user'
  import { useI18n } from 'vue-i18n'
  import { HttpError } from '@/utils/http/error'
  import { fetchAdminCaptcha, fetchLogin, fetchGetUserInfo } from '@/api/auth'
  import { getPublicAppSettings } from '@/api/admin'
  import { ElNotification, ElMessage, type FormInstance, type FormRules } from 'element-plus'
  import { useSettingStore } from '@/store/modules/setting'
  import {
    markPendingReminderAfterLogin,
    preparePendingReminderAudio
  } from '@/utils/pending-reminder'

  defineOptions({ name: 'Login' })

  const settingStore = useSettingStore()
  const { t, locale } = useI18n()
  const formKey = ref(0)

  watch(locale, () => {
    formKey.value++
  })

  const userStore = useUserStore()
  const router = useRouter()
  const route = useRoute()

  const systemName = computed(() => settingStore.systemName)
  const displaySystemName = computed(() => systemName.value || t('login.leftView.title'))
  const formRef = ref<FormInstance>()
  const legacyBackendCompat = import.meta.env.VITE_LEGACY_BACKEND_COMPAT === 'true'
  const captchaImage = ref('')
  const captchaLoading = ref(false)
  const captchaFocused = ref(false)
  const captchaSupported = ref<boolean | null>(legacyBackendCompat ? false : null)

  const formData = reactive({
    username: '',
    password: '',
    captchaId: '',
    captchaCode: '',
    totpCode: '',
    rememberPassword: true
  })

  const rules = computed<FormRules>(() => ({
    username: [{ required: true, message: t('login.placeholder.username'), trigger: 'blur' }],
    password: [{ required: true, message: t('login.placeholder.password'), trigger: 'blur' }],
    ...(captchaSupported.value === false
      ? {}
      : {
          captchaCode: [
            { required: true, message: t('login.placeholder.captcha'), trigger: 'blur' },
            { len: 4, message: t('login.placeholder.captcha'), trigger: 'blur' }
          ]
        })
  }))

  const loading = ref(false)

  const loadSystemName = async () => {
    try {
      const settings = await getPublicAppSettings()
      settingStore.setSystemName(settings.system_name || '')
    } catch {
      settingStore.setSystemName('')
    }
  }
  const loadCaptcha = async () => {
    if (captchaLoading.value) return
    captchaLoading.value = true
    formData.captchaId = ''
    formData.captchaCode = ''
    try {
      const captcha = await fetchAdminCaptcha()
      captchaSupported.value = true
      formData.captchaId = captcha.captcha_id
      captchaImage.value = captcha.captcha_image
      await nextTick()
      formRef.value?.clearValidate('captchaCode')
    } catch (error) {
      captchaImage.value = ''
      if (error instanceof HttpError && error.code === 404) {
        captchaSupported.value = false
        await nextTick()
        formRef.value?.clearValidate('captchaCode')
      } else {
        captchaSupported.value = true
      }
    } finally {
      captchaLoading.value = false
    }
  }
  const normalizeCaptchaCode = (value: string) => {
    formData.captchaCode = value
      .toUpperCase()
      .replace(/[^0-9A-Z]/g, '')
      .slice(0, 4)
  }
  const handleSubmit = async () => {
    if (!formRef.value) return
    preparePendingReminderAudio()

    let loginSucceeded = false
    let captchaSubmitted = false
    try {
      const valid = await formRef.value.validate()
      if (!valid) return
      if (captchaSupported.value !== false && !formData.captchaId) {
        ElMessage.warning(t('login.captchaUnavailable'))
        await loadCaptcha()
        return
      }

      loading.value = true
      const { username, password, captchaId, captchaCode } = formData

      captchaSubmitted = captchaSupported.value !== false
      const loginPayload = {
        username,
        password
      } as Parameters<typeof fetchLogin>[0]
      if (captchaSupported.value !== false) {
        loginPayload.captcha_id = captchaId
        loginPayload.captcha_code = captchaCode
        loginPayload.totp_code = formData.totpCode
      }
      const response = await fetchLogin(loginPayload)
      if (!response.token) {
        throw new Error('登录失败，未收到有效令牌')
      }
      userStore.setToken(response.token)
      const userInfo = await fetchGetUserInfo()
      userStore.setUserInfo(userInfo)
      userStore.setLoginStatus(true)
      markPendingReminderAfterLogin()
      loginSucceeded = true
      showLoginSuccessNotice()
      const redirect = route.query.redirect as string
      router.push(redirect || '/')
    } catch (error) {
      if (error instanceof HttpError) {
        ElMessage.error(error.message || '登录失败')
      } else {
        ElMessage.error('登录失败，请稍后重试')
        console.error('[Login] Unexpected error:', error)
      }
    } finally {
      loading.value = false
      if (captchaSubmitted && !loginSucceeded) {
        await loadCaptcha()
      }
    }
  }
  const showLoginSuccessNotice = () => {
    setTimeout(() => {
      ElNotification({
        title: t('login.success.title'),
        type: 'success',
        duration: 2500,
        zIndex: 10000,
        message: `${t('login.success.message')}, ${systemName.value}!`
      })
    }, 1000)
  }

  onMounted(() => {
    void Promise.all([loadSystemName(), legacyBackendCompat ? Promise.resolve() : loadCaptcha()])
  })
</script>

<style lang="scss" scoped>
  .login-page {
    --login-bg: #f5f6f8;
    --login-surface: #fff;
    --login-soft: #eef1f4;
    --login-text: #17191d;
    --login-muted: #727983;
    --login-border: #d9dee5;
    --login-brand: #121417;
    --login-brand-muted: #a6adb7;

    position: relative;
    display: grid;
    grid-template-columns: minmax(420px, 44%) minmax(0, 1fr);
    width: 100%;
    min-height: 100vh;
    min-height: 100dvh;
    overflow: hidden;
    color: var(--login-text);
    letter-spacing: 0;
    background: var(--login-bg);
  }

  .brand-stage {
    position: relative;
    display: flex;
    min-width: 0;
    min-height: 100vh;
    min-height: 100dvh;
    padding: 32px 48px;
    overflow: hidden;
    color: #fff;
    background: var(--login-brand);
  }

  .brand-stage::before,
  .brand-stage::after {
    position: absolute;
    pointer-events: none;
    content: '';
    background: rgb(255 255 255 / 8%);
  }

  .brand-stage::before {
    top: 0;
    bottom: 0;
    left: 72%;
    width: 1px;
  }

  .brand-stage::after {
    right: 0;
    bottom: 22%;
    left: 0;
    height: 1px;
  }

  .brand-lockup {
    position: absolute;
    top: 32px;
    left: 48px;
    z-index: 2;
    display: flex;
    gap: 14px;
    align-items: center;
  }

  .brand-logo {
    flex: 0 0 auto;
    overflow: hidden;
    border-radius: 8px;
    box-shadow: 0 12px 32px rgb(0 0 0 / 24%);
  }

  .brand-name {
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .brand-name span,
  .access-label {
    font-size: 11px;
    font-weight: 600;
    line-height: 1.4;
    color: var(--login-brand-muted);
    text-transform: uppercase;
    letter-spacing: 0;
  }

  .brand-name strong {
    max-width: 320px;
    overflow: hidden;
    font-size: 17px;
    font-weight: 600;
    line-height: 1.4;
    color: #fff;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .brand-content {
    position: relative;
    z-index: 1;
    width: min(100%, 560px);
    margin: auto 0;
  }

  .brand-sequence {
    display: grid;
    grid-template-columns: auto minmax(40px, 104px) auto;
    gap: 14px;
    align-items: center;
    width: min(100%, 270px);
    margin-bottom: 28px;
    font-size: 11px;
    font-weight: 600;
    color: #8f98a5;
  }

  .brand-sequence i {
    display: block;
    height: 1px;
    background: #3c424a;
  }

  .brand-content h1 {
    max-width: 520px;
    margin: 0;
    font-size: 48px;
    font-weight: 650;
    line-height: 1.18;
    color: #f7f8fa;
    letter-spacing: 0;
  }

  .brand-content > p {
    max-width: 480px;
    margin: 22px 0 0;
    font-size: 16px;
    line-height: 1.8;
    color: var(--login-brand-muted);
  }

  .brand-graphic {
    display: grid;
    grid-template-columns: 120px minmax(0, 1fr);
    gap: 24px;
    align-items: end;
    height: 124px;
    margin-top: 58px;
    border-top: 1px solid rgb(255 255 255 / 12%);
    border-bottom: 1px solid rgb(255 255 255 / 12%);
  }

  .graphic-index {
    align-self: center;
    font-size: 68px;
    font-weight: 700;
    line-height: 1;
    color: #2a7fff;
  }

  .graphic-lines {
    display: grid;
    gap: 15px;
    align-self: center;
  }

  .graphic-lines i {
    display: block;
    height: 2px;
    background: #3b4149;
  }

  .graphic-lines i:nth-child(1) {
    width: 100%;
  }

  .graphic-lines i:nth-child(2) {
    width: 72%;
    background: #2a7fff;
  }

  .graphic-lines i:nth-child(3) {
    width: 44%;
  }

  .brand-footer {
    position: absolute;
    right: 48px;
    bottom: 32px;
    left: 48px;
    z-index: 2;
    display: flex;
    gap: 24px;
    align-items: center;
    justify-content: space-between;
    font-size: 11px;
    font-weight: 600;
    color: #7f8792;
  }

  .secure-status {
    display: flex;
    gap: 9px;
    align-items: center;
  }

  .secure-status i {
    width: 7px;
    height: 7px;
    background: #38c793;
    border-radius: 50%;
    box-shadow: 0 0 0 4px rgb(56 199 147 / 12%);
  }

  .login-pane {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 0;
    min-height: 100vh;
    min-height: 100dvh;
    padding: 104px 64px 56px;
    background: var(--login-bg);
  }

  .login-form-wrap {
    width: min(100%, 430px);
  }

  .form-heading {
    margin-bottom: 38px;
  }

  .access-label {
    display: block;
    margin-bottom: 12px;
    color: var(--main-color);
  }

  .form-heading h2 {
    margin: 0;
    font-size: 36px;
    font-weight: 650;
    line-height: 1.2;
    color: var(--login-text);
    letter-spacing: 0;
  }

  .form-heading p {
    margin: 12px 0 0;
    font-size: 14px;
    line-height: 1.7;
    color: var(--login-muted);
  }

  .login-field {
    margin-bottom: 24px;
  }

  .field-wrap {
    width: 100%;
  }

  .field-wrap > label {
    display: block;
    margin-bottom: 9px;
    font-size: 13px;
    font-weight: 600;
    line-height: 1.4;
    color: var(--login-text);
  }

  :deep(.login-input .el-input__wrapper) {
    height: 52px !important;
    padding: 0 15px;
    background: var(--login-surface);
    border-radius: 8px;
    box-shadow: 0 0 0 1px var(--login-border) inset !important;
    transition:
      box-shadow 0.18s ease,
      background-color 0.18s ease;
  }

  :deep(.login-input .el-input__wrapper:hover) {
    box-shadow: 0 0 0 1px #aeb5be inset !important;
  }

  :deep(.login-input .el-input__wrapper.is-focus) {
    box-shadow:
      0 0 0 1px var(--main-color) inset,
      0 0 0 4px rgb(42 127 255 / 10%) !important;
  }

  :deep(.login-input .el-input__prefix) {
    margin-right: 9px;
    font-size: 18px;
    color: var(--login-muted);
  }

  :deep(.login-input .el-input__inner) {
    color: var(--login-text);
    letter-spacing: 0;
  }

  :deep(.login-input .el-input__inner::placeholder) {
    color: #9da4ad;
  }

  :deep(.el-form-item.is-error .login-input .el-input__wrapper) {
    box-shadow:
      0 0 0 1px var(--el-color-danger) inset,
      0 0 0 4px rgb(245 108 108 / 8%) !important;
  }

  :deep(.login-field .el-form-item__error) {
    padding-top: 5px;
    font-size: 12px;
  }

  .captcha-control {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 168px;
    width: 100%;
    height: 52px;
    overflow: hidden;
    background: var(--login-surface);
    border: 1px solid var(--login-border);
    border-radius: 8px;
    transition:
      border-color 0.18s ease,
      box-shadow 0.18s ease;
  }

  .captcha-control:hover {
    border-color: #aeb5be;
  }

  .captcha-control.is-focused {
    border-color: var(--main-color);
    box-shadow: 0 0 0 4px rgb(42 127 255 / 10%);
  }

  :deep(.el-form-item.is-error) .captcha-control {
    border-color: var(--el-color-danger);
    box-shadow: 0 0 0 4px rgb(245 108 108 / 8%);
  }

  :deep(.captcha-input .el-input__wrapper) {
    height: 50px !important;
    padding: 0 15px;
    background: transparent;
    border-radius: 0;
    box-shadow: none !important;
  }

  :deep(.captcha-input .el-input__inner) {
    color: var(--login-text);
    letter-spacing: 0;
  }

  :deep(.captcha-input.has-value .el-input__inner) {
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 15px;
    font-weight: 700;
  }

  .captcha-preview {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 40px;
    width: 168px;
    height: 50px;
    padding: 0;
    overflow: hidden;
    color: var(--login-muted);
    cursor: pointer;
    background: var(--login-soft);
    border: 0;
    border-left: 1px solid var(--login-border);
  }

  .captcha-preview:disabled {
    cursor: wait;
  }

  .captcha-image-surface,
  .captcha-refresh-surface {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 0;
  }

  .captcha-image-surface {
    padding: 4px 5px;
  }

  .captcha-image-surface img {
    width: 100%;
    height: 40px;
    object-fit: fill;
    border-radius: 4px;
    transition: opacity 0.18s ease;
  }

  .captcha-control.is-loading .captcha-image-surface img {
    opacity: 0.4;
  }

  .captcha-refresh-surface {
    border-left: 1px solid var(--login-border);
  }

  .captcha-empty-icon {
    font-size: 20px;
    color: var(--login-muted);
  }

  .captcha-refresh-icon {
    font-size: 18px;
    color: var(--login-muted);
    transition:
      color 0.18s ease,
      transform 0.18s ease;
  }

  .captcha-preview:hover .captcha-refresh-icon {
    color: var(--main-color);
    transform: rotate(28deg);
  }

  .captcha-refresh-icon.is-loading {
    animation: captcha-spin 0.8s linear infinite;
  }

  .form-options {
    display: flex;
    align-items: center;
    min-height: 24px;
    margin-top: 2px;
  }

  :deep(.form-options .el-checkbox__label) {
    font-size: 13px;
    color: var(--login-muted);
  }

  .login-submit {
    width: 100%;
    height: 52px;
    margin-top: 30px;
    font-size: 15px;
    font-weight: 600;
    border-radius: 8px;
  }

  .login-submit span {
    display: inline-flex;
    gap: 8px;
    align-items: center;
    letter-spacing: 0;
  }

  .login-submit :deep(.art-svg-icon) {
    font-size: 18px;
  }

  .form-footer {
    display: flex;
    gap: 7px;
    align-items: center;
    margin-top: 28px;
    font-size: 12px;
    color: #949ba4;
  }

  .form-footer :deep(.art-svg-icon) {
    font-size: 15px;
  }

  :global(.dark) .login-page {
    --login-bg: #191c20;
    --login-surface: #20242a;
    --login-soft: #252a31;
    --login-text: #f1f3f5;
    --login-muted: #9ba3ad;
    --login-border: #373d45;
    --login-brand: #0e1012;
  }

  :global(.dark) .captcha-image-surface {
    background: #eef3f8;
  }

  @media only screen and (width <= 1180px) {
    .login-page {
      display: block;
    }

    .brand-stage {
      display: none;
    }

    .login-pane {
      min-height: 100vh;
      min-height: 100dvh;
      padding: 110px 48px 48px;
    }
  }

  @media only screen and (width <= 640px) {
    .login-page {
      overflow: auto;
    }

    .login-pane {
      align-items: flex-start;
      padding: 112px 24px 36px;
    }

    .login-form-wrap {
      width: 100%;
    }

    .form-heading {
      margin-bottom: 32px;
    }

    .form-heading h2 {
      font-size: 30px;
    }

    .captcha-control {
      grid-template-columns: minmax(0, 1fr) 154px;
    }

    .captcha-preview {
      grid-template-columns: minmax(0, 1fr) 38px;
      width: 154px;
    }
  }

  @media only screen and (height <= 760px) and (width > 1180px) {
    .brand-stage {
      padding: 24px 40px;
    }

    .brand-lockup {
      top: 24px;
      left: 40px;
    }

    .brand-content h1 {
      font-size: 40px;
    }

    .brand-graphic {
      height: 92px;
      margin-top: 32px;
    }

    .graphic-index {
      font-size: 54px;
    }

    .brand-footer {
      right: 40px;
      bottom: 24px;
      left: 40px;
    }

    .login-pane {
      padding-top: 80px;
      padding-bottom: 32px;
    }

    .form-heading {
      margin-bottom: 24px;
    }

    .form-heading h2 {
      font-size: 32px;
    }

    .login-field {
      margin-bottom: 18px;
    }

    .login-submit {
      margin-top: 22px;
    }

    .form-footer {
      margin-top: 18px;
    }
  }

  @keyframes captcha-spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
