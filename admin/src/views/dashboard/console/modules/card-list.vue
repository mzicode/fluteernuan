<template>
  <div class="stat-board" :title="lastUpdatedText">
    <div class="stat-grid">
      <div
        v-for="(item, index) in dataList"
        :key="item.des"
        class="stat-item"
        :style="{ '--metric-delay': `${index * 70}ms` }"
      >
        <CircularMetric
          :label="item.des"
          :value="item.num"
          :icon="item.icon"
          :tone="item.tone"
          :progress="item.progress"
          :caption="item.subText"
          :change="item.change"
          :animate="true"
          :animation-trigger="metricAnimationTrigger"
        />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import CircularMetric from '@/components/core/cards/art-circular-metric/index.vue'
  import { getDashboardStats, getSystemSettings } from '@/api/admin'

  const props = withDefaults(
    defineProps<{
      refreshToken?: number
      pendingTotal?: number
      pendingModules?: number
      healthAbnormal?: number
    }>(),
    {
      refreshToken: 0,
      pendingTotal: 0,
      pendingModules: 0,
      healthAbnormal: 0
    }
  )

  interface CardDataItem {
    des: string
    icon: string
    num: number
    subText: string
    change?: string
    progress?: number | null
    tone: 'blue' | 'cyan' | 'violet' | 'orange' | 'rose' | 'green'
  }

  /**
   * 数据统计卡片
   */
  const dataList = reactive<CardDataItem[]>([
    {
      des: '总用户数',
      icon: 'ri:user-line',
      num: 0,
      subText: '今日新增',
      change: '+0',
      tone: 'blue'
    },
    {
      des: '今日新增',
      icon: 'ri:user-add-line',
      num: 0,
      subText: '新注册',
      change: '0',
      tone: 'cyan'
    },
    {
      des: '在线用户',
      icon: 'ri:user-follow-line',
      num: 0,
      subText: '在线率',
      change: '0%',
      progress: 0,
      tone: 'violet'
    },
    {
      des: '群/频道',
      icon: 'ri:group-line',
      num: 0,
      subText: '频道',
      change: '0',
      tone: 'orange'
    },
    {
      des: '待审核',
      icon: 'ri:inbox-archive-line',
      num: 0,
      subText: '涉及模块',
      change: '0',
      tone: 'rose'
    },
    {
      des: '系统状态',
      icon: 'ri:pulse-line',
      num: 0,
      subText: '异常项',
      change: '0',
      tone: 'green'
    }
  ])

  const lastUpdatedAt = ref<Date | null>(null)
  const pendingThreshold = ref(100)
  const metricAnimationTrigger = ref(0)
  const requesting = ref(false)
  const initialized = ref(false)
  let lastMetricSignature = ''

  const lastUpdatedText = computed(() => {
    if (!lastUpdatedAt.value) return '等待刷新'
    return `更新于 ${lastUpdatedAt.value.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit'
    })}`
  })

  const commitMetricAnimation = () => {
    const signature = dataList
      .map((item) => `${item.num}:${item.progress ?? ''}:${item.change || ''}:${item.tone}`)
      .join('|')
    if (signature !== lastMetricSignature) {
      lastMetricSignature = signature
      metricAnimationTrigger.value += 1
    }
  }

  const syncOperationalMetrics = () => {
    dataList[4].num = props.pendingTotal
    dataList[4].change = `${props.pendingModules}`
    dataList[4].progress = Math.min(
      100,
      Math.max(0, Math.round((props.pendingTotal / pendingThreshold.value) * 100))
    )

    dataList[5].num = props.healthAbnormal
    dataList[5].change = `${props.healthAbnormal}`
    dataList[5].tone = props.healthAbnormal > 0 ? 'rose' : 'green'
    dataList[5].progress = Math.round(
      ((7 - Math.min(7, Math.max(0, props.healthAbnormal))) / 7) * 100
    )
    commitMetricAnimation()
  }

  // 加载统计数据
  const loadStats = async () => {
    if (requesting.value) return
    requesting.value = true
    try {
      const [stats, settings] = await Promise.all([getDashboardStats(), getSystemSettings()])

      const configuredProgress = (key: string) => {
        const ratio = stats.progress?.[key]?.ratio
        return typeof ratio === 'number' && Number.isFinite(ratio) ? ratio : null
      }
      pendingThreshold.value = Math.max(1, settings.dashboard_pending_review_threshold ?? 100)
      const progressOf = (value: number, capacity?: number) =>
        capacity && capacity > 0
          ? Math.min(100, Math.max(0, Math.round((value / capacity) * 100)))
          : null

      // 更新数据
      dataList[0].num = stats.total_users
      dataList[0].change = stats.new_users_today > 0 ? `+${stats.new_users_today}` : '0'
      dataList[0].progress =
        configuredProgress('total_users') ??
        progressOf(stats.total_users, settings.dashboard_total_users_capacity)

      dataList[1].num = stats.new_users_today
      dataList[1].change = stats.new_users_today > 0 ? `+${stats.new_users_today}` : '0'
      dataList[1].progress =
        configuredProgress('new_users_today') ??
        progressOf(stats.new_users_today, settings.dashboard_new_users_daily_target)

      dataList[2].num = stats.online_users
      dataList[2].change =
        stats.total_users > 0
          ? `${Math.round((stats.online_users / stats.total_users) * 100)}%`
          : '0%'
      dataList[2].progress =
        stats.total_users > 0 ? Math.round((stats.online_users / stats.total_users) * 100) : 0

      dataList[3].num = stats.total_groups + stats.total_channels
      dataList[3].change = `${stats.total_channels}`
      dataList[3].progress = configuredProgress('groups_channels')

      dataList[3].progress ??= progressOf(
        stats.total_groups + stats.total_channels,
        settings.dashboard_groups_channels_capacity
      )

      syncOperationalMetrics()
      lastUpdatedAt.value = new Date()
    } catch (error) {
      console.error('加载统计数据失败:', error)
      if (!initialized.value) ElMessage.error('加载统计数据失败')
    } finally {
      initialized.value = true
      requesting.value = false
    }
  }

  watch(
    () => props.refreshToken,
    () => void loadStats(),
    { immediate: true }
  )
  watch(
    () => [props.pendingTotal, props.pendingModules, props.healthAbnormal],
    syncOperationalMetrics
  )
</script>

<style scoped lang="scss">
  .stat-board {
    margin-bottom: 14px;
  }

  .stat-grid {
    display: grid;
    grid-template-columns: repeat(6, minmax(0, 1fr));
    gap: 10px;
  }

  .stat-item {
    display: flex;
    min-width: 0;
    animation: statItemIn 520ms calc(120ms + var(--metric-delay, 0ms))
      cubic-bezier(0.22, 1, 0.36, 1) both;
    will-change: transform, opacity;
  }

  @keyframes statItemIn {
    from {
      opacity: 0;
      transform: translateY(10px);
    }

    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .stat-item {
      animation: none;
      will-change: auto;
    }
  }

  @media (width <= 1200px) {
    .stat-grid {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }

    .stat-item {
      min-height: 124px;
    }
  }

  @media (width <= 640px) {
    .stat-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 8px;
    }

    .stat-item {
      min-height: 112px;
    }
  }
</style>
