<template>
  <div class="agreement-page">
    <div class="agreement-card">
      <div class="eyebrow">合规确认</div>
      <h1>{{ agreement?.title || '源码使用与合规责任协议' }}</h1>
      <p class="meta" v-if="agreement">版本 {{ agreement.version }} · 内容摘要 {{ agreement.content_hash }}</p>
      <div v-loading="loading" class="agreement-body">
        <pre v-if="agreement">{{ agreement.content }}</pre>
        <el-empty v-else description="协议加载失败，请刷新页面重试" />
      </div>
      <el-checkbox v-model="checked" :disabled="loading || submitting">
        我已阅读、理解并同意遵守以上协议
      </el-checkbox>
      <div class="actions">
        <el-button type="primary" :loading="submitting" :disabled="!checked || !agreement" @click="submit">
          同意并进入客服后台
        </el-button>
        <el-button :disabled="submitting" @click="logout">不同意并退出</el-button>
      </div>
      <p class="hint">未确认协议前，服务端会阻止客服后台业务接口。</p>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { onMounted, ref } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { ElMessage } from 'element-plus'
  import { acceptServiceAdminAgreement, fetchServiceAdminAgreement, type ServiceAdminAgreement } from '@/service/api/service-admin'
  import { useSessionStore } from '@/stores/session'

  const router = useRouter()
  const route = useRoute()
  const session = useSessionStore()
  const agreement = ref<ServiceAdminAgreement | null>(null)
  const checked = ref(false)
  const loading = ref(true)
  const submitting = ref(false)

  async function load() {
    loading.value = true
    try {
      agreement.value = await fetchServiceAdminAgreement()
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '协议加载失败')
    } finally {
      loading.value = false
    }
  }

  async function submit() {
    if (!agreement.value || !checked.value) return
    submitting.value = true
    try {
      await acceptServiceAdminAgreement({ version: agreement.value.version, content_hash: agreement.value.content_hash })
      window.dispatchEvent(new CustomEvent('service-admin-agreement-accepted'))
      const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/workbench'
      await router.replace(redirect)
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '协议确认失败')
    } finally {
      submitting.value = false
    }
  }

  function logout() {
    void session.logout()
  }

  onMounted(load)
</script>

<style scoped>
  .agreement-page { min-height: 100vh; display: grid; place-items: center; padding: 32px 20px; background: #f5f7fa; }
  .agreement-card { width: min(900px, 100%); padding: 34px; background: #fff; border: 1px solid #dce2e8; border-radius: 8px; box-shadow: 0 12px 36px rgba(23, 33, 43, .12); }
  .eyebrow { color: #0f766e; font-size: 12px; font-weight: 800; letter-spacing: .08em; }
  h1 { margin: 8px 0; font-size: 28px; color: #17212b; }
  .meta, .hint { color: #66717d; font-size: 13px; }
  .agreement-body { min-height: 260px; margin: 20px 0; }
  pre { max-height: 52vh; overflow: auto; margin: 0; padding: 18px; white-space: pre-wrap; background: #f8fafb; border: 1px solid #e2e8f0; border-radius: 6px; color: #263241; font: 14px/1.8 system-ui, 'Microsoft YaHei', sans-serif; }
  .actions { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 20px; }
</style>
