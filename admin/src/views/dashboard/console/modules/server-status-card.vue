<template>
  <section class="art-card health-panel" v-loading="loading">
    <header class="panel-head">
      <div>
        <div class="title-line">
          <h4>系统健康与告警</h4>
          <ElTag :type="overallType" size="small" effect="plain">{{ overallText }}</ElTag>
        </div>
        <p>{{ runtime?.server_time || '等待状态数据' }}</p>
      </div>
      <RouterLink to="/system/health" class="panel-link" aria-label="进入系统健康详情">
        运维中心
        <ArtSvgIcon icon="ri:arrow-right-s-line" />
      </RouterLink>
    </header>

    <div class="health-metrics">
      <div
        v-for="metric in healthMetrics"
        :key="metric.label"
        class="metric-cell"
        :class="metric.tone"
      >
        <span>{{ metric.label }}</span>
        <strong>{{ metric.value }}</strong>
        <small>{{ metric.caption }}</small>
      </div>
    </div>

    <div class="dependency-strip" aria-label="依赖服务状态">
      <div
        v-for="item in dependencyMetrics"
        :key="item.name"
        :title="item.error || `${item.name} 正常`"
      >
        <i :class="item.status"></i>
        <span>{{ item.name }}</span>
        <b>{{ item.status === 'ok' ? '正常' : '异常' }}</b>
      </div>
    </div>

    <div class="alert-head">
      <span>活动告警</span>
      <b :class="{ danger: firingAlerts.length > 0 }">{{ firingAlerts.length }}</b>
    </div>

    <TransitionGroup v-if="firingAlerts.length" name="alert-row" tag="div" class="alert-list">
      <RouterLink
        v-for="alert in firingAlerts.slice(0, 2)"
        :key="alert.id"
        to="/system/health"
        class="alert-row"
      >
        <i :class="alert.severity"></i>
        <div>
          <strong>{{ alert.summary || alert.alert_name }}</strong>
          <span
            >{{ alert.service || alert.instance || '系统服务' }} ·
            {{ formatAlertTime(alert.starts_at) }}</span
          >
        </div>
        <ArtSvgIcon icon="ri:arrow-right-s-line" />
      </RouterLink>
    </TransitionGroup>

    <div v-else class="healthy-state" :class="{ unavailable: alertsAvailable === false }">
      <span class="healthy-check">
        <ArtSvgIcon :icon="alertsAvailable === false ? 'ri:link-unlink-m' : 'ri:check-line'" />
      </span>
      <div>
        <strong>{{ alertsAvailable === false ? '告警源暂不可用' : '当前无活动告警' }}</strong>
        <span>{{ alertsAvailable === false ? '请进入运维中心检查连接' : '关键服务运行正常' }}</span>
      </div>
    </div>
  </section>
</template>

<script setup lang="ts">
  import {
    getObservabilityAlerts,
    getRuntimeStatus,
    type ObservabilityAlertEvent,
    type RuntimeStatus
  } from '@/api/admin'
  import { ElMessage } from 'element-plus'

  const props = withDefaults(defineProps<{ refreshToken?: number }>(), { refreshToken: 0 })
  const emit = defineEmits<{ healthChange: [count: number] }>()

  const runtime = ref<RuntimeStatus | null>(null)
  const firingAlerts = ref<ObservabilityAlertEvent[]>([])
  const alertsAvailable = ref<boolean | null>(null)
  const loading = ref(true)
  const requesting = ref(false)
  const initialized = ref(false)

  const dependencyMetrics = computed(() => [
    {
      name: 'MySQL',
      status: runtime.value?.mysql_status === 'ok' ? 'ok' : 'error',
      error: runtime.value?.mysql_error
    },
    {
      name: 'MongoDB',
      status: runtime.value?.mongo_status === 'ok' ? 'ok' : 'error',
      error: runtime.value?.mongo_error
    },
    {
      name: 'Redis',
      status: runtime.value?.redis_status === 'ok' ? 'ok' : 'error',
      error: runtime.value?.redis_error
    }
  ])

  const oldestQueue = computed(() => {
    const entries = Object.entries(runtime.value?.queue_oldest_task_age_seconds || {})
    if (!entries.length) return { name: '暂无积压', seconds: 0 }
    const [name, seconds] = entries.reduce((oldest, item) =>
      Number(item[1]) > Number(oldest[1]) ? item : oldest
    )
    return { name: formatQueueName(name), seconds: Number(seconds) || 0 }
  })

  const healthMetrics = computed(() => {
    const p95 = Number(runtime.value?.api_p95_latency_ms || 0)
    const errorRate = Number(runtime.value?.api_error_rate || 0)
    const queueSeconds = oldestQueue.value.seconds
    return [
      {
        label: 'API P95',
        value: runtime.value ? `${Math.round(p95)} ms` : '-',
        caption: `${runtime.value?.api_window_seconds || 300} 秒窗口`,
        tone: p95 >= 3000 ? 'critical' : p95 >= 1000 ? 'warning' : 'normal'
      },
      {
        label: '错误率',
        value: runtime.value ? `${errorRate.toFixed(2)}%` : '-',
        caption: `${runtime.value?.api_errors || 0} 次错误`,
        tone: errorRate >= 5 ? 'critical' : errorRate >= 1 ? 'warning' : 'normal'
      },
      {
        label: '最老队列',
        value: formatDuration(queueSeconds),
        caption: oldestQueue.value.name,
        tone: queueSeconds >= 3600 ? 'critical' : queueSeconds >= 900 ? 'warning' : 'normal'
      },
      {
        label: '活动告警',
        value: alertsAvailable.value === false ? '不可用' : `${firingAlerts.value.length} 条`,
        caption:
          alertsAvailable.value === false
            ? '检查告警连接'
            : firingAlerts.value.length
              ? '需要关注'
              : '暂无告警',
        tone:
          alertsAvailable.value === false
            ? 'warning'
            : firingAlerts.value.some((item) => item.severity === 'critical')
              ? 'critical'
              : firingAlerts.value.length
                ? 'warning'
                : 'normal'
      }
    ]
  })

  const abnormalCount = computed(() => {
    const dependencyErrors = dependencyMetrics.value.filter((item) => item.status !== 'ok').length
    const thresholdErrors = healthMetrics.value.filter((item) => item.tone !== 'normal').length
    return dependencyErrors + thresholdErrors
  })
  const overallType = computed(() => {
    if (!runtime.value) return 'info'
    return abnormalCount.value > 0 ? 'warning' : 'success'
  })
  const overallText = computed(() => {
    if (!runtime.value) return '加载中'
    return abnormalCount.value > 0 ? `${abnormalCount.value} 项异常` : '运行正常'
  })

  function formatQueueName(value: string) {
    const names: Record<string, string> = {
      message_send: '消息发送',
      message_sync: '消息同步',
      push_notify: '推送通知',
      delayed: '延迟队列',
      dead: '死信队列'
    }
    return names[value] || value.replaceAll('_', ' ')
  }

  function formatDuration(seconds: number) {
    if (!seconds) return '0 分钟'
    if (seconds < 60) return '< 1 分钟'
    if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟`
    if (seconds < 86400) return `${Math.floor(seconds / 3600)} 小时`
    return `${Math.floor(seconds / 86400)} 天`
  }

  function formatAlertTime(value?: string) {
    if (!value) return '-'
    const timestamp = new Date(value).getTime()
    if (!Number.isFinite(timestamp)) return '-'
    const minutes = Math.floor(Math.max(0, Date.now() - timestamp) / 60000)
    if (minutes < 1) return '刚刚'
    if (minutes < 60) return `${minutes} 分钟前`
    return `${Math.floor(minutes / 60)} 小时前`
  }

  const loadHealth = async () => {
    if (requesting.value) return
    requesting.value = true
    if (!initialized.value) loading.value = true
    const [runtimeResult, alertResult] = await Promise.allSettled([
      getRuntimeStatus(),
      getObservabilityAlerts()
    ])
    if (runtimeResult.status === 'fulfilled') runtime.value = runtimeResult.value
    if (alertResult.status === 'fulfilled') {
      alertsAvailable.value = alertResult.value.available
      firingAlerts.value = alertResult.value.firing || []
    } else {
      alertsAvailable.value = false
    }
    if (
      !initialized.value &&
      runtimeResult.status === 'rejected' &&
      alertResult.status === 'rejected'
    ) {
      ElMessage.error('加载系统健康状态失败')
    }
    initialized.value = true
    loading.value = false
    requesting.value = false
    emit('healthChange', abnormalCount.value)
  }

  watch(
    () => props.refreshToken,
    () => void loadHealth(),
    { immediate: true }
  )
</script>

<style scoped lang="scss">
  .health-panel {
    width: 100%;
    padding: 0;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .panel-head,
  .title-line,
  .panel-link,
  .dependency-strip > div,
  .alert-head,
  .healthy-state {
    display: flex;
    align-items: center;
  }

  .panel-head {
    gap: 12px;
    justify-content: space-between;
    min-height: 65px;
    padding: 12px 16px;
    border-bottom: 1px solid var(--el-border-color-lighter);

    h4 {
      margin: 0;
      font-size: 15px;
      font-weight: 650;
      color: var(--el-text-color-primary);
    }

    p {
      margin: 3px 0 0;
      font-size: 11px;
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-secondary);
    }
  }

  .title-line {
    gap: 8px;
  }

  .panel-link {
    flex: 0 0 auto;
    gap: 2px;
    font-size: 12px;
    font-weight: 600;
    color: var(--el-color-primary);
  }

  .health-metrics {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    border-bottom: 1px solid var(--el-border-color-lighter);
  }

  .metric-cell {
    position: relative;
    min-width: 0;
    padding: 12px 14px;
    border-right: 1px solid var(--el-border-color-extra-light);
    border-bottom: 1px solid var(--el-border-color-extra-light);

    &:nth-child(2n) {
      border-right: 0;
    }

    &:nth-child(n + 3) {
      border-bottom: 0;
    }

    &::before {
      position: absolute;
      top: 13px;
      right: 13px;
      width: 6px;
      height: 6px;
      content: '';
      background: var(--el-color-success);
      border-radius: 50%;
    }

    &.warning::before {
      background: var(--el-color-warning);
    }

    &.critical::before {
      background: var(--el-color-danger);
    }

    > span,
    small {
      display: block;
      overflow: hidden;
      font-size: 11px;
      color: var(--el-text-color-secondary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    strong {
      display: block;
      margin: 5px 0 3px;
      font-size: 18px;
      font-weight: 700;
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-primary);
    }

    &.warning strong {
      color: var(--el-color-warning-dark-2);
    }

    &.critical strong {
      color: var(--el-color-danger);
    }
  }

  .dependency-strip {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    padding: 10px 14px;
    border-bottom: 1px solid var(--el-border-color-lighter);

    > div {
      gap: 6px;
      min-width: 0;
      padding-right: 7px;
    }

    i {
      flex: 0 0 7px;
      width: 7px;
      height: 7px;
      background: var(--el-color-danger);
      border-radius: 50%;

      &.ok {
        background: var(--el-color-success);
      }
    }

    span,
    b {
      overflow: hidden;
      font-size: 11px;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    span {
      color: var(--el-text-color-primary);
    }

    b {
      font-weight: 500;
      color: var(--el-text-color-secondary);
    }
  }

  .alert-head {
    justify-content: space-between;
    min-height: 36px;
    padding: 0 14px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    background: var(--el-fill-color-extra-light);
    border-bottom: 1px solid var(--el-border-color-lighter);

    b {
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-primary);

      &.danger {
        color: var(--el-color-danger);
      }
    }
  }

  .alert-row {
    display: grid;
    grid-template-columns: 7px minmax(0, 1fr) 16px;
    gap: 9px;
    align-items: center;
    min-height: 56px;
    padding: 8px 14px;
    color: inherit;
    border-bottom: 1px solid var(--el-border-color-extra-light);
    transition: background-color 180ms ease;

    &:hover {
      background: var(--el-fill-color-extra-light);
    }

    > i {
      width: 7px;
      height: 7px;
      background: var(--el-color-warning);
      border-radius: 50%;

      &.critical {
        background: var(--el-color-danger);
      }
    }

    strong,
    span {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    strong {
      font-size: 12px;
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    span {
      margin-top: 3px;
      font-size: 10px;
      color: var(--el-text-color-secondary);
    }
  }

  .healthy-state {
    gap: 10px;
    min-height: 70px;
    padding: 10px 14px;

    .healthy-check {
      display: grid;
      flex: 0 0 30px;
      place-items: center;
      width: 30px;
      height: 30px;
      color: var(--el-color-success);
      background: color-mix(in srgb, var(--el-color-success) 10%, transparent);
      border-radius: 50%;
    }

    &.unavailable .healthy-check {
      color: var(--el-color-warning);
      background: color-mix(in srgb, var(--el-color-warning) 10%, transparent);
    }

    strong,
    span {
      display: block;
    }

    strong {
      font-size: 12px;
      color: var(--el-text-color-primary);
    }

    span {
      margin-top: 3px;
      font-size: 10px;
      color: var(--el-text-color-secondary);
    }
  }

  .alert-row-enter-active,
  .alert-row-leave-active,
  .alert-row-move {
    transition: all 260ms cubic-bezier(0.22, 1, 0.36, 1);
  }

  .alert-row-enter-from,
  .alert-row-leave-to {
    opacity: 0;
    transform: translateY(5px);
  }

  @media (prefers-reduced-motion: reduce) {
    .alert-row,
    .alert-row-enter-active,
    .alert-row-leave-active,
    .alert-row-move {
      transition: none;
    }
  }
</style>
