<!-- 控制台 - 真实数据仪表盘 -->
<template>
  <div class="console-page">
    <header class="console-head">
      <div>
        <h2>控制台首页</h2>
        <p>待办、业务趋势与系统状态</p>
      </div>
      <div class="head-actions">
        <div class="live-state">
          <span class="live-state__dot"></span>
          <span>后台同步 · {{ lastUpdatedText }}</span>
        </div>
        <ElButton :loading="refreshing" @click="refreshDashboard">
          <ArtSvgIcon icon="ri:refresh-line" />
          刷新
        </ElButton>
      </div>
    </header>

    <CardList
      :refresh-token="refreshToken"
      :pending-total="pendingSummary.total"
      :pending-modules="pendingSummary.modules"
      :health-abnormal="healthAbnormal"
    />

    <div class="dashboard-flow">
      <main class="dashboard-column dashboard-column--main">
        <div class="dashboard-module module-pending">
          <PendingTasksCard
            :refresh-token="refreshToken"
            @summary-change="pendingSummary = $event"
          />
        </div>
        <div class="dashboard-module module-trend">
          <UserGrowthChart :refresh-token="refreshToken" />
        </div>
        <div class="dashboard-module module-activity">
          <NewUserList :refresh-token="refreshToken" />
        </div>
      </main>

      <aside class="dashboard-column dashboard-column--side">
        <div class="dashboard-module module-health">
          <ServerStatusCard
            :refresh-token="refreshToken"
            @health-change="healthAbnormal = $event"
          />
        </div>
        <div class="dashboard-module module-online">
          <OnlineUserList :refresh-token="refreshToken" />
        </div>
        <div class="dashboard-module module-actions">
          <QuickActions />
        </div>
      </aside>
    </div>
  </div>
</template>

<script setup lang="ts">
  import CardList from './modules/card-list.vue'
  import ServerStatusCard from './modules/server-status-card.vue'
  import NewUserList from './modules/new-user-list.vue'
  import OnlineUserList from './modules/online-user-list.vue'
  import PendingTasksCard from './modules/pending-tasks-card.vue'
  import UserGrowthChart from './modules/user-growth-chart.vue'
  import QuickActions from './modules/quick-actions.vue'

  defineOptions({ name: 'Console' })

  const refreshToken = ref(0)
  const refreshing = ref(false)
  const lastUpdatedAt = ref<Date | null>(null)
  const pendingSummary = ref({ total: 0, modules: 0 })
  const healthAbnormal = ref(0)
  let refreshTimer: number | null = null

  const lastUpdatedText = computed(() => {
    if (!lastUpdatedAt.value) return '连接中'
    return lastUpdatedAt.value.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    })
  })

  const refreshDashboard = () => {
    if (refreshing.value) return
    refreshing.value = true
    refreshToken.value += 1
    lastUpdatedAt.value = new Date()
    window.setTimeout(() => {
      refreshing.value = false
    }, 650)
  }

  const refreshDashboardSilently = () => {
    refreshToken.value += 1
    lastUpdatedAt.value = new Date()
  }

  onMounted(() => {
    lastUpdatedAt.value = new Date()
    refreshTimer = window.setInterval(refreshDashboardSilently, 30000)
  })

  onUnmounted(() => {
    if (refreshTimer !== null) window.clearInterval(refreshTimer)
  })
</script>

<style scoped lang="scss">
  .console-page {
    padding-bottom: 8px;
  }

  .console-head {
    display: flex;
    gap: 16px;
    align-items: flex-end;
    justify-content: space-between;
    margin-bottom: 14px;
    animation: consoleSectionIn 420ms cubic-bezier(0.22, 1, 0.36, 1) both;

    h2 {
      margin: 0;
      font-size: 20px;
      font-weight: 700;
      color: var(--el-text-color-primary);
      letter-spacing: 0;
    }

    p {
      margin: 4px 0 0;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  .head-actions {
    display: flex;
    gap: 12px;
    align-items: center;

    :deep(.el-button) {
      gap: 5px;
      border-radius: 8px;
    }
  }

  .live-state {
    display: inline-flex;
    gap: 7px;
    align-items: center;
    padding-bottom: 2px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .live-state__dot {
    width: 7px;
    height: 7px;
    background: var(--el-color-success);
    border-radius: 50%;
    box-shadow: 0 0 0 0 color-mix(in srgb, var(--el-color-success) 30%, transparent);
    animation: livePulse 2.2s ease-out infinite;
  }

  .dashboard-flow {
    display: grid;
    grid-template-columns: minmax(0, 2fr) minmax(320px, 1fr);
    gap: 14px;
    align-items: start;
  }

  .dashboard-column {
    display: flex;
    flex-direction: column;
    gap: 14px;
    min-width: 0;
  }

  .dashboard-module {
    --module-accent: #3b82f6;
    --module-soft: rgb(59 130 246 / 5%);

    min-width: 0;
    animation: consoleSectionIn 460ms cubic-bezier(0.22, 1, 0.36, 1) both;

    :deep(.art-card) {
      margin-bottom: 0;
      overflow: hidden;
      background:
        radial-gradient(circle at 100% 0%, var(--module-soft), transparent 360px),
        linear-gradient(145deg, var(--module-soft), transparent 220px), var(--el-bg-color);
    }
  }

  .module-pending {
    --module-accent: #d97706;
    --module-soft: rgb(217 119 6 / 5%);
  }

  .module-trend {
    --module-accent: #3b82f6;
    --module-soft: rgb(59 130 246 / 5%);
  }

  .module-activity {
    --module-accent: #7c3aed;
    --module-soft: rgb(124 58 237 / 5%);
  }

  .module-health {
    --module-accent: #16a34a;
    --module-soft: rgb(22 163 74 / 5%);
  }

  .module-online {
    --module-accent: #0891b2;
    --module-soft: rgb(8 145 178 / 5%);
  }

  .module-actions {
    --module-accent: #64748b;
    --module-soft: rgb(100 116 139 / 5%);
  }

  .module-health {
    animation-delay: 80ms;
  }

  .module-trend,
  .module-online {
    animation-delay: 140ms;
  }

  .module-activity,
  .module-actions {
    animation-delay: 200ms;
  }

  @keyframes consoleSectionIn {
    from {
      opacity: 0;
      transform: translateY(8px);
    }

    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @keyframes livePulse {
    70%,
    100% {
      box-shadow: 0 0 0 7px transparent;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .console-head,
    .dashboard-module,
    .live-state__dot {
      animation: none;
    }
  }

  @media (width <= 1100px) {
    .dashboard-flow {
      grid-template-columns: minmax(0, 1.45fr) minmax(300px, 1fr);
    }
  }

  @media (width <= 900px) {
    .dashboard-flow {
      display: flex;
      flex-direction: column;
    }

    .dashboard-column {
      display: contents;
    }

    .module-pending {
      order: 1;
    }

    .module-health {
      order: 2;
    }

    .module-trend {
      order: 3;
    }

    .module-actions {
      order: 4;
    }

    .module-activity {
      order: 5;
    }

    .module-online {
      order: 6;
    }
  }

  @media (width <= 640px) {
    .console-head {
      flex-direction: column;
      align-items: flex-start;
    }

    .head-actions {
      justify-content: space-between;
      width: 100%;
    }
  }
</style>
