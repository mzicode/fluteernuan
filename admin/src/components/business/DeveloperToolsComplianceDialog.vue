<template>
  <ElDialog
    v-model="visible"
    class="devtools-compliance-dialog"
    width="min(720px, calc(100vw - 32px))"
    :show-close="false"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :destroy-on-close="false"
    append-to-body
    align-center
  >
    <template #header>
      <div class="devtools-warning-header">
        <div class="devtools-warning-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:alarm-warning-line" />
        </div>
        <div>
          <p>SECURITY &amp; COMPLIANCE WARNING</p>
          <h2>开发者工具使用与安全合规警示</h2>
          <span>检测到当前页面可能正在打开浏览器开发者工具。</span>
        </div>
      </div>
    </template>

    <div class="devtools-warning-body">
      <div class="devtools-danger-notice">
        <ArtSvgIcon icon="ri:error-warning-fill" />
        <strong>开发者工具仅限获得明确授权的调试、运维与安全审计使用。</strong>
      </div>

      <p class="devtools-intro">
        未经授权访问、测试、修改或获取本系统及其数据，可能违反服务协议和适用法律法规。
        对后台接口的访问和操作可能依据安全策略记录审计日志。
      </p>

      <section class="devtools-terms" aria-label="禁止行为">
        <h3>严禁实施以下行为</h3>
        <ol>
          <li>绕过登录、验证码、权限控制、访问频率限制或其他安全防护措施。</li>
          <li>扫描、探测、攻击非本人所有或未获得书面授权的账号、接口、主机与网络。</li>
          <li>窃取、复制、传播或交易个人信息、业务数据、访问令牌、密码、密钥及其他敏感信息。</li>
          <li>篡改请求或数据、注入恶意代码、破坏服务可用性，或协助任何违法违规活动。</li>
          <li>超出授权范围开展安全测试；发现风险后应立即停止操作并通过授权渠道报告。</li>
        </ol>
      </section>

      <ElCheckbox v-model="confirmed" class="devtools-confirmation">
        我已阅读并理解以上警示，确认已获得明确授权，并承诺仅在授权范围内合法合规地使用开发者工具
      </ElCheckbox>
    </div>

    <template #footer>
      <div class="devtools-warning-actions">
        <ElButton @click="exitAdmin">
          <ArtSvgIcon icon="ri:logout-box-r-line" />
          退出后台
        </ElButton>
        <ElButton type="danger" :disabled="!confirmed" @click="acknowledge">
          <ArtSvgIcon icon="ri:shield-check-line" />
          已知悉，仅用于授权调试
        </ElButton>
      </div>
    </template>
  </ElDialog>
</template>

<script setup lang="ts">
  import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
  import { storeToRefs } from 'pinia'
  import { useUserStore } from '@/store/modules/user'

  const userStore = useUserStore()
  const { isLogin } = storeToRefs(userStore)
  const visible = ref(false)
  const confirmed = ref(false)

  let acknowledgedForCurrentOpening = false
  let suspectedSamples = 0
  let clearedSamples = 0
  let detectorTimer: number | undefined

  function showWarning() {
    if (!isLogin.value || visible.value || acknowledgedForCurrentOpening) return
    confirmed.value = false
    visible.value = true
  }

  function isDeveloperToolsShortcut(event: KeyboardEvent) {
    if (event.key === 'F12') return true
    if (!event.ctrlKey || !event.shiftKey) return false
    return ['I', 'J', 'C'].includes(event.key.toUpperCase())
  }

  function onKeydown(event: KeyboardEvent) {
    if (!isDeveloperToolsShortcut(event) || !isLogin.value) return
    acknowledgedForCurrentOpening = false
    showWarning()
  }

  function isLikelyDeveloperToolsOpen() {
    if (!window.matchMedia('(pointer: fine)').matches || window.innerWidth < 700) return false
    if (window.outerWidth <= 0 || window.outerHeight <= 0) return false
    const widthDifference = Math.max(0, window.outerWidth - window.innerWidth)
    const heightDifference = Math.max(0, window.outerHeight - window.innerHeight)
    return widthDifference > 170 || heightDifference > 170
  }

  function sampleDeveloperToolsState() {
    if (!isLogin.value) return
    if (isLikelyDeveloperToolsOpen()) {
      clearedSamples = 0
      suspectedSamples += 1
      if (suspectedSamples >= 2) showWarning()
      return
    }

    suspectedSamples = 0
    clearedSamples += 1
    if (clearedSamples >= 3) acknowledgedForCurrentOpening = false
  }

  function acknowledge() {
    if (!confirmed.value) return
    acknowledgedForCurrentOpening = true
    visible.value = false
    console.warn('开发者工具合规警示已确认：仅允许在获得明确授权的范围内进行合法调试。')
  }

  function exitAdmin() {
    visible.value = false
    userStore.logOut()
  }

  watch(isLogin, (loggedIn) => {
    if (!loggedIn) {
      visible.value = false
      confirmed.value = false
      acknowledgedForCurrentOpening = false
      suspectedSamples = 0
      clearedSamples = 0
    }
  })

  onMounted(() => {
    window.addEventListener('keydown', onKeydown, true)
    detectorTimer = window.setInterval(sampleDeveloperToolsState, 1000)
  })

  onBeforeUnmount(() => {
    window.removeEventListener('keydown', onKeydown, true)
    if (detectorTimer !== undefined) window.clearInterval(detectorTimer)
  })
</script>

<style lang="scss">
  .devtools-compliance-dialog {
    overflow: hidden;
    border: 1px solid color-mix(in srgb, var(--el-color-danger) 34%, var(--el-border-color));
    border-radius: 10px;
    box-shadow: 0 28px 90px rgb(0 0 0 / 42%);

    .el-dialog__header {
      padding: 22px 24px 18px;
      margin: 0;
      background: linear-gradient(135deg, var(--el-color-danger-light-9), var(--el-bg-color));
      border-bottom: 1px solid var(--el-border-color-lighter);
    }

    .el-dialog__body {
      padding: 22px 24px;
    }

    .el-dialog__footer {
      padding: 16px 24px 20px;
      border-top: 1px solid var(--el-border-color-lighter);
    }
  }

  .devtools-warning-header {
    display: flex;
    gap: 14px;
    align-items: flex-start;

    p {
      margin: 0 0 3px;
      font-size: 11px;
      font-weight: 800;
      color: var(--el-color-danger);
      letter-spacing: 0.12em;
    }

    h2 {
      margin: 0 0 5px;
      font-size: 21px;
      font-weight: 750;
      color: var(--el-text-color-primary);
    }

    span {
      font-size: 13px;
      color: var(--el-text-color-secondary);
    }
  }

  .devtools-warning-icon {
    display: grid;
    flex: 0 0 44px;
    width: 44px;
    height: 44px;
    font-size: 24px;
    color: var(--el-color-danger);
    background: var(--el-color-danger-light-8);
    border: 1px solid var(--el-color-danger-light-6);
    border-radius: 9px;
    place-items: center;
  }

  .devtools-danger-notice {
    display: flex;
    gap: 9px;
    align-items: center;
    padding: 11px 13px;
    color: var(--el-color-danger-dark-2);
    background: var(--el-color-danger-light-9);
    border: 1px solid var(--el-color-danger-light-7);
    border-radius: 7px;

    .art-svg-icon {
      flex: 0 0 auto;
      font-size: 18px;
    }
  }

  .devtools-intro {
    margin: 15px 2px;
    font-size: 13px;
    line-height: 1.75;
    color: var(--el-text-color-regular);
  }

  .devtools-terms {
    padding: 15px 17px;
    background: var(--el-fill-color-lighter);
    border: 1px solid var(--el-border-color);
    border-radius: 7px;

    h3 {
      margin: 0 0 8px;
      font-size: 14px;
      color: var(--el-text-color-primary);
    }

    ol {
      padding-left: 22px;
      margin: 0;
      font-size: 13px;
      line-height: 1.8;
      color: var(--el-text-color-regular);
    }
  }

  .devtools-confirmation {
    align-items: flex-start;
    height: auto;
    margin-top: 16px;
    white-space: normal;

    .el-checkbox__input {
      margin-top: 3px;
    }

    .el-checkbox__label {
      line-height: 1.65;
      white-space: normal;
    }
  }

  .devtools-warning-actions {
    display: flex;
    gap: 10px;
    justify-content: flex-end;

    .el-button {
      gap: 6px;
      min-width: 132px;
    }
  }

  @media (width <= 560px) {
    .devtools-compliance-dialog {
      .el-dialog__header,
      .el-dialog__body,
      .el-dialog__footer {
        padding-right: 18px;
        padding-left: 18px;
      }
    }

    .devtools-warning-icon {
      display: none;
    }

    .devtools-warning-actions {
      flex-direction: column-reverse;

      .el-button {
        width: 100%;
        min-height: 40px;
        margin: 0;
      }
    }
  }
</style>
