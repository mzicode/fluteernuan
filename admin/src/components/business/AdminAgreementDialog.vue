<template>
  <ElDialog
    v-model="visible"
    class="admin-agreement-dialog"
    width="min(760px, calc(100vw - 32px))"
    :show-close="false"
    :close-on-click-modal="false"
    :close-on-press-escape="false"
    :destroy-on-close="false"
    append-to-body
    align-center
  >
    <template #header>
      <div class="agreement-header">
        <div class="agreement-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:shield-check-line" />
        </div>
        <div>
          <p class="agreement-eyebrow">登录前合规确认</p>
          <h2>{{ agreement?.title || '源码使用与合规责任协议' }}</h2>
          <p>请确认本次登录及后续操作符合适用法律法规和协议约定。</p>
        </div>
      </div>
    </template>

    <div v-loading="loading" class="agreement-content">
      <template v-if="agreement">
        <div class="agreement-notice">
          <ArtSvgIcon icon="ri:alert-line" />
          <span v-if="isDemoAdmin">
            本演示站仅供合法功能体验，严禁用于任何违法违规活动。系统将记录本次访问
            IP、确认时间及浏览器信息，用于安全审计和违法违规行为追溯。
          </span>
          <span v-else>禁止利用本系统实施违法犯罪、侵害他人权益或规避监管的活动。</span>
        </div>

        <div class="agreement-meta">
          <span>协议版本：{{ agreement.version }}</span>
          <span>内容摘要：{{ shortHash }}</span>
        </div>

        <div class="agreement-document" tabindex="0" aria-label="协议全文">
          <pre>{{ agreement.content }}</pre>
        </div>

        <ElCheckbox v-model="checked" :disabled="submitting" class="agreement-check">
          <template v-if="isDemoAdmin">
            我已知悉系统将记录本次访问 IP，并承诺不使用本演示站从事任何违法违规活动
          </template>
          <template v-else>
            我已完整阅读、理解并同意遵守以上协议，并承诺仅将系统用于合法合规用途
          </template>
        </ElCheckbox>
      </template>

      <ElResult
        v-else-if="!loading"
        icon="error"
        title="协议加载失败"
        sub-title="后台内容暂未开放，请重试加载协议。"
      >
        <template #extra>
          <ElButton :loading="loading" @click="loadAgreement">
            <ArtSvgIcon icon="ri:refresh-line" />
            重新加载
          </ElButton>
        </template>
      </ElResult>
    </div>

    <template #footer>
      <div class="agreement-actions">
        <ElButton :disabled="submitting" @click="logout">
          <ArtSvgIcon icon="ri:logout-box-r-line" />
          不同意并退出
        </ElButton>
        <ElButton
          type="primary"
          :loading="submitting"
          :disabled="loading || !agreement || !checked"
          @click="acceptAgreement"
        >
          <ArtSvgIcon icon="ri:shield-check-line" />
          同意并进入后台
        </ElButton>
      </div>
    </template>
  </ElDialog>
</template>

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue'
  import { ElMessage } from 'element-plus'
  import { acceptAdminAgreement, getAdminAgreement, type AdminAgreement } from '@/api/admin'
  import { useUserStore } from '@/store/modules/user'

  const emit = defineEmits<{
    resolved: []
  }>()

  const userStore = useUserStore()
  const agreement = ref<AdminAgreement | null>(null)
  const visible = ref(false)
  const loading = ref(true)
  const submitting = ref(false)
  const checked = ref(false)

  const shortHash = computed(() => {
    const hash = agreement.value?.content_hash || ''
    return hash.length > 18 ? `${hash.slice(0, 10)}...${hash.slice(-8)}` : hash
  })
  const isDemoAdmin = computed(() => userStore.info?.roles?.includes('R_DEMO') === true)

  async function loadAgreement() {
    loading.value = true
    agreement.value = null
    checked.value = false
    visible.value = true

    try {
      const current = await getAdminAgreement()
      agreement.value = current
      if (current.accepted) {
        visible.value = false
        emit('resolved')
      }
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '协议加载失败')
    } finally {
      loading.value = false
    }
  }

  async function acceptAgreement() {
    if (!agreement.value || !checked.value || submitting.value) return

    submitting.value = true
    try {
      await acceptAdminAgreement({
        version: agreement.value.version,
        content_hash: agreement.value.content_hash
      })
      visible.value = false
      window.dispatchEvent(new CustomEvent('admin-agreement-accepted'))
      ElMessage.success('协议确认成功')
      emit('resolved')
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '协议确认失败，请重试')
    } finally {
      submitting.value = false
    }
  }

  function logout() {
    userStore.logOut()
  }

  onMounted(loadAgreement)
</script>

<style lang="scss">
  .admin-agreement-dialog {
    display: flex;
    flex-direction: column;
    max-height: calc(100vh - 32px);
    overflow: hidden;
    border-radius: 8px;

    .el-dialog__header {
      padding: 24px 26px 18px;
      margin: 0;
      border-bottom: 1px solid var(--el-border-color-lighter);
    }

    .el-dialog__body {
      min-height: 0;
      padding: 20px 26px;
      overflow: auto;
    }

    .el-dialog__footer {
      padding: 16px 26px 20px;
      border-top: 1px solid var(--el-border-color-lighter);
    }
  }

  .agreement-header {
    display: flex;
    gap: 14px;
    align-items: flex-start;

    h2 {
      margin: 2px 0 5px;
      font-size: 20px;
      font-weight: 700;
      color: var(--el-text-color-primary);
      letter-spacing: 0;
    }

    p {
      margin: 0;
      font-size: 13px;
      line-height: 1.6;
      color: var(--el-text-color-secondary);
    }

    .agreement-eyebrow {
      font-size: 12px;
      font-weight: 700;
      color: var(--el-color-primary);
    }
  }

  .agreement-icon {
    display: grid;
    flex: 0 0 42px;
    width: 42px;
    height: 42px;
    font-size: 22px;
    color: var(--el-color-primary);
    background: var(--el-color-primary-light-9);
    border: 1px solid var(--el-color-primary-light-7);
    border-radius: 8px;
    place-items: center;
  }

  .agreement-content {
    min-height: 240px;
  }

  .agreement-notice {
    display: flex;
    gap: 9px;
    align-items: flex-start;
    padding: 11px 13px;
    margin-bottom: 14px;
    font-size: 13px;
    line-height: 1.6;
    color: var(--el-color-warning-dark-2);
    background: var(--el-color-warning-light-9);
    border: 1px solid var(--el-color-warning-light-7);
    border-radius: 6px;

    .art-svg-icon {
      flex: 0 0 auto;
      margin-top: 3px;
      font-size: 17px;
    }
  }

  .agreement-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 18px;
    margin-bottom: 10px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .agreement-document {
    max-height: min(36vh, 360px);
    overflow: auto;
    background: var(--el-fill-color-lighter);
    border: 1px solid var(--el-border-color);
    border-radius: 6px;

    &:focus-visible {
      outline: 2px solid var(--el-color-primary-light-5);
      outline-offset: 2px;
    }

    pre {
      padding: 16px 18px;
      margin: 0;
      font:
        13px/1.75 system-ui,
        'Microsoft YaHei',
        sans-serif;
      color: var(--el-text-color-regular);
      white-space: pre-wrap;
      word-break: break-word;
    }
  }

  .agreement-check {
    align-items: flex-start;
    height: auto;
    margin-top: 16px;
    white-space: normal;

    .el-checkbox__input {
      margin-top: 3px;
    }

    .el-checkbox__label {
      line-height: 1.6;
      white-space: normal;
    }
  }

  .agreement-actions {
    display: flex;
    gap: 10px;
    justify-content: flex-end;

    .el-button {
      gap: 6px;
      min-width: 132px;
    }
  }

  @media (width <= 560px) {
    .admin-agreement-dialog {
      .el-dialog__header,
      .el-dialog__body,
      .el-dialog__footer {
        padding-right: 18px;
        padding-left: 18px;
      }
    }

    .agreement-icon {
      display: none;
    }

    .agreement-actions {
      flex-direction: column-reverse;

      .el-button {
        width: 100%;
        min-height: 40px;
        margin: 0;
      }
    }
  }
</style>
