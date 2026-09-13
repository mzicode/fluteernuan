<template>
  <div class="capacity-page" :class="{ 'is-dark': isDark }">
    <header class="hero-head">
      <div class="hero-title-group">
        <span class="page-title-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:dashboard-3-line" />
        </span>
        <div>
          <div class="eyebrow"><span class="eyebrow-dot" /> SYSTEM CAPACITY / LIVE TELEMETRY</div>
          <h1>容量控制台</h1>
          <p>用服务器实时采样与压测证据，观察当前资源水位和可承载范围。</p>
        </div>
      </div>
      <div class="head-actions">
        <ElButton :icon="Refresh" :loading="loading" @click="manualRefresh">刷新采样</ElButton>
        <ElButton
          type="primary"
          :icon="VideoPlay"
          :loading="assessing"
          :disabled="!overview?.online_nodes"
          @click="runAssessment"
          >重新评估</ElButton
        >
        <ElButton :icon="Download" :disabled="!overview?.latest_assessment" @click="downloadReport"
          >导出报告</ElButton
        >
      </div>
    </header>

    <div class="live-bar">
      <span class="live-pill"><i /> LIVE AGENT TELEMETRY</span>
      <span>{{ telemetryNodeName }}</span>
      <span>最近采样 {{ sampleTime }}</span>
      <span class="live-refresh">静默同步 · {{ lastSyncedText }}</span>
    </div>

    <section v-loading="telemetryLoading" class="telemetry-grid">
      <article class="metric-card metric-cpu">
        <div class="metric-top"
          ><div class="metric-heading"
            ><span class="metric-icon metric-icon--cpu" aria-hidden="true"
              ><ArtSvgIcon icon="ri:cpu-line" /></span
            ><div><span class="metric-kicker">PROCESSOR</span><h2>CPU 资源</h2></div></div
          ><span class="metric-status">{{ telemetryStatus }}</span></div
        >
        <div class="ring-wrap"
          ><div class="metric-ring" :style="ringStyle(cpuPercent, '#39d98a')"
            ><div class="ring-center"
              ><strong>{{ cpuPercent }}<small>%</small></strong
              ><span>当前使用</span></div
            ></div
          ></div
        >
        <div class="metric-foot"
          ><span>有效 / 主机</span><strong>{{ effectiveCpu }} / {{ hostCpuText }}</strong></div
        >
        <div class="micro-bars" aria-hidden="true"
          ><i
            v-for="(value, index) in cpuHistory"
            :key="`cpu-${index}`"
            :style="{ height: `${Math.max(12, value)}%` }"
        /></div>
      </article>

      <article class="metric-card metric-memory">
        <div class="metric-top"
          ><div class="metric-heading"
            ><span class="metric-icon metric-icon--memory" aria-hidden="true"
              ><ArtSvgIcon icon="ri:database-2-line" /></span
            ><div><span class="metric-kicker">MEMORY</span><h2>内存水位</h2></div></div
          ><span class="metric-status">{{ memoryUsedText }}</span></div
        >
        <div class="ring-wrap"
          ><div class="metric-ring" :style="ringStyle(memoryPercent, '#55b7ff')"
            ><div class="ring-center"
              ><strong>{{ memoryPercent }}<small>%</small></strong
              ><span>已使用</span></div
            ></div
          ></div
        >
        <div class="metric-foot"
          ><span>可用 / 总量</span
          ><strong>{{ memoryAvailableText }} / {{ memoryTotalText }}</strong></div
        >
        <div class="micro-bars blue" aria-hidden="true"
          ><i
            v-for="(value, index) in memoryHistory"
            :key="`memory-${index}`"
            :style="{ height: `${Math.max(12, value)}%` }"
        /></div>
      </article>

      <article class="metric-card metric-network">
        <div class="metric-top"
          ><div class="metric-heading"
            ><span class="metric-icon metric-icon--network" aria-hidden="true"
              ><ArtSvgIcon icon="ri:line-chart-line" /></span
            ><div><span class="metric-kicker">NETWORK FLOW</span><h2>网络流量</h2></div></div
          ><span class="metric-status">{{ networkSource }}</span></div
        >
        <div class="network-chart-wrap">
          <div class="network-chart-legend">
            <span class="download"><i />下行</span>
            <span class="upload"><i />上行</span>
          </div>
          <svg
            class="network-wave-chart"
            viewBox="0 0 280 140"
            preserveAspectRatio="none"
            role="img"
            :aria-label="`下行 ${downloadText}，上行 ${uploadText}`"
          >
            <defs>
              <linearGradient id="network-download-area" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stop-color="#ffb020" stop-opacity="0.28" />
                <stop offset="1" stop-color="#ffb020" stop-opacity="0" />
              </linearGradient>
              <linearGradient id="network-upload-area" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stop-color="#22b455" stop-opacity="0.3" />
                <stop offset="1" stop-color="#22b455" stop-opacity="0" />
              </linearGradient>
            </defs>
            <g class="network-chart-grid" aria-hidden="true">
              <line v-for="y in [20, 56, 92, 128]" :key="y" x1="0" :y1="y" x2="280" :y2="y" />
            </g>
            <path :d="downloadAreaPath" fill="url(#network-download-area)" />
            <path :d="uploadAreaPath" fill="url(#network-upload-area)" />
            <path class="network-line download" :d="downloadLinePath" />
            <path class="network-line upload" :d="uploadLinePath" />
            <g class="network-points download" aria-hidden="true">
              <circle
                v-for="(point, index) in downloadChartPoints"
                :key="`download-${index}`"
                :cx="point.x"
                :cy="point.y"
                r="2.7"
              />
            </g>
            <g class="network-points upload" aria-hidden="true">
              <circle
                v-for="(point, index) in uploadChartPoints"
                :key="`upload-${index}`"
                :cx="point.x"
                :cy="point.y"
                r="2.7"
              />
            </g>
          </svg>
        </div>
        <div class="metric-foot network-foot"
          ><span><small>下行</small>{{ downloadText }}</span
          ><strong><small>上行</small>{{ uploadText }}</strong></div
        >
      </article>

      <article class="metric-card metric-capacity">
        <div class="metric-top"
          ><div class="metric-heading"
            ><span class="metric-icon metric-icon--capacity" aria-hidden="true"
              ><ArtSvgIcon icon="ri:group-line" /></span
            ><div
              ><span class="metric-kicker">CAPACITY ESTIMATE</span
              ><h2>标准文本模型估算（非实测）</h2></div
            ></div
          ><span class="metric-status accent">{{ confidenceText }}</span></div
        >
        <div class="capacity-number"
          >{{ formatNumber(standardScenario?.recommended) }}<small> 估算在线用户</small></div
        >
        <div class="capacity-range"
          ><span>保守 {{ formatNumber(standardScenario?.lower) }}</span
          ><span>上限 {{ formatNumber(standardScenario?.upper) }}</span></div
        >
        <div class="capacity-track"><i :style="{ width: `${confidenceScore}%` }" /></div>
        <div class="metric-foot"
          ><span>评估状态</span><strong>{{ phaseLabel }}</strong></div
        >
      </article>
    </section>

    <section class="pressure-panel">
      <div class="pressure-title"
        ><div
          ><span class="metric-kicker">LOAD TEST OBSERVATION</span><h2>压测观测台</h2
          ><p>压测期间持续显示 Agent 最近采样的资源值，数据不会写入业务消息。</p></div
        ><span class="observe-badge"><i /> 采样在线</span></div
      >
      <div class="pressure-grid">
        <div
          ><span>CPU 核心 / 主机</span><strong>{{ hostCpuText }}</strong
          ><small>{{ hostName }}</small></div
        >
        <div
          ><span>宿主机内存</span><strong>{{ memoryUsedText }} / {{ memoryTotalText }}</strong
          ><small>API 容器占用 {{ containerMemoryText }}</small></div
        >
        <div
          ><span>网络接口</span><strong>{{ networkInterface }}</strong
          ><small>链路 {{ networkLinkText }}</small></div
        >
        <div
          ><span>当前 API 估算</span><strong>{{ formatQps(applicationQps) }}</strong
          ><small>{{ applicationStatus }}</small></div
        >
      </div>
    </section>

    <section class="section-block scenarios-block">
      <div class="section-head"
        ><div
          ><span class="metric-kicker">CAPACITY MODEL</span><h2>场景容量</h2
          ><p>建议值应用模型安全系数和单机故障预留。</p></div
        ><ElTag effect="plain">模型 {{ overview?.model_version || '-' }}</ElTag></div
      >
      <div v-if="scenarios.length" class="scenario-grid">
        <article v-for="scenario in scenarios" :key="scenario.scenario_id" class="scenario-card">
          <div class="scenario-head"
            ><div
              ><span>{{ scenarioLabel(scenario.scenario_id) }}</span
              ><h3>{{ scenario.scenario_name }}</h3></div
            ><ElTag
              :type="scenario.status === 'estimated' ? 'success' : 'warning'"
              effect="light"
              >{{ scenario.status === 'estimated' ? '可估算' : '数据不足' }}</ElTag
            ></div
          >
          <strong class="scenario-value">{{ formatNumber(scenario.recommended) }}</strong
          ><span class="scenario-unit">模型建议同时在线人数（未经压测认证）</span>
          <div class="range-row"
            ><span>下限 {{ formatNumber(scenario.lower) }}</span
            ><span>上限 {{ formatNumber(scenario.upper) }}</span></div
          >
          <div class="bottleneck-row"
            ><span>主要瓶颈</span><strong>{{ resourceLabel(scenario.bottleneck) }}</strong></div
          >
        </article>
      </div>
      <ElEmpty v-else :image-size="88" description="等待 Agent 采样后生成评估" />
    </section>

    <section class="detail-grid">
      <div class="section-block"
        ><div class="section-head compact"
          ><div
            ><span class="metric-kicker">LIMITS</span><h2>限制资源</h2
            ><p>标准文本场景按资源容量从低到高排列。</p></div
          ></div
        ><ElTable :data="standardScenario?.limits || []" height="300"
          ><ElTableColumn label="资源" min-width="130"
            ><template #default="{ row }">{{
              resourceLabel(row.resource)
            }}</template></ElTableColumn
          ><ElTableColumn label="容量上限" min-width="150"
            ><template #default="{ row }">{{ formatNumber(row.capacity) }}</template></ElTableColumn
          ><ElTableColumn prop="formula_id" label="计算公式" min-width="180" /></ElTable
      ></div>
      <div class="section-block"
        ><div class="section-head compact"
          ><div
            ><span class="metric-kicker">EVIDENCE</span><h2>证据完整度</h2
            ><p>缺失项会降低置信度或阻止输出容量。</p></div
          ></div
        ><div class="confidence-panel"
          ><ElProgress
            type="dashboard"
            :percentage="confidenceScore"
            :width="142"
            :stroke-width="11"
          /><div
            ><strong>{{ overview?.result?.confidence.grade || '-' }} 级</strong
            ><span>模型不会用默认高值替代关键缺失数据。</span></div
          ></div
        ><div class="evidence-list"
          ><span v-for="item in overview?.result?.confidence.missing || []" :key="item"
            ><ArtSvgIcon icon="ri:error-warning-line" />{{ metricLabel(item) }}</span
          ><span v-if="!(overview?.result?.confidence.missing || []).length" class="complete"
            ><ArtSvgIcon icon="ri:checkbox-circle-line" />关键证据完整</span
          ></div
        ></div
      >
    </section>
  </div>
</template>

<script setup lang="ts">
  import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
  import { Download, Refresh, VideoPlay } from '@element-plus/icons-vue'
  import { ElMessage } from 'element-plus'
  import { useSettingStore } from '@/store/modules/setting'
  import {
    createCapacityAssessment,
    getCapacityNode,
    getCapacityNodes,
    getCapacityOverview,
    getCapacityReport,
    type CapacityNodeDetails,
    type CapacityOverviewResponse
  } from '@/api/admin'

  defineOptions({ name: 'CapacityOverview' })
  const { isDark } = storeToRefs(useSettingStore())
  const loading = ref(false)
  const assessing = ref(false)
  const telemetryLoading = ref(false)
  const telemetryRequesting = ref(false)
  const overview = ref<CapacityOverviewResponse>()
  const nodeDetail = ref<CapacityNodeDetails>()
  const lastSyncedAt = ref<Date | null>(null)
  let lastHistorySample = ''
  let timer: ReturnType<typeof setInterval> | undefined
  const cpuHistory = ref<number[]>([])
  const memoryHistory = ref<number[]>([])
  const downloadHistory = ref<number[]>([])
  const uploadHistory = ref<number[]>([])
  const scenarios = computed(() => overview.value?.result?.scenarios || [])
  const standardScenario = computed(() =>
    scenarios.value.find((item) => item.scenario_id === 'standard_text')
  )
  const host = computed(() => nodeDetail.value?.details?.host)
  const application = computed(() => nodeDetail.value?.details?.application)
  const cpuPercent = computed(() =>
    Math.min(100, Math.max(0, Math.round(host.value?.cpu_usage_percent || 0)))
  )
  const memoryPercent = computed(() => {
    const total = host.value?.memory_total_bytes || 0
    const used = host.value?.memory_used_bytes || total - (host.value?.memory_available_bytes || 0)
    return total ? Math.min(100, Math.max(0, Math.round((used / total) * 100))) : 0
  })
  const networkLink = computed(() => host.value?.network_link_bps || 0)
  const effectiveCpu = computed(() => (host.value?.effective_cpu_cores || 0).toFixed(1))
  const hostCpuText = computed(() => `${host.value?.cpu_cores || 0} 核`)
  const memoryUsedText = computed(() =>
    formatBytes(
      host.value?.memory_used_bytes ||
        Math.max(
          0,
          (host.value?.memory_total_bytes || 0) - (host.value?.memory_available_bytes || 0)
        )
    )
  )
  const memoryAvailableText = computed(() => formatBytes(host.value?.memory_available_bytes || 0))
  const memoryTotalText = computed(() => formatBytes(host.value?.memory_total_bytes || 0))
  const containerMemoryText = computed(() =>
    formatBytes(host.value?.container_memory_used_bytes || 0)
  )
  const networkInterface = computed(() => host.value?.network_interface || '未识别')
  const networkLinkText = computed(() => formatBps(networkLink.value))
  const downloadText = computed(() => formatBps(host.value?.network_receive_bps || 0))
  const uploadText = computed(() => formatBps(host.value?.network_transmit_bps || 0))
  const downloadSeries = computed(() =>
    chartSeries(downloadHistory.value, host.value?.network_receive_bps || 0)
  )
  const uploadSeries = computed(() =>
    chartSeries(uploadHistory.value, host.value?.network_transmit_bps || 0)
  )
  const networkChartMax = computed(
    () => Math.max(1, ...downloadSeries.value, ...uploadSeries.value) * 1.12
  )
  const downloadChartPoints = computed(() => chartPoints(downloadSeries.value))
  const uploadChartPoints = computed(() => chartPoints(uploadSeries.value))
  const downloadLinePath = computed(() => smoothPath(downloadChartPoints.value))
  const uploadLinePath = computed(() => smoothPath(uploadChartPoints.value))
  const downloadAreaPath = computed(() => areaPath(downloadChartPoints.value))
  const uploadAreaPath = computed(() => areaPath(uploadChartPoints.value))
  const networkSource = computed(() =>
    host.value?.telemetry_scope === 'host' ? '宿主机实时' : '等待宿主机采样'
  )
  const hostName = computed(() => host.value?.hostname || nodeDetail.value?.node.name || '等待节点')
  const applicationQps = computed(() => application.value?.estimated_qps || 0)
  const applicationStatus = computed(() => application.value?.health_status || '等待采样')
  const telemetryNodeName = computed(() => nodeDetail.value?.node.name || '未连接节点')
  const sampleTime = computed(() =>
    nodeDetail.value?.node.last_sample_at
      ? formatDateTime(nodeDetail.value.node.last_sample_at)
      : '暂无'
  )
  const telemetryStatus = computed(() =>
    nodeDetail.value?.node.sample_status === 'fresh' ? '实时采样' : '等待采样'
  )
  const phaseLabel = computed(
    () =>
      ({
        waiting_for_agent: '等待 Agent',
        collecting_baseline: '采集中',
        assessment_ready: '评估完成',
        database_unavailable: '数据库不可用'
      })[overview.value?.phase_status || ''] || '初始化中'
  )
  const confidenceScore = computed(() => overview.value?.result?.confidence.score || 0)
  const confidenceText = computed(() => {
    const confidence = overview.value?.result?.confidence
    return confidence ? `${confidence.grade} / ${confidence.score}` : '-'
  })
  const lastSyncedText = computed(() => {
    if (!lastSyncedAt.value) return '连接中'
    return lastSyncedAt.value.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false
    })
  })

  function ringStyle(value: number, color: string) {
    const track = isDark.value ? 'rgba(255,255,255,.08)' : 'rgba(148,163,184,.20)'
    return {
      background: `conic-gradient(${color} ${value}%, ${track} ${value}% 100%)`
    }
  }
  async function loadOverview() {
    overview.value = await getCapacityOverview()
  }
  async function loadTelemetry(showInitialLoading = false) {
    if (telemetryRequesting.value) return
    telemetryRequesting.value = true
    if (showInitialLoading && !nodeDetail.value) telemetryLoading.value = true
    try {
      const nodes = await getCapacityNodes()
      const node = nodes.list.find((item) => !item.stale) || nodes.list[0]
      if (node) {
        nodeDetail.value = await getCapacityNode(node.uuid)
        const sampleKey = nodeDetail.value.node.last_sample_at || ''
        if (sampleKey && sampleKey !== lastHistorySample) {
          lastHistorySample = sampleKey
          cpuHistory.value = [...cpuHistory.value.slice(-7), cpuPercent.value]
          memoryHistory.value = [...memoryHistory.value.slice(-7), memoryPercent.value]
          downloadHistory.value = [
            ...downloadHistory.value.slice(-11),
            host.value?.network_receive_bps || 0
          ]
          uploadHistory.value = [
            ...uploadHistory.value.slice(-11),
            host.value?.network_transmit_bps || 0
          ]
        }
        lastSyncedAt.value = sampleKey ? new Date(sampleKey) : new Date()
      }
    } finally {
      telemetryLoading.value = false
      telemetryRequesting.value = false
    }
  }
  async function refreshAll(showButtonLoading = false, showInitialLoading = false) {
    if (showButtonLoading) loading.value = true
    try {
      await Promise.all([loadOverview(), loadTelemetry(showInitialLoading)])
    } finally {
      if (showButtonLoading) loading.value = false
    }
  }
  const manualRefresh = () => refreshAll(true)
  async function runAssessment() {
    assessing.value = true
    try {
      await createCapacityAssessment()
      await refreshAll(false)
    } finally {
      assessing.value = false
    }
  }
  async function downloadReport() {
    const uuid = overview.value?.latest_assessment?.uuid
    if (!uuid) return
    const report = await getCapacityReport(uuid)
    const blob = new Blob([report.markdown], { type: 'text/markdown;charset=utf-8' })
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `customer-capacity-${uuid}.md`
    anchor.click()
    URL.revokeObjectURL(url)
    ElMessage.success(`报告已生成，SHA256：${report.sha256['report.md']}`)
  }
  function formatNumber(value?: number) {
    return new Intl.NumberFormat('zh-CN').format(value || 0)
  }
  function formatBytes(value?: number) {
    if (!value) return '-'
    const units = ['B', 'KB', 'MB', 'GB', 'TB']
    let n = value
    let i = 0
    while (n >= 1024 && i < units.length - 1) {
      n /= 1024
      i++
    }
    return `${n.toFixed(n >= 10 ? 0 : 1)} ${units[i]}`
  }
  function formatBps(value?: number) {
    if (!value) return '-'
    if (value >= 1e9) return `${(value / 1e9).toFixed(1)} Gbps`
    if (value >= 1e6) return `${(value / 1e6).toFixed(1)} Mbps`
    return `${(value / 1e3).toFixed(1)} Kbps`
  }
  function formatQps(value?: number) {
    return value ? `${value.toFixed(0)} QPS` : '-'
  }
  function chartSeries(values: number[], current: number) {
    const series = values.length ? values : [current]
    return series.length === 1 ? [series[0], series[0]] : series
  }
  function chartPoints(values: number[]) {
    const width = 280
    const top = 10
    const bottom = 128
    return values.map((value, index) => ({
      x: values.length === 1 ? width : (index / (values.length - 1)) * width,
      y: bottom - (Math.max(0, value) / networkChartMax.value) * (bottom - top)
    }))
  }
  function smoothPath(points: Array<{ x: number; y: number }>) {
    if (!points.length) return ''
    return points.slice(1).reduce((path, point, index) => {
      const previous = points[index]
      const middleX = (previous.x + point.x) / 2
      return `${path} C ${middleX} ${previous.y}, ${middleX} ${point.y}, ${point.x} ${point.y}`
    }, `M ${points[0].x} ${points[0].y}`)
  }
  function areaPath(points: Array<{ x: number; y: number }>) {
    if (!points.length) return ''
    return `${smoothPath(points)} L ${points.at(-1)?.x || 280} 128 L ${points[0].x} 128 Z`
  }
  function formatDateTime(value: string) {
    return new Date(value).toLocaleString('zh-CN', { hour12: false })
  }
  function scenarioLabel(id: string) {
    return (
      (
        { light_idle: '连接保持', standard_text: '日常消息', text_media: '媒体活跃' } as Record<
          string,
          string
        >
      )[id] || id
    )
  }
  function resourceLabel(value?: string) {
    return (
      (
        {
          memory: '内存',
          file_descriptors: '文件描述符',
          ingress: '入口连接',
          bandwidth: '网络带宽',
          cpu: 'CPU',
          api: 'API 处理能力',
          mysql: 'MySQL',
          mongo: 'MongoDB',
          redis: 'Redis'
        } as Record<string, string>
      )[value || ''] ||
      value ||
      '-'
    )
  }
  function metricLabel(value: string) {
    return (
      (
        {
          host: '主机证据',
          dependencies: '依赖证据',
          api: 'API 证据',
          network: '网络证据',
          calibration: '压测校准',
          topology: '拓扑证据',
          container_memory_limit: '容器内存上限'
        } as Record<string, string>
      )[value] || value.replaceAll('_', ' ')
    )
  }
  onMounted(async () => {
    await refreshAll(false, true)
    timer = setInterval(() => void loadTelemetry(false), 5000)
  })
  onBeforeUnmount(() => {
    if (timer) clearInterval(timer)
  })
</script>

<style scoped lang="scss">
  @use '../capacity-theme' as capacityTheme;

  .capacity-page {
    min-height: 100%;
    padding: 28px;
    color: #e7f2ff;
    background:
      radial-gradient(circle at 85% 0%, rgba(36, 104, 154, 0.18), transparent 34%), #07111e;
  }
  .hero-head,
  .section-head,
  .metric-top,
  .scenario-head,
  .range-row,
  .bottleneck-row,
  .pressure-title {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 18px;
  }
  .hero-head {
    margin-bottom: 16px;
  }
  .hero-title-group {
    display: flex;
    align-items: center;
    gap: 14px;
    min-width: 0;
  }
  .page-title-icon {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 50px;
    height: 50px;
    color: #55b7ff;
    border: 1px solid rgb(85 183 255 / 34%);
    border-radius: 14px;
    background: rgb(85 183 255 / 10%);
    box-shadow: 0 8px 22px rgb(20 121 194 / 14%);
    font-size: 24px;
  }
  .eyebrow,
  .metric-kicker {
    color: #6ee7ff;
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 1.4px;
  }
  .eyebrow-dot,
  .live-pill i,
  .observe-badge i {
    display: inline-block;
    width: 7px;
    height: 7px;
    margin-right: 6px;
    border-radius: 50%;
    background: #39d98a;
    box-shadow: 0 0 12px #39d98a;
  }
  h1 {
    margin: 8px 0 6px;
    color: #f5fbff;
    font-size: 30px;
    letter-spacing: 0.3px;
  }
  h2 {
    margin: 0;
    color: #f2f8ff;
    font-size: 17px;
  }
  h3 {
    margin: 5px 0 0;
    color: #f2f8ff;
    font-size: 15px;
  }
  p {
    margin: 0;
    color: #88a0b8;
    font-size: 13px;
  }
  .hero-head p {
    max-width: 560px;
    line-height: 1.6;
  }
  .head-actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px;
  }
  .live-bar,
  .metric-card,
  .pressure-panel,
  .section-block {
    border: 1px solid rgba(125, 176, 215, 0.2);
    background: rgba(10, 27, 43, 0.84);
    box-shadow: 0 12px 40px rgba(0, 0, 0, 0.16);
  }
  .live-bar {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 18px;
    min-height: 42px;
    padding: 0 15px;
    color: #91aac2;
    font-size: 12px;
  }
  .live-pill {
    color: #a9ffd2;
    font-weight: 700;
  }
  .live-refresh {
    margin-left: auto;
    color: #6ee7ff;
  }
  .telemetry-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 14px;
    margin-top: 14px;
  }
  .metric-card {
    --metric-accent: #55b7ff;
    --metric-tint: rgb(85 183 255 / 8%);

    min-width: 0;
    min-height: 300px;
    padding: 18px;
    overflow: hidden;
    position: relative;
    background: linear-gradient(145deg, var(--metric-tint), transparent 58%), rgb(10 27 43 / 68%);
    backdrop-filter: blur(16px) saturate(128%);
    -webkit-backdrop-filter: blur(16px) saturate(128%);
  }
  .metric-cpu {
    --metric-accent: #39d98a;
    --metric-tint: rgb(57 217 138 / 9%);
  }
  .metric-memory {
    --metric-accent: #55b7ff;
    --metric-tint: rgb(85 183 255 / 9%);
  }
  .metric-network {
    --metric-accent: #ffb84d;
    --metric-tint: rgb(255 184 77 / 10%);
  }
  .metric-capacity {
    --metric-accent: #9b7cff;
    --metric-tint: rgb(155 124 255 / 10%);
  }
  .metric-heading {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
  }
  .metric-icon {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 38px;
    height: 38px;
    border: 1px solid currentcolor;
    border-radius: 10px;
    font-size: 19px;
  }
  .metric-icon--cpu {
    color: #39d98a;
    border-color: rgb(57 217 138 / 34%);
    background: rgb(57 217 138 / 11%);
  }
  .metric-icon--memory {
    color: #55b7ff;
    border-color: rgb(85 183 255 / 34%);
    background: rgb(85 183 255 / 11%);
  }
  .metric-icon--network {
    color: #ffb84d;
    border-color: rgb(255 184 77 / 38%);
    background: rgb(255 184 77 / 12%);
  }
  .metric-icon--capacity {
    color: #a98cff;
    border-color: rgb(155 124 255 / 36%);
    background: rgb(155 124 255 / 12%);
  }
  .metric-kicker {
    color: #7b9bb7;
    font-size: 10px;
  }
  .metric-status {
    padding: 4px 7px;
    color: #a9ffd2;
    border: 1px solid rgba(57, 217, 138, 0.35);
    border-radius: 999px;
    font-size: 10px;
  }
  .metric-status.accent {
    color: #ffd38c;
    border-color: rgba(255, 184, 77, 0.45);
  }
  .ring-wrap {
    display: grid;
    place-items: center;
    padding: 19px 0 15px;
  }
  .metric-ring {
    display: grid;
    place-items: center;
    width: 164px;
    height: 164px;
    border-radius: 50%;
    transform: rotate(-2deg);
    box-shadow: 0 0 28px rgba(79, 186, 255, 0.12);
  }
  .ring-center {
    display: grid;
    place-items: center;
    width: 128px;
    height: 128px;
    border: 1px solid rgba(255, 255, 255, 0.09);
    border-radius: 50%;
    background: #0b1a2a;
    transform: rotate(2deg);
  }
  .ring-center strong {
    color: #f4fbff;
    font-size: 32px;
    line-height: 1;
  }
  .ring-center strong small {
    margin-left: 2px;
    color: #a4bdd4;
    font-size: 14px;
  }
  .ring-center span {
    color: #7f9ab3;
    font-size: 11px;
  }
  .metric-foot {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 8px;
    padding-top: 12px;
    border-top: 1px solid rgba(137, 178, 210, 0.16);
    color: #8ba5bd;
    font-size: 12px;
  }
  .metric-foot strong {
    color: #ecf7ff;
    font-size: 14px;
  }
  .network-foot strong {
    color: #ffca70;
  }
  .network-foot small {
    margin-right: 6px;
    color: #7f9ab3;
    font-size: 10px;
    font-weight: 400;
  }
  .network-chart-wrap {
    padding: 14px 0 10px;
  }
  .network-chart-legend {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 14px;
    color: #8ba5bd;
    font-size: 10px;
  }
  .network-chart-legend span {
    display: inline-flex;
    align-items: center;
    gap: 5px;
  }
  .network-chart-legend i {
    width: 6px;
    height: 6px;
    border-radius: 50%;
  }
  .network-chart-legend .download i {
    background: #ffb020;
  }
  .network-chart-legend .upload i {
    background: #22b455;
  }
  .network-wave-chart {
    display: block;
    width: 100%;
    height: 140px;
    margin-top: 3px;
    overflow: visible;
  }
  .network-chart-grid line {
    stroke: rgba(137, 178, 210, 0.18);
    stroke-dasharray: 4 4;
    stroke-width: 1;
    vector-effect: non-scaling-stroke;
  }
  .network-line {
    fill: none;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-width: 2.2;
    vector-effect: non-scaling-stroke;
  }
  .network-line.download {
    stroke: #ffb020;
  }
  .network-line.upload {
    stroke: #22b455;
  }
  .network-points.download {
    fill: #ffb020;
  }
  .network-points.upload {
    fill: #22b455;
  }
  .micro-bars {
    display: flex;
    align-items: flex-end;
    gap: 4px;
    height: 22px;
    margin-top: 14px;
    opacity: 0.75;
  }
  .micro-bars i {
    flex: 1;
    min-width: 3px;
    background: #39d98a;
    border-radius: 2px 2px 0 0;
  }
  .micro-bars.blue i {
    background: #55b7ff;
  }
  .micro-bars.amber i {
    background: #ffb84d;
  }
  .capacity-number {
    margin: 54px 0 11px;
    color: #f2f8ff;
    font-size: 32px;
    font-weight: 750;
    white-space: nowrap;
  }
  .capacity-number small {
    color: #8ba5bd;
    font-size: 12px;
    font-weight: 400;
  }
  .capacity-range {
    display: flex;
    justify-content: space-between;
    color: #8ba5bd;
    font-size: 12px;
  }
  .capacity-track {
    height: 6px;
    margin: 18px 0 16px;
    overflow: hidden;
    border-radius: 99px;
    background: rgba(255, 255, 255, 0.08);
  }
  .capacity-track i {
    display: block;
    height: 100%;
    border-radius: inherit;
    background: #ffb84d;
    box-shadow: 0 0 15px rgba(255, 184, 77, 0.75);
  }
  .pressure-panel {
    margin-top: 14px;
    padding: 20px;
  }
  .pressure-title {
    align-items: flex-start;
    margin-bottom: 18px;
  }
  .pressure-title h2 {
    margin: 5px 0;
  }
  .observe-badge {
    color: #a9ffd2;
    font-size: 12px;
  }
  .pressure-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    border-top: 1px solid rgba(137, 178, 210, 0.16);
    border-left: 1px solid rgba(137, 178, 210, 0.16);
  }
  .pressure-grid > div {
    min-width: 0;
    padding: 15px;
    border-right: 1px solid rgba(137, 178, 210, 0.16);
    border-bottom: 1px solid rgba(137, 178, 210, 0.16);
  }
  .pressure-grid span,
  .pressure-grid small {
    display: block;
    color: #7f9ab3;
    font-size: 11px;
  }
  .pressure-grid strong {
    display: block;
    margin: 8px 0 5px;
    color: #f1f8ff;
    font-size: 19px;
    overflow-wrap: anywhere;
  }
  .pressure-grid small {
    color: #6ee7ff;
  }
  .section-block {
    margin-top: 14px;
    padding: 20px;
  }
  .section-head {
    align-items: flex-start;
    margin-bottom: 16px;
  }
  .section-head p {
    margin-top: 5px;
  }
  .scenario-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 12px;
  }
  .scenario-card {
    min-width: 0;
    padding: 16px;
    border: 1px solid rgba(125, 176, 215, 0.18);
    background: rgba(7, 20, 33, 0.72);
  }
  .scenario-head > div > span,
  .scenario-unit {
    color: #7f9ab3;
    font-size: 11px;
  }
  .scenario-value {
    display: block;
    margin-top: 23px;
    color: #f2f8ff;
    font-size: 29px;
  }
  .scenario-unit {
    display: block;
    margin-top: 4px;
  }
  .range-row {
    margin-top: 16px;
    padding: 10px 0;
    border-block: 1px solid rgba(137, 178, 210, 0.13);
    color: #9bb1c6;
    font-size: 11px;
  }
  .bottleneck-row {
    margin-top: 12px;
    color: #7f9ab3;
    font-size: 12px;
  }
  .bottleneck-row strong {
    color: #ffca70;
  }
  .detail-grid {
    display: grid;
    grid-template-columns: minmax(0, 1.4fr) minmax(280px, 0.8fr);
    gap: 14px;
  }
  .detail-grid .section-block {
    min-width: 0;
  }
  .section-head.compact {
    margin-bottom: 12px;
  }
  .confidence-panel {
    display: flex;
    align-items: center;
    gap: 18px;
    padding: 6px 0 17px;
  }
  .confidence-panel strong,
  .confidence-panel span {
    display: block;
  }
  .confidence-panel strong {
    color: #f2f8ff;
    font-size: 22px;
  }
  .confidence-panel span {
    max-width: 220px;
    margin-top: 7px;
    color: #7f9ab3;
    font-size: 12px;
    line-height: 1.6;
  }
  .evidence-list {
    display: flex;
    flex-direction: column;
    gap: 7px;
  }
  .evidence-list span {
    display: flex;
    align-items: center;
    gap: 7px;
    padding: 8px 10px;
    color: #ffd38c;
    background: rgba(126, 81, 22, 0.25);
    font-size: 11px;
  }
  .evidence-list .complete {
    color: #a9ffd2;
    background: rgba(32, 119, 77, 0.22);
  }
  :deep(.el-loading-mask) {
    background-color: rgba(7, 17, 30, 0.82);
  }
  :deep(.el-table),
  :deep(.el-table tr),
  :deep(.el-table th.el-table__cell) {
    color: #c9dced;
    background: transparent;
  }
  :deep(.el-table th.el-table__cell) {
    color: #7f9ab3;
    background: rgba(115, 169, 211, 0.07);
  }
  :deep(.el-table td.el-table__cell),
  :deep(.el-table th.el-table__cell) {
    border-bottom-color: rgba(137, 178, 210, 0.13);
  }
  :deep(.el-table--enable-row-hover .el-table__body tr:hover > td.el-table__cell) {
    background: rgba(67, 151, 206, 0.1);
  }
  .capacity-page:not(.is-dark) {
    @include capacityTheme.light-page;
  }
  .capacity-page:not(.is-dark) .page-title-icon {
    color: #2563eb;
    border-color: #bfdbfe;
    background: #eff6ff;
    box-shadow: 0 8px 18px rgb(37 99 235 / 12%);
  }
  .capacity-page:not(.is-dark) .metric-card {
    background:
      linear-gradient(145deg, var(--metric-tint), transparent 62%), rgb(255 255 255 / 72%);
  }
  @media (max-width: 1200px) {
    .telemetry-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
    .scenario-grid {
      grid-template-columns: 1fr;
    }
  }
  @media (max-width: 860px) {
    .capacity-page {
      padding: 16px;
    }
    .hero-head {
      align-items: flex-start;
      flex-direction: column;
    }
    .head-actions {
      justify-content: flex-start;
    }
    .pressure-grid,
    .detail-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
  @media (max-width: 560px) {
    .capacity-page {
      padding: 12px;
    }
    .telemetry-grid,
    .pressure-grid,
    .detail-grid {
      grid-template-columns: 1fr;
    }
    .live-refresh {
      margin-left: 0;
    }
    .metric-card {
      min-height: 280px;
    }
  }
</style>
