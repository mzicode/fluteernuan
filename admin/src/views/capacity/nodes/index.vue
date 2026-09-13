<template>
  <div class="capacity-page nodes-page" :class="{ 'is-dark': isDark }">
    <header class="hero-head">
      <div
        ><div class="eyebrow"><span class="eyebrow-dot" /> SYSTEM CAPACITY / NODE FLEET</div
        ><h1>节点检测</h1><p>查看每个容量 Agent 的主机、容器、API、依赖和网络采样状态。</p></div
      >
      <ElButton type="primary" :icon="Refresh" :loading="loading" @click="loadNodes"
        >刷新节点</ElButton
      >
    </header>
    <div class="live-bar"
      ><span class="live-pill"><i /> AGENT FLEET</span><span>{{ nodes.length }} 个节点已注册</span
      ><span>在线 {{ onlineCount }}</span
      ><span>有效采样 {{ freshCount }}</span
      ><span class="live-refresh">点击节点查看详情</span></div
    >
    <ElAlert
      title="容量估算，未进行真实并发压测认证"
      type="warning"
      :closable="false"
      show-icon
      class="disclaimer"
    />

    <section class="fleet-grid">
      <article class="fleet-card"
        ><div class="fleet-icon green">●</div
        ><div
          ><span>在线节点</span><strong>{{ onlineCount }} / {{ nodes.length }}</strong
          ><small>Agent 心跳正常</small></div
        ></article
      >
      <article class="fleet-card"
        ><div class="fleet-icon blue">◌</div
        ><div
          ><span>有效采样</span><strong>{{ freshCount }}</strong
          ><small>可用于容量评估</small></div
        ></article
      >
      <article class="fleet-card"
        ><div class="fleet-icon amber">⌁</div
        ><div
          ><span>过期节点</span><strong>{{ staleCount }}</strong
          ><small>需要重新连接</small></div
        ></article
      >
      <article class="fleet-card"
        ><div class="mini-ring" :style="ringStyle(freshRatio, '#55b7ff')"
          ><b>{{ freshRatio }}<small>%</small></b></div
        ><div
          ><span>采样完整度</span><strong>{{ freshRatio }}%</strong
          ><small>最新数据覆盖率</small></div
        ></article
      >
    </section>

    <section class="panel">
      <div class="panel-head"
        ><div
          ><span class="metric-kicker">REGISTERED AGENTS</span><h2>节点舰队</h2
          ><p>点击任意节点查看资源快照、依赖状态和检测警告。</p></div
        ><div class="legend"><i class="online" />在线 <i class="stale" />过期</div></div
      >
      <ElTable v-loading="loading" :data="nodes" height="520" @row-click="openNode">
        <ElTableColumn label="节点" min-width="200"
          ><template #default="{ row }"
            ><div class="node-name"
              ><i :class="row.stale ? 'stale' : 'online'" /><strong>{{ row.name }}</strong
              ><ElTag v-if="!row.stale" type="success" effect="dark" size="small"
                >ONLINE</ElTag
              ></div
            ><small>{{ row.uuid }}</small></template
          ></ElTableColumn
        >
        <ElTableColumn label="环境" min-width="150"
          ><template #default="{ row }"
            >{{ row.operating_system }} / {{ row.architecture }}</template
          ></ElTableColumn
        >
        <ElTableColumn prop="deployment_mode" label="部署模式" min-width="150" />
        <ElTableColumn label="Agent" min-width="125"
          ><template #default="{ row }">{{ row.agent_version || '-' }}</template></ElTableColumn
        >
        <ElTableColumn label="采样状态" width="120"
          ><template #default="{ row }"
            ><ElTag :type="sampleTag(row.sample_status)" effect="light">{{
              sampleLabel(row.sample_status)
            }}</ElTag></template
          ></ElTableColumn
        >
        <ElTableColumn label="最近上报" min-width="175"
          ><template #default="{ row }">{{
            formatDateTime(row.last_sample_at)
          }}</template></ElTableColumn
        >
        <ElTableColumn width="54" align="right"
          ><template #default><ArtSvgIcon icon="ri:arrow-right-s-line" /></template
        ></ElTableColumn>
        <template #empty><ElEmpty :image-size="86" description="尚未注册容量 Agent" /></template>
      </ElTable>
    </section>

    <ElDrawer
      v-model="drawerVisible"
      size="min(700px, 100%)"
      :with-header="false"
      class="tech-drawer"
      :class="{ 'is-dark': isDark, 'is-light': !isDark }"
    >
      <div v-loading="detailLoading" class="drawer-content" :class="{ 'is-dark': isDark }">
        <div class="drawer-head"
          ><div
            ><div class="eyebrow">NODE TELEMETRY</div><h2>{{ detail?.node.name || '-' }}</h2
            ><span>{{ detail?.node.uuid }}</span></div
          ><ElButton circle :icon="Close" aria-label="关闭" @click="drawerVisible = false"
        /></div>
        <ElAlert
          :title="detail?.disclaimer || '容量估算，未进行真实并发压测认证'"
          type="warning"
          :closable="false"
        />
        <template v-if="detail?.details">
          <section class="metric-section"
            ><div class="section-label">HOST & CONTAINER</div><h3>主机与容器</h3
            ><div class="metric-grid"
              ><div
                ><span>有效 CPU</span
                ><strong>{{ detail.details.host.effective_cpu_cores.toFixed(2) }} 核</strong></div
              ><div
                ><span>可用内存</span
                ><strong>{{ formatBytes(detail.details.host.memory_available_bytes) }}</strong></div
              ><div
                ><span>容器内存上限</span
                ><strong>{{
                  formatBytes(detail.details.host.container_memory_limit_bytes)
                }}</strong></div
              ><div
                ><span>文件描述符</span
                ><strong
                  >{{ formatNumber(detail.details.host.fd_used) }} /
                  {{ formatNumber(detail.details.host.fd_limit) }}</strong
                ></div
              ><div
                ><span>磁盘可用</span
                ><strong>{{ formatBytes(detail.details.host.disk_available_bytes) }}</strong></div
              ><div
                ><span>cgroup</span><strong>{{ detail.details.host.cgroup_version }}</strong></div
              ></div
            ></section
          >
          <section class="metric-section"
            ><div class="section-label">NETWORK & INGRESS</div><h3>网络与入口</h3
            ><div class="network-row"
              ><div
                ><span>网卡</span
                ><strong>{{ detail.details.host.network_interface || '-' }}</strong></div
              ><div
                ><span>链路能力</span
                ><strong>{{ formatBPS(detail.details.host.network_link_bps) }}</strong></div
              ><div
                ><span>证据来源</span
                ><strong>{{ evidenceLabel(detail.details.host.network_evidence) }}</strong></div
              ></div
            ></section
          >
          <section class="metric-section"
            ><div class="section-label">DEPENDENCIES</div><h3>应用与依赖</h3
            ><ElTable :data="dependencyRows" size="small"
              ><ElTableColumn prop="name" label="组件" width="110" /><ElTableColumn
                label="状态"
                width="90"
                ><template #default="{ row }"
                  ><ElTag :type="row.available ? 'success' : 'danger'" effect="light">{{
                    row.available ? '可用' : '异常'
                  }}</ElTag></template
                ></ElTableColumn
              ><ElTableColumn prop="endpoint" label="端点" min-width="140" /><ElTableColumn
                label="连接池"
                width="86"
                ><template #default="{ row }">{{
                  formatNumber(row.pool_limit)
                }}</template></ElTableColumn
              ><ElTableColumn label="保守 QPS" width="106"
                ><template #default="{ row }">{{
                  formatNumber(row.estimated_qps)
                }}</template></ElTableColumn
              ></ElTable
            ></section
          >
          <section v-if="detail.details.warnings?.length" class="metric-section"
            ><div class="section-label">WARNINGS</div><h3>检测提示</h3
            ><div class="warning-list"
              ><span v-for="item in detail.details.warnings" :key="item"
                ><ArtSvgIcon icon="ri:information-line" />{{ warningLabel(item) }}</span
              ></div
            ></section
          > </template
        ><ElEmpty v-else description="节点尚未上报有效采样" />
      </div>
    </ElDrawer>
  </div>
</template>

<script setup lang="ts">
  import { computed, onMounted, ref } from 'vue'
  import { Close, Refresh } from '@element-plus/icons-vue'
  import { useSettingStore } from '@/store/modules/setting'
  import {
    getCapacityNode,
    getCapacityNodes,
    type CapacityNodeDetails,
    type CapacityNodeItem
  } from '@/api/admin'
  defineOptions({ name: 'CapacityNodes' })
  const { isDark } = storeToRefs(useSettingStore())
  const loading = ref(false)
  const detailLoading = ref(false)
  const drawerVisible = ref(false)
  const nodes = ref<CapacityNodeItem[]>([])
  const detail = ref<CapacityNodeDetails>()
  const onlineCount = computed(() => nodes.value.filter((item) => !item.stale).length)
  const freshCount = computed(
    () => nodes.value.filter((item) => item.sample_status === 'fresh').length
  )
  const staleCount = computed(() => nodes.value.filter((item) => item.stale).length)
  const freshRatio = computed(() =>
    nodes.value.length ? Math.round((freshCount.value / nodes.value.length) * 100) : 0
  )
  const dependencyRows = computed(() =>
    Object.entries(detail.value?.details?.dependencies || {}).map(([name, value]) => ({
      name: dependencyLabel(name),
      ...value
    }))
  )
  async function loadNodes() {
    loading.value = true
    try {
      nodes.value = (await getCapacityNodes()).list
    } finally {
      loading.value = false
    }
  }
  async function openNode(row: CapacityNodeItem) {
    drawerVisible.value = true
    detailLoading.value = true
    try {
      detail.value = await getCapacityNode(row.uuid)
    } finally {
      detailLoading.value = false
    }
  }
  const ringStyle = (value: number, color: string) => {
    const track = isDark.value ? 'rgba(255,255,255,.08)' : 'rgba(148,163,184,.20)'
    return { background: `conic-gradient(${color} ${value}%, ${track} ${value}% 100%)` }
  }
  const formatNumber = (value?: number) => new Intl.NumberFormat('zh-CN').format(value || 0)
  const formatDateTime = (value?: string) =>
    value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '-'
  function formatBytes(value?: number) {
    if (!value) return '-'
    const units = ['B', 'KB', 'MB', 'GB', 'TB']
    const index = Math.min(Math.floor(Math.log(value) / Math.log(1024)), units.length - 1)
    return `${(value / 1024 ** index).toFixed(index > 2 ? 2 : 1)} ${units[index]}`
  }
  function formatBPS(value?: number) {
    if (!value) return '-'
    return value >= 1e9 ? `${(value / 1e9).toFixed(1)} Gbps` : `${(value / 1e6).toFixed(1)} Mbps`
  }
  const sampleTag = (value: string) =>
    value === 'fresh' ? 'success' : value === 'stale' ? 'warning' : 'info'
  const sampleLabel = (value: string) =>
    (({ fresh: '有效', stale: '已过期', missing: '未采样' }) as Record<string, string>)[value] ||
    value
  const dependencyLabel = (value: string) =>
    (({ mysql: 'MySQL', mongo: 'MongoDB', redis: 'Redis' }) as Record<string, string>)[value] ||
    value
  const evidenceLabel = (value: string) =>
    (
      ({ configured: '明确配置', nic_link_upper_bound: '网卡链路上限', unknown: '未知' }) as Record<
        string,
        string
      >
    )[value] || value
  const warningLabel = (value: string) =>
    (
      ({
        container_memory_limit_unknown: '未识别到容器内存上限，模型已应用保守折减',
        network_uses_nic_link_upper_bound: '网络值来自网卡链路上限，不代表公网可用带宽',
        network_capacity_unavailable: '未识别到可信网络容量'
      }) as Record<string, string>
    )[value] || value
  onMounted(loadNodes)
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
  .panel-head,
  .drawer-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 18px;
  }
  .hero-head {
    margin-bottom: 16px;
  }
  .eyebrow,
  .metric-kicker,
  .section-label {
    color: #6ee7ff;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1.4px;
  }
  .eyebrow-dot,
  .live-pill i {
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
  }
  h2 {
    margin: 5px 0;
    color: #f2f8ff;
    font-size: 18px;
  }
  h3 {
    margin: 6px 0 14px;
    color: #f2f8ff;
    font-size: 15px;
  }
  p {
    margin: 0;
    color: #88a0b8;
    font-size: 13px;
  }
  .head-actions {
    display: flex;
    gap: 8px;
  }
  .live-bar,
  .disclaimer,
  .fleet-card,
  .panel {
    border: 1px solid rgba(125, 176, 215, 0.2);
    background: rgba(10, 27, 43, 0.86);
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
  .disclaimer {
    margin: 14px 0;
    background: rgba(94, 63, 20, 0.3);
  }
  .fleet-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 14px;
  }
  .fleet-card {
    display: flex;
    align-items: center;
    gap: 13px;
    min-width: 0;
    padding: 16px;
  }
  .fleet-card span,
  .fleet-card small {
    display: block;
    color: #7f9ab3;
    font-size: 11px;
  }
  .fleet-card strong {
    display: block;
    margin: 7px 0 4px;
    color: #f2f8ff;
    font-size: 23px;
  }
  .fleet-icon {
    display: grid;
    place-items: center;
    width: 42px;
    height: 42px;
    border: 1px solid currentColor;
    border-radius: 50%;
    font-size: 18px;
  }
  .fleet-icon.green {
    color: #39d98a;
  }
  .fleet-icon.blue {
    color: #55b7ff;
  }
  .fleet-icon.amber {
    color: #ffb84d;
  }
  .mini-ring {
    display: grid;
    place-items: center;
    flex: 0 0 auto;
    width: 48px;
    height: 48px;
    border-radius: 50%;
  }
  .mini-ring b {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    border-radius: 50%;
    background: #0b1a2a;
    color: #f2f8ff;
    font-size: 13px;
  }
  .mini-ring small {
    font-size: 8px;
  }
  .panel {
    margin-top: 14px;
    padding: 20px;
  }
  .panel-head {
    align-items: flex-start;
    margin-bottom: 16px;
  }
  .panel-head p {
    margin-top: 5px;
  }
  .legend {
    display: flex;
    align-items: center;
    gap: 7px;
    color: #91aac2;
    font-size: 12px;
  }
  .legend i,
  .node-name i {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
  }
  i.online {
    background: #39d98a;
    box-shadow: 0 0 10px #39d98a;
  }
  i.stale {
    background: #ffb84d;
  }
  .node-name {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .node-name small {
    display: block;
  }
  .node-name + small {
    display: block;
    max-width: 220px;
    margin-top: 5px;
    overflow: hidden;
    color: #6f8aa2;
    text-overflow: ellipsis;
  }
  .drawer-content {
    min-height: 100%;
    padding: 24px;
    color: #e7f2ff;
    background: #07111e;
  }
  .drawer-head {
    align-items: flex-start;
    margin-bottom: 16px;
  }
  .metric-section {
    margin-top: 22px;
    padding-top: 20px;
    border-top: 1px solid rgba(137, 178, 210, 0.16);
  }
  .metric-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1px;
    overflow: hidden;
    border: 1px solid rgba(137, 178, 210, 0.16);
    background: rgba(137, 178, 210, 0.16);
  }
  .metric-grid > div,
  .network-row > div {
    min-width: 0;
    padding: 14px;
    background: #0a1b2b;
  }
  .metric-grid span,
  .network-row span {
    display: block;
    color: #7f9ab3;
    font-size: 11px;
  }
  .metric-grid strong,
  .network-row strong {
    display: block;
    margin-top: 7px;
    color: #eef8ff;
    font-size: 14px;
    overflow-wrap: anywhere;
  }
  .network-row {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    overflow: hidden;
    border: 1px solid rgba(137, 178, 210, 0.16);
    background: rgba(137, 178, 210, 0.16);
  }
  .warning-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .warning-list span {
    display: flex;
    gap: 8px;
    padding: 10px;
    color: #ffd38c;
    background: rgba(126, 81, 22, 0.25);
    font-size: 12px;
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
  :deep(.tech-drawer.el-drawer) {
    background: #07111e;
  }
  .capacity-page:not(.is-dark) {
    @include capacityTheme.light-page;

    .mini-ring b {
      background: #f8fafc;
    }
  }
  .drawer-content:not(.is-dark) {
    color: #243044;
    background: #f3f6fa;

    h2,
    h3,
    .metric-grid strong,
    .network-row strong {
      color: #152033;
    }

    .eyebrow,
    .section-label {
      color: #087f9d;
    }

    .metric-section,
    .metric-grid,
    .network-row {
      border-color: #dfe7ef;
    }

    .metric-grid,
    .network-row {
      background: #dfe7ef;
    }

    .metric-grid > div,
    .network-row > div {
      background: #fff;
    }

    .metric-grid span,
    .network-row span {
      color: #6b7c91;
    }

    .warning-list span {
      color: #8a5900;
      background: #fff6df;
    }

    :deep(.el-loading-mask) {
      background-color: rgb(248 250 252 / 84%);
    }

    :deep(.el-table),
    :deep(.el-table tr) {
      color: #344256;
      background: transparent;
    }

    :deep(.el-table th.el-table__cell) {
      color: #64748b;
      background: #f5f7fa;
    }
  }
  :deep(.tech-drawer.is-light.el-drawer) {
    background: #f3f6fa;
  }
  @media (max-width: 1050px) {
    .fleet-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }
  @media (max-width: 700px) {
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
    .network-row {
      grid-template-columns: 1fr;
    }
    .network-row > div + div {
      border-top: 1px solid rgba(137, 178, 210, 0.16);
    }
  }
  @media (max-width: 520px) {
    .capacity-page {
      padding: 12px;
    }
    .fleet-grid {
      grid-template-columns: 1fr;
    }
    .live-refresh {
      margin-left: 0;
    }
    .metric-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
