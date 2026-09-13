<template>
  <div class="ai-config-page" v-loading="loading">
    <ElAlert type="info" :closable="false" show-icon>
      API Key 会加密保存在服务端，页面只显示首尾脱敏提示。机器人私聊默认回复；群聊按 @、回复或全部消息触发。
    </ElAlert>

    <section class="panel auto-start-panel">
      <div class="panel-title auto-start-title">
        <div>
          <h3>机器人加入群后自动启动 AI</h3>
          <p>开启后，群管理员添加机器人即可使用：自动绑定默认模型、启用全天候 @ / 回复触发，并由机器人发送一次使用说明。关闭后仍按当前流程手动配置和启动。</p>
        </div>
        <ElSwitch v-model="autoStartOnGroupAdd" :loading="autoStartSaving" active-text="自动启动" inactive-text="手动启动" @change="saveAutoStart" />
      </div>
      <ElAlert v-if="autoStartOnGroupAdd" type="success" :closable="false" show-icon>
        当前已开启。此设置只影响之后添加到群里的机器人，已有机器人的单独配置不会被覆盖。
      </ElAlert>
    </section>

    <section class="overview-panel">
      <div class="overview-head">
        <div>
          <h2>AI 运行概览</h2>
          <p>快速了解模型调用、费用和安全审核情况</p>
        </div>
        <ElTag effect="plain" round>近 30 天</ElTag>
      </div>
      <div class="usage-grid">
        <div class="metric primary"><span>请求总数</span><strong>{{ usage.requests }}</strong><small>次调用</small></div>
        <div class="metric success"><span>调用成功</span><strong>{{ usage.succeeded }}</strong><small>正常响应</small></div>
        <div class="metric danger"><span>调用失败</span><strong>{{ usage.failed }}</strong><small>需要关注</small></div>
        <div class="metric info"><span>Token 用量</span><strong>{{ formatNumber(usage.total_tokens) }}</strong><small>累计消耗</small></div>
        <div class="metric warning"><span>估算费用</span><strong>¥{{ formatMoney(usage.cost_micros) }}</strong><small>人民币</small></div>
        <div class="metric danger"><span>审核拦截</span><strong>{{ usage.moderation_blocked }}</strong><small>风险请求</small></div>
      </div>
    </section>

    <section class="panel">
      <div class="panel-title">
        <div><h3>模型供应商</h3><p>四种供应商统一走 OpenAI-compatible Chat Completions 协议。</p></div>
      </div>
      <div class="provider-grid">
        <ElCard v-for="item in providers" :key="item.provider" shadow="never" class="provider-card">
          <template #header>
            <div class="provider-head">
              <div>
                <strong>{{ item.display_name }}</strong>
                <ElTag v-if="item.api_key_configured" type="success" size="small">密钥已配置</ElTag>
                <ElTag v-else type="warning" size="small">待填写密钥</ElTag>
              </div>
              <ElSwitch v-model="item.enabled" active-text="启用" />
            </div>
          </template>
          <ElForm label-position="top">
            <ElFormItem label="显示名称"><ElInput v-model="item.display_name" /></ElFormItem>
            <ElFormItem label="接口 Base URL"><ElInput v-model="item.base_url" /></ElFormItem>
            <ElFormItem label="模型"><ElInput v-model="item.model" /></ElFormItem>
            <ElFormItem label="API Key">
              <ElInput v-model="apiKeys[item.provider]" type="password" show-password :placeholder="item.api_key_hint ? `留空保留：${item.api_key_hint}` : '请输入 API Key'" autocomplete="new-password" />
            </ElFormItem>
            <div class="number-grid">
              <ElFormItem label="超时（秒）"><ElInputNumber v-model="item.request_timeout_seconds" :min="5" :max="180" /></ElFormItem>
              <ElFormItem label="最大输出 Token"><ElInputNumber v-model="item.max_output_tokens" :min="64" :max="32768" /></ElFormItem>
              <ElFormItem label="输入价（微元/百万 Token）"><ElInputNumber v-model="item.input_price_micros_per_million" :min="0" /></ElFormItem>
              <ElFormItem label="输出价（微元/百万 Token）"><ElInputNumber v-model="item.output_price_micros_per_million" :min="0" /></ElFormItem>
              <ElFormItem label="月预算（微元，0 不限制）"><ElInputNumber v-model="item.monthly_budget_micros" :min="0" /></ElFormItem>
            </div>
            <ElCheckbox v-model="item.is_default">设为默认供应商</ElCheckbox>
            <ElCheckbox v-model="item.moderation_enabled">启用内容审核</ElCheckbox>
            <div v-if="item.last_tested_at" class="test-state">
              <ElTag :type="item.last_test_status === 'success' ? 'success' : 'danger'" size="small">{{ item.last_test_status === 'success' ? '连接成功' : '连接失败' }}</ElTag>
              <span>{{ item.last_test_latency_ms }} ms · {{ item.last_test_message }}</span>
            </div>
            <div class="card-actions">
              <ElButton :loading="testing === item.provider" :disabled="!item.api_key_configured && !apiKeys[item.provider]" @click="testProvider(item)">测试连接</ElButton>
              <ElButton type="primary" :loading="saving === item.provider" @click="saveProvider(item)">保存</ElButton>
            </div>
          </ElForm>
        </ElCard>
      </div>
    </section>

    <section class="panel">
      <div class="panel-title">
        <div><h3>知识库 / RAG</h3><p>导入纯文本资料，回答自动检索并携带来源片段。</p></div>
        <ElButton type="primary" @click="knowledgeDialogVisible = true">新建知识库</ElButton>
      </div>
      <ElTable :data="knowledgeBases" row-key="id" empty-text="暂无知识库">
        <ElTableColumn label="名称" prop="name" min-width="180" />
        <ElTableColumn label="说明" prop="description" min-width="220" show-overflow-tooltip />
        <ElTableColumn label="版本" prop="version" width="90" />
        <ElTableColumn label="状态" width="110"><template #default="{ row }"><ElTag :type="row.status === 'published' ? 'success' : 'info'">{{ row.status }}</ElTag></template></ElTableColumn>
        <ElTableColumn label="操作" width="180"><template #default="{ row }"><ElButton link type="primary" @click="openKnowledge(row)">文档管理</ElButton></template></ElTableColumn>
      </ElTable>
    </section>

    <section class="panel">
      <div class="panel-title">
        <div><h3>AI 机器人</h3><p>先在客户端机器人管理中创建机器人，再在这里绑定模型和人格。</p></div>
        <ElButton @click="loadBots">刷新</ElButton>
      </div>
      <ElTable :data="botRows" row-key="bot_uuid" empty-text="暂无机器人，请先在客户端创建">
        <ElTableColumn label="机器人" min-width="210">
          <template #default="{ row }"><div class="bot-cell"><ElAvatar :size="38" :src="row.avatar">{{ row.nickname?.slice(0, 1) }}</ElAvatar><div><strong>{{ row.nickname }} <ElTag v-if="row.bot_kind === 'group_assistant'" size="small" type="warning">系统群助手</ElTag></strong><span>@{{ row.username }}</span></div></div></template>
        </ElTableColumn>
        <ElTableColumn label="AI 状态" width="110"><template #default="{ row }"><ElTag :type="row.enabled ? 'success' : 'info'">{{ row.enabled ? '运行中' : row.profile_id ? '已停用' : '未配置' }}</ElTag></template></ElTableColumn>
        <ElTableColumn label="供应商" width="130"><template #default="{ row }">{{ providerName(row.provider) }}</template></ElTableColumn>
        <ElTableColumn label="群聊触发" width="150"><template #default="{ row }">{{ triggerName(row.trigger_mode) }}</template></ElTableColumn>
        <ElTableColumn label="每日请求" width="120" prop="daily_request_limit" />
        <ElTableColumn label="操作" width="100" fixed="right"><template #default="{ row }"><ElButton type="primary" link @click="openBot(row)">配置</ElButton></template></ElTableColumn>
      </ElTable>
    </section>

    <ElDialog v-model="botDialogVisible" title="配置 AI 机器人" width="680px" destroy-on-close>
      <ElForm :model="botForm" label-position="top">
        <div class="dialog-bot" v-if="editingBot"><strong>{{ editingBot.nickname }}</strong><span>@{{ editingBot.username }}</span><ElSwitch v-model="botForm.enabled" active-text="启用 AI 回复" /></div>
        <ElFormItem label="模型供应商">
          <ElSelect v-model="botForm.provider_config_id" class="full-width" placeholder="请选择已启用供应商">
            <ElOption v-for="item in enabledProviders" :key="item.id" :label="`${item.display_name} / ${item.model}`" :value="item.id" />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="知识库（可选）">
          <ElSelect v-model="botForm.knowledge_base_id" clearable class="full-width" placeholder="不使用知识库">
            <ElOption v-for="item in publishedKnowledgeBases" :key="item.id" :label="`${item.name} / v${item.version}`" :value="item.id" />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="系统人格提示词"><ElInput v-model="botForm.system_prompt" type="textarea" :rows="7" maxlength="10000" show-word-limit placeholder="例如：你是本群的产品顾问，回答简洁、准确，不编造信息。" /></ElFormItem>
        <div class="form-grid">
          <ElFormItem label="群聊触发方式"><ElSelect v-model="botForm.trigger_mode"><ElOption label="@机器人或回复机器人" value="mention_or_reply" /><ElOption label="仅 @机器人" value="mention" /><ElOption label="读取并回复全部消息" value="all_messages" /></ElSelect></ElFormItem>
          <ElFormItem label="上下文消息数"><ElInputNumber v-model="botForm.context_message_count" :min="1" :max="50" /></ElFormItem>
          <ElFormItem label="温度"><ElSlider v-model="temperature" :min="0" :max="2" :step="0.1" show-input /></ElFormItem>
          <ElFormItem label="单次最大输出 Token（0 跟随供应商）"><ElInputNumber v-model="botForm.max_output_tokens" :min="0" :max="32768" /></ElFormItem>
          <ElFormItem label="每日请求上限（0 不限制）"><ElInputNumber v-model="botForm.daily_request_limit" :min="0" :max="1000000" /></ElFormItem>
          <ElFormItem label="每日 Token 上限（0 不限制）"><ElInputNumber v-model="botForm.daily_token_limit" :min="0" :max="1000000000" /></ElFormItem>
          <ElFormItem label="每日费用上限（微元，0 不限制）"><ElInputNumber v-model="botForm.daily_cost_limit_micros" :min="0" /></ElFormItem>
          <ElFormItem label="活跃开始（分钟）"><ElInputNumber v-model="botForm.active_start_minute" :min="0" :max="1439" /></ElFormItem>
          <ElFormItem label="活跃结束（分钟）"><ElInputNumber v-model="botForm.active_end_minute" :min="1" :max="1440" /></ElFormItem>
          <ElFormItem label="时区"><ElInput v-model="botForm.timezone" /></ElFormItem>
        </div>
        <ElFormItem label="失败降级提示"><ElInput v-model="botForm.fallback_message" maxlength="500" /></ElFormItem>
        <ElCheckbox v-model="botForm.stream_enabled">启用流式回答</ElCheckbox>
        <ElCheckbox v-model="botForm.moderation_enabled">启用敏感配置泄露防护</ElCheckbox>
        <ElAlert v-if="botForm.trigger_mode === 'all_messages'" type="warning" :closable="false">此模式只在群管理员授予机器人“读取全部消息”权限后生效，会增加调用费用。</ElAlert>
      </ElForm>
      <template #footer><ElButton @click="botDialogVisible = false">取消</ElButton><ElButton type="primary" :loading="botSaving" @click="saveBot">保存配置</ElButton></template>
    </ElDialog>

    <section class="panel">
      <div class="panel-title"><div><h3>群摘要、治理与高级自动化</h3><p>治理默认只生成待人工复核案例，不自动删除、禁言或踢人。</p></div></div>
      <ElForm inline>
        <ElFormItem label="群聊 UUID"><ElInput v-model="groupChatId" placeholder="输入群聊 UUID" style="width: 360px" /></ElFormItem>
        <ElFormItem><ElButton :disabled="!groupChatId" @click="loadGroupPolicy">读取配置</ElButton></ElFormItem>
      </ElForm>
      <template v-if="groupPolicyLoaded">
        <div class="form-grid">
          <ElFormItem label="AI 机器人"><ElSelect v-model="groupPolicy.bot_id"><ElOption v-for="item in enabledBots" :key="item.bot_id" :label="item.nickname" :value="item.bot_id" /></ElSelect></ElFormItem>
          <ElFormItem label="摘要周期"><ElSelect v-model="groupPolicy.summary_schedule"><ElOption label="每天" value="daily" /><ElOption label="每周" value="weekly" /></ElSelect></ElFormItem>
          <ElFormItem label="摘要小时"><ElInputNumber v-model="groupPolicy.summary_hour" :min="0" :max="23" /></ElFormItem>
          <ElFormItem label="时区"><ElInput v-model="groupPolicy.timezone" /></ElFormItem>
          <ElFormItem label="风险阈值"><ElSlider v-model="riskThreshold" :min="0" :max="1" :step="0.05" show-input /></ElFormItem>
          <ElFormItem label="风险词（每行一个）"><ElInput v-model="blockedTermsText" type="textarea" :rows="3" /></ElFormItem>
        </div>
        <div class="policy-actions"><ElSwitch v-model="groupPolicy.summary_enabled" active-text="定时摘要" /><ElSwitch v-model="groupPolicy.governance_enabled" active-text="治理提示" /><ElButton type="primary" @click="saveGroupPolicyConfig">保存策略</ElButton><ElButton @click="generateSummary">立即生成并发布摘要</ElButton></div>
      </template>
      <ElDivider />
      <div class="panel-title"><div><h3>待人工复核</h3></div><ElButton @click="loadGovernanceCases">刷新</ElButton></div>
      <ElTable :data="governanceCases" row-key="id" empty-text="暂无风险案例">
        <ElTableColumn label="类型" prop="category" width="130" /><ElTableColumn label="证据" prop="evidence" min-width="260" /><ElTableColumn label="置信度" width="100"><template #default="{ row }">{{ (row.confidence_milli / 10).toFixed(0) }}%</template></ElTableColumn><ElTableColumn label="状态" prop="status" width="110" />
        <ElTableColumn label="操作" width="150"><template #default="{ row }"><ElButton link type="success" @click="reviewCase(row, 'confirmed')">确认</ElButton><ElButton link @click="reviewCase(row, 'dismissed')">忽略</ElButton></template></ElTableColumn>
      </ElTable>
    </section>

    <ElDialog v-model="knowledgeDialogVisible" title="新建知识库" width="520px"><ElForm label-position="top"><ElFormItem label="名称"><ElInput v-model="knowledgeForm.name" /></ElFormItem><ElFormItem label="说明"><ElInput v-model="knowledgeForm.description" type="textarea" /></ElFormItem></ElForm><template #footer><ElButton @click="knowledgeDialogVisible = false">取消</ElButton><ElButton type="primary" @click="createKnowledge">创建</ElButton></template></ElDialog>
    <ElDialog v-model="documentDialogVisible" :title="`文档管理 · ${selectedKnowledge?.name || ''}`" width="760px"><ElForm label-position="top"><ElFormItem label="文档标题"><ElInput v-model="documentForm.title" /></ElFormItem><ElFormItem label="来源 URL（可选）"><ElInput v-model="documentForm.source_url" /></ElFormItem><ElFormItem label="正文"><ElInput v-model="documentForm.content" type="textarea" :rows="10" maxlength="500000" show-word-limit /></ElFormItem><ElButton type="primary" @click="addDocument">导入并切块</ElButton></ElForm><ElDivider /><ElTable :data="knowledgeDocuments"><ElTableColumn label="标题" prop="title" /><ElTableColumn label="片段" prop="chunk_count" width="80" /><ElTableColumn label="操作" width="90"><template #default="{ row }"><ElButton link type="danger" @click="archiveDocument(row)">归档</ElButton></template></ElTableColumn></ElTable></ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { ElMessage } from 'element-plus'
  import {
    addAIKnowledgeDocument, archiveAIKnowledgeDocument, createAIKnowledgeBase,
    generateAIGroupSummary, getAIBots, getAIGovernanceCases, getAIGroupPolicy,
    getAIKnowledgeBases, getAIKnowledgeDocuments, getAIProviders, getAIUsage,
    getSystemSettings, reviewAIGovernanceCase, saveAIBot, saveAIGroupPolicy, saveAIProvider, testAIProvider, updateSystemSettings,
    type AIBotConfig, type AIGovernanceCase, type AIGroupPolicy, type AIKnowledgeBase,
    type AIKnowledgeDocument, type AIProviderCode, type AIProviderConfig,
    type AISaveBotParams, type AIUsageSummary
  } from '@/api/admin'

  defineOptions({ name: 'SystemAIConfig' })

  const loading = ref(false)
  const autoStartOnGroupAdd = ref(false)
  const autoStartSaving = ref(false)
  const providers = ref<AIProviderConfig[]>([])
  const botRows = ref<AIBotConfig[]>([])
  const usage = reactive<AIUsageSummary>({ requests: 0, succeeded: 0, failed: 0, total_tokens: 0, cost_micros: 0, moderation_blocked: 0 })
  const apiKeys = reactive<Record<AIProviderCode, string>>({ aliyun: '', deepseek: '', openai: '', custom: '' })
  const saving = ref<AIProviderCode | ''>('')
  const testing = ref<AIProviderCode | ''>('')
  const botSaving = ref(false)
  const botDialogVisible = ref(false)
  const editingBot = ref<AIBotConfig>()
  const botForm = reactive<AISaveBotParams>({
    provider_config_id: 0, enabled: false, system_prompt: '', trigger_mode: 'mention_or_reply',
    context_message_count: 12, temperature_milli: 700, daily_request_limit: 1000,
    daily_token_limit: 1000000, max_output_tokens: 0, knowledge_base_id: undefined,
    stream_enabled: true, active_start_minute: 0, active_end_minute: 1440,
    timezone: 'Asia/Shanghai', fallback_message: 'AI 服务暂时不可用，请稍后重试。',
    daily_cost_limit_micros: 0, moderation_enabled: true
  })
  const knowledgeBases = ref<AIKnowledgeBase[]>([])
  const knowledgeDocuments = ref<AIKnowledgeDocument[]>([])
  const selectedKnowledge = ref<AIKnowledgeBase>()
  const knowledgeDialogVisible = ref(false)
  const documentDialogVisible = ref(false)
  const knowledgeForm = reactive({ name: '', description: '' })
  const documentForm = reactive({ title: '', content: '', source_url: '' })
  const groupChatId = ref('')
  const groupPolicyLoaded = ref(false)
  const groupPolicy = reactive<AIGroupPolicy>({
    bot_id: 0, summary_enabled: false, summary_schedule: 'daily', summary_hour: 18,
    timezone: 'Asia/Shanghai', governance_enabled: false, governance_mode: 'suggest',
    blocked_terms_json: '[]', risk_threshold_milli: 800
  })
  const blockedTermsText = ref('')
  const governanceCases = ref<AIGovernanceCase[]>([])
  const temperature = computed({ get: () => botForm.temperature_milli / 1000, set: (value: number) => { botForm.temperature_milli = Math.round(value * 1000) } })
  const enabledProviders = computed(() => providers.value.filter((item) => item.enabled && item.api_key_configured))
  const publishedKnowledgeBases = computed(() => knowledgeBases.value.filter((item) => item.status === 'published'))
  const enabledBots = computed(() => botRows.value.filter((item) => item.enabled && item.bot_id))
  const riskThreshold = computed({ get: () => groupPolicy.risk_threshold_milli / 1000, set: (value: number) => { groupPolicy.risk_threshold_milli = Math.round(value * 1000) } })

  const formatNumber = (value: number) => new Intl.NumberFormat('zh-CN').format(value || 0)
  const formatMoney = (value: number) => (Number(value || 0) / 1000000).toFixed(4)
  const providerName = (code?: AIProviderCode) => providers.value.find((item) => item.provider === code)?.display_name || '—'
  const triggerName = (mode: string) => ({ mention: '仅 @', mention_or_reply: '@ 或回复', all_messages: '全部消息' }[mode] || '—')

  async function loadAll() {
    loading.value = true
    try {
      const [providerResult, botResult, usageResult, knowledgeResult, settingsResult] = await Promise.all([getAIProviders(), getAIBots(), getAIUsage(), getAIKnowledgeBases(), getSystemSettings()])
      providers.value = providerResult.items || []
      botRows.value = botResult.items || []
      knowledgeBases.value = knowledgeResult.items || []
      autoStartOnGroupAdd.value = settingsResult.ai_bot_auto_start_on_group_add === true
      Object.assign(usage, usageResult)
    } finally { loading.value = false }
  }
  async function loadBots() { const result = await getAIBots(); botRows.value = result.items || [] }
  async function saveAutoStart(value: string | number | boolean) {
    const enabled = value === true
    if (enabled && !providers.value.some((item) => item.enabled && item.is_default && item.api_key_configured)) {
      autoStartOnGroupAdd.value = false
      ElMessage.warning('请先启用、配置并设定一个默认模型供应商')
      return
    }
    autoStartSaving.value = true
    try {
      await updateSystemSettings({ ai_bot_auto_start_on_group_add: enabled })
      ElMessage.success(enabled ? '机器人入群自动启动 AI 已开启' : '已恢复为手动启动 AI')
    } catch (error) {
      autoStartOnGroupAdd.value = !enabled
      ElMessage.error(error instanceof Error ? error.message : '自动启动设置保存失败')
    } finally { autoStartSaving.value = false }
  }
  async function saveProvider(item: AIProviderConfig) {
    saving.value = item.provider
    try {
      await saveAIProvider(item.provider, {
        display_name: item.display_name, base_url: item.base_url, model: item.model,
        api_key: apiKeys[item.provider] || undefined, enabled: item.enabled, is_default: item.is_default,
        request_timeout_seconds: item.request_timeout_seconds, max_output_tokens: item.max_output_tokens,
        input_price_micros_per_million: item.input_price_micros_per_million,
        output_price_micros_per_million: item.output_price_micros_per_million,
        monthly_budget_micros: item.monthly_budget_micros, moderation_enabled: item.moderation_enabled
      })
      apiKeys[item.provider] = ''
      ElMessage.success('供应商配置已加密保存')
      const result = await getAIProviders(); providers.value = result.items || []
    } finally { saving.value = '' }
  }
  async function testProvider(item: AIProviderConfig) {
    if (apiKeys[item.provider]) { await saveProvider(item) }
    testing.value = item.provider
    try { const result = await testAIProvider(item.provider); ElMessage.success(`连接成功，${result.latency_ms} ms`) }
    catch (error) { ElMessage.error(error instanceof Error ? error.message : '连接失败，请检查地址、模型和密钥') }
    finally { testing.value = ''; const result = await getAIProviders(); providers.value = result.items || [] }
  }
  function openBot(row: AIBotConfig) {
    editingBot.value = row
    Object.assign(botForm, {
      provider_config_id: row.provider_config_id || enabledProviders.value[0]?.id || 0,
      enabled: row.enabled ?? false, system_prompt: row.system_prompt || '',
      trigger_mode: row.trigger_mode || 'mention_or_reply', context_message_count: row.context_message_count || 12,
      temperature_milli: row.temperature_milli ?? 700, daily_request_limit: row.daily_request_limit ?? 1000,
      daily_token_limit: row.daily_token_limit ?? 1000000, max_output_tokens: row.max_output_tokens || 0,
      knowledge_base_id: row.knowledge_base_id || undefined, stream_enabled: row.stream_enabled ?? true,
      active_start_minute: row.profile_id ? (row.active_start_minute ?? 0) : 0,
      active_end_minute: row.profile_id && row.active_end_minute > 0 ? row.active_end_minute : 1440,
      timezone: row.timezone || 'Asia/Shanghai', fallback_message: row.fallback_message || 'AI 服务暂时不可用，请稍后重试。',
      daily_cost_limit_micros: row.daily_cost_limit_micros ?? 0, moderation_enabled: row.moderation_enabled ?? true
    })
    botDialogVisible.value = true
  }
  async function saveBot() {
    if (!editingBot.value || !botForm.provider_config_id) { ElMessage.warning('请选择已启用并配置密钥的供应商'); return }
    botSaving.value = true
    try { await saveAIBot(editingBot.value.bot_uuid, { ...botForm }); ElMessage.success('AI 机器人配置已保存'); botDialogVisible.value = false; await loadBots() }
    finally { botSaving.value = false }
  }
  async function createKnowledge() {
    if (!knowledgeForm.name.trim()) { ElMessage.warning('请输入知识库名称'); return }
    await createAIKnowledgeBase({ name: knowledgeForm.name.trim(), description: knowledgeForm.description.trim() })
    knowledgeDialogVisible.value = false
    Object.assign(knowledgeForm, { name: '', description: '' })
    knowledgeBases.value = (await getAIKnowledgeBases()).items || []
    ElMessage.success('知识库已创建')
  }
  async function openKnowledge(row: AIKnowledgeBase) {
    selectedKnowledge.value = row
    knowledgeDocuments.value = (await getAIKnowledgeDocuments(row.id)).items || []
    documentDialogVisible.value = true
  }
  async function addDocument() {
    if (!selectedKnowledge.value || !documentForm.title.trim() || !documentForm.content.trim()) { ElMessage.warning('请填写标题和正文'); return }
    await addAIKnowledgeDocument(selectedKnowledge.value.id, { title: documentForm.title.trim(), content: documentForm.content.trim(), source_url: documentForm.source_url.trim() || undefined })
    Object.assign(documentForm, { title: '', content: '', source_url: '' })
    await openKnowledge(selectedKnowledge.value)
    knowledgeBases.value = (await getAIKnowledgeBases()).items || []
    ElMessage.success('文档已导入并发布')
  }
  async function archiveDocument(row: AIKnowledgeDocument) {
    if (!selectedKnowledge.value) return
    await archiveAIKnowledgeDocument(selectedKnowledge.value.id, row.id)
    await openKnowledge(selectedKnowledge.value)
    ElMessage.success('文档已归档')
  }
  async function loadGroupPolicy() {
    if (!groupChatId.value.trim()) return
    const result = await getAIGroupPolicy(groupChatId.value.trim())
    Object.assign(groupPolicy, result)
    if (!groupPolicy.bot_id && enabledBots.value[0]) groupPolicy.bot_id = enabledBots.value[0].bot_id
    try {
      const terms = JSON.parse(groupPolicy.blocked_terms_json || '[]')
      blockedTermsText.value = Array.isArray(terms) ? terms.join('\n') : ''
    } catch { blockedTermsText.value = '' }
    groupPolicyLoaded.value = true
    await loadGovernanceCases()
  }
  async function saveGroupPolicyConfig() {
    if (!groupPolicy.bot_id) { ElMessage.warning('请选择已启用的 AI 机器人'); return }
    groupPolicy.blocked_terms_json = JSON.stringify(blockedTermsText.value.split(/\r?\n/).map((item) => item.trim()).filter(Boolean))
    Object.assign(groupPolicy, await saveAIGroupPolicy(groupChatId.value.trim(), { ...groupPolicy }))
    ElMessage.success('群 AI 策略已保存')
  }
  async function generateSummary() {
    await generateAIGroupSummary(groupChatId.value.trim(), { summary_type: 'manual', publish: true })
    ElMessage.success('群摘要已生成并发布')
  }
  async function loadGovernanceCases() {
    const result = await getAIGovernanceCases({ chat_id: groupChatId.value.trim() || undefined, status: 'pending' })
    governanceCases.value = result.items || []
  }
  async function reviewCase(row: AIGovernanceCase, status: 'confirmed' | 'dismissed') {
    await reviewAIGovernanceCase(row.id, status)
    await loadGovernanceCases()
    ElMessage.success(status === 'confirmed' ? '已确认风险案例' : '已忽略风险案例')
  }
  onMounted(loadAll)
</script>

<style scoped lang="scss">
  .ai-config-page { padding: 20px; }
  .overview-panel { padding: 18px; margin: 16px 0 18px; background: var(--art-main-bg-color); border: 1px solid var(--art-border-color); border-radius: 14px; box-shadow: 0 4px 18px rgb(15 23 42 / 4%); }
  .overview-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; h2 { margin: 0 0 4px; font-size: 18px; line-height: 1.35; } p { margin: 0; color: var(--art-text-gray-600); font-size: 13px; } }
  .usage-grid { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 10px; }
  .metric { position: relative; min-width: 0; padding: 14px 16px 13px; overflow: hidden; background: var(--metric-bg); border: 1px solid color-mix(in srgb, var(--metric-color) 14%, transparent); border-radius: 10px; span { display: block; overflow: hidden; color: var(--art-text-gray-600); font-size: 13px; text-overflow: ellipsis; white-space: nowrap; } strong { display: block; margin: 6px 0 2px; overflow: hidden; color: var(--metric-color); font-size: 24px; line-height: 1.2; text-overflow: ellipsis; white-space: nowrap; } small { color: var(--art-text-gray-500); font-size: 11px; } &.primary { --metric-color: var(--el-color-primary); --metric-bg: var(--el-color-primary-light-9); } &.success { --metric-color: var(--el-color-success); --metric-bg: var(--el-color-success-light-9); } &.danger { --metric-color: var(--el-color-danger); --metric-bg: var(--el-color-danger-light-9); } &.info { --metric-color: var(--el-color-info); --metric-bg: var(--el-color-info-light-9); } &.warning { --metric-color: var(--el-color-warning); --metric-bg: var(--el-color-warning-light-9); } }
  .panel { padding: 20px; margin-bottom: 18px; background: var(--art-main-bg-color); border: 1px solid var(--art-border-color); border-radius: 12px; }
  .auto-start-panel { margin-top: 16px; }
  .auto-start-title { margin-bottom: 0; gap: 24px; > div { max-width: 900px; } }
  .auto-start-panel > .el-alert { margin-top: 16px; }
  .panel-title { display: flex; align-items: center; justify-content: space-between; margin-bottom: 18px; h3 { margin: 0 0 5px; font-size: 18px; } p { margin: 0; color: var(--art-text-gray-600); font-size: 13px; } }
  .provider-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 16px; }
  .provider-card { border-radius: 10px; }
  .provider-head { display: flex; align-items: center; justify-content: space-between; > div { display: flex; gap: 10px; align-items: center; } }
  .number-grid, .form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 18px; }
  .test-state { display: flex; gap: 8px; align-items: center; min-height: 28px; margin-top: 10px; color: var(--art-text-gray-600); font-size: 12px; }
  .card-actions { display: flex; justify-content: flex-end; margin-top: 12px; }
  .policy-actions { display: flex; align-items: center; flex-wrap: wrap; gap: 14px; margin: 8px 0 18px; }
  .bot-cell { display: flex; gap: 10px; align-items: center; div { display: flex; flex-direction: column; } span { color: var(--art-text-gray-600); font-size: 12px; } }
  .dialog-bot { display: flex; gap: 10px; align-items: center; padding: 12px 14px; margin-bottom: 16px; background: var(--el-fill-color-light); border-radius: 8px; span { margin-right: auto; color: var(--art-text-gray-600); } }
  .full-width { width: 100%; }
  @media (width <= 1400px) { .usage-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); } }
  @media (width <= 1100px) { .provider-grid { grid-template-columns: 1fr; } }
  @media (width <= 720px) { .overview-panel { padding: 14px; } .overview-head { align-items: flex-start; } .usage-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } .metric { padding: 13px 14px 12px; } .number-grid, .form-grid { grid-template-columns: 1fr; } .ai-config-page { padding: 12px; } }
</style>
