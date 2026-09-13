<template>
  <div class="health-page">
    <section class="page-head">
      <div class="page-title-group">
        <span class="page-title-icon" aria-hidden="true">
          <ArtSvgIcon icon="ri:heart-pulse-line" />
        </span>
        <div>
          <p>系统配置 / 运维状态</p>
          <h1>实时监控</h1>
          <span>统一查看依赖、消息链路、指标趋势、主动告警和节点状态。</span>
        </div>
      </div>
      <div class="head-actions">
        <div class="live-status">
          <span class="live-dot" />
          <span>实时监测中</span>
          <small>{{ lastUpdatedText }}</small>
        </div>
        <ElButton
          :icon="Refresh"
          type="primary"
          :loading="loading || uploadLogLoading || trendLoading || alertLoading"
          @click="refreshAll"
        >
          刷新状态
        </ElButton>
      </div>
    </section>

    <section class="metric-grid" aria-label="实时监控核心指标">
      <article class="metric-card metric-card--status" :class="statusTone(health?.status)">
        <header class="metric-card-head">
          <span class="metric-label">系统状态</span>
          <span class="metric-status-chip">
            <i aria-hidden="true" />
            {{ statusLabel(health?.status) }}
          </span>
        </header>
        <div class="metric-status-main">
          <span class="metric-icon metric-icon--large" aria-hidden="true">
            <ArtSvgIcon :icon="statusIcon(health?.status)" />
          </span>
          <div>
            <strong>{{ statusLabel(health?.status) }}</strong>
            <span>{{ health?.server_time || '等待首次采样' }}</span>
          </div>
        </div>
        <div class="metric-health-strip">
          <span
            >API 错误率 <b>{{ formatRate(apiHealth?.error_rate) }}</b></span
          >
          <span
            >P95 <b>{{ formatDuration(apiHealth?.p95_latency_ms) }}</b></span
          >
        </div>
      </article>

      <article class="metric-card metric-card--uptime">
        <header class="metric-card-head">
          <span class="metric-label">运行时长</span>
          <span class="metric-icon"><ArtSvgIcon icon="ri:timer-flash-line" /></span>
        </header>
        <div class="metric-readout" :title="health?.uptime_text || '-'">
          <strong>{{ uptimeDaysText }}</strong>
        </div>
        <footer class="metric-card-foot">启动于 {{ health?.started_at || '-' }}</footer>
      </article>

      <article class="metric-card metric-card--connection">
        <header class="metric-card-head">
          <span class="metric-label">在线连接</span>
          <span class="metric-icon metric-icon--cyan"><ArtSvgIcon icon="ri:radar-line" /></span>
        </header>
        <div class="metric-readout">
          <strong>{{ formatNumber(componentValue('WebSocket', 'online_connections')) }}</strong>
          <em>条</em>
        </div>
        <footer class="metric-card-foot">WebSocket 当前连接</footer>
      </article>

      <article class="metric-card metric-card--users">
        <header class="metric-card-head">
          <span class="metric-label">在线用户</span>
          <span class="metric-icon metric-icon--violet"
            ><ArtSvgIcon icon="ri:user-follow-line"
          /></span>
        </header>
        <div class="metric-readout">
          <strong>{{ formatNumber(componentValue('WebSocket', 'online_users')) }}</strong>
          <em>人</em>
        </div>
        <footer class="metric-card-foot">WebSocket 活跃用户</footer>
      </article>

      <article class="metric-card metric-card--runtime">
        <header class="metric-card-head">
          <span class="metric-label">Goroutine</span>
          <span class="metric-icon metric-icon--violet"><ArtSvgIcon icon="ri:cpu-line" /></span>
        </header>
        <div class="metric-readout">
          <strong>{{ formatNumber(health?.runtime?.goroutines) }}</strong>
          <em>个</em>
        </div>
        <footer class="metric-card-foot">{{ health?.runtime?.cpu_num || 0 }} 个 CPU 核心</footer>
      </article>

      <article class="metric-card metric-card--memory">
        <header class="metric-card-head">
          <span class="metric-label">内存占用</span>
          <span class="metric-icon metric-icon--blue"
            ><ArtSvgIcon icon="ri:database-2-line"
          /></span>
        </header>
        <div class="metric-readout">
          <strong>{{ formatNumber(health?.runtime?.memory_alloc_mb) }}</strong>
          <em>MB</em>
        </div>
        <footer class="metric-card-foot">
          系统保留 {{ formatNumber(health?.runtime?.memory_sys_mb) }} MB
        </footer>
      </article>

      <article class="metric-card metric-card--queue">
        <header class="metric-card-head">
          <span class="metric-label">队列积压</span>
          <span class="metric-icon metric-icon--orange"
            ><ArtSvgIcon icon="ri:inbox-archive-line"
          /></span>
        </header>
        <div class="metric-readout">
          <strong>{{ queueBacklog }}</strong>
          <em>条</em>
        </div>
        <footer class="metric-card-foot">
          {{ formatNumber(summaryComponent('queue')?.dead) }} 条死信
        </footer>
      </article>

      <article class="metric-card metric-card--upload">
        <header class="metric-card-head">
          <span class="metric-label">上传失败率</span>
          <span class="metric-icon metric-icon--rose"
            ><ArtSvgIcon icon="ri:upload-cloud-2-line"
          /></span>
        </header>
        <div class="metric-readout">
          <strong>{{ formatRate(summaryComponent('upload')?.failure_rate) }}</strong>
        </div>
        <footer class="metric-card-foot">
          {{ formatNumber(summaryComponent('upload')?.failed) }} 次失败 / {{ checkWindow }}
        </footer>
      </article>
    </section>

    <section class="content-grid">
      <div class="section-card section-card--trend span-12">
        <div class="section-head trend-head">
          <div class="section-title">
            <span class="section-icon section-icon--trend"
              ><ArtSvgIcon icon="ri:line-chart-line"
            /></span>
            <div>
              <h2>健康趋势</h2>
              <p>{{ trendSubtitle }}</p>
            </div>
          </div>
          <ElRadioGroup v-model="trendMinutes" size="small" @change="loadTrend">
            <ElRadioButton :value="15">15 分钟</ElRadioButton>
            <ElRadioButton :value="60">1 小时</ElRadioButton>
            <ElRadioButton :value="360">6 小时</ElRadioButton>
            <ElRadioButton :value="1440">24 小时</ElRadioButton>
            <ElRadioButton :value="10080">7 天</ElRadioButton>
          </ElRadioGroup>
        </div>
        <div v-loading="trendLoading" class="trend-chart-wrap">
          <ElEmpty
            v-if="trendData.length === 0 && !trendLoading"
            :image-size="92"
            description="暂无趋势数据"
          />
          <div v-show="trendData.length > 0" ref="trendChartRef" class="trend-chart"></div>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card section-card--alert span-12">
        <div class="section-head alert-head">
          <div class="section-title">
            <span class="section-icon section-icon--alert"
              ><ArtSvgIcon icon="ri:alarm-warning-line"
            /></span>
            <div>
              <h2>告警中心</h2>
              <p>Alertmanager 通知会落库保留，恢复通知不会删除故障证据。</p>
            </div>
          </div>
          <div class="alert-summary">
            <ElTag :type="alertSummary.available ? 'success' : 'info'" effect="plain">
              {{ alertSummary.available ? '通知链路可用' : '尚未启用' }}
            </ElTag>
            <ElTag :type="alertSummary.firing.length > 0 ? 'danger' : 'success'" effect="dark">
              当前 {{ alertSummary.firing.length }} 条
            </ElTag>
          </div>
        </div>
        <ElTabs v-model="alertTab" class="alert-tabs">
          <ElTabPane :label="`当前告警 ${alertSummary.firing.length}`" name="firing" />
          <ElTabPane :label="`已恢复 ${alertSummary.resolved.length}`" name="resolved" />
        </ElTabs>
        <ElAlert
          v-if="alertSummary.error"
          :title="alertSummary.error"
          type="warning"
          :closable="false"
          show-icon
          class="alert-error"
        />
        <ElTable v-loading="alertLoading" :data="visibleAlerts" class="clean-table" height="280">
          <ElTableColumn label="级别" width="92">
            <template #default="{ row }">
              <ElTag :type="severityTag(row.severity)" effect="light">{{
                severityLabel(row.severity)
              }}</ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="alert_name" label="告警" min-width="180" />
          <ElTableColumn prop="summary" label="摘要" min-width="260" show-overflow-tooltip />
          <ElTableColumn label="节点" min-width="150">
            <template #default="{ row }">{{ row.node_id || row.instance || '-' }}</template>
          </ElTableColumn>
          <ElTableColumn label="时间" min-width="168">
            <template #default="{ row }">{{ formatDateTime(row.received_at) }}</template>
          </ElTableColumn>
          <ElTableColumn label="通知" width="100">
            <template #default="{ row }">
              <ElTag type="success" effect="plain">{{
                row.notification_status || 'received'
              }}</ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="状态" width="118">
            <template #default="{ row }">
              <ElButton
                v-if="row.status === 'firing'"
                link
                type="primary"
                size="small"
                @click="toggleAlertAcknowledgement(row)"
              >
                {{ row.state === 'acknowledged' ? '取消确认' : '确认告警' }}
              </ElButton>
              <ElTag v-else type="success" effect="plain">已恢复</ElTag>
            </template>
          </ElTableColumn>
          <template #empty>
            <ElEmpty
              :image-size="84"
              :description="alertTab === 'firing' ? '当前没有告警' : '暂无恢复记录'"
            />
          </template>
        </ElTable>
        <div class="alert-meta">
          <span>接收器：{{ alertSummary.receiver || '-' }}</span>
          <span>最近通知：{{ formatDateTime(alertSummary.last_received_at) }}</span>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card section-card--component span-8">
        <div class="section-head">
          <div class="section-title">
            <span class="section-icon section-icon--component"
              ><ArtSvgIcon icon="ri:stack-line"
            /></span>
            <div>
              <h2>组件状态</h2>
              <p>依赖服务、存储、连接和队列的实时检查结果。</p>
            </div>
          </div>
        </div>
        <ElTable v-loading="loading" :data="components" class="clean-table" height="424">
          <ElTableColumn label="组件" width="150">
            <template #default="{ row }">
              <div class="component-name">
                <span class="status-dot" :class="statusTone(row.status)" />
                <span>{{ row.name }}</span>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="状态" width="110">
            <template #default="{ row }">
              <ElTag :type="statusTag(row.status)" effect="light">
                {{ statusLabel(row.status) }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="关键指标" min-width="280">
            <template #default="{ row }">
              <div class="detail-line">{{ componentDetail(row) }}</div>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="error" label="异常" min-width="220" show-overflow-tooltip>
            <template #default="{ row }">{{ row.error || '-' }}</template>
          </ElTableColumn>
          <template #empty>
            <ElEmpty :image-size="92" description="暂无健康数据" />
          </template>
        </ElTable>
      </div>

      <div class="section-card section-card--runtime span-4">
        <div class="section-head">
          <div class="section-title">
            <span class="section-icon section-icon--runtime"
              ><ArtSvgIcon icon="ri:cpu-line"
            /></span>
            <div>
              <h2>后端进程</h2>
              <p>当前服务进程和内存指标。</p>
            </div>
          </div>
        </div>
        <div class="runtime-list">
          <div v-for="item in runtimeRows" :key="item.label">
            <span>{{ item.label }}</span>
            <b>{{ item.value }}</b>
          </div>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card section-card--storage span-4">
        <div class="section-head">
          <div class="section-title">
            <span class="section-icon section-icon--storage"
              ><ArtSvgIcon icon="ri:cloud-line"
            /></span>
            <div>
              <h2>存储</h2>
              <p>当前上传链路配置。</p>
            </div>
          </div>
        </div>
        <div class="key-value-list">
          <div>
            <span>类型</span>
            <b>{{ summaryComponent('storage')?.provider || '-' }}</b>
          </div>
          <div>
            <span>Endpoint</span>
            <b>{{ summaryComponent('storage')?.endpoint || '-' }}</b>
          </div>
          <div>
            <span>Bucket</span>
            <b>{{ summaryComponent('storage')?.bucket || '-' }}</b>
          </div>
          <div>
            <span>公开域名</span>
            <b>{{ summaryComponent('storage')?.public_base_url || '-' }}</b>
          </div>
        </div>
      </div>

      <div class="section-card section-card--queue span-4">
        <div class="section-head">
          <div class="section-title">
            <span class="section-icon section-icon--queue"
              ><ArtSvgIcon icon="ri:inbox-archive-line"
            /></span>
            <div>
              <h2>队列</h2>
              <p>Redis 队列积压和死信。</p>
            </div>
          </div>
          <div class="queue-actions">
            <ElButton
              size="small"
              :icon="Refresh"
              :loading="queueActionLoading"
              @click="retryDeadQueueAction"
            >
              重试死信
            </ElButton>
            <ElButton
              size="small"
              type="danger"
              plain
              :icon="Delete"
              :loading="queueActionLoading"
              @click="clearDeadQueueAction"
            >
              清理死信
            </ElButton>
          </div>
        </div>
        <div class="orb-grid">
          <div
            v-for="item in queueRows"
            :key="item.label"
            class="data-orb"
            :class="[`tone-${item.tone}`, { 'has-progress': item.progress !== null }]"
            :style="orbStyle(item.progress)"
            :title="
              item.oldestAge > 0 ? `Oldest task ${formatDuration(item.oldestAge * 1000)}` : ''
            "
          >
            <span>{{ item.label }}</span>
            <strong>{{ item.value }}</strong>
            <em v-if="item.progress !== null">{{ formatRate(item.progress) }}</em>
            <small v-if="item.oldestAge > 0">{{ formatDuration(item.oldestAge * 1000) }}</small>
          </div>
        </div>
      </div>

      <div class="section-card section-card--socket span-4">
        <div class="section-head">
          <div class="section-title">
            <span class="section-icon section-icon--socket"
              ><ArtSvgIcon icon="ri:radar-line"
            /></span>
            <div>
              <h2>WebSocket</h2>
              <p>在线连接、断连和发送队列。</p>
            </div>
          </div>
        </div>
        <div class="orb-grid">
          <div class="data-orb tone-cyan">
            <span>连接</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.online_connections) }}</strong>
          </div>
          <div
            class="data-orb tone-green"
            :class="{ 'has-progress': progressValue('websocket', 'online_users') !== null }"
            :style="orbStyle(progressValue('websocket', 'online_users'))"
          >
            <span>在线用户</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.online_users) }}</strong>
            <em v-if="progressValue('websocket', 'online_users') !== null">{{
              formatRate(progressValue('websocket', 'online_users'))
            }}</em>
          </div>
          <div
            class="data-orb tone-violet"
            :class="{ 'has-progress': progressValue('websocket', 'active_chats') !== null }"
            :style="orbStyle(progressValue('websocket', 'active_chats'))"
          >
            <span>活跃会话</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.active_chats) }}</strong>
            <em v-if="progressValue('websocket', 'active_chats') !== null">{{
              formatRate(progressValue('websocket', 'active_chats'))
            }}</em>
          </div>
          <div class="data-orb tone-orange">
            <span>累计断连</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.total_disconnects) }}</strong>
          </div>
          <div
            class="data-orb"
            :class="
              Number(summaryComponent('websocket')?.dropped_messages || 0) > 0
                ? 'tone-danger'
                : 'tone-slate'
            "
          >
            <span>丢弃消息</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.dropped_messages) }}</strong>
          </div>
          <div
            class="data-orb tone-blue"
            :class="{ 'has-progress': progressValue('websocket', 'broadcast_queue') !== null }"
            :style="orbStyle(progressValue('websocket', 'broadcast_queue'))"
          >
            <span>广播队列</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.broadcast_queue_len) }}</strong>
            <em v-if="progressValue('websocket', 'broadcast_queue') !== null">{{
              formatRate(progressValue('websocket', 'broadcast_queue'))
            }}</em>
          </div>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card section-card--failure span-8">
        <div class="section-head">
          <div class="section-title">
            <span class="section-icon section-icon--failure"
              ><ArtSvgIcon icon="ri:file-warning-line"
            /></span>
            <div>
              <h2>最近上传失败</h2>
              <p>OSS/local 上传失败的用户、类型和原因。</p>
            </div>
          </div>
          <ElButton :icon="Refresh" :loading="uploadLogLoading" @click="loadUploadLogs">
            刷新
          </ElButton>
        </div>
        <ElTable
          v-loading="uploadLogLoading"
          :data="uploadFailures"
          class="clean-table"
          height="300"
        >
          <ElTableColumn prop="created_at" label="时间" min-width="150" />
          <ElTableColumn prop="actor_type" label="来源" width="90">
            <template #default="{ row }">{{ actorLabel(row.actor_type) }}</template>
          </ElTableColumn>
          <ElTableColumn prop="user_id" label="用户" width="86">
            <template #default="{ row }">{{ row.user_id || row.admin_id || '-' }}</template>
          </ElTableColumn>
          <ElTableColumn prop="media_type" label="类型" width="110" />
          <ElTableColumn prop="provider" label="存储" width="100" />
          <ElTableColumn prop="duration_ms" label="耗时" width="96">
            <template #default="{ row }">{{ row.duration_ms }} ms</template>
          </ElTableColumn>
          <ElTableColumn prop="error" label="错误" min-width="240" show-overflow-tooltip />
          <template #empty>
            <ElEmpty :image-size="92" description="暂无上传失败" />
          </template>
        </ElTable>
      </div>

      <div class="section-card section-card--push span-4">
        <div class="section-head">
          <div class="section-title">
            <span class="section-icon section-icon--push"
              ><ArtSvgIcon icon="ri:send-plane-line"
            /></span>
            <div>
              <h2>推送</h2>
              <p>最近窗口投递质量。</p>
            </div>
          </div>
        </div>
        <div class="orb-grid">
          <div
            class="data-orb tone-blue"
            :class="{ 'has-progress': progressValue('push', 'success_rate') !== null }"
            :style="orbStyle(progressValue('push', 'success_rate'))"
          >
            <span>发送</span>
            <strong>{{ formatNumber(summaryComponent('push')?.total) }}</strong>
            <em v-if="progressValue('push', 'success_rate') !== null">{{
              formatRate(progressValue('push', 'success_rate'))
            }}</em>
          </div>
          <div
            class="data-orb"
            :class="[
              Number(summaryComponent('push')?.failed || 0) > 0 ? 'tone-danger' : 'tone-slate',
              { 'has-progress': progressValue('push', 'failed') !== null }
            ]"
            :style="orbStyle(progressValue('push', 'failed'))"
          >
            <span>失败</span>
            <strong>{{ formatNumber(summaryComponent('push')?.failed) }}</strong>
            <em v-if="progressValue('push', 'failed') !== null">
              {{ formatRate(progressValue('push', 'failed')) }}
            </em>
          </div>
          <div
            class="data-orb tone-green"
            :class="{ 'has-progress': progressValue('push', 'success_rate') !== null }"
            :style="orbStyle(progressValue('push', 'success_rate'))"
          >
            <span>成功率</span>
            <strong>{{ formatRate(summaryComponent('push')?.success_rate) }}</strong>
            <em v-if="progressValue('push', 'success_rate') !== null">{{
              formatRate(progressValue('push', 'success_rate'))
            }}</em>
          </div>
          <div class="data-orb tone-slate">
            <span>窗口</span>
            <strong>{{ checkWindow }}</strong>
          </div>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card section-card--maintenance span-12">
        <div class="section-head maintenance-head">
          <div class="section-title">
            <span class="section-icon section-icon--maintenance"
              ><ArtSvgIcon icon="ri:archive-stack-line"
            /></span>
            <div>
              <h2>数据治理摘要</h2>
              <p
                >这里仅展示运行状态和最近记录；候选明细、媒体预览与正式操作已迁移到独立治理中心。</p
              >
            </div>
          </div>
          <div class="maintenance-actions">
            <ElTag :type="maintenanceConfig?.enabled ? 'success' : 'info'" effect="plain">
              自动任务{{ maintenanceConfig?.enabled ? '已开启' : '已关闭' }}
            </ElTag>
            <ElTag :type="maintenanceConfig?.dry_run ? 'warning' : 'danger'" effect="plain">
              {{ maintenanceConfig?.dry_run ? '自动预演' : '正式执行' }}
            </ElTag>
            <ElTag :type="backupGateReady ? 'success' : 'danger'" effect="plain">
              备份门禁{{ backupGateReady ? '已就绪' : '未就绪' }}
            </ElTag>
            <ElButton type="primary" @click="router.push('/system/data-governance')">
              进入数据治理中心
            </ElButton>
          </div>
        </div>

        <div class="maintenance-summary">
          <span
            >批次 <b>{{ formatNumber(maintenanceConfig?.batch_size) }}</b></span
          >
          <span
            >单任务上限 <b>{{ formatNumber(maintenanceConfig?.max_delete_per_job) }}</b></span
          >
          <span
            >执行间隔 <b>{{ formatGoDuration(maintenanceConfig?.interval) }}</b></span
          >
          <span
            >备份有效期 <b>{{ formatGoDuration(maintenanceConfig?.backup_max_age) }}</b></span
          >
          <span
            >最近备份 <b>{{ maintenanceBackupText }}</b></span
          >
        </div>

        <ElAlert
          v-if="maintenanceError"
          :title="maintenanceError"
          type="warning"
          :closable="false"
          show-icon
          class="maintenance-error"
        />
        <ElAlert
          v-else-if="!backupGateReady"
          :title="`正式清理已锁定：${backupGateMessage}`"
          type="warning"
          :closable="false"
          show-icon
          class="maintenance-error"
        />
        <div v-loading="maintenanceLoading" class="maintenance-glance">
          <div
            v-for="run in latestMaintenanceRuns.slice(0, 3)"
            :key="run.run_id"
            class="glance-item"
          >
            <div class="maintenance-job">
              <strong>{{ maintenanceJobLabel(run.job_name) }}</strong>
              <small>{{ formatDateTime(run.started_at) }}</small>
            </div>
            <ElTag :type="maintenanceStatusTag(run.status)" effect="light">
              {{ maintenanceStatusLabel(run.status) }}
            </ElTag>
            <span>候选 {{ formatNumber(run.candidate_count) }}</span>
            <span>已删除 {{ formatNumber(run.deleted_count) }}</span>
          </div>
          <ElEmpty
            v-if="latestMaintenanceRuns.length === 0"
            :image-size="72"
            description="暂无维护记录，请进入数据治理中心查看"
          />
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
  import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue'
  import { useRouter } from 'vue-router'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { Delete, Refresh } from '@element-plus/icons-vue'
  import { echarts, type EChartsOption } from '@/plugins/echarts'
  import { useUserStore } from '@/store/modules/user'
  import {
    getUploadLogs,
    getObservabilityAlerts,
    getMaintenanceStatus,
    acknowledgeObservabilityAlert,
    clearDeadQueue,
    getSystemHealthDetail,
    getSystemHealthTrend,
    retryDeadQueue,
    unacknowledgeObservabilityAlert,
    type HealthComponent,
    type HealthMetricSnapshotItem,
    type HealthStatus,
    type MaintenanceConfig,
    type MaintenanceJobRun,
    type MaintenanceStatusResponse,
    type ObservabilityAlertEvent,
    type ObservabilityAlertSummary,
    type SystemHealthDetailResponse,
    type UploadLogItem
  } from '@/api/admin'

  defineOptions({ name: 'SystemHealth' })

  // 健康详情、失败日志和趋势采样来自三个独立接口，分别维护加载状态，互不阻塞。
  const loading = ref(false)
  const uploadLogLoading = ref(false)
  const trendLoading = ref(false)
  const alertLoading = ref(false)
  const maintenanceLoading = ref(false)
  const queueActionLoading = ref(false)
  const trendMinutes = ref(1440)
  const alertTab = ref<'firing' | 'resolved'>('firing')
  const health = ref<SystemHealthDetailResponse | null>(null)
  const alertSummary = ref<ObservabilityAlertSummary>({
    available: false,
    receiver: '',
    firing: [],
    resolved: []
  })
  const uploadFailures = ref<UploadLogItem[]>([])
  const trendData = ref<HealthMetricSnapshotItem[]>([])
  const trendChartRef = ref<HTMLElement>()
  const maintenance = ref<MaintenanceStatusResponse | null>(null)
  const maintenanceError = ref('')
  const userStore = useUserStore()
  const router = useRouter()
  let trendChart: ReturnType<typeof echarts.init> | null = null
  let healthStreamAbort: AbortController | null = null
  let healthStreamReconnectTimer: number | null = null

  const components = computed(() => health.value?.components || [])
  const uptimeDaysText = computed(() => {
    if (!health.value) return '-'
    const uptimeSeconds = Number(health.value.uptime_seconds)
    if (!Number.isFinite(uptimeSeconds)) return '-'
    return `${Math.floor(Math.max(0, uptimeSeconds) / 86400)}天`
  })
  const checkWindow = computed(() => health.value?.summary?.check_window || '15m')
  const apiHealth = computed(() => health.value?.summary?.api)
  const lastUpdatedAt = ref<Date | null>(null)
  const lastUpdatedText = computed(() =>
    lastUpdatedAt.value
      ? `更新于 ${lastUpdatedAt.value.toLocaleTimeString('zh-CN', {
          hour: '2-digit',
          minute: '2-digit',
          second: '2-digit'
        })}`
      : '等待首次刷新'
  )
  const queueBacklog = computed(() => {
    const queue = summaryComponent('queue')
    return formatNumber(
      Number(queue?.message_send || 0) +
        Number(queue?.message_sync || 0) +
        Number(queue?.push_notify || 0) +
        Number(queue?.delayed || 0) +
        Number(queue?.dead || 0)
    )
  })
  const trendSubtitle = computed(() => {
    const range = trendRangeLabel(trendMinutes.value)
    if (trendData.value.length === 0) return `近 ${range}暂无采样`
    return `近 ${range}，${trendData.value.length} 个采样点`
  })
  const visibleAlerts = computed<ObservabilityAlertEvent[]>(
    () => alertSummary.value[alertTab.value] || []
  )
  const maintenanceConfig = computed<MaintenanceConfig | null>(
    () => maintenance.value?.config || null
  )
  const backupGateReady = computed(() => maintenance.value?.backup_gate?.ready === true)
  const backupGateMessage = computed(() => {
    const gate = maintenance.value?.backup_gate
    if (!gate) return '尚未读取近期已验证备份状态'
    if (!gate.last_success_at) return '未找到已验证备份记录'
    if (Number(gate.age_seconds || 0) < 0) return '备份时间异常，请校准服务器时间'
    const maxAgeHours = Number(gate.max_age || 0) / 1_000_000_000 / 3600
    return `最近已验证备份已超过 ${maxAgeHours} 小时`
  })
  const maintenanceBackupText = computed(() => {
    const gate = maintenance.value?.backup_gate
    if (!gate?.last_success_at) return '无已验证备份'
    const age = Number(gate.age_seconds || 0)
    if (age < 60) return '刚刚'
    if (age < 3600) return `${Math.floor(age / 60)} 分钟前`
    return `${(age / 3600).toFixed(1)} 小时前`
  })
  const latestMaintenanceRuns = computed<MaintenanceJobRun[]>(() => {
    const seen = new Set<string>()
    return (maintenance.value?.runs || []).filter((run) => {
      if (seen.has(run.job_name)) return false
      seen.add(run.job_name)
      return true
    })
  })

  const summaryComponent = (key: 'storage' | 'upload' | 'websocket' | 'push' | 'queue' | 'api') =>
    health.value?.summary?.[key]

  const progressValue = (
    component: 'storage' | 'upload' | 'websocket' | 'push' | 'queue' | 'api',
    key: string
  ) => {
    const ratio = summaryComponent(component)?.progress?.[key]?.ratio
    return typeof ratio === 'number' && Number.isFinite(ratio) ? ratio : null
  }

  const orbStyle = (progress: number | null) =>
    progress === null
      ? undefined
      : ({ '--orb-progress': `${Math.min(100, Math.max(0, progress))}%` } as Record<string, string>)

  const componentValue = (name: string, key: string) =>
    components.value.find((item) => item.name === name)?.[key]

  const statusLabel = (status?: HealthStatus | string) => {
    if (status === 'ok') return '正常'
    if (status === 'warning') return '警告'
    if (status === 'error') return '异常'
    return '未读取'
  }

  const statusTag = (status?: HealthStatus | string) => {
    if (status === 'ok') return 'success'
    if (status === 'warning') return 'warning'
    if (status === 'error') return 'danger'
    return 'info'
  }

  const statusTone = (status?: HealthStatus | string) => {
    if (status === 'ok') return 'success'
    if (status === 'warning') return 'warning'
    if (status === 'error') return 'danger'
    return 'info'
  }

  const statusIcon = (status?: HealthStatus | string) => {
    if (status === 'ok') return 'ri:shield-check-line'
    if (status === 'warning') return 'ri:alarm-warning-line'
    if (status === 'error') return 'ri:close-circle-line'
    return 'ri:pulse-line'
  }

  const formatNumber = (value: unknown) => Number(value || 0).toLocaleString()
  const formatRate = (value: unknown) => `${Number(value || 0).toFixed(1)}%`
  const formatDuration = (value: unknown) => {
    const milliseconds = Number(value || 0)
    if (!Number.isFinite(milliseconds) || milliseconds <= 0) return '-'
    if (milliseconds < 1000) return `${Math.round(milliseconds)} ms`
    return `${(milliseconds / 1000).toFixed(1)} s`
  }
  const formatGoDuration = (value?: number) => {
    const seconds = Number(value || 0) / 1_000_000_000
    if (!Number.isFinite(seconds) || seconds <= 0) return '-'
    if (seconds >= 86400) return `${seconds / 86400} 天`
    if (seconds >= 3600) return `${seconds / 3600} 小时`
    if (seconds >= 60) return `${seconds / 60} 分钟`
    return `${seconds} 秒`
  }
  const formatTrendTime = (value: string) => {
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return value || '-'
    const month = `${date.getMonth() + 1}`.padStart(2, '0')
    const day = `${date.getDate()}`.padStart(2, '0')
    const hour = `${date.getHours()}`.padStart(2, '0')
    const minute = `${date.getMinutes()}`.padStart(2, '0')
    if (trendMinutes.value > 1440) return `${month}-${day} ${hour}:${minute}`
    return `${hour}:${minute}`
  }
  const trendRangeLabel = (minutes: number) => {
    if (minutes < 60) return `${minutes} 分钟`
    if (minutes < 1440) return `${minutes / 60} 小时`
    return `${minutes / 1440} 天`
  }
  const formatDateTime = (value?: string) => {
    if (!value) return '-'
    const date = new Date(value)
    return Number.isNaN(date.getTime()) ? value : date.toLocaleString()
  }
  const severityLabel = (value?: string) =>
    value === 'critical' ? '严重' : value === 'warning' ? '警告' : value || '信息'
  const severityTag = (value?: string) =>
    value === 'critical' ? 'danger' : value === 'warning' ? 'warning' : 'info'
  const actorLabel = (value?: string) => {
    if (value === 'admin') return '后台'
    if (value === 'user') return '用户'
    return value || '-'
  }
  const maintenanceJobLabels: Record<string, string> = {
    upload_logs: '上传诊断日志',
    push_delivery_logs: '推送投递日志',
    admin_login_logs: '管理员登录日志',
    admin_security_events: '管理员安全事件',
    observability_alert_events: '告警事件',
    outbox_completed: '已完成 Outbox',
    outbox_dead: 'Outbox 死信',
    external_cleanup_success: '外部清理成功任务',
    external_cleanup_failed: '外部清理失败任务',
    deleted_media_metadata: '已删除媒体元数据'
  }
  const maintenanceJobLabel = (value: string) => maintenanceJobLabels[value] || value
  const maintenanceStatusLabel = (value: MaintenanceJobRun['status']) => {
    if (value === 'success') return '成功'
    if (value === 'dry_run') return '预演'
    if (value === 'running') return '执行中'
    if (value === 'failed') return '失败'
    return '未执行'
  }
  const maintenanceStatusTag = (value: MaintenanceJobRun['status']) => {
    if (value === 'success') return 'success'
    if (value === 'dry_run') return 'warning'
    if (value === 'running') return 'primary'
    if (value === 'failed') return 'danger'
    return 'info'
  }

  const runtimeRows = computed(() => {
    const runtime = health.value?.runtime
    if (!runtime) return []
    return [
      { label: 'Go', value: runtime.go_version },
      { label: '系统', value: `${runtime.os}/${runtime.arch}` },
      { label: 'CPU', value: `${runtime.cpu_num}` },
      { label: 'Goroutine', value: formatNumber(runtime.goroutines) },
      { label: 'Alloc', value: `${runtime.memory_alloc_mb} MB` },
      { label: 'Heap', value: `${runtime.heap_inuse_mb} MB` },
      { label: 'Sys', value: `${runtime.memory_sys_mb} MB` },
      { label: 'GC', value: formatNumber(runtime.gc_count) },
      { label: '节点', value: health.value?.observability?.node_id || '-' },
      { label: '环境', value: health.value?.observability?.environment || '-' },
      {
        label: 'Prometheus',
        value: health.value?.observability?.metrics_enabled ? '已启用' : '未启用'
      },
      { label: 'Trace', value: health.value?.observability?.tracing_enabled ? '已启用' : '未启用' }
    ]
  })

  const queueRows = computed(() => {
    const queue = summaryComponent('queue')
    const oldest = (key: string) =>
      Number((queue?.oldest_task_age_seconds as Record<string, unknown> | undefined)?.[key] || 0)
    return [
      {
        label: '发送',
        value: formatNumber(queue?.message_send),
        tone: 'blue',
        progress: progressValue('queue', 'message_send'),
        oldestAge: oldest('message_send')
      },
      {
        label: '同步',
        value: formatNumber(queue?.message_sync),
        tone: 'cyan',
        progress: progressValue('queue', 'message_sync'),
        oldestAge: oldest('message_sync')
      },
      {
        label: '推送',
        value: formatNumber(queue?.push_notify),
        tone: 'violet',
        progress: progressValue('queue', 'push_notify'),
        oldestAge: oldest('push_notify')
      },
      {
        label: '延迟',
        value: formatNumber(queue?.delayed),
        tone: Number(queue?.delayed || 0) > 0 ? 'orange' : 'slate',
        progress: progressValue('queue', 'delayed'),
        oldestAge: oldest('delayed')
      },
      {
        label: '死信',
        value: formatNumber(queue?.dead),
        tone: Number(queue?.dead || 0) > 0 ? 'danger' : 'green',
        progress: progressValue('queue', 'dead'),
        oldestAge: oldest('dead')
      }
    ]
  })

  const componentDetail = (row: HealthComponent) => {
    switch (row.name) {
      case 'MySQL':
        return `连接 ${formatNumber(row.open_connections)}，使用中 ${formatNumber(row.in_use)}，空闲 ${formatNumber(row.idle)}`
      case 'MongoDB':
      case 'Redis':
        return row.error ? '检查失败' : '连接可用'
      case 'Storage':
        return `${row.provider || '-'} / ${row.bucket || '-'}`
      case 'Upload':
        return `上传 ${formatNumber(row.total)}，失败 ${formatNumber(row.failed)}，失败率 ${formatRate(row.failure_rate)}`
      case 'WebSocket':
        return `连接 ${formatNumber(row.online_connections)}，断连 ${formatNumber(row.total_disconnects)}，丢弃 ${formatNumber(row.dropped_messages)}`
      case 'Push':
        return `发送 ${formatNumber(row.total)}，失败 ${formatNumber(row.failed)}，成功率 ${formatRate(row.success_rate)}`
      case 'Queue':
        return `发送 ${formatNumber(row.message_send)}，推送 ${formatNumber(row.push_notify)}，死信 ${formatNumber(row.dead)}`
      case 'API':
        return `5xx ${formatRate(row.error_rate)} / P95 ${formatDuration(Number(row.p95_latency_ms || 0))}`
      default:
        return '-'
    }
  }

  const loadHealth = async () => {
    loading.value = true
    try {
      health.value = await getSystemHealthDetail()
    } catch {
      ElMessage.error('读取系统健康状态失败')
    } finally {
      loading.value = false
    }
  }

  const loadUploadLogs = async () => {
    uploadLogLoading.value = true
    try {
      const result = await getUploadLogs({
        page: 1,
        page_size: 8,
        success: 'false'
      })
      uploadFailures.value = result.list || []
    } catch {
      ElMessage.error('读取上传失败日志失败')
    } finally {
      uploadLogLoading.value = false
    }
  }

  const loadAlerts = async () => {
    alertLoading.value = true
    try {
      const result = await getObservabilityAlerts()
      // Older/local API responses may encode empty slices as null; normalize them
      // before the template accesses length or renders the active tab.
      alertSummary.value = {
        ...result,
        firing: Array.isArray(result.firing) ? result.firing : [],
        resolved: Array.isArray(result.resolved) ? result.resolved : []
      }
    } catch {
      alertSummary.value = {
        available: false,
        receiver: '',
        firing: [],
        resolved: [],
        error: '读取告警中心失败'
      }
    } finally {
      alertLoading.value = false
    }
  }

  const loadMaintenance = async () => {
    maintenanceLoading.value = true
    maintenanceError.value = ''
    try {
      maintenance.value = await getMaintenanceStatus()
    } catch {
      maintenanceError.value = '读取数据保留任务失败，请检查 API、权限和维护任务审计表。'
    } finally {
      maintenanceLoading.value = false
    }
  }

  const renderTrendChart = () => {
    // 无数据或容器不存在时销毁旧实例，防止切换时间范围后残留过期图表。
    if (!trendChartRef.value || trendData.value.length === 0) {
      trendChart?.dispose()
      trendChart = null
      return
    }
    if (!trendChart) {
      trendChart = echarts.init(trendChartRef.value)
    }

    const labels = trendData.value.map((item) => formatTrendTime(item.created_at))
    const option: EChartsOption = {
      color: ['#2563eb', '#dc2626', '#f59e0b', '#059669', '#7c3aed'],
      tooltip: {
        trigger: 'axis',
        backgroundColor: '#ffffff',
        borderColor: '#e5e7eb',
        borderWidth: 1,
        textStyle: {
          color: '#111827'
        }
      },
      legend: {
        top: 0,
        right: 0,
        itemWidth: 12,
        itemHeight: 8,
        textStyle: {
          color: '#475569'
        }
      },
      grid: {
        left: 16,
        right: 56,
        top: 42,
        bottom: 18,
        containLabel: true
      },
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: labels,
        axisLine: {
          lineStyle: {
            color: '#e5e7eb'
          }
        },
        axisTick: {
          show: false
        },
        axisLabel: {
          color: '#64748b'
        }
      },
      yAxis: [
        {
          type: 'value',
          minInterval: 1,
          name: '数量',
          nameTextStyle: {
            color: '#64748b'
          },
          axisLine: {
            show: false
          },
          axisTick: {
            show: false
          },
          axisLabel: {
            color: '#64748b'
          },
          splitLine: {
            lineStyle: {
              color: '#eef2f7',
              type: 'dashed'
            }
          }
        },
        {
          type: 'value',
          minInterval: 1,
          name: 'MB',
          nameTextStyle: {
            color: '#64748b'
          },
          axisLine: {
            show: false
          },
          axisTick: {
            show: false
          },
          axisLabel: {
            color: '#64748b'
          },
          splitLine: {
            show: false
          }
        }
      ],
      series: [
        {
          name: '在线连接',
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.ws_online_connections || 0)
        },
        {
          name: '上传失败',
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.upload_failed || 0)
        },
        {
          name: '推送失败',
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.push_failed || 0)
        },
        {
          name: '死信队列',
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.queue_dead || 0)
        },
        {
          name: '内存',
          type: 'line',
          smooth: true,
          symbol: 'none',
          yAxisIndex: 1,
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.memory_alloc_mb || 0)
        }
      ]
    }
    trendChart.setOption(option, true)
    window.setTimeout(() => trendChart?.resize(), 80)
  }

  const loadTrend = async () => {
    trendLoading.value = true
    try {
      const result = await getSystemHealthTrend({ minutes: trendMinutes.value })
      trendData.value = result.list || []
      await nextTick()
      renderTrendChart()
    } catch {
      trendData.value = []
      trendChart?.dispose()
      trendChart = null
      ElMessage.error('读取健康趋势失败')
    } finally {
      trendLoading.value = false
    }
  }

  const retryDeadQueueAction = async () => {
    queueActionLoading.value = true
    try {
      const result = await retryDeadQueue(100)
      ElMessage.success(`已重试 ${result.moved} 条死信任务`)
      await loadHealth()
    } catch {
      ElMessage.error('重试死信队列失败')
    } finally {
      queueActionLoading.value = false
    }
  }

  const clearDeadQueueAction = async () => {
    try {
      await ElMessageBox.confirm(
        '最多永久删除 100 条死信任务，操作会记录到安全审计日志。',
        '确认清理队列',
        { type: 'warning', confirmButtonText: '清理', cancelButtonText: '取消' }
      )
    } catch {
      return
    }
    queueActionLoading.value = true
    try {
      const result = await clearDeadQueue(100)
      ElMessage.success(`已清理 ${result.cleared} 条死信任务`)
      await loadHealth()
    } catch {
      ElMessage.error('清理死信队列失败')
    } finally {
      queueActionLoading.value = false
    }
  }

  const toggleAlertAcknowledgement = async (row: ObservabilityAlertEvent) => {
    try {
      if (row.state === 'acknowledged') {
        await unacknowledgeObservabilityAlert(row.id)
      } else {
        await acknowledgeObservabilityAlert(row.id)
      }
      await loadAlerts()
      ElMessage.success(row.state === 'acknowledged' ? '已取消告警确认' : '已确认告警')
    } catch {
      ElMessage.error('更新告警状态失败')
    }
  }

  const applyHealthStreamEvent = (event: any) => {
    const snapshot = event?.data
    if (!snapshot || !health.value) return
    const queue = health.value.summary.queue as Record<string, any>
    queue.message_send = snapshot.queue_message_send
    queue.message_sync = snapshot.queue_message_sync
    queue.push_notify = snapshot.queue_push_notify
    queue.delayed = snapshot.queue_delayed
    queue.dead = snapshot.queue_dead
    queue.oldest_task_age_seconds = event.queue_oldest_task_age_seconds || {}
    if (event.api) health.value.summary.api = event.api
    health.value.runtime.goroutines = snapshot.goroutines
    health.value.runtime.memory_alloc_mb = snapshot.memory_alloc_mb
    if (event.alerts) {
      alertSummary.value = {
        ...event.alerts,
        firing: Array.isArray(event.alerts.firing) ? event.alerts.firing : [],
        resolved: Array.isArray(event.alerts.resolved) ? event.alerts.resolved : []
      }
    }
    lastUpdatedAt.value = new Date()
  }

  const startHealthStream = async () => {
    if (healthStreamReconnectTimer !== null) {
      window.clearTimeout(healthStreamReconnectTimer)
      healthStreamReconnectTimer = null
    }
    healthStreamAbort?.abort()
    const controller = new AbortController()
    healthStreamAbort = controller
    const token = userStore.accessToken
    if (!token) return
    try {
      const apiBase = import.meta.env.VITE_API_URL || '/api/v1'
      const response = await fetch(`${apiBase}/admin/system/health-stream`, {
        headers: { Authorization: `Bearer ${token}` },
        signal: controller.signal
      })
      if (!response.ok || !response.body) return
      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''
      while (!controller.signal.aborted) {
        const { done, value } = await reader.read()
        if (done) break
        buffer += decoder.decode(value, { stream: true })
        const blocks = buffer.split('\n\n')
        buffer = blocks.pop() || ''
        for (const block of blocks) {
          const line = block.split('\n').find((item) => item.startsWith('data:'))
          if (!line) continue
          try {
            applyHealthStreamEvent(JSON.parse(line.slice(5).trim()))
          } catch {
            // Ignore a malformed event and keep the stream alive.
          }
        }
      }
      if (!controller.signal.aborted) {
        healthStreamReconnectTimer = window.setTimeout(startHealthStream, 3000)
      }
    } catch (error) {
      if (!controller.signal.aborted) {
        console.warn('health stream disconnected', error)
        healthStreamReconnectTimer = window.setTimeout(startHealthStream, 3000)
      }
    }
  }

  const refreshAll = async () => {
    await Promise.allSettled([
      loadHealth(),
      loadUploadLogs(),
      loadTrend(),
      loadAlerts(),
      loadMaintenance()
    ])
    lastUpdatedAt.value = new Date()
  }

  const handleResize = () => {
    trendChart?.resize()
  }

  onMounted(() => {
    refreshAll()
    startHealthStream()
    window.addEventListener('resize', handleResize)
  })

  onUnmounted(() => {
    // ECharts 实例和全局监听器都不随 Vue 自动释放，需要在页面卸载时显式清理。
    window.removeEventListener('resize', handleResize)
    healthStreamAbort?.abort()
    if (healthStreamReconnectTimer !== null) window.clearTimeout(healthStreamReconnectTimer)
    trendChart?.dispose()
  })
</script>

<style lang="scss" scoped>
  .health-page {
    min-height: 100%;
    padding: 18px;
    background: #f6f8fb;
  }

  .page-head,
  .section-card,
  .metric-card {
    background: var(--el-bg-color-overlay, #fff);
    border: 1px solid var(--el-border-color-lighter, #e6ebf2);
    border-radius: 8px;
    box-shadow: 0 8px 20px rgb(15 23 42 / 3%);
  }

  .page-head {
    display: flex;
    gap: 18px;
    align-items: flex-start;
    justify-content: space-between;
    padding: 18px 20px;
    margin-bottom: 14px;
  }

  .page-title-group {
    display: flex;
    gap: 14px;
    align-items: center;
    min-width: 0;
  }

  .page-title-icon {
    position: relative;
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 60px;
    height: 60px;
    font-size: 32px;
    color: #2563eb;
    background: #eff6ff;
    border: 1px solid #bfdbfe;
    border-radius: 50%;
    box-shadow: 0 8px 18px rgb(37 99 235 / 14%);
  }

  .page-title-icon .art-svg-icon {
    position: absolute;
    top: 50%;
    left: 50%;
    display: block;
    width: 32px;
    height: 32px;
    font-size: 32px;
    color: #2563eb;
    transform: translate(-50%, -50%);
  }

  .page-head p,
  .page-head span,
  .section-head p,
  .metric-card small {
    margin: 0;
    font-size: 13px;
    line-height: 20px;
    color: #64748b;
  }

  .page-head h1 {
    margin: 4px 0 6px;
    font-size: 22px;
    font-weight: 700;
    line-height: 30px;
    color: #111827;
  }

  .head-actions,
  .section-head {
    display: flex;
    gap: 12px;
    align-items: flex-start;
    justify-content: space-between;
  }

  .queue-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    justify-content: flex-end;
  }

  .head-actions {
    align-items: center;
  }

  .live-status {
    display: grid;
    grid-template-columns: 9px auto;
    column-gap: 7px;
    align-items: center;
    padding: 8px 11px;
    font-size: 12px;
    font-weight: 650;
    color: #15803d;
    background: #f0fdf4;
    border: 1px solid #bbf7d0;
    border-radius: 18px;
  }

  .live-status small {
    grid-column: 2;
    font-size: 11px;
    font-weight: 400;
    color: #64748b;
  }

  .live-dot {
    grid-row: 1 / 3;
    width: 8px;
    height: 8px;
    background: #22c55e;
    border-radius: 50%;
    box-shadow: 0 0 0 3px rgb(34 197 94 / 12%);
  }

  .alert-head {
    align-items: center;
  }

  .section-title {
    display: flex;
    gap: 11px;
    align-items: flex-start;
    min-width: 0;
  }

  .section-icon {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 34px;
    height: 34px;
    font-size: 18px;
    color: #2563eb;
    background: #eff6ff;
    border: 1px solid #dbeafe;
    border-radius: 50%;
  }

  .section-icon--alert {
    color: #ea580c;
    background: #fff7ed;
    border-color: #fed7aa;
  }

  .section-icon--trend,
  .section-icon--socket {
    color: #0284c7;
    background: #f0f9ff;
    border-color: #bae6fd;
  }

  .section-icon--component,
  .section-icon--runtime {
    color: #16a34a;
    background: #f0fdf4;
    border-color: #bbf7d0;
  }

  .section-icon--storage {
    color: #7c3aed;
    background: #f5f3ff;
    border-color: #ddd6fe;
  }

  .section-icon--queue,
  .section-icon--push {
    color: #ca8a04;
    background: #fefce8;
    border-color: #fde68a;
  }

  .section-icon--failure {
    color: #e11d48;
    background: #fff1f2;
    border-color: #fecdd3;
  }

  .section-icon--maintenance {
    color: #0f766e;
    background: #f0fdfa;
    border-color: #99f6e4;
  }

  .alert-summary,
  .alert-meta {
    display: flex;
    gap: 8px;
    align-items: center;
  }

  .alert-tabs {
    margin-top: -4px;
  }

  .alert-error {
    margin-bottom: 12px;
  }

  .alert-meta {
    justify-content: flex-end;
    margin-top: 10px;
    font-size: 12px;
    color: #64748b;
  }

  .metric-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
    margin-bottom: 14px;
  }

  .metric-card {
    --metric-card-accent: #64748b;
    --metric-card-soft: rgb(100 116 139 / 7%);

    position: relative;
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 166px;
    padding: 16px;
    overflow: hidden;
    text-align: left;
    background:
      radial-gradient(circle at 100% 0%, var(--metric-card-soft), transparent 54%),
      linear-gradient(145deg, var(--metric-card-soft), transparent 44%),
      color-mix(in srgb, var(--el-bg-color-overlay, #fff) 74%, transparent);
    -webkit-backdrop-filter: blur(16px) saturate(128%);
    backdrop-filter: blur(16px) saturate(128%);
    transition:
      border-color 180ms ease,
      box-shadow 180ms ease,
      transform 180ms ease;
  }

  .metric-card:hover {
    border-color: #cbd5e1;
    box-shadow: 0 12px 28px rgb(15 23 42 / 7%);
    transform: translateY(-2px);
  }

  .metric-card--uptime {
    --metric-card-accent: #64748b;
    --metric-card-soft: rgb(100 116 139 / 8%);
  }

  .metric-card--connection {
    --metric-card-accent: #0891b2;
    --metric-card-soft: rgb(8 145 178 / 9%);
  }

  .metric-card--users,
  .metric-card--runtime {
    --metric-card-accent: #7c3aed;
    --metric-card-soft: rgb(124 58 237 / 8%);
  }

  .metric-card--memory {
    --metric-card-accent: #2563eb;
    --metric-card-soft: rgb(37 99 235 / 8%);
  }

  .metric-card--queue {
    --metric-card-accent: #d97706;
    --metric-card-soft: rgb(217 119 6 / 8%);
  }

  .metric-card--upload {
    --metric-card-accent: #e11d48;
    --metric-card-soft: rgb(225 29 72 / 8%);
  }

  .metric-card-head {
    display: flex;
    gap: 10px;
    align-items: center;
    justify-content: space-between;
  }

  .metric-label {
    display: block;
    font-size: 13px;
    font-weight: 650;
    line-height: 20px;
    color: #475569;
  }

  .metric-icon {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 34px;
    height: 34px;
    font-size: 17px;
    color: #475569;
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 9px;
  }

  .metric-icon--large {
    position: relative;
    width: 54px;
    height: 54px;
    font-size: 28px;
    color: #047857;
    background: #ecfdf5;
    border-color: #a7f3d0;
    border-radius: 14px;
  }

  .metric-icon--large .art-svg-icon {
    position: absolute;
    top: 50%;
    left: 50%;
    display: block;
    width: 28px;
    height: 28px;
    font-size: 28px;
    transform: translate(-50%, -50%);
  }

  .metric-icon--cyan {
    color: #0e7490;
    background: #ecfeff;
    border-color: #a5f3fc;
  }

  .metric-icon--violet {
    color: #6d28d9;
    background: #f5f3ff;
    border-color: #ddd6fe;
  }

  .metric-icon--blue {
    color: #1d4ed8;
    background: #eff6ff;
    border-color: #bfdbfe;
  }

  .metric-icon--orange {
    color: #b45309;
    background: #fffbeb;
    border-color: #fde68a;
  }

  .metric-icon--rose {
    color: #be123c;
    background: #fff1f2;
    border-color: #fecdd3;
  }

  .metric-readout {
    display: flex;
    gap: 5px;
    align-items: center;
    min-height: 48px;
    margin-top: 18px;
    font-variant-numeric: tabular-nums;
  }

  .metric-readout strong {
    max-width: 100%;
    overflow: hidden;
    font-size: clamp(25px, 1.65vw, 32px);
    font-weight: 720;
    line-height: 40px;
    color: #0f172a;
    text-overflow: ellipsis;
    letter-spacing: -0.035em;
    white-space: nowrap;
  }

  .metric-readout em {
    padding-bottom: 5px;
    font-size: 11px;
    font-style: normal;
    font-weight: 600;
    color: #64748b;
  }

  .metric-card-foot {
    margin-top: auto;
    overflow: hidden;
    font-size: 12px;
    line-height: 20px;
    color: #64748b;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .metric-card--status {
    background:
      linear-gradient(135deg, rgb(16 185 129 / 7%), transparent 54%),
      color-mix(in srgb, var(--el-bg-color-overlay, #fff) 74%, transparent);
  }

  .metric-status-chip {
    display: inline-flex;
    gap: 6px;
    align-items: center;
    padding: 3px 8px;
    font-size: 11px;
    font-weight: 650;
    color: #047857;
    background: #ecfdf5;
    border: 1px solid #a7f3d0;
    border-radius: 999px;
  }

  .metric-status-chip i {
    width: 6px;
    height: 6px;
    background: currentcolor;
    border-radius: 50%;
    box-shadow: 0 0 0 3px rgb(16 185 129 / 12%);
    animation: livePulse 2.2s ease-in-out infinite;
  }

  .metric-status-main {
    display: flex;
    gap: 11px;
    align-items: center;
    margin-top: 13px;
  }

  .metric-status-main > div {
    min-width: 0;
  }

  .metric-status-main strong,
  .metric-status-main span {
    display: block;
  }

  .metric-status-main strong {
    font-size: 22px;
    font-weight: 720;
    line-height: 28px;
    color: #047857;
  }

  .metric-status-main span {
    overflow: hidden;
    font-size: 11px;
    line-height: 18px;
    color: #64748b;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .metric-health-strip {
    display: flex;
    gap: 10px;
    justify-content: space-between;
    padding-top: 10px;
    margin-top: auto;
    font-size: 11px;
    color: #64748b;
    border-top: 1px solid rgb(16 185 129 / 14%);
  }

  .metric-health-strip b {
    margin-left: 3px;
    font-variant-numeric: tabular-nums;
    color: #0f172a;
  }

  .metric-card--status.warning .metric-icon--large,
  .metric-card--status.warning .metric-status-chip {
    color: #b45309;
    background: #fffbeb;
    border-color: #fde68a;
  }

  .metric-card--status.warning .metric-status-main strong {
    color: #b45309;
  }

  .metric-card--status.danger .metric-icon--large,
  .metric-card--status.danger .metric-status-chip {
    color: #b91c1c;
    background: #fef2f2;
    border-color: #fecaca;
  }

  .metric-card--status.danger .metric-status-main strong {
    color: #b91c1c;
  }

  .metric-card--status.info .metric-icon--large,
  .metric-card--status.info .metric-status-chip {
    color: #475569;
    background: #f8fafc;
    border-color: #e2e8f0;
  }

  .metric-card--status.info .metric-status-main strong {
    color: #334155;
  }

  @keyframes livePulse {
    0%,
    100% {
      opacity: 1;
      transform: scale(1);
    }

    50% {
      opacity: 0.62;
      transform: scale(0.76);
    }
  }

  .content-grid {
    display: grid;
    grid-template-columns: repeat(12, minmax(0, 1fr));
    gap: 14px;
    margin-bottom: 14px;
  }

  .span-4 {
    grid-column: span 4;
  }

  .span-8 {
    grid-column: span 8;
  }

  .span-12 {
    grid-column: 1 / -1;
  }

  .section-card {
    --section-card-accent: #3b82f6;
    --section-card-soft: rgb(59 130 246 / 5%);

    min-width: 0;
    padding: 18px;
    background:
      radial-gradient(circle at 100% 0%, var(--section-card-soft), transparent 340px),
      linear-gradient(145deg, var(--section-card-soft), transparent 220px),
      color-mix(in srgb, var(--el-bg-color-overlay, #fff) 74%, transparent);
    -webkit-backdrop-filter: blur(16px) saturate(128%);
    backdrop-filter: blur(16px) saturate(128%);
  }

  .section-card--alert {
    --section-card-accent: #ea580c;
    --section-card-soft: rgb(234 88 12 / 5%);
  }

  .section-card--failure {
    --section-card-accent: #e11d48;
    --section-card-soft: rgb(225 29 72 / 5%);
  }

  .section-card--trend,
  .section-card--socket {
    --section-card-accent: #0284c7;
    --section-card-soft: rgb(2 132 199 / 5%);
  }

  .section-card--component,
  .section-card--runtime {
    --section-card-accent: #16a34a;
    --section-card-soft: rgb(22 163 74 / 5%);
  }

  .section-card--storage {
    --section-card-accent: #7c3aed;
    --section-card-soft: rgb(124 58 237 / 5%);
  }

  .section-card--queue,
  .section-card--push {
    --section-card-accent: #ca8a04;
    --section-card-soft: rgb(202 138 4 / 5%);
  }

  .section-card--maintenance {
    --section-card-accent: #0f766e;
    --section-card-soft: rgb(15 118 110 / 5%);
  }

  .maintenance-head {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;
  }

  .maintenance-actions,
  .maintenance-summary {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }

  .maintenance-summary {
    padding: 10px 12px;
    margin-bottom: 12px;
    font-size: 12px;
    color: #64748b;
    background: color-mix(in srgb, var(--section-card-accent) 4%, var(--el-bg-color));
    border: 1px solid color-mix(in srgb, var(--section-card-accent) 13%, transparent);
    border-radius: 8px;
  }

  .maintenance-summary span:not(:last-child)::after {
    margin-left: 8px;
    color: #cbd5e1;
    content: '/';
  }

  .maintenance-summary b {
    margin-left: 3px;
    font-variant-numeric: tabular-nums;
    color: var(--el-text-color-primary);
  }

  .maintenance-error {
    margin-bottom: 12px;
  }

  .maintenance-glance {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 10px;
    min-height: 82px;
  }

  .glance-item {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 7px 12px;
    align-items: center;
    padding: 12px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    background: var(--el-fill-color-lighter);
    border: 1px solid var(--el-border-color-extra-light);
    border-radius: 9px;
  }

  .maintenance-job {
    display: grid;
    gap: 2px;
  }

  .maintenance-job strong {
    font-size: 13px;
    color: var(--el-text-color-primary);
  }

  .maintenance-job small {
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 11px;
    color: var(--el-text-color-secondary);
  }

  .section-head {
    margin-bottom: 14px;
  }

  .section-head h2 {
    margin: 0 0 4px;
    font-size: 17px;
    font-weight: 650;
    line-height: 24px;
    color: #111827;
  }

  .trend-head {
    align-items: center;
  }

  .trend-chart-wrap {
    position: relative;
    min-height: 336px;
  }

  .trend-chart {
    width: 100%;
    height: 336px;
  }

  .clean-table {
    --el-table-border-color: #edf2f7;
    --el-table-header-bg-color: #f8fafc;
    --el-table-header-text-color: #475569;

    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .component-name {
    display: flex;
    gap: 8px;
    align-items: center;
    font-weight: 600;
  }

  .status-dot {
    width: 8px;
    height: 8px;
    background: #cbd5e1;
    border-radius: 999px;
  }

  .status-dot.success {
    background: #10b981;
  }

  .status-dot.warning {
    background: #f59e0b;
  }

  .status-dot.danger {
    background: #ef4444;
  }

  .detail-line {
    overflow: hidden;
    color: #334155;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .runtime-list,
  .key-value-list {
    display: grid;
    gap: 10px;
  }

  .runtime-list div,
  .key-value-list div {
    display: flex;
    gap: 12px;
    align-items: center;
    justify-content: space-between;
    padding: 10px 12px;
    background: #f8fafc;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .runtime-list span,
  .key-value-list span {
    font-size: 13px;
    color: #64748b;
  }

  .runtime-list b,
  .key-value-list b {
    max-width: 70%;
    overflow: hidden;
    font-size: 13px;
    color: #111827;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .orb-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px;
    padding: 8px 2px 12px;
  }

  .data-orb {
    --orb-color: #64748b;

    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    justify-self: center;
    width: 116px;
    height: 116px;
    background: var(--el-bg-color);
    border: 8px solid color-mix(in srgb, var(--orb-color) 18%, var(--el-fill-color-light));
    border-radius: 50%;
    box-shadow:
      0 0 0 1px rgb(255 255 255 / 88%),
      0 8px 18px rgb(15 23 42 / 6%);
    transition:
      transform 180ms ease,
      box-shadow 180ms ease;
    animation: healthOrbIn 560ms cubic-bezier(0.22, 1, 0.36, 1) both;
    will-change: transform, box-shadow;

    &.has-progress {
      position: relative;
      background: conic-gradient(
        var(--orb-color) var(--orb-progress),
        var(--el-fill-color-light) var(--orb-progress)
      );
      isolation: isolate;
      border-color: transparent;
      animation:
        healthOrbIn 560ms cubic-bezier(0.22, 1, 0.36, 1) both,
        healthOrbGlow 2.9s 760ms ease-in-out infinite;

      &::before {
        position: absolute;
        inset: 8px;
        z-index: -1;
        content: '';
        background: var(--el-bg-color);
        border-radius: 50%;
      }

      > * {
        position: relative;
        z-index: 1;
      }

      &::after {
        position: absolute;
        inset: -8px;
        z-index: 0;
        pointer-events: none;
        content: '';
        background: conic-gradient(
          from -38deg,
          transparent 0deg,
          rgb(255 255 255 / 0%) 18deg,
          rgb(255 255 255 / 68%) 28deg,
          rgb(255 255 255 / 0%) 42deg,
          transparent 58deg
        );
        border-radius: 50%;
        opacity: 0;
        animation: healthOrbSweep 3.8s 950ms ease-in-out infinite;
      }
    }

    &:hover {
      box-shadow:
        0 0 0 1px rgb(255 255 255 / 88%),
        0 12px 24px rgb(15 23 42 / 12%);
      transform: translateY(-2px);
    }

    span {
      max-width: 90px;
      overflow: hidden;
      font-size: 12px;
      line-height: 1.2;
      color: var(--el-text-color-secondary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    strong {
      max-width: 96px;
      margin-top: 7px;
      overflow: hidden;
      font-size: 22px;
      font-weight: 700;
      line-height: 1.1;
      color: var(--el-text-color-primary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    em {
      margin-top: 5px;
      font-size: 10px;
      font-style: normal;
      line-height: 1;
      color: var(--orb-color);
      animation: healthOrbProgressIn 560ms 300ms cubic-bezier(0.22, 1, 0.36, 1) both;
    }

    small {
      margin-top: 4px;
      font-size: 10px;
      line-height: 1;
      color: var(--el-text-color-secondary);
    }
  }

  .orb-grid .data-orb:nth-child(2) {
    animation-delay: 70ms, 830ms;
  }

  .orb-grid .data-orb:nth-child(3) {
    animation-delay: 140ms, 900ms;
  }

  .orb-grid .data-orb:nth-child(4) {
    animation-delay: 210ms, 970ms;
  }

  .orb-grid .data-orb:nth-child(5) {
    animation-delay: 280ms, 1040ms;
  }

  .orb-grid .data-orb:nth-child(6) {
    animation-delay: 350ms, 1110ms;
  }

  @keyframes healthOrbIn {
    from {
      opacity: 0;
      transform: scale(0.78) rotate(-12deg);
    }

    to {
      opacity: 1;
      transform: scale(1) rotate(0deg);
    }
  }

  @keyframes healthOrbSweep {
    0%,
    58%,
    100% {
      opacity: 0;
      transform: rotate(0deg);
    }

    12%,
    34% {
      opacity: 0.72;
    }

    46% {
      opacity: 0;
      transform: rotate(360deg);
    }
  }

  @keyframes healthOrbProgressIn {
    from {
      opacity: 0;
      transform: scale(0.72);
    }

    to {
      opacity: 1;
      transform: scale(1);
    }
  }

  @keyframes healthOrbGlow {
    0%,
    100% {
      filter: drop-shadow(0 7px 13px rgb(15 23 42 / 8%));
    }

    50% {
      filter: drop-shadow(0 7px 16px color-mix(in srgb, var(--orb-color) 28%, transparent));
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .data-orb,
    .data-orb em,
    .data-orb.has-progress::after {
      transition-duration: 0.01ms !important;
      animation: none !important;
    }
  }

  .data-orb.tone-blue {
    --orb-color: #3b82f6;
  }

  .data-orb.tone-cyan {
    --orb-color: #0891b2;
  }

  .data-orb.tone-violet {
    --orb-color: #7c3aed;
  }

  .data-orb.tone-orange {
    --orb-color: #d97706;
  }

  .data-orb.tone-green {
    --orb-color: #16a34a;
  }

  .data-orb.tone-danger {
    --orb-color: #e11d48;
  }

  .data-orb.tone-slate {
    --orb-color: #64748b;
  }

  @media (width >= 1700px) {
    .metric-grid {
      grid-template-columns: 1.28fr repeat(7, minmax(0, 1fr));
    }
  }

  @media (width <= 1200px) {
    .span-4,
    .span-8,
    .span-12 {
      grid-column: 1 / -1;
    }
  }

  @media (width <= 768px) {
    .health-page {
      padding: 12px;
    }

    .page-head,
    .head-actions,
    .trend-head,
    .alert-head,
    .maintenance-head {
      flex-direction: column;
    }

    .maintenance-actions {
      width: 100%;
    }

    .maintenance-glance {
      grid-template-columns: 1fr;
    }

    .alert-meta {
      flex-direction: column;
      align-items: flex-start;
    }

    .metric-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .live-status {
      width: 100%;
    }

    .page-title-group {
      align-items: flex-start;
    }
  }

  @media (width <= 480px) {
    .metric-grid {
      grid-template-columns: 1fr;
    }

    .orb-grid {
      gap: 10px;
    }

    .data-orb {
      width: 108px;
      height: 108px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .metric-card,
    .metric-status-chip i {
      transition: none;
      animation: none;
    }
  }

  :global(.dark) .metric-card {
    border-color: rgb(71 85 105 / 55%);
    box-shadow: 0 8px 22px rgb(0 0 0 / 12%);
  }

  :global(.dark) .metric-card--status {
    background:
      linear-gradient(135deg, rgb(16 185 129 / 10%), transparent 56%),
      color-mix(in srgb, var(--el-bg-color-overlay) 72%, transparent);
  }

  :global(.dark) .metric-label,
  :global(.dark) .metric-card-foot,
  :global(.dark) .metric-status-main span,
  :global(.dark) .metric-health-strip,
  :global(.dark) .metric-readout em {
    color: var(--el-text-color-secondary);
  }

  :global(.dark) .metric-readout strong,
  :global(.dark) .metric-health-strip b {
    color: var(--el-text-color-primary);
  }
</style>
