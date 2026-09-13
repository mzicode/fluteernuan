<template>
  <div class="governance-page">
    <section class="page-head">
      <div class="page-title-group">
        <span class="page-title-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:database-2-line" />
        </span>
        <div>
          <p>系统配置 / 数据运维</p>
          <h1>数据治理中心</h1>
          <span>查看数据保留、媒体资产、清理门禁和执行记录。</span>
        </div>
      </div>
      <div class="head-actions">
        <ElTag :type="runtimeEnvironment.type" effect="dark" class="environment-tag">
          {{ runtimeEnvironment.label }}
        </ElTag>
        <div class="sync-status">
          <span class="sync-dot" aria-hidden="true" />
          <span>治理数据已连接</span>
          <small>{{ updatedText }}</small>
        </div>
        <ElButton type="primary" :icon="Refresh" :loading="pageLoading" @click="refreshAll">
          刷新数据
        </ElButton>
      </div>
    </section>

    <nav class="workspace-launcher" aria-label="数据治理工作区">
      <button
        type="button"
        class="workspace-entry workspace-entry--overview"
        :class="{ 'is-active': activeWorkspace === 'overview' }"
        @click="goToWorkspace('overview')"
      >
        <span class="workspace-entry-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:dashboard-3-line" />
        </span>
        <span class="workspace-entry-copy">
          <strong>治理总览</strong>
          <small>容量、健康评分与增长趋势</small>
        </span>
        <ArtSvgIcon class="workspace-entry-arrow" icon="ri:arrow-right-s-line" />
      </button>
      <button
        type="button"
        class="workspace-entry workspace-entry--cleanup"
        :class="{ 'is-active': activeWorkspace === 'cleanup' }"
        @click="goToWorkspace('cleanup')"
      >
        <span class="workspace-entry-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:delete-bin-6-line" />
        </span>
        <span class="workspace-entry-copy">
          <strong>待清理数据</strong>
          <small>{{ formatNumber(preview?.total_would_delete) }} 条可执行候选</small>
        </span>
        <ArtSvgIcon class="workspace-entry-arrow" icon="ri:arrow-right-s-line" />
      </button>
      <button
        type="button"
        class="workspace-entry workspace-entry--media"
        :class="{ 'is-active': activeWorkspace === 'media' }"
        @click="goToWorkspace('media')"
      >
        <span class="workspace-entry-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:folder-image-line" />
        </span>
        <span class="workspace-entry-copy">
          <strong>文件管理与预览</strong>
          <small> {{ formatNumber(mediaSummary.local_count) }} 个本地文件，可查看图片和视频 </small>
        </span>
        <ArtSvgIcon class="workspace-entry-arrow" icon="ri:arrow-right-s-line" />
      </button>
    </nav>

    <section ref="overviewSectionRef" class="overview-card">
      <div class="overview-head">
        <div>
          <h2>治理概览</h2>
          <p>数据库候选记录和媒体存储的实时统计</p>
        </div>
        <span class="overview-time">清单生成于 {{ formatDateTime(preview?.generated_at) }}</span>
      </div>
      <div class="data-orb-grid" aria-label="数据治理核心指标">
        <article class="data-orb tone-indigo">
          <span>过期候选</span>
          <strong>{{ formatNumber(preview?.total_candidates) }}</strong>
          <small>条记录</small>
        </article>
        <article class="data-orb tone-rose">
          <span>本次最多删除</span>
          <strong>{{ formatNumber(preview?.total_would_delete) }}</strong>
          <small>条记录</small>
        </article>
        <article class="data-orb tone-amber">
          <span>上限保护</span>
          <strong>{{ formatNumber(preview?.total_protected) }}</strong>
          <small>条记录</small>
        </article>
        <article class="data-orb tone-violet">
          <span>预计释放空间</span>
          <strong>{{ formatBytes(preview?.total_recorded_bytes) }}</strong>
          <small>当前可核算媒体记录</small>
        </article>
        <article class="data-orb tone-cyan">
          <span>媒体资产</span>
          <strong>{{ formatNumber(mediaTotal) }}</strong>
          <small>个对象</small>
        </article>
        <article class="data-orb tone-emerald">
          <span>本地媒体容量</span>
          <strong>{{ formatBytes(mediaSummary.local_bytes) }}</strong>
          <small>{{ formatNumber(mediaSummary.local_count) }} 个本地对象</small>
        </article>
      </div>
    </section>

    <section class="capacity-risk-card">
      <div class="capacity-head">
        <div>
          <h2>容量风险</h2>
          <p>来自容量 Agent 的真实磁盘采样，耗尽时间按最近增长速度估算</p>
        </div>
        <ElRadioGroup v-model="capacityWindow" size="small" @change="loadCapacity">
          <ElRadioButton :value="7">近 7 天</ElRadioButton>
          <ElRadioButton :value="30">近 30 天</ElRadioButton>
        </ElRadioGroup>
      </div>
      <div v-loading="capacityLoading" class="capacity-body">
        <div class="disk-ring" :style="diskRingStyle">
          <div class="disk-ring-inner">
            <strong>{{ diskUsageText }}</strong>
            <span>磁盘使用率</span>
          </div>
        </div>
        <div class="capacity-facts">
          <article>
            <span>磁盘剩余</span>
            <strong>{{ formatBytes(capacity?.disk.available_bytes) }}</strong>
            <small>总容量 {{ formatBytes(capacity?.disk.total_bytes) }}</small>
          </article>
          <article :class="capacityRiskTone">
            <span>预计可用天数</span>
            <strong>{{ remainingDaysText }}</strong>
            <small>{{ exhaustDateText }}</small>
          </article>
          <article>
            <span>日均增长</span>
            <strong>{{ formatBytes(capacity?.forecast.average_daily_growth_bytes) }}</strong>
            <small>{{ forecastBasisText }}</small>
          </article>
          <article>
            <span>采样状态</span>
            <strong>{{ capacitySampleState }}</strong>
            <small>{{ formatDateTime(capacity?.disk.sample_at) }}</small>
          </article>
        </div>
      </div>
    </section>

    <section class="insights-grid">
      <article class="insight-card health-score-card">
        <div class="insight-head">
          <div>
            <h2>治理健康评分</h2>
            <p>根据容量、备份、清单和异常数据综合计算</p>
          </div>
          <ElTag :type="governanceHealth.tag" effect="plain">{{ governanceHealth.label }}</ElTag>
        </div>
        <div class="health-score-main">
          <div class="health-score-ring" :style="healthScoreStyle">
            <div>
              <strong>{{ governanceHealth.score }}</strong>
              <span>分</span>
            </div>
          </div>
          <ul class="health-reasons">
            <li v-for="reason in governanceHealth.reasons" :key="reason.text">
              <i :class="reason.tone" aria-hidden="true" />
              <span>{{ reason.text }}</span>
            </li>
          </ul>
        </div>
      </article>

      <article class="insight-card trend-card">
        <div class="insight-head">
          <div>
            <h2>增长与清理趋势</h2>
            <p>媒体新增容量、治理日志与每日清理结果</p>
          </div>
          <ElRadioGroup v-model="insightsWindow" size="small" @change="loadInsights">
            <ElRadioButton :value="7">7 天</ElRadioButton>
            <ElRadioButton :value="30">30 天</ElRadioButton>
          </ElRadioGroup>
        </div>
        <div v-loading="insightsLoading" class="trend-chart-wrap">
          <div v-show="insights?.trend.length" ref="trendChartRef" class="trend-chart" />
          <ElEmpty v-if="!insightsLoading && !insights?.trend.length" description="暂无趋势数据" />
        </div>
      </article>

      <article class="insight-card distribution-card">
        <div class="insight-head">
          <div>
            <h2>媒体占用排行</h2>
            <p>按当前有效媒体容量统计</p>
          </div>
        </div>
        <div class="distribution-list">
          <div v-for="item in distributionRows" :key="item.kind" class="distribution-item">
            <div>
              <span>{{ mediaKindLabel(item.kind) }}</span>
              <strong>{{ formatBytes(item.bytes) }}</strong>
            </div>
            <div class="distribution-track">
              <i :style="{ width: `${item.percent}%` }" />
            </div>
            <small>{{ formatNumber(item.count) }} 个 · {{ item.percent.toFixed(1) }}%</small>
          </div>
          <ElEmpty v-if="!distributionRows.length" description="暂无媒体统计" />
        </div>
      </article>
    </section>

    <section class="safety-bar">
      <div class="safety-state">
        <ElTag :type="maintenance?.config.enabled ? 'success' : 'info'" effect="plain">
          自动任务{{ maintenance?.config.enabled ? '已开启' : '已关闭' }}
        </ElTag>
        <ElTag :type="maintenance?.config.dry_run ? 'warning' : 'danger'" effect="plain">
          {{ maintenance?.config.dry_run ? '自动预演模式' : '自动正式模式' }}
        </ElTag>
        <ElTag :type="backupReady ? 'success' : 'danger'" effect="plain">
          备份门禁{{ backupReady ? '已就绪' : '未就绪' }}
        </ElTag>
        <ElTag :type="previewFresh ? 'success' : 'warning'" effect="plain">
          清理清单{{ previewFresh ? '有效' : '已过期' }}
        </ElTag>
      </div>
      <p>{{ safetyMessage }}</p>
    </section>

    <div ref="workspaceTabsRef" class="workspace-tabs-anchor">
      <ElTabs v-model="activeTab" class="governance-tabs" @tab-change="handleWorkspaceTabChange">
        <ElTabPane label="待清理数据" name="cleanup">
          <section class="panel panel--cleanup">
            <div class="panel-head">
              <div>
                <h2>正式清理清单</h2>
                <p>展示真实候选数量、截止时间、保护数量和样本记录；清单有效期为 10 分钟。</p>
              </div>
              <div class="panel-actions">
                <ElButton :icon="Refresh" :loading="previewLoading" @click="loadPreview">
                  重新生成清单
                </ElButton>
                <ElButton
                  type="primary"
                  plain
                  :disabled="isDemoAdmin"
                  :loading="actionLoading"
                  @click="runDryPreview"
                >
                  写入预演审计
                </ElButton>
              </div>
            </div>

            <ElAlert
              v-if="cleanupError"
              :title="cleanupError"
              type="warning"
              show-icon
              :closable="false"
              class="panel-alert"
            />

            <div class="danger-zone">
              <span class="danger-zone-icon" aria-hidden="true">
                <ArtSvgIcon icon="ri:delete-bin-6-line" />
              </span>
              <div class="danger-zone-copy">
                <strong>正式清理危险操作</strong>
                <p>永久删除当前清单内的过期数据，仅超级管理员可执行。</p>
                <div v-if="formalBlockers.length" class="formal-blockers">
                  <ElTag
                    v-for="reason in formalBlockers"
                    :key="reason"
                    type="danger"
                    effect="plain"
                  >
                    {{ reason }}
                  </ElTag>
                </div>
                <ElTag v-else type="success" effect="plain">所有执行门禁均已通过</ElTag>
              </div>
              <ElButton
                type="danger"
                :icon="Delete"
                :disabled="!canRunFormal"
                :loading="actionLoading"
                @click="runFormalCleanup"
              >
                按当前清单正式清理
              </ElButton>
            </div>

            <ElTable v-loading="previewLoading" :data="preview?.jobs || []" row-key="job_name">
              <ElTableColumn type="expand">
                <template #default="{ row }">
                  <div class="sample-wrap">
                    <div class="sample-head">
                      <strong>候选样本（最多展示 10 条）</strong>
                      <span>截止：{{ formatDateTime(row.cutoff_at) }}</span>
                    </div>
                    <ElTable :data="row.samples" size="small" border>
                      <ElTableColumn prop="id" label="记录 ID" width="110" />
                      <ElTableColumn label="过期依据时间" min-width="180">
                        <template #default="scope">{{
                          formatDateTime(scope.row.expired_at)
                        }}</template>
                      </ElTableColumn>
                      <ElTableColumn prop="original_name" label="文件名" min-width="150">
                        <template #default="scope">{{ scope.row.original_name || '-' }}</template>
                      </ElTableColumn>
                      <ElTableColumn
                        prop="object_key"
                        label="媒体路径"
                        min-width="260"
                        show-overflow-tooltip
                      >
                        <template #default="scope">{{ scope.row.object_key || '-' }}</template>
                      </ElTableColumn>
                      <ElTableColumn label="记录大小" width="110" align="right">
                        <template #default="scope">{{
                          formatBytes(scope.row.size_bytes)
                        }}</template>
                      </ElTableColumn>
                    </ElTable>
                  </div>
                </template>
              </ElTableColumn>
              <ElTableColumn label="治理任务" min-width="220">
                <template #default="{ row }">
                  <div class="job-name">
                    <strong>{{ jobLabel(row.job_name) }}</strong>
                    <small>{{ row.job_name }}</small>
                  </div>
                </template>
              </ElTableColumn>
              <ElTableColumn label="保留周期" width="110">
                <template #default="{ row }">{{ row.retention_days }} 天</template>
              </ElTableColumn>
              <ElTableColumn label="候选" width="110" align="right">
                <template #default="{ row }">{{ formatNumber(row.candidate_count) }}</template>
              </ElTableColumn>
              <ElTableColumn label="本次删除" width="120" align="right">
                <template #default="{ row }">
                  <strong class="danger-number">{{ formatNumber(row.would_delete_count) }}</strong>
                </template>
              </ElTableColumn>
              <ElTableColumn label="受保护" width="110" align="right">
                <template #default="{ row }">{{ formatNumber(row.protected_count) }}</template>
              </ElTableColumn>
              <ElTableColumn label="媒体记录大小" width="140" align="right">
                <template #default="{ row }">{{ formatBytes(row.recorded_bytes) }}</template>
              </ElTableColumn>
              <ElTableColumn label="截止时间" min-width="180">
                <template #default="{ row }">{{ formatDateTime(row.cutoff_at) }}</template>
              </ElTableColumn>
            </ElTable>
          </section>

          <section class="panel panel--history history-panel">
            <div class="panel-head">
              <div>
                <h2>清理执行审计</h2>
                <p>保留预演、正式执行、删除数量、上限跳过和错误信息。</p>
              </div>
            </div>
            <div class="audit-timeline">
              <article v-for="run in maintenance?.runs || []" :key="run.id" class="audit-event">
                <span
                  class="audit-marker"
                  :class="`audit-marker--${run.status}`"
                  aria-hidden="true"
                />
                <div class="audit-event-main">
                  <div class="audit-event-title">
                    <strong>{{ jobLabel(run.job_name) }}</strong>
                    <ElTag :type="statusTag(run.status)" effect="light" size="small">
                      {{ statusLabel(run.status) }}
                    </ElTag>
                    <time>{{ formatDateTime(run.started_at) }}</time>
                  </div>
                  <div class="audit-event-stats">
                    <span>候选 {{ formatNumber(run.candidate_count) }}</span>
                    <span>删除 {{ formatNumber(run.deleted_count) }}</span>
                    <span>跳过 {{ formatNumber(run.skipped_count) }}</span>
                    <span v-if="run.error" class="audit-error">{{ run.error }}</span>
                  </div>
                </div>
              </article>
              <ElEmpty v-if="!maintenance?.runs?.length" description="暂无治理执行记录" />
            </div>
          </section>
        </ElTabPane>

        <ElTabPane label="文件管理与预览" name="media">
          <section class="panel panel--media">
            <div class="panel-head media-panel-head">
              <div>
                <h2>文件管理与预览</h2>
                <p>本地文件通过后台同源地址访问；云存储文件使用已登记的公开地址。</p>
              </div>
              <div class="media-filter">
                <ElInput
                  v-model="mediaFilters.search"
                  clearable
                  placeholder="文件名、Media ID 或路径"
                  @keyup.enter="applyMediaFilters"
                />
                <ElSelect
                  v-model="mediaFilters.kind"
                  placeholder="文件类型"
                  clearable
                  @change="applyMediaFilters"
                >
                  <ElOption label="图片" value="image" />
                  <ElOption label="视频" value="video" />
                  <ElOption label="音频" value="audio" />
                </ElSelect>
                <ElSelect
                  v-model="mediaFilters.provider"
                  placeholder="存储位置"
                  clearable
                  @change="applyMediaFilters"
                >
                  <ElOption label="本地存储" value="local" />
                  <ElOption label="阿里云 OSS" value="aliyun" />
                  <ElOption label="七牛云" value="qiniu" />
                  <ElOption label="S3" value="s3" />
                </ElSelect>
                <ElSelect
                  v-model="mediaFilters.status"
                  placeholder="生命周期状态"
                  clearable
                  @change="applyMediaFilters"
                >
                  <ElOption label="已绑定" value="bound" />
                  <ElOption label="待绑定" value="uploaded" />
                  <ElOption label="清理中" value="deleting" />
                  <ElOption label="已删除" value="deleted" />
                  <ElOption label="失败" value="failed" />
                </ElSelect>
                <ElSelect
                  v-model="mediaFilters.special"
                  placeholder="专项筛选"
                  clearable
                  @change="applyMediaFilters"
                >
                  <ElOption label="大文件（≥50MB）" value="large" />
                  <ElOption label="长期未更新（90天）" value="stale" />
                </ElSelect>
                <ElRadioGroup v-model="mediaView" size="small">
                  <ElRadioButton value="card">卡片</ElRadioButton>
                  <ElRadioButton value="list">列表</ElRadioButton>
                </ElRadioGroup>
                <ElButton type="primary" @click="applyMediaFilters">查询</ElButton>
              </div>
            </div>

            <div class="media-summary">
              <span
                >图片 <b>{{ formatNumber(mediaSummary.image_count) }}</b></span
              >
              <span
                >视频 <b>{{ formatNumber(mediaSummary.video_count) }}</b></span
              >
              <span
                >总登记容量 <b>{{ formatBytes(mediaSummary.total_bytes) }}</b></span
              >
              <span
                >待处理异常 <b>{{ formatNumber(mediaSummary.cleanup_pending_count) }}</b></span
              >
              <span
                >已删除记录 <b>{{ formatNumber(mediaSummary.deleted_count) }}</b></span
              >
            </div>

            <div
              v-loading="mediaLoading"
              class="media-grid"
              :class="{ 'media-grid--list': mediaView === 'list' }"
            >
              <article v-for="item in mediaItems" :key="item.media_id" class="media-card">
                <div class="media-preview">
                  <ElImage
                    v-if="item.file_kind === 'image' && item.accessible"
                    :src="mediaAccessUrl(item)"
                    :preview-src-list="[mediaAccessUrl(item)]"
                    preview-teleported
                    fit="cover"
                    loading="lazy"
                  >
                    <template #error><div class="preview-fallback">图片加载失败</div></template>
                  </ElImage>
                  <video
                    v-else-if="item.file_kind === 'video' && item.accessible"
                    :src="mediaAccessUrl(item)"
                    controls
                    preload="metadata"
                  />
                  <div v-else class="preview-fallback">
                    <ArtSvgIcon :icon="fileIcon(item.file_kind)" />
                    <span>{{ item.accessible ? '文件可访问' : '文件不可访问或已回收' }}</span>
                  </div>
                  <ElTag class="media-status" :type="mediaStatusTag(item.status)" size="small">
                    {{ mediaStatusLabel(item.status) }}
                  </ElTag>
                  <ElTag class="media-provider" type="info" size="small" effect="dark">
                    {{ providerLabel(item.provider) }}
                  </ElTag>
                </div>
                <div class="media-info">
                  <strong :title="item.original_name || item.object_key">
                    {{ item.original_name || fileName(item.object_key) }}
                  </strong>
                  <p :title="item.object_key">{{ item.object_key }}</p>
                  <div class="media-meta">
                    <span>{{ formatBytes(item.size_bytes) }}</span>
                    <span>{{ item.detected_mime || item.category }}</span>
                    <span>{{ formatDateTime(item.created_at) }}</span>
                  </div>
                  <div class="media-foot">
                    <span v-if="item.provider === 'local'">
                      本地文件：{{ item.file_exists ? '存在' : '不存在' }}
                    </span>
                    <span v-else>云端对象</span>
                    <ElButton
                      link
                      type="primary"
                      :disabled="!item.accessible"
                      @click="openMedia(item)"
                    >
                      新窗口打开
                    </ElButton>
                  </div>
                </div>
              </article>
              <ElEmpty
                v-if="!mediaLoading && mediaItems.length === 0"
                description="没有匹配的媒体文件"
              />
            </div>

            <ElPagination
              v-model:current-page="mediaPage"
              :page-size="mediaPageSize"
              :total="mediaTotal"
              layout="total, prev, pager, next"
              background
              class="media-pagination"
              @current-change="loadMedia"
            />
          </section>
        </ElTabPane>
      </ElTabs>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
  import { Delete, Refresh } from '@element-plus/icons-vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { echarts, type EChartsOption } from '@/plugins/echarts'
  import { useUserStore } from '@/store/modules/user'
  import {
    getDataGovernanceCapacity,
    getDataGovernanceInsights,
    getMaintenancePreview,
    getMaintenanceStatus,
    getMediaObjects,
    runMaintenanceDryRun,
    runMaintenanceFormal,
    type DataGovernanceCapacityResponse,
    type DataGovernanceInsightsResponse,
    type MaintenanceCleanupPreview,
    type MaintenanceJobRun,
    type MaintenanceStatusResponse,
    type MediaObjectItem,
    type MediaObjectSummary
  } from '@/api/admin'

  defineOptions({ name: 'DataGovernanceCenter' })

  const emptyMediaSummary = (): MediaObjectSummary => ({
    total_bytes: 0,
    local_count: 0,
    local_bytes: 0,
    image_count: 0,
    video_count: 0,
    deleted_count: 0,
    cleanup_pending_count: 0
  })

  const userStore = useUserStore()
  const activeTab = ref('cleanup')
  const activeWorkspace = ref<'overview' | 'cleanup' | 'media'>('overview')
  const overviewSectionRef = ref<HTMLElement>()
  const workspaceTabsRef = ref<HTMLElement>()
  const pageLoading = ref(false)
  const previewLoading = ref(false)
  const actionLoading = ref(false)
  const mediaLoading = ref(false)
  const capacityLoading = ref(false)
  const insightsLoading = ref(false)
  const cleanupError = ref('')
  const maintenance = ref<MaintenanceStatusResponse | null>(null)
  const preview = ref<MaintenanceCleanupPreview | null>(null)
  const mediaItems = ref<MediaObjectItem[]>([])
  const mediaSummary = ref<MediaObjectSummary>(emptyMediaSummary())
  const mediaTotal = ref(0)
  const mediaPage = ref(1)
  const mediaPageSize = 12
  const capacityWindow = ref<7 | 30>(30)
  const insightsWindow = ref<7 | 30>(30)
  const capacity = ref<DataGovernanceCapacityResponse | null>(null)
  const insights = ref<DataGovernanceInsightsResponse | null>(null)
  const trendChartRef = ref<HTMLElement>()
  const mediaView = ref<'card' | 'list'>('card')
  const lastUpdatedAt = ref<Date | null>(null)
  const nowTick = ref(Date.now())
  const mediaFilters = reactive({ search: '', kind: '', provider: '', status: '', special: '' })
  let trendChart: ReturnType<typeof echarts.init> | null = null

  const isDemoAdmin = computed(() => userStore.info.roles?.includes('R_DEMO') === true)
  const isSuperAdmin = computed(() => userStore.info.roles?.includes('R_SUPER') === true)
  const backupReady = computed(() => maintenance.value?.backup_gate.ready === true)
  const previewFresh = computed(() => {
    if (!preview.value?.preview_token || !preview.value.expires_at) return false
    return new Date(preview.value.expires_at).getTime() > nowTick.value
  })
  const runtimeEnvironment = computed(() => {
    const hostname = window.location.hostname.toLowerCase()
    const local = hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1'
    return local
      ? { label: '本地环境', type: 'info' as const }
      : { label: '生产环境', type: 'danger' as const }
  })
  const formalBlockers = computed(() => {
    const reasons: string[] = []
    if (isDemoAdmin.value) reasons.push('演示管理员禁止执行')
    else if (!isSuperAdmin.value) reasons.push('仅超级管理员可执行')
    if (!backupReady.value) reasons.push('备份门禁未就绪')
    if (!previewFresh.value) reasons.push('清理清单无效或已过期')
    if (Number(preview.value?.total_would_delete || 0) <= 0) reasons.push('当前没有可清理数据')
    return reasons
  })
  const canRunFormal = computed(() => formalBlockers.value.length === 0)
  const diskUsage = computed(() =>
    Math.min(100, Math.max(0, Number(capacity.value?.disk.usage_percent || 0)))
  )
  const diskUsageText = computed(() =>
    capacity.value?.disk.available ? `${diskUsage.value.toFixed(1)}%` : '暂无采样'
  )
  const diskRingStyle = computed(() => ({
    '--disk-progress': `${diskUsage.value * 3.6}deg`,
    '--disk-color':
      diskUsage.value >= 90 ? '#dc2626' : diskUsage.value >= 80 ? '#d97706' : '#2563eb'
  }))
  const remainingDaysText = computed(() => {
    const days = capacity.value?.forecast.days_remaining
    if (days === null || days === undefined) return '暂无法预测'
    if (days >= 3650) return '10 年以上'
    if (days < 1) return '不足 1 天'
    return `${Math.floor(days)} 天`
  })
  const exhaustDateText = computed(() => {
    const value = capacity.value?.forecast.exhaust_at
    return value ? `预计 ${new Date(value).toLocaleDateString('zh-CN')} 耗尽` : '等待有效增长样本'
  })
  const forecastBasisText = computed(() => {
    const basis = capacity.value?.forecast.basis
    if (basis === 'disk_samples')
      return `磁盘采样，观察 ${capacity.value?.forecast.observed_days || 0} 天`
    if (basis === 'local_media_growth')
      return `本地媒体增长，近 ${capacity.value?.window_days || 30} 天`
    return '数据不足，暂不推算'
  })
  const capacitySampleState = computed(() => {
    if (!capacity.value?.disk.available) return '未接入'
    return capacity.value.disk.sample_stale ? '采样已过期' : '采样正常'
  })
  const capacityRiskTone = computed(() => {
    const days = capacity.value?.forecast.days_remaining
    if (days !== null && days !== undefined && days <= 30) return 'fact-danger'
    if (diskUsage.value >= 80 || (days !== null && days !== undefined && days <= 90))
      return 'fact-warning'
    return 'fact-safe'
  })
  const governanceHealth = computed(() => {
    let score = 100
    const reasons: Array<{ text: string; tone: string }> = []
    if (!capacity.value?.disk.available) {
      score -= 15
      reasons.push({ text: '容量 Agent 暂无磁盘采样', tone: 'danger' })
    } else if (capacity.value.disk.sample_stale) {
      score -= 10
      reasons.push({ text: '磁盘采样已超过 15 分钟', tone: 'warning' })
    } else {
      reasons.push({ text: `磁盘采样正常，使用率 ${diskUsage.value.toFixed(1)}%`, tone: 'safe' })
    }
    if (diskUsage.value >= 90) score -= 35
    else if (diskUsage.value >= 80) score -= 20
    else if (diskUsage.value >= 70) score -= 10
    const remaining = capacity.value?.forecast.days_remaining
    if (remaining !== null && remaining !== undefined) {
      if (remaining <= 30) score -= 25
      else if (remaining <= 90) score -= 15
      else if (remaining <= 180) score -= 8
      reasons.push({
        text: `预计容量还能使用 ${Math.max(0, Math.floor(remaining))} 天`,
        tone: remaining <= 30 ? 'danger' : remaining <= 90 ? 'warning' : 'safe'
      })
    } else {
      reasons.push({ text: '增长样本不足，暂不能预测耗尽时间', tone: 'warning' })
    }
    if (!backupReady.value) {
      score -= 20
      reasons.push({ text: '近期可验证备份尚未就绪', tone: 'danger' })
    } else {
      reasons.push({ text: '近期可验证备份已就绪', tone: 'safe' })
    }
    const pending = Number(mediaSummary.value.cleanup_pending_count || 0)
    if (pending > 0) {
      score -= Math.min(15, 5 + Math.floor(Math.log10(pending + 1)) * 5)
      reasons.push({ text: `${formatNumber(pending)} 个媒体对象待处理`, tone: 'warning' })
    }
    if (maintenance.value?.runs?.some((run) => run.status === 'failed')) {
      score -= 10
      reasons.push({ text: '近期存在清理失败记录', tone: 'danger' })
    }
    score = Math.min(100, Math.max(0, score))
    if (score >= 90)
      return { score, label: '优秀', tag: 'success' as const, color: '#059669', reasons }
    if (score >= 75)
      return { score, label: '健康', tag: 'primary' as const, color: '#2563eb', reasons }
    if (score >= 60)
      return { score, label: '需关注', tag: 'warning' as const, color: '#d97706', reasons }
    return { score, label: '高风险', tag: 'danger' as const, color: '#dc2626', reasons }
  })
  const healthScoreStyle = computed(() => ({
    '--score-progress': `${governanceHealth.value.score * 3.6}deg`,
    '--score-color': governanceHealth.value.color
  }))
  const distributionRows = computed(() => {
    const rows = insights.value?.distribution || []
    const total = rows.reduce((sum, item) => sum + Number(item.bytes || 0), 0)
    return rows.map((item) => ({
      ...item,
      percent: total > 0 ? (Number(item.bytes || 0) / total) * 100 : 0
    }))
  })
  const updatedText = computed(() =>
    lastUpdatedAt.value
      ? `更新于 ${lastUpdatedAt.value.toLocaleTimeString('zh-CN', { hour12: false })}`
      : '等待刷新'
  )
  const safetyMessage = computed(() => {
    if (!backupReady.value) return '正式清理已锁定：需要最近一次通过验证且未超过有效期的备份。'
    if (!previewFresh.value)
      return '请先生成最新清理清单，正式清理只接受 10 分钟内且未使用过的清单。'
    if (!preview.value?.total_would_delete) return '当前没有需要清理的数据，正式清理按钮保持禁用。'
    return `当前清单最多删除 ${formatNumber(preview.value.total_would_delete)} 条；正式执行仍需两次人工确认。`
  })

  const jobLabels: Record<string, string> = {
    upload_logs: '上传诊断日志',
    push_delivery_logs: '推送投递日志',
    admin_login_logs: '管理员登录日志',
    admin_security_events: '管理员安全事件',
    observability_alert_events: '告警事件',
    outbox_completed: '已完成 Outbox',
    outbox_dead: 'Outbox 死信',
    external_cleanup_success: '外部清理成功任务',
    external_cleanup_failed: '外部清理失败任务',
    deleted_media_metadata: '已回收媒体元数据'
  }
  const jobLabel = (value: string) => jobLabels[value] || value
  const formatNumber = (value?: number | string | null) =>
    Number(value || 0).toLocaleString('zh-CN')
  const formatBytes = (value?: number | null) => {
    const bytes = Number(value || 0)
    if (!Number.isFinite(bytes) || bytes <= 0) return '0 B'
    const units = ['B', 'KB', 'MB', 'GB', 'TB']
    const index = Math.min(
      Math.max(0, Math.floor(Math.log(bytes) / Math.log(1024))),
      units.length - 1
    )
    return `${(bytes / 1024 ** index).toFixed(index === 0 ? 0 : 1)} ${units[index]}`
  }
  const formatDateTime = (value?: string) => {
    if (!value) return '-'
    const date = new Date(value)
    return Number.isNaN(date.getTime()) ? value : date.toLocaleString('zh-CN', { hour12: false })
  }
  const mediaKindLabel = (value: string) =>
    value === 'image'
      ? '图片'
      : value === 'video'
        ? '视频'
        : value === 'audio'
          ? '音频'
          : '其他文件'
  const statusLabel = (value: MaintenanceJobRun['status']) =>
    value === 'success'
      ? '成功'
      : value === 'dry_run'
        ? '预演'
        : value === 'running'
          ? '执行中'
          : value === 'failed'
            ? '失败'
            : '跳过'
  const statusTag = (value: MaintenanceJobRun['status']) =>
    value === 'success'
      ? 'success'
      : value === 'dry_run'
        ? 'warning'
        : value === 'failed'
          ? 'danger'
          : 'info'

  const loadStatus = async () => {
    maintenance.value = await getMaintenanceStatus()
  }
  const loadPreview = async () => {
    previewLoading.value = true
    cleanupError.value = ''
    try {
      preview.value = await getMaintenancePreview()
      nowTick.value = Date.now()
    } catch {
      preview.value = null
      cleanupError.value = '生成清理清单失败，请检查数据库和 Redis 状态。'
    } finally {
      previewLoading.value = false
    }
  }
  const loadMedia = async () => {
    mediaLoading.value = true
    try {
      const result = await getMediaObjects({
        page: mediaPage.value,
        page_size: mediaPageSize,
        search: mediaFilters.search || undefined,
        kind: (mediaFilters.kind || undefined) as 'image' | 'video' | 'audio' | undefined,
        provider: mediaFilters.provider || undefined,
        status: mediaFilters.status || undefined,
        min_size_bytes: mediaFilters.special === 'large' ? 50 * 1024 * 1024 : undefined,
        age_days: mediaFilters.special === 'stale' ? 90 : undefined,
        sort_by: mediaFilters.special === 'large' ? 'size_desc' : 'created_desc'
      })
      mediaItems.value = result.list || []
      mediaTotal.value = Number(result.total || 0)
      mediaSummary.value = result.summary || emptyMediaSummary()
    } catch {
      mediaItems.value = []
      mediaTotal.value = 0
      mediaSummary.value = emptyMediaSummary()
      ElMessage.error('读取媒体资产失败')
    } finally {
      mediaLoading.value = false
    }
  }
  const loadCapacity = async () => {
    capacityLoading.value = true
    try {
      capacity.value = await getDataGovernanceCapacity(capacityWindow.value)
    } catch {
      capacity.value = null
      ElMessage.error('读取容量风险数据失败')
    } finally {
      capacityLoading.value = false
    }
  }
  const renderTrendChart = () => {
    if (!trendChartRef.value || !insights.value?.trend.length) {
      trendChart?.dispose()
      trendChart = null
      return
    }
    if (!trendChart) trendChart = echarts.init(trendChartRef.value)
    const rows = insights.value.trend
    const option: EChartsOption = {
      animationDuration: 350,
      color: ['#0891b2', '#7c3aed', '#dc2626'],
      tooltip: { trigger: 'axis' },
      legend: { top: 0, data: ['新增媒体容量', '新增治理记录', '清理删除'] },
      grid: { top: 42, right: 48, bottom: 30, left: 52, containLabel: true },
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: rows.map((item) => item.date.slice(5))
      },
      yAxis: [
        {
          type: 'value',
          name: '容量',
          minInterval: 1,
          axisLabel: { formatter: (value: number) => formatBytes(value) }
        },
        { type: 'value', name: '记录数', minInterval: 1 }
      ],
      series: [
        {
          name: '新增媒体容量',
          type: 'line',
          smooth: true,
          showSymbol: false,
          areaStyle: { opacity: 0.08 },
          data: rows.map((item) => item.media_bytes)
        },
        {
          name: '新增治理记录',
          type: 'line',
          smooth: true,
          showSymbol: false,
          yAxisIndex: 1,
          data: rows.map((item) => item.log_records + item.outbox_records + item.media_count)
        },
        {
          name: '清理删除',
          type: 'bar',
          yAxisIndex: 1,
          barMaxWidth: 18,
          data: rows.map((item) => item.cleanup_deleted)
        }
      ]
    }
    trendChart.setOption(option, true)
  }
  const loadInsights = async () => {
    insightsLoading.value = true
    try {
      insights.value = await getDataGovernanceInsights(insightsWindow.value)
      await nextTick()
      renderTrendChart()
    } catch {
      insights.value = null
      trendChart?.dispose()
      trendChart = null
      ElMessage.error('读取治理趋势失败')
    } finally {
      insightsLoading.value = false
    }
  }
  const refreshAll = async () => {
    pageLoading.value = true
    await Promise.allSettled([
      loadStatus(),
      loadPreview(),
      loadMedia(),
      loadCapacity(),
      loadInsights()
    ])
    lastUpdatedAt.value = new Date()
    pageLoading.value = false
  }
  const applyMediaFilters = () => {
    mediaPage.value = 1
    loadMedia()
  }
  const scrollToWorkspace = (element?: HTMLElement) => {
    element?.scrollIntoView({ behavior: 'smooth', block: 'start' })
  }
  const goToWorkspace = async (workspace: 'overview' | 'cleanup' | 'media') => {
    activeWorkspace.value = workspace
    if (workspace === 'overview') {
      scrollToWorkspace(overviewSectionRef.value)
      return
    }
    activeTab.value = workspace
    await nextTick()
    scrollToWorkspace(workspaceTabsRef.value)
  }
  const handleWorkspaceTabChange = (name: string | number) => {
    if (name === 'cleanup' || name === 'media') activeWorkspace.value = name
  }

  const runDryPreview = async () => {
    try {
      await ElMessageBox.confirm(
        '本操作只统计候选并写入审计，不会删除任何记录或文件。',
        '执行安全预演',
        {
          type: 'info',
          confirmButtonText: '开始预演',
          cancelButtonText: '取消'
        }
      )
    } catch {
      return
    }
    actionLoading.value = true
    try {
      const results = await runMaintenanceDryRun()
      const count = results.reduce((sum, item) => sum + Number(item.candidate_count || 0), 0)
      ElMessage.success(`预演审计完成，共 ${formatNumber(count)} 条候选`)
      await Promise.all([loadStatus(), loadPreview()])
    } catch {
      ElMessage.error('预演失败，未执行任何删除')
    } finally {
      actionLoading.value = false
    }
  }

  const runFormalCleanup = async () => {
    if (!canRunFormal.value || !preview.value) return
    const token = preview.value.preview_token
    const count = preview.value.total_would_delete
    try {
      await ElMessageBox.confirm(
        `你已查看当前清单。本次最多永久删除 ${formatNumber(count)} 条过期记录，操作受备份门禁、分布式锁和批次上限保护。`,
        '第一次确认：按清单正式清理',
        { type: 'warning', confirmButtonText: '继续核对', cancelButtonText: '取消' }
      )
      await ElMessageBox.prompt('请输入“确认治理”完成第二次确认。', '第二次确认', {
        type: 'error',
        confirmButtonText: '正式执行',
        cancelButtonText: '取消',
        inputValidator: (value) => value === '确认治理' || '请输入完整的“确认治理”'
      })
    } catch {
      return
    }
    actionLoading.value = true
    try {
      const results = await runMaintenanceFormal(token)
      const deleted = results.reduce((sum, item) => sum + Number(item.deleted_count || 0), 0)
      ElMessage.success(`正式清理完成，共删除 ${formatNumber(deleted)} 条记录`)
      preview.value = null
      await Promise.all([loadStatus(), loadPreview(), loadMedia()])
    } catch {
      preview.value = null
      ElMessage.error('正式清理失败或清单已失效，请重新生成清单后检查门禁')
      await Promise.allSettled([loadStatus(), loadPreview()])
    } finally {
      actionLoading.value = false
    }
  }

  const mediaAccessUrl = (item: MediaObjectItem) => {
    if (item.provider === 'local' && item.object_key) {
      const key = item.object_key.replaceAll('\\', '/').replace(/^\/+/, '')
      return `/${key}`
    }
    return item.access_url || item.url
  }
  const openMedia = (item: MediaObjectItem) => {
    const url = mediaAccessUrl(item)
    if (url) window.open(url, '_blank', 'noopener,noreferrer')
  }
  const fileName = (path: string) => path.split('/').filter(Boolean).at(-1) || path
  const fileIcon = (kind: MediaObjectItem['file_kind']) =>
    kind === 'audio' ? 'ri:music-2-line' : kind === 'video' ? 'ri:video-line' : 'ri:file-3-line'
  const providerLabel = (value: string) =>
    value === 'local'
      ? '本地'
      : value === 'aliyun'
        ? 'OSS'
        : value === 'qiniu'
          ? '七牛'
          : value.toUpperCase()
  const mediaStatusLabel = (value: string) => {
    const labels: Record<string, string> = {
      uploading: '上传中',
      uploaded: '待绑定',
      binding: '绑定中',
      bound: '已绑定',
      quarantined: '隔离',
      deleting: '清理中',
      deleted: '已删除',
      failed: '失败'
    }
    return labels[value] || value
  }
  const mediaStatusTag = (value: string) =>
    value === 'bound'
      ? 'success'
      : value === 'deleted'
        ? 'info'
        : value === 'failed' || value === 'quarantined'
          ? 'danger'
          : 'warning'

  const resizeTrendChart = () => trendChart?.resize()

  onMounted(() => {
    window.addEventListener('resize', resizeTrendChart)
    refreshAll()
  })
  onBeforeUnmount(() => {
    window.removeEventListener('resize', resizeTrendChart)
    trendChart?.dispose()
    trendChart = null
  })
</script>

<style scoped lang="scss">
  .governance-page {
    min-height: 100%;
    padding: 18px;
    color: var(--el-text-color-primary);
    background: var(--el-bg-color-page, #f6f8fb);
  }

  .page-head,
  .page-title-group,
  .head-actions,
  .sync-status,
  .overview-head,
  .capacity-head,
  .capacity-body,
  .panel-head,
  .safety-bar,
  .panel-actions,
  .safety-state,
  .media-filter,
  .media-summary,
  .media-meta,
  .media-foot,
  .sample-head {
    display: flex;
    gap: 12px;
    align-items: center;
  }

  .page-head,
  .overview-head,
  .capacity-head,
  .panel-head,
  .safety-bar,
  .media-foot,
  .sample-head {
    justify-content: space-between;
  }

  .page-head,
  .overview-card,
  .capacity-risk-card,
  .panel,
  .safety-bar {
    background: var(--el-bg-color-overlay, #fff);
    border: 1px solid var(--el-border-color-lighter, #e6ebf2);
    border-radius: 8px;
    box-shadow: 0 8px 20px rgb(15 23 42 / 3%);
  }

  .page-head {
    padding: 18px 20px;
    margin-bottom: 14px;
  }

  .workspace-launcher {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 12px;
    margin-bottom: 14px;
  }

  .workspace-entry {
    --workspace-tone: #2563eb;

    display: flex;
    gap: 12px;
    align-items: center;
    min-width: 0;
    padding: 14px 16px;
    color: var(--el-text-color-primary);
    text-align: left;
    cursor: pointer;
    background:
      radial-gradient(
        circle at 100% 0%,
        color-mix(in srgb, var(--workspace-tone) 11%, transparent),
        transparent 180px
      ),
      var(--el-bg-color-overlay, #fff);
    border: 1px solid color-mix(in srgb, var(--workspace-tone) 20%, var(--el-border-color));
    border-radius: 8px;
    box-shadow: 0 6px 16px rgb(15 23 42 / 3%);
    transition:
      border-color 0.18s ease,
      box-shadow 0.18s ease,
      transform 0.18s ease;
  }

  .workspace-entry:hover,
  .workspace-entry.is-active {
    border-color: color-mix(in srgb, var(--workspace-tone) 58%, var(--el-border-color));
    box-shadow: 0 9px 22px color-mix(in srgb, var(--workspace-tone) 10%, transparent);
    transform: translateY(-1px);
  }

  .workspace-entry--cleanup {
    --workspace-tone: #dc2626;
  }

  .workspace-entry--media {
    --workspace-tone: #0891b2;
  }

  .workspace-entry-icon {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 40px;
    height: 40px;
    color: var(--workspace-tone);
    background: color-mix(in srgb, var(--workspace-tone) 10%, var(--el-bg-color-overlay));
    border-radius: 50%;
  }

  .workspace-entry-icon :deep(svg) {
    width: 20px;
    height: 20px;
  }

  .workspace-entry-copy {
    display: grid;
    flex: 1;
    gap: 3px;
    min-width: 0;
  }

  .workspace-entry-copy strong,
  .workspace-entry-copy small {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .workspace-entry-copy strong {
    font-size: 14px;
  }

  .workspace-entry-copy small {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .workspace-entry-arrow {
    flex: 0 0 auto;
    color: color-mix(in srgb, var(--workspace-tone) 72%, var(--el-text-color-secondary));
  }

  h1,
  h2,
  p {
    margin: 0;
  }

  h1 {
    margin: 2px 0 3px;
    font-size: 23px;
    line-height: 1.3;
  }

  h2 {
    font-size: 17px;
  }

  .page-title-icon {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 60px;
    height: 60px;
    color: #2563eb;
    background: #eff6ff;
    border: 1px solid #dbeafe;
    border-radius: 50%;
  }

  .page-title-icon :deep(svg) {
    width: 28px;
    height: 28px;
  }

  .page-title-group p {
    font-size: 12px;
    font-weight: 600;
    color: #2563eb;
  }

  .page-title-group > div > span,
  .overview-head p,
  .overview-time {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .sync-status {
    font-size: 13px;
    color: var(--el-text-color-regular);
  }

  .sync-status small {
    color: var(--el-text-color-secondary);
  }

  .sync-dot {
    width: 8px;
    height: 8px;
    background: #22c55e;
    border: 2px solid #dcfce7;
    border-radius: 50%;
    box-shadow: 0 0 0 3px rgb(34 197 94 / 10%);
  }

  .environment-tag {
    flex: 0 0 auto;
    letter-spacing: 0.04em;
  }

  .overview-card {
    padding: 18px 20px 20px;
    background:
      radial-gradient(circle at 100% 0%, rgb(37 99 235 / 8%), transparent 330px),
      linear-gradient(145deg, rgb(37 99 235 / 4%), transparent 240px),
      var(--el-bg-color-overlay, #fff);
  }

  .overview-head {
    padding-bottom: 14px;
    border-bottom: 1px solid var(--el-border-color-extra-light);
  }

  .overview-head p {
    margin-top: 4px;
  }

  .data-orb-grid {
    display: grid;
    grid-template-columns: repeat(6, minmax(132px, 1fr));
    gap: 18px;
    padding-top: 20px;
  }

  .data-orb {
    --tone: #64748b;

    display: flex;
    flex-direction: column;
    gap: 4px;
    align-items: center;
    justify-content: center;
    width: 132px;
    height: 132px;
    margin: 0 auto;
    text-align: center;
    background:
      radial-gradient(
        circle at 50% 40%,
        color-mix(in srgb, var(--tone) 7%, transparent),
        transparent 65%
      ),
      var(--el-bg-color-overlay, #fff);
    border: 8px solid color-mix(in srgb, var(--tone) 18%, var(--el-fill-color-light));
    border-radius: 50%;
    box-shadow:
      0 0 0 1px color-mix(in srgb, var(--tone) 22%, transparent),
      0 8px 18px rgb(15 23 42 / 6%);
  }

  .data-orb span {
    font-size: 12px;
    font-weight: 600;
    color: color-mix(in srgb, var(--tone) 82%, var(--el-text-color-primary));
  }

  .data-orb strong {
    max-width: 112px;
    overflow: hidden;
    font-size: 22px;
    font-variant-numeric: tabular-nums;
    line-height: 1.2;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .data-orb small {
    max-width: 108px;
    overflow: hidden;
    font-size: 11px;
    color: var(--el-text-color-placeholder);
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .tone-indigo {
    --tone: #6366f1;
  }

  .tone-rose {
    --tone: #e11d48;
  }

  .tone-amber {
    --tone: #d97706;
  }

  .tone-cyan {
    --tone: #0891b2;
  }

  .tone-violet {
    --tone: #7c3aed;
  }

  .tone-emerald {
    --tone: #059669;
  }

  .capacity-risk-card {
    padding: 18px 20px 20px;
    margin-top: 14px;
    background:
      radial-gradient(circle at 0% 100%, rgb(8 145 178 / 7%), transparent 300px),
      linear-gradient(145deg, rgb(8 145 178 / 3%), transparent 260px),
      var(--el-bg-color-overlay, #fff);
  }

  .capacity-head {
    padding-bottom: 14px;
    border-bottom: 1px solid var(--el-border-color-extra-light);
  }

  .capacity-head p {
    margin-top: 4px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .capacity-body {
    min-height: 176px;
    padding-top: 18px;
  }

  .disk-ring {
    --disk-color: #2563eb;
    --disk-progress: 0deg;

    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 148px;
    height: 148px;
    background: conic-gradient(
      var(--disk-color) 0deg var(--disk-progress),
      var(--el-fill-color-light) var(--disk-progress) 360deg
    );
    border-radius: 50%;
    box-shadow: 0 8px 22px color-mix(in srgb, var(--disk-color) 16%, transparent);
  }

  .disk-ring-inner {
    display: flex;
    flex-direction: column;
    gap: 3px;
    align-items: center;
    justify-content: center;
    width: 114px;
    height: 114px;
    background: var(--el-bg-color-overlay, #fff);
    border-radius: 50%;
  }

  .disk-ring-inner strong {
    font-size: 24px;
    font-variant-numeric: tabular-nums;
  }

  .disk-ring-inner span {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .capacity-facts {
    display: grid;
    flex: 1;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
  }

  .capacity-facts article {
    display: flex;
    flex-direction: column;
    gap: 7px;
    justify-content: center;
    min-height: 112px;
    padding: 16px;
    background: color-mix(in srgb, var(--el-fill-color-light) 66%, transparent);
    border: 1px solid var(--el-border-color-extra-light);
    border-radius: 8px;
  }

  .capacity-facts span,
  .capacity-facts small {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .capacity-facts strong {
    font-size: 20px;
    font-variant-numeric: tabular-nums;
  }

  .capacity-facts .fact-safe strong {
    color: #059669;
  }

  .capacity-facts .fact-warning strong {
    color: #d97706;
  }

  .capacity-facts .fact-danger strong {
    color: #dc2626;
  }

  .insights-grid {
    display: grid;
    grid-template-columns: minmax(270px, 0.9fr) minmax(520px, 1.8fr) minmax(270px, 0.9fr);
    gap: 14px;
    margin-top: 14px;
  }

  .insight-card {
    min-width: 0;
    padding: 18px;
    background:
      linear-gradient(145deg, rgb(124 58 237 / 4%), transparent 220px),
      var(--el-bg-color-overlay, #fff);
    border: 1px solid var(--el-border-color-lighter, #e6ebf2);
    border-radius: 8px;
    box-shadow: 0 8px 20px rgb(15 23 42 / 3%);
  }

  .trend-card {
    background:
      radial-gradient(circle at 100% 0%, rgb(8 145 178 / 6%), transparent 300px),
      var(--el-bg-color-overlay, #fff);
  }

  .distribution-card {
    background:
      linear-gradient(145deg, rgb(5 150 105 / 5%), transparent 220px),
      var(--el-bg-color-overlay, #fff);
  }

  .insight-head {
    display: flex;
    gap: 10px;
    align-items: center;
    justify-content: space-between;
    min-height: 43px;
    padding-bottom: 12px;
    border-bottom: 1px solid var(--el-border-color-extra-light);
  }

  .insight-head p {
    margin-top: 4px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .health-score-main {
    display: flex;
    flex-direction: column;
    gap: 16px;
    align-items: center;
    padding-top: 18px;
  }

  .health-score-ring {
    --score-color: #2563eb;
    --score-progress: 0deg;

    display: grid;
    place-items: center;
    width: 126px;
    height: 126px;
    background: conic-gradient(
      var(--score-color) 0deg var(--score-progress),
      var(--el-fill-color-light) var(--score-progress) 360deg
    );
    border-radius: 50%;
    box-shadow: 0 8px 20px color-mix(in srgb, var(--score-color) 14%, transparent);
  }

  .health-score-ring > div {
    display: flex;
    align-items: baseline;
    justify-content: center;
    width: 98px;
    height: 98px;
    background: var(--el-bg-color-overlay, #fff);
    border-radius: 50%;
  }

  .health-score-ring strong {
    align-self: center;
    font-size: 34px;
    color: var(--score-color);
  }

  .health-score-ring span {
    align-self: center;
    margin-left: 3px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .health-reasons {
    display: grid;
    gap: 9px;
    width: 100%;
    padding: 0;
    margin: 0;
    list-style: none;
  }

  .health-reasons li {
    display: flex;
    gap: 8px;
    align-items: flex-start;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .health-reasons i {
    flex: 0 0 auto;
    width: 8px;
    height: 8px;
    margin-top: 4px;
    background: #94a3b8;
    border-radius: 50%;
  }

  .health-reasons i.safe {
    background: #10b981;
  }

  .health-reasons i.warning {
    background: #f59e0b;
  }

  .health-reasons i.danger {
    background: #ef4444;
  }

  .trend-chart-wrap {
    min-height: 276px;
    padding-top: 10px;
  }

  .trend-chart {
    width: 100%;
    height: 276px;
  }

  .distribution-list {
    display: grid;
    gap: 16px;
    padding-top: 18px;
  }

  .distribution-item > div:first-child {
    display: flex;
    gap: 12px;
    align-items: center;
    justify-content: space-between;
    font-size: 13px;
  }

  .distribution-track {
    height: 7px;
    margin: 7px 0 5px;
    overflow: hidden;
    background: var(--el-fill-color-light);
    border-radius: 999px;
  }

  .distribution-track i {
    display: block;
    height: 100%;
    background: linear-gradient(90deg, #0891b2, #10b981);
    border-radius: inherit;
  }

  .distribution-item small {
    font-size: 11px;
    color: var(--el-text-color-placeholder);
  }

  .safety-bar {
    padding: 12px 14px;
    margin-top: 14px;
    background:
      linear-gradient(90deg, rgb(14 165 233 / 6%), transparent 58%),
      var(--el-bg-color-overlay, #fff);
  }

  .safety-bar p {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .workspace-tabs-anchor {
    margin-top: 16px;
    scroll-margin-top: 16px;
  }

  .governance-tabs {
    margin-top: 0;
  }

  .panel {
    --panel-tone: #2563eb;

    padding: 18px;
    background:
      radial-gradient(
        circle at 100% 0%,
        color-mix(in srgb, var(--panel-tone) 6%, transparent),
        transparent 340px
      ),
      linear-gradient(
        145deg,
        color-mix(in srgb, var(--panel-tone) 3%, transparent),
        transparent 240px
      ),
      var(--el-bg-color-overlay, #fff);
  }

  .panel--history {
    --panel-tone: #7c3aed;
  }

  .panel--media {
    --panel-tone: #0891b2;
  }

  .history-panel {
    margin-top: 16px;
  }

  .panel-head {
    margin-bottom: 16px;
  }

  .panel-head p {
    margin-top: 5px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .panel-actions,
  .media-filter,
  .media-summary,
  .safety-state {
    flex-wrap: wrap;
  }

  .panel-alert {
    margin-bottom: 14px;
  }

  .danger-zone {
    display: flex;
    gap: 14px;
    align-items: center;
    padding: 14px;
    margin-bottom: 16px;
    background: linear-gradient(100deg, rgb(220 38 38 / 8%), rgb(220 38 38 / 2%));
    border: 1px solid rgb(220 38 38 / 22%);
    border-radius: 8px;
  }

  .danger-zone-icon {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 42px;
    height: 42px;
    color: #dc2626;
    background: rgb(220 38 38 / 10%);
    border-radius: 50%;
  }

  .danger-zone-icon :deep(svg) {
    width: 21px;
    height: 21px;
  }

  .danger-zone-copy {
    flex: 1;
    min-width: 0;
  }

  .danger-zone-copy p {
    margin: 3px 0 8px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .formal-blockers {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .audit-timeline {
    position: relative;
    max-height: 430px;
    padding-left: 13px;
    overflow: auto;
  }

  .audit-timeline::before {
    position: absolute;
    top: 10px;
    bottom: 10px;
    left: 18px;
    width: 1px;
    content: '';
    background: var(--el-border-color);
  }

  .audit-event {
    position: relative;
    display: flex;
    gap: 14px;
    padding: 8px 10px 16px 0;
  }

  .audit-marker {
    z-index: 1;
    box-sizing: content-box;
    flex: 0 0 auto;
    width: 11px;
    height: 11px;
    margin-top: 5px;
    background: #94a3b8;
    border: 3px solid var(--el-bg-color-overlay, #fff);
    border-radius: 50%;
  }

  .audit-marker--success {
    background: #10b981;
  }

  .audit-marker--dry_run,
  .audit-marker--running {
    background: #f59e0b;
  }

  .audit-marker--failed {
    background: #ef4444;
  }

  .audit-event-main {
    flex: 1;
    min-width: 0;
    padding: 11px 13px;
    background: color-mix(in srgb, var(--el-fill-color-light) 62%, transparent);
    border: 1px solid var(--el-border-color-extra-light);
    border-radius: 8px;
  }

  .audit-event-title,
  .audit-event-stats {
    display: flex;
    flex-wrap: wrap;
    gap: 8px 12px;
    align-items: center;
  }

  .audit-event-title time {
    margin-left: auto;
    font-size: 11px;
    color: var(--el-text-color-placeholder);
  }

  .audit-event-stats {
    margin-top: 8px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .audit-error {
    color: var(--el-color-danger);
  }

  .danger-number {
    color: var(--el-color-danger);
  }

  .job-name {
    display: grid;
    gap: 2px;
  }

  .job-name small {
    font-family: ui-monospace, monospace;
    color: var(--el-text-color-secondary);
  }

  .sample-wrap {
    padding: 10px 24px 20px;
    background: var(--el-fill-color-lighter);
  }

  .sample-head {
    margin-bottom: 10px;
    font-size: 12px;
  }

  .media-filter :deep(.el-input) {
    width: 230px;
  }

  .media-filter :deep(.el-select) {
    width: 130px;
  }

  .media-summary {
    padding: 10px 12px;
    margin-bottom: 16px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    background: var(--el-fill-color-lighter);
    border-radius: 9px;
  }

  .media-summary b {
    margin-left: 4px;
    color: var(--el-text-color-primary);
  }

  .media-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 14px;
    min-height: 240px;
  }

  .media-grid--list {
    grid-template-columns: 1fr;
  }

  .media-grid--list .media-card {
    display: grid;
    grid-template-columns: 240px minmax(0, 1fr);
  }

  .media-grid--list .media-preview {
    height: 150px;
  }

  .media-grid--list .media-info {
    align-content: center;
  }

  .media-card {
    overflow: hidden;
    background:
      linear-gradient(150deg, rgb(8 145 178 / 6%), transparent 170px),
      var(--el-bg-color-overlay, #fff);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
    transition:
      transform 0.18s ease,
      box-shadow 0.18s ease;
  }

  .media-card:hover {
    box-shadow: 0 10px 26px rgb(15 23 42 / 10%);
    transform: translateY(-2px);
  }

  .media-preview {
    position: relative;
    height: 180px;
    background: #0f172a;
  }

  .media-preview :deep(.el-image),
  .media-preview video {
    width: 100%;
    height: 100%;
    object-fit: contain;
  }

  .preview-fallback {
    display: flex;
    flex-direction: column;
    gap: 9px;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: #94a3b8;
  }

  .preview-fallback :deep(svg) {
    width: 34px;
    height: 34px;
  }

  .media-status,
  .media-provider {
    position: absolute;
    top: 9px;
    z-index: 2;
  }

  .media-status {
    left: 9px;
  }

  .media-provider {
    right: 9px;
  }

  .media-info {
    display: grid;
    gap: 8px;
    padding: 13px;
  }

  .media-info > strong,
  .media-info > p {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .media-info > p {
    font-family: ui-monospace, monospace;
    font-size: 11px;
    color: var(--el-text-color-secondary);
  }

  .media-meta {
    flex-wrap: wrap;
    font-size: 11px;
    color: var(--el-text-color-placeholder);
  }

  .media-foot {
    padding-top: 7px;
    font-size: 11px;
    border-top: 1px solid var(--el-border-color-extra-light);
  }

  .media-pagination {
    justify-content: flex-end;
    margin-top: 18px;
  }

  @media (width <= 1500px) {
    .insights-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .trend-card {
      grid-row: 1;
      grid-column: 1 / -1;
    }
  }

  @media (width <= 1280px) {
    .data-orb-grid {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }

    .media-grid {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }

    .capacity-facts {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (width <= 860px) {
    .governance-page {
      padding: 12px;
    }

    .page-head,
    .overview-head,
    .capacity-head,
    .panel-head,
    .safety-bar {
      flex-direction: column;
      align-items: flex-start;
    }

    .head-actions {
      justify-content: space-between;
      width: 100%;
    }

    .data-orb-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .workspace-launcher {
      grid-template-columns: 1fr;
    }

    .media-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .insights-grid {
      grid-template-columns: 1fr;
    }

    .trend-card {
      grid-row: auto;
      grid-column: auto;
    }

    .capacity-body {
      align-items: flex-start;
    }
  }

  @media (width <= 560px) {
    .media-grid {
      grid-template-columns: 1fr;
    }

    .page-title-group,
    .head-actions,
    .sync-status {
      align-items: flex-start;
    }

    .head-actions,
    .sync-status {
      flex-direction: column;
    }

    .capacity-body,
    .danger-zone,
    .insight-head {
      flex-direction: column;
      align-items: flex-start;
    }

    .capacity-facts {
      grid-template-columns: 1fr;
      width: 100%;
    }

    .disk-ring {
      align-self: center;
    }

    .danger-zone > .el-button {
      width: 100%;
    }

    .media-grid--list .media-card {
      display: block;
    }

    .media-grid--list .media-preview {
      height: 180px;
    }

    .media-filter :deep(.el-input),
    .media-filter :deep(.el-select) {
      width: 100%;
    }
  }

  @media (width <= 420px) {
    .data-orb-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
