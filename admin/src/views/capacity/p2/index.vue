<template>
  <div class="capacity-page p2-page" :class="{ 'is-dark': isDark }">
    <header class="hero-head"
      ><div
        ><div class="eyebrow"><span class="eyebrow-dot" /> SYSTEM CAPACITY / CLUSTER CONTROL</div
        ><h1>集群与扩容</h1
        ><p>汇总在线节点、核对带宽证据，并在不修改真实配置的情况下推演扩容结果。</p></div
      ><ElButton type="primary" :icon="Refresh" :loading="loading" @click="load"
        >刷新集群</ElButton
      ></header
    >
    <div class="live-bar"
      ><span class="live-pill"><i /> CLUSTER CONTROL</span
      ><span>{{ cluster?.total_nodes || 0 }} 个节点</span
      ><span>在线 {{ cluster?.online_nodes || 0 }}</span
      ><span>N-1 容灾 {{ cluster?.online_nodes ? '可计算' : '等待节点' }}</span
      ><span class="live-refresh">模型 {{ history[0]?.model_version || '-' }}</span></div
    >
    <ElAlert
      title="容量估算，未进行真实并发压测认证"
      type="warning"
      :closable="false"
      show-icon
      class="disclaimer"
    />

    <section class="cluster-grid">
      <article class="cluster-card"
        ><div class="cluster-label">ONLINE NODES</div
        ><div class="cluster-value"
          >{{ cluster?.online_nodes ?? 0 }}<small> / {{ cluster?.total_nodes ?? 0 }}</small></div
        ><div class="cluster-line"><i :style="{ width: `${onlineRatio}%` }" /></div
        ><span>在线节点占比 {{ onlineRatio }}%</span></article
      >
      <article class="cluster-card"
        ><div class="cluster-label">N-1 RESILIENCE</div
        ><div class="cluster-value accent">{{ nMinusOneCapacity }}</div
        ><span>标准文本容灾建议值</span
        ><div class="cluster-chip">{{
          cluster?.online_nodes ? '故障预留已计算' : '等待有效节点'
        }}</div></article
      >
      <article class="cluster-card"
        ><div class="cluster-label">BANDWIDTH EVIDENCE</div
        ><div class="cluster-value">{{ bandwidth.length }}</div
        ><span>已授权带宽结果</span
        ><div class="cluster-chip" :class="bandwidth.length ? 'success' : 'muted'">{{
          bandwidth.length ? '证据可追溯' : '暂无结果'
        }}</div></article
      >
      <article class="cluster-card"
        ><div class="cluster-label">CAPACITY STATUS</div
        ><div class="status-orb" :class="cluster?.online_nodes ? 'online' : 'idle'"><i /></div
        ><div class="cluster-status">{{
          cluster?.online_nodes ? 'CLUSTER READY' : 'WAITING NODES'
        }}</div
        ><span>依赖共享状态需单独复核</span></article
      >
    </section>

    <section class="panel"
      ><div class="panel-head"
        ><div
          ><span class="metric-kicker">MULTI-NODE CAPACITY</span><h2>多节点容量</h2
          ><p>N-1 结果会预留单节点故障空间，共享依赖会降低可用置信度。</p></div
        ><ElTag effect="dark" type="info">N-1 MODEL</ElTag></div
      ><ElTable :data="cluster?.scenarios || []" size="small"
        ><ElTableColumn prop="scenario_name" label="场景" min-width="150" /><ElTableColumn
          label="在线建议值"
          width="140"
          ><template #default="{ row }"
            ><strong class="table-number">{{
              formatNumber(row.online_recommended)
            }}</strong></template
          ></ElTableColumn
        ><ElTableColumn label="N-1 建议值" width="135"
          ><template #default="{ row }"
            ><strong class="table-number amber">{{
              formatNumber(row.n_minus_one_recommended)
            }}</strong></template
          ></ElTableColumn
        ><ElTableColumn prop="bottleneck" label="主要瓶颈" min-width="130" /><ElTableColumn
          label="共享依赖"
          width="110"
          ><template #default="{ row }"
            ><ElTag :type="row.shared_dependency ? 'warning' : 'success'" effect="light">{{
              row.shared_dependency ? '需复核' : '独立'
            }}</ElTag></template
          ></ElTableColumn
        ></ElTable
      ><div v-if="cluster?.warnings?.length" class="warnings"
        ><ElTag v-for="warning in cluster.warnings" :key="warning" type="warning" effect="light">{{
          warning
        }}</ElTag></div
      ></section
    >

    <div class="columns"
      ><section class="panel"
        ><div class="panel-head"
          ><div
            ><span class="metric-kicker">BANDWIDTH PROOF</span><h2>带宽检测证据</h2
            ><p>仅展示经过授权并上报的受控结果，不把网卡链路上限当成公网带宽。</p></div
          ><span class="proof-mark">AUDITED</span></div
        ><ElTable :data="bandwidth" size="small" max-height="320"
          ><ElTableColumn prop="node_name" label="节点" min-width="120" /><ElTableColumn
            prop="endpoint_id"
            label="端点"
            min-width="110"
          /><ElTableColumn prop="status" label="状态" width="86" /><ElTableColumn
            label="下行"
            width="110"
            ><template #default="{ row }">{{
              formatBps(row.download_bps)
            }}</template></ElTableColumn
          ><ElTableColumn label="上行" width="110"
            ><template #default="{ row }">{{ formatBps(row.upload_bps) }}</template></ElTableColumn
          ></ElTable
        ><ElEmpty v-if="!bandwidth.length" description="暂无授权带宽检测结果" :image-size="64"
      /></section>

      <section class="panel simulator"
        ><div class="panel-head"
          ><div
            ><span class="metric-kicker">EXPANSION LAB</span><h2>扩容模拟</h2
            ><p>结果只存在于当前页面，不会修改服务器真实配置。</p></div
          ><span class="simulator-mark">SIMULATION</span></div
        ><ElForm label-position="top" @submit.prevent
          ><ElFormItem label="评估编号"
            ><ElSelect v-model="simulation.assessment_uuid" filterable placeholder="选择已完成评估"
              ><ElOption
                v-for="item in history"
                :key="item.uuid"
                :label="`${item.uuid.slice(0, 8)} · ${item.capacity_recommended.toLocaleString()}`"
                :value="item.uuid" /></ElSelect></ElFormItem
          ><div class="form-grid"
            ><ElFormItem label="新增 API 节点"
              ><ElInputNumber v-model="simulation.add_api_nodes" :min="0" :max="100" /></ElFormItem
            ><ElFormItem label="内存增加比例"
              ><ElInputNumber
                v-model="simulation.memory_increase_ratio"
                :min="0"
                :max="10"
                :step="0.1" /></ElFormItem
            ><ElFormItem label="带宽增加比例"
              ><ElInputNumber
                v-model="simulation.bandwidth_increase_ratio"
                :min="0"
                :max="10"
                :step="0.1" /></ElFormItem
            ><ElFormItem label="依赖容量增加比例"
              ><ElInputNumber
                v-model="simulation.database_capacity_ratio"
                :min="0"
                :max="10"
                :step="0.1" /></ElFormItem></div
          ><ElButton
            type="primary"
            :icon="MagicStick"
            :loading="simulating"
            :disabled="!simulation.assessment_uuid"
            @click="runSimulation"
            >生成模拟结果</ElButton
          ></ElForm
        ><ElTable
          v-if="simulationResult"
          :data="simulationResult.scenarios"
          size="small"
          class="simulation-table"
          ><ElTableColumn prop="scenario_name" label="场景" min-width="110" /><ElTableColumn
            label="基线"
            width="100"
            ><template #default="{ row }">{{ formatNumber(row.baseline) }}</template></ElTableColumn
          ><ElTableColumn label="模拟" width="100"
            ><template #default="{ row }"
              ><strong class="table-number">{{ formatNumber(row.simulated) }}</strong></template
            ></ElTableColumn
          ></ElTable
        ></section
      ></div
    >

    <section class="panel history-panel"
      ><div class="panel-head"
        ><div
          ><span class="metric-kicker">ASSESSMENT HISTORY</span><h2>历史评估</h2
          ><p>模型版本不同的结果不能直接横向比较。</p></div
        ><span class="history-count">{{ history.length }} RECORDS</span></div
      ><ElTable :data="history" size="small"
        ><ElTableColumn label="完成时间" min-width="170"
          ><template #default="{ row }">{{ formatDate(row.finished_at) }}</template></ElTableColumn
        ><ElTableColumn prop="trigger_type" label="触发方式" width="110" /><ElTableColumn
          prop="model_version"
          label="模型"
          width="100" /><ElTableColumn label="建议值" width="110"
          ><template #default="{ row }">{{
            formatNumber(row.capacity_recommended)
          }}</template></ElTableColumn
        ><ElTableColumn prop="confidence_grade" label="置信度" width="90" /><ElTableColumn
          prop="node_count"
          label="节点数"
          width="90" /></ElTable
    ></section>
  </div>
</template>

<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { MagicStick, Refresh } from '@element-plus/icons-vue'
  import { ElMessage } from 'element-plus'
  import { useSettingStore } from '@/store/modules/setting'
  import {
    getCapacityBandwidthResults,
    getCapacityCluster,
    getCapacityHistory,
    simulateCapacityExpansion,
    type CapacityBandwidthResultItem,
    type CapacityClusterResponse,
    type CapacityExpansionSimulation,
    type CapacityHistoryItem
  } from '@/api/admin'
  defineOptions({ name: 'CapacityP2' })
  const { isDark } = storeToRefs(useSettingStore())
  const loading = ref(false)
  const simulating = ref(false)
  const cluster = ref<CapacityClusterResponse>()
  const bandwidth = ref<CapacityBandwidthResultItem[]>([])
  const history = ref<CapacityHistoryItem[]>([])
  const simulationResult = ref<CapacityExpansionSimulation>()
  const simulation = reactive({
    assessment_uuid: '',
    add_api_nodes: 0,
    memory_increase_ratio: 0,
    bandwidth_increase_ratio: 0,
    database_capacity_ratio: 0
  })
  const onlineRatio = computed(() =>
    cluster.value?.total_nodes
      ? Math.round((cluster.value.online_nodes / cluster.value.total_nodes) * 100)
      : 0
  )
  const nMinusOneCapacity = computed(() => {
    const item = cluster.value?.scenarios?.find(
      (scenario) => scenario.scenario_id === 'standard_text'
    )
    return formatNumber(item?.n_minus_one_recommended)
  })
  async function load() {
    loading.value = true
    try {
      ;[cluster.value, bandwidth.value, history.value] = await Promise.all([
        getCapacityCluster(),
        getCapacityBandwidthResults().then((value) => value.list),
        getCapacityHistory().then((value) => value.list)
      ])
    } finally {
      loading.value = false
    }
  }
  async function runSimulation() {
    simulating.value = true
    try {
      simulationResult.value = await simulateCapacityExpansion(simulation)
      ElMessage.success('扩容模拟已生成')
    } finally {
      simulating.value = false
    }
  }
  const formatNumber = (value?: number) => new Intl.NumberFormat('zh-CN').format(value || 0)
  const formatBps = (value?: number) =>
    !value
      ? '-'
      : value >= 1e9
        ? `${(value / 1e9).toFixed(1)} Gbps`
        : `${(value / 1e6).toFixed(1)} Mbps`
  const formatDate = (value?: string) =>
    value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '-'
  onMounted(load)
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
  .panel-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 18px;
  }
  .hero-head {
    margin-bottom: 16px;
  }
  .eyebrow,
  .metric-kicker {
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
  p {
    margin: 0;
    color: #88a0b8;
    font-size: 13px;
  }
  .live-bar,
  .disclaimer,
  .cluster-card,
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
  .cluster-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 14px;
  }
  .cluster-card {
    min-width: 0;
    min-height: 150px;
    padding: 17px;
  }
  .cluster-label {
    color: #7b9bb7;
    font-size: 10px;
    letter-spacing: 1.3px;
  }
  .cluster-value {
    margin: 17px 0 5px;
    color: #f2f8ff;
    font-size: 29px;
    font-weight: 750;
  }
  .cluster-value small {
    color: #7f9ab3;
    font-size: 15px;
    font-weight: 400;
  }
  .cluster-value.accent {
    color: #ffca70;
  }
  .cluster-card > span {
    color: #7f9ab3;
    font-size: 11px;
  }
  .cluster-line {
    height: 6px;
    margin: 14px 0 7px;
    overflow: hidden;
    border-radius: 99px;
    background: rgba(255, 255, 255, 0.08);
  }
  .cluster-line i {
    display: block;
    height: 100%;
    border-radius: inherit;
    background: #39d98a;
    box-shadow: 0 0 12px rgba(57, 217, 138, 0.75);
  }
  .cluster-chip {
    display: inline-block;
    margin-top: 15px;
    padding: 4px 7px;
    color: #ffd38c;
    border: 1px solid rgba(255, 184, 77, 0.35);
    border-radius: 999px;
    font-size: 10px;
  }
  .cluster-chip.success {
    color: #a9ffd2;
    border-color: rgba(57, 217, 138, 0.35);
  }
  .cluster-chip.muted {
    color: #9bb1c6;
    border-color: rgba(137, 178, 210, 0.25);
  }
  .status-orb {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    margin: 13px 0 8px;
    border: 1px solid #39d98a;
    border-radius: 50%;
  }
  .status-orb i {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: #39d98a;
    box-shadow: 0 0 16px #39d98a;
  }
  .status-orb.idle {
    border-color: #778da1;
  }
  .status-orb.idle i {
    background: #778da1;
    box-shadow: none;
  }
  .cluster-status {
    margin-bottom: 5px;
    color: #a9ffd2;
    font-size: 13px;
    font-weight: 750;
    letter-spacing: 0.7px;
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
  .proof-mark,
  .simulator-mark,
  .history-count {
    color: #6ee7ff;
    font-size: 10px;
    letter-spacing: 1px;
  }
  .columns {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(380px, 1fr);
    gap: 14px;
  }
  .warnings {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-top: 12px;
  }
  .form-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0 12px;
  }
  .simulation-table {
    margin-top: 16px;
  }
  .table-number {
    color: #6ee7ff;
  }
  .table-number.amber {
    color: #ffca70;
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
  :deep(.el-form-item__label) {
    color: #91aac2;
  }
  :deep(.el-input__wrapper),
  :deep(.el-select__wrapper) {
    background: #0b1a2a;
    box-shadow: 0 0 0 1px rgba(125, 176, 215, 0.22) inset;
  }
  :deep(.el-input__inner),
  :deep(.el-select__selected-item) {
    color: #e7f2ff;
  }
  .capacity-page:not(.is-dark) {
    @include capacityTheme.light-page;
  }
  @media (max-width: 1100px) {
    .cluster-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
    .columns {
      grid-template-columns: 1fr;
    }
  }
  @media (max-width: 650px) {
    .capacity-page {
      padding: 16px;
    }
    .hero-head {
      align-items: flex-start;
      flex-direction: column;
    }
    .cluster-grid {
      grid-template-columns: 1fr;
    }
    .form-grid {
      grid-template-columns: 1fr;
    }
    .live-refresh {
      margin-left: 0;
    }
  }
  @media (max-width: 520px) {
    .capacity-page {
      padding: 12px;
    }
  }
</style>
