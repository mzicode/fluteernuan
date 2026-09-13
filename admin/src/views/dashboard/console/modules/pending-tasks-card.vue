<template>
  <section class="art-card pending-card" v-loading="loading">
    <header class="panel-head">
      <div>
        <div class="title-line">
          <h4>待办工作台</h4>
          <span class="pending-total" :class="queueState">共 {{ totalPending }} 项</span>
        </div>
        <p>{{ activeModules }} 个模块有待处理内容</p>
      </div>
      <div class="head-actions">
        <ElButton
          text
          circle
          :loading="loading"
          aria-label="刷新待办"
          title="刷新待办"
          @click="loadTasks(true)"
        >
          <ArtSvgIcon icon="ri:refresh-line" />
        </ElButton>
      </div>
    </header>

    <div class="task-table">
      <div class="task-row task-row--head">
        <span>事项</span>
        <span>最新记录</span>
        <span>最老等待</span>
        <span class="count-head">待办</span>
        <span></span>
      </div>

      <div
        v-for="(item, index) in orderedTasks"
        :key="item.key"
        class="task-row task-row--data"
        :class="itemState(item)"
        :style="{ '--row-delay': `${index * 55}ms` }"
      >
        <div class="task-name">
          <span class="task-icon" :class="item.key">
            <ArtSvgIcon :icon="item.icon" />
          </span>
          <span>{{ item.title }}</span>
        </div>
        <div class="task-desc" :title="item.latest">{{ item.latest || '暂无记录' }}</div>
        <div class="task-time">{{ formatWaitingTime(item.oldestCreatedAt) }}</div>
        <div class="task-count">
          <ArtCountTo v-if="item.count > 0" :target="item.count" :duration="620" />
          <span v-else>0</span>
        </div>
        <RouterLink :to="item.path" class="task-action" :aria-label="`进入${item.title}`">
          <span>进入处理</span>
          <ArtSvgIcon icon="ri:arrow-right-s-line" />
        </RouterLink>
      </div>
    </div>

    <footer class="pending-foot">
      <span class="threshold-track" aria-hidden="true">
        <i :style="{ width: `${pendingRatio}%` }"></i>
      </span>
      <span>待办阈值使用率 {{ pendingRatio }}%</span>
      <RouterLink to="/system/settings">阈值设置</RouterLink>
    </footer>
  </section>
</template>

<script setup lang="ts">
  import {
    getMomentList,
    getRechargeOrders,
    getSystemSettings,
    getWithdrawList,
    getWithdrawStats
  } from '@/api/admin'
  import { getReportList, getReportStats } from '@/api/report'
  import { ElNotification } from 'element-plus'
  import {
    consumePendingReminderAfterLogin,
    hasPendingReminderAfterLogin,
    speakPendingReminder
  } from '@/utils/pending-reminder'

  const props = withDefaults(defineProps<{ refreshToken?: number }>(), { refreshToken: 0 })
  const emit = defineEmits<{
    summaryChange: [summary: { total: number; modules: number }]
  }>()

  interface PendingTask {
    key: 'reports' | 'withdraw' | 'recharge' | 'moments'
    title: string
    count: number
    latest: string
    oldestCreatedAt: string
    path: string
    icon: string
  }

  const loading = ref(true)
  const requesting = ref(false)
  const initialized = ref(false)
  const threshold = ref(100)
  const router = useRouter()
  const tasks = reactive<PendingTask[]>([
    {
      key: 'reports',
      title: '举报处理',
      count: 0,
      latest: '',
      oldestCreatedAt: '',
      path: '/report/list',
      icon: 'ri:alarm-warning-line'
    },
    {
      key: 'withdraw',
      title: '提现审核',
      count: 0,
      latest: '',
      oldestCreatedAt: '',
      path: '/wallet/withdraw',
      icon: 'ri:money-cny-box-line'
    },
    {
      key: 'recharge',
      title: '充值审核',
      count: 0,
      latest: '',
      oldestCreatedAt: '',
      path: '/wallet/recharge',
      icon: 'ri:bank-card-line'
    },
    {
      key: 'moments',
      title: '动态审核',
      count: 0,
      latest: '',
      oldestCreatedAt: '',
      path: '/moment/list',
      icon: 'ri:compass-3-line'
    }
  ])

  const totalPending = computed(() => tasks.reduce((sum, item) => sum + item.count, 0))
  const activeModules = computed(() => tasks.filter((item) => item.count > 0).length)
  const pendingRatio = computed(() =>
    Math.min(100, Math.round((totalPending.value / Math.max(1, threshold.value)) * 100))
  )
  const queueState = computed(() => {
    if (pendingRatio.value >= 100) return 'critical'
    if (pendingRatio.value >= 70) return 'warning'
    return 'quiet'
  })
  const orderedTasks = computed(() =>
    [...tasks].sort((left, right) => Number(right.count > 0) - Number(left.count > 0))
  )

  const setTask = (
    key: PendingTask['key'],
    count: number,
    latest: string,
    oldestCreatedAt?: string
  ) => {
    const item = tasks.find((task) => task.key === key)
    if (!item) return
    item.count = count
    item.latest = latest
    item.oldestCreatedAt = oldestCreatedAt || ''
  }

  const compactText = (value?: string | null) => {
    const text = (value || '').trim()
    if (!text) return ''
    return text.length > 28 ? `${text.slice(0, 28)}...` : text
  }

  const loadReports = async () => {
    const [stats, list] = await Promise.all([
      getReportStats(),
      getReportList({ page: 1, page_size: 100, status: '0' })
    ])
    const latest = list.list[0]
    const oldest = list.list.at(-1)
    setTask(
      'reports',
      stats.overview.pending || 0,
      latest ? `${latest.reason_text || '举报'} · ${latest.target_name || latest.target_id}` : '',
      oldest?.created_at
    )
  }

  const loadWithdraw = async () => {
    const [stats, list] = await Promise.all([
      getWithdrawStats(),
      getWithdrawList({ page: 1, page_size: 100, status: 'pending' })
    ])
    const latest = list.list[0]
    const oldest = list.list.at(-1)
    setTask(
      'withdraw',
      stats.pending_count || 0,
      latest ? `${latest.user_name || latest.username || latest.user_id} · ¥${latest.amount}` : '',
      oldest?.created_at
    )
  }

  const loadRecharge = async () => {
    const result = await getRechargeOrders({ page: 1, page_size: 100, status: 'pending' })
    const latest = result.list[0]
    const oldest = result.list.at(-1)
    setTask(
      'recharge',
      result.total || 0,
      latest ? `${latest.user_name || latest.username || latest.user_id} · ¥${latest.amount}` : '',
      oldest?.created_at
    )
  }

  const loadMoments = async () => {
    const result = await getMomentList({ page: 1, page_size: 100, only_pending: true })
    const latest = result.list[0]
    const oldest = result.list.at(-1)
    setTask(
      'moments',
      result.total || 0,
      latest ? `${latest.user_name || '用户'} · ${compactText(latest.content)}` : '',
      oldest?.created_at
    )
  }

  const loadTasks = async (showLoading = false) => {
    if (requesting.value) return
    requesting.value = true
    if (showLoading || !initialized.value) loading.value = true
    try {
      const settingsPromise = getSystemSettings().then((settings) => {
        threshold.value = Math.max(1, settings.dashboard_pending_review_threshold ?? 100)
      })
      const results = await Promise.allSettled([
        settingsPromise,
        loadReports(),
        loadWithdraw(),
        loadRecharge(),
        loadMoments()
      ])
      emit('summaryChange', { total: totalPending.value, modules: activeModules.value })
      const taskDataLoaded = results.slice(1).some((result) => result.status === 'fulfilled')
      if (taskDataLoaded) notifyPendingAfterLogin()
    } finally {
      initialized.value = true
      loading.value = false
      requesting.value = false
    }
  }

  const notifyPendingAfterLogin = () => {
    if (!hasPendingReminderAfterLogin()) return
    consumePendingReminderAfterLogin()
    if (totalPending.value <= 0) return

    const activeTasks = orderedTasks.value.filter((item) => item.count > 0)
    const taskSummary = activeTasks.map((item) => `${item.title}${item.count}项`).join('，')
    const voiceMessage = `您有${totalPending.value}项待处理事项。${taskSummary}。请及时处理。`
    const targetPath = activeTasks[0]?.path || '/'

    speakPendingReminder(voiceMessage)
    const notification = ElNotification({
      title: `待办提醒 · ${totalPending.value} 项`,
      message: `${taskSummary}。点击进入处理。`,
      type: queueState.value === 'critical' ? 'error' : 'warning',
      position: 'bottom-right',
      duration: 12000,
      showClose: true,
      customClass: 'pending-login-notification',
      onClick: () => {
        notification.close()
        void router.push(targetPath)
      }
    })
  }

  const itemState = (item: PendingTask) => {
    if (item.count <= 0) return 'quiet'
    const ratio = item.count / Math.max(1, threshold.value)
    if (ratio >= 1) return 'critical'
    if (ratio >= 0.7) return 'warning'
    return 'normal'
  }

  const formatWaitingTime = (value?: string) => {
    if (!value) return '-'
    const timestamp = new Date(value).getTime()
    if (!Number.isFinite(timestamp)) return '-'
    const diff = Math.max(0, Date.now() - timestamp)
    const minutes = Math.floor(diff / 60000)
    const hours = Math.floor(diff / 3600000)
    const days = Math.floor(diff / 86400000)
    if (minutes < 1) return '< 1 分钟'
    if (minutes < 60) return `${minutes} 分钟`
    if (hours < 24) return `${hours} 小时`
    return `${days} 天`
  }

  watch(
    () => props.refreshToken,
    () => void loadTasks(false),
    { immediate: true }
  )
</script>

<style scoped lang="scss">
  .pending-card {
    padding: 0;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .panel-head,
  .head-actions,
  .title-line,
  .pending-foot {
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
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  .title-line,
  .head-actions {
    gap: 9px;
  }

  .pending-total {
    min-width: 26px;
    padding: 2px 7px;
    font-size: 12px;
    font-weight: 700;
    line-height: 18px;
    color: var(--el-text-color-primary);
    text-align: center;
    background: var(--el-fill-color-light);
    border: 1px solid var(--el-border-color-light);
    border-radius: 999px;

    &.warning {
      color: var(--el-color-warning-dark-2);
      background: color-mix(in srgb, var(--el-color-warning) 9%, transparent);
      border-color: color-mix(in srgb, var(--el-color-warning) 35%, transparent);
    }

    &.critical {
      color: var(--el-color-danger);
      background: color-mix(in srgb, var(--el-color-danger) 8%, transparent);
      border-color: color-mix(in srgb, var(--el-color-danger) 35%, transparent);
    }
  }

  .task-table {
    padding: 0 16px;
  }

  .task-row {
    display: grid;
    grid-template-columns: minmax(130px, 0.8fr) minmax(220px, 1.5fr) 92px 58px 88px;
    gap: 12px;
    align-items: center;
  }

  .task-row--head {
    min-height: 35px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    border-bottom: 1px solid var(--el-border-color-extra-light);
  }

  .count-head {
    text-align: center;
  }

  .task-row--data {
    position: relative;
    min-height: 58px;
    border-bottom: 1px solid var(--el-border-color-extra-light);
    animation: taskRowIn 440ms var(--row-delay) cubic-bezier(0.22, 1, 0.36, 1) both;

    &:last-child {
      border-bottom: 0;
    }

    &::before {
      position: absolute;
      top: 10px;
      bottom: 10px;
      left: -16px;
      width: 3px;
      content: '';
      background: transparent;
      border-radius: 0 3px 3px 0;
    }

    &.warning::before {
      background: var(--el-color-warning);
    }

    &.critical::before {
      background: var(--el-color-danger);
    }

    &:hover {
      background: color-mix(in srgb, var(--el-fill-color-light) 60%, transparent);
    }
  }

  .task-name {
    display: flex;
    gap: 9px;
    align-items: center;
    min-width: 0;
    font-size: 13px;
    font-weight: 600;
    color: var(--el-text-color-primary);
  }

  .task-icon {
    display: grid;
    flex: 0 0 30px;
    place-items: center;
    width: 30px;
    height: 30px;
    font-size: 15px;
    color: var(--el-text-color-regular);
    background: var(--el-fill-color-light);
    border-radius: 7px;

    &.reports {
      color: var(--el-color-warning-dark-2);
    }

    &.withdraw {
      color: var(--el-color-danger);
    }

    &.recharge {
      color: var(--el-color-primary);
    }

    &.moments {
      color: var(--el-color-success);
    }
  }

  .task-desc,
  .task-time {
    overflow: hidden;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .task-count {
    font-size: 19px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--el-text-color-primary);
    text-align: center;
  }

  .task-row--data.warning .task-count {
    color: var(--el-color-warning-dark-2);
  }

  .task-row--data.critical .task-count {
    color: var(--el-color-danger);
  }

  .task-row--data.quiet {
    opacity: 0.5;
  }

  .task-action {
    display: inline-flex;
    gap: 2px;
    align-items: center;
    justify-content: flex-end;
    font-size: 12px;
    font-weight: 600;
    color: var(--el-color-primary);

    svg {
      transition: transform 180ms ease;
    }

    &:hover svg {
      transform: translateX(3px);
    }
  }

  .pending-foot {
    gap: 9px;
    min-height: 38px;
    padding: 0 16px;
    font-size: 11px;
    color: var(--el-text-color-secondary);
    background: var(--el-fill-color-extra-light);
    border-top: 1px solid var(--el-border-color-lighter);

    a {
      margin-left: auto;
      color: var(--el-color-primary);
    }
  }

  .threshold-track {
    width: 72px;
    height: 4px;
    overflow: hidden;
    background: var(--el-border-color-lighter);
    border-radius: 2px;

    i {
      display: block;
      height: 100%;
      background: var(--el-color-primary);
      border-radius: inherit;
      transition: width 560ms cubic-bezier(0.22, 1, 0.36, 1);
    }
  }

  @keyframes taskRowIn {
    from {
      opacity: 0;
      transform: translateX(-8px);
    }

    to {
      opacity: 1;
      transform: translateX(0);
    }
  }

  @media (width <= 1200px) {
    .task-row {
      grid-template-columns: minmax(120px, 1fr) minmax(180px, 1.3fr) 58px 82px;
    }

    .task-row > :nth-child(3) {
      display: none;
    }
  }

  @media (width <= 640px) {
    .task-row--head,
    .task-desc,
    .task-time,
    .task-action span,
    .pending-foot > span:not(.threshold-track) {
      display: none;
    }

    .task-row {
      grid-template-columns: minmax(0, 1fr) 48px 30px;
      gap: 8px;
    }

    .task-action {
      font-size: 18px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .task-row--data,
    .task-action svg,
    .threshold-track i {
      transition: none;
      animation: none;
    }
  }

  :global(.pending-login-notification) {
    cursor: pointer;
    border-radius: 8px;
  }
</style>
