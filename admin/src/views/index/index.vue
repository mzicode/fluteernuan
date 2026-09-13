<!-- 布局容器 -->
<template>
  <div class="app-layout">
    <aside id="app-sidebar">
      <ArtSidebarMenu />
    </aside>

    <main id="app-main">
      <div id="app-header">
        <ArtHeaderBar />
      </div>
      <div id="app-content">
        <ArtPageContent v-if="agreementResolved" />
        <div v-else class="agreement-loading-shell" aria-hidden="true">
          <div class="agreement-loading-shell__title"></div>
          <div class="agreement-loading-shell__grid">
            <span v-for="item in 6" :key="item"></span>
          </div>
        </div>
      </div>
    </main>

    <div id="app-global">
      <ArtGlobalComponent v-if="agreementResolved" />
      <AdminAgreementDialog @resolved="agreementResolved = true" />
    </div>
  </div>
</template>

<script setup lang="ts">
  import { ref } from 'vue'
  import AdminAgreementDialog from '@/components/business/AdminAgreementDialog.vue'

  defineOptions({ name: 'AppLayout' })

  const agreementResolved = ref(false)
</script>

<style lang="scss" scoped>
  @use './style';

  .agreement-loading-shell {
    padding: 24px;
  }

  .agreement-loading-shell__title,
  .agreement-loading-shell__grid span {
    display: block;
    background: var(--el-fill-color-light);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 6px;
  }

  .agreement-loading-shell__title {
    width: 180px;
    height: 28px;
    margin-bottom: 18px;
  }

  .agreement-loading-shell__grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 14px;

    span {
      min-height: 128px;
    }
  }

  @media (width <= 900px) {
    .agreement-loading-shell__grid {
      grid-template-columns: 1fr;
    }
  }
</style>
