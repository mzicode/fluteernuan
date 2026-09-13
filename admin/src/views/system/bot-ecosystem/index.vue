<template>
  <div class="ecosystem-page" v-loading="loading">
    <ElAlert type="warning" :closable="false" show-icon>
      当前机器人订单只运行在 Sandbox
      独立账本，不会调用微信、支付宝或普通用户钱包，也不会伪造真实支付成功。
    </ElAlert>

    <section class="panel">
      <div class="panel-title">
        <div>
          <h2>Mini App 配置</h2>
          <p>由管理员配置所属机器人、HTTPS 启动地址和精确安全域名。</p>
        </div>
        <ElButton type="primary" @click="openCreate">新建 Mini App</ElButton>
      </div>
      <ElTable :data="miniApps" row-key="id" empty-text="暂无 Mini App">
        <ElTableColumn label="应用" min-width="210">
          <template #default="{ row }">
            <strong>{{ row.name }}</strong>
            <div class="muted">{{ row.description || '暂无说明' }}</div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="所属机器人" min-width="160">
          <template #default="{ row }">{{ botName(row.bot_id) }}</template>
        </ElTableColumn>
        <ElTableColumn label="启动地址" min-width="260" show-overflow-tooltip>
          <template #default="{ row }">
            <a class="url-link" :href="row.start_url" target="_blank" rel="noopener noreferrer">
              {{ row.start_url }}
            </a>
          </template>
        </ElTableColumn>
        <ElTableColumn label="安全域名" min-width="220">
          <template #default="{ row }">
            <ElTag
              v-for="domain in allowedDomains(row)"
              :key="domain"
              size="small"
              type="info"
              class="domain-tag"
            >
              {{ domain }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态/版本" width="130">
          <template #default="{ row }">
            <ElTag :type="row.status === 'published' ? 'success' : 'info'">
              {{ row.status === 'published' ? '已启用' : row.status }}
            </ElTag>
            <span class="version">v{{ row.version }}</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="操作" width="100" fixed="right">
          <template #default="{ row }">
            <ElButton link type="primary" @click="openEdit(row)">编辑</ElButton>
          </template>
        </ElTableColumn>
      </ElTable>
    </section>

    <section class="panel">
      <div class="panel-title">
        <div>
          <h2>机器人应用市场管理</h2>
          <p>市场内容仅由管理员添加和维护，不接受开发者提交或自助上架。</p>
        </div>
        <div class="filters">
          <ElSelect v-model="listingStatus" style="width: 150px" @change="loadListings">
            <ElOption label="全部" value="" />
            <ElOption label="已上架" value="approved" />
            <ElOption label="已下架" value="delisted" />
          </ElSelect>
          <ElButton @click="loadListings">刷新</ElButton>
          <ElButton type="primary" @click="openListingCreate">新增市场应用</ElButton>
        </div>
      </div>
      <ElTable :data="listings" row-key="id" empty-text="暂无应用">
        <ElTableColumn label="应用" min-width="220">
          <template #default="{ row }">
            <strong>{{ row.name }}</strong>
            <div class="muted">{{ row.short_description }}</div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="分类" prop="category" width="120" />
        <ElTableColumn label="定价" width="140">
          <template #default="{ row }">{{ price(row) }}</template>
        </ElTableColumn>
        <ElTableColumn label="安装/评价" width="140">
          <template #default="{ row }">{{ row.install_count }} / {{ row.review_count }}</template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="110">
          <template #default="{ row }">
            <ElTag :type="tagType(row.status)">{{ statusName(row.status) }}</ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="操作" width="260" fixed="right">
          <template #default="{ row }">
            <ElButton link type="primary" @click="openListingEdit(row)">编辑</ElButton>
            <ElButton
              v-if="row.status !== 'approved'"
              link
              type="success"
              @click="setListingStatus(row, 'approved')"
            >
              上架
            </ElButton>
            <ElButton
              v-if="row.status === 'approved'"
              link
              type="warning"
              @click="setListingStatus(row, 'delisted')"
            >
              下架
            </ElButton>
          </template>
        </ElTableColumn>
      </ElTable>
    </section>

    <ElDialog
      v-model="dialogVisible"
      :title="editingApp ? '编辑 Mini App' : '新建 Mini App'"
      width="680px"
      destroy-on-close
      @closed="formRef?.clearValidate()"
    >
      <ElForm ref="formRef" :model="form" :rules="formRules" label-position="top">
        <ElFormItem label="所属机器人" prop="bot_id">
          <ElSelect
            v-model="form.bot_id"
            class="full-width"
            filterable
            :disabled="Boolean(editingApp)"
            placeholder="请选择机器人"
          >
            <ElOption
              v-for="bot in activeBots"
              :key="bot.bot_id"
              :label="`${bot.nickname || bot.username}（@${bot.username}）`"
              :value="bot.bot_id"
            />
          </ElSelect>
          <div v-if="editingApp" class="form-help"
            >编辑时不能更换所属机器人，避免已上架商品关联错位。</div
          >
        </ElFormItem>
        <ElFormItem label="应用名称" prop="name">
          <ElInput
            v-model="form.name"
            maxlength="120"
            show-word-limit
            placeholder="例如：订单查询助手"
          />
        </ElFormItem>
        <ElFormItem label="功能说明">
          <ElInput
            v-model="form.description"
            type="textarea"
            :rows="3"
            maxlength="500"
            show-word-limit
            placeholder="说明应用用途和主要功能"
          />
        </ElFormItem>
        <ElFormItem label="HTTPS 启动地址" prop="start_url">
          <ElInput v-model="form.start_url" placeholder="https://app.example.com/start" />
          <div class="form-help"
            >只允许 HTTPS、443 端口和公网域名，不允许 IP、localhost 或内网地址。</div
          >
        </ElFormItem>
        <ElFormItem label="额外安全域名（每行一个）">
          <ElInput
            v-model="form.allowed_domains_text"
            type="textarea"
            :rows="5"
            placeholder="api.example.com&#10;static.example.com"
          />
          <div class="form-help"
            >启动地址的域名会自动加入；不支持通配符、协议、端口或路径，最多 20 个。</div
          >
        </ElFormItem>
        <ElAlert type="info" :closable="false" show-icon>
          保存现有应用会立即更新客户端打开地址和域名白名单，并将配置版本加 1。
        </ElAlert>
      </ElForm>
      <template #footer>
        <ElButton @click="dialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="saving" @click="saveMiniApp">保存</ElButton>
      </template>
    </ElDialog>

    <ElDialog
      v-model="listingDialogVisible"
      :title="editingListing ? '编辑市场应用' : '新增市场应用'"
      width="680px"
      destroy-on-close
      @closed="listingFormRef?.clearValidate()"
    >
      <ElForm
        ref="listingFormRef"
        :model="listingForm"
        :rules="listingFormRules"
        label-position="top"
      >
        <ElFormItem label="所属机器人" prop="bot_id">
          <ElSelect
            v-model="listingForm.bot_id"
            class="full-width"
            filterable
            :disabled="Boolean(editingListing)"
            placeholder="请选择机器人"
          >
            <ElOption
              v-for="bot in activeBots"
              :key="bot.bot_id"
              :label="`${bot.nickname || bot.username}（@${bot.username}）`"
              :value="bot.bot_id"
            />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="关联 Mini App（可选）">
          <ElSelect
            v-model="listingForm.mini_app_id"
            class="full-width"
            clearable
            placeholder="不关联 Mini App"
          >
            <ElOption
              v-for="app in listingMiniApps"
              :key="app.id"
              :label="app.name"
              :value="app.id"
            />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="市场名称" prop="name">
          <ElInput v-model="listingForm.name" maxlength="120" show-word-limit />
        </ElFormItem>
        <ElFormItem label="简介">
          <ElInput
            v-model="listingForm.short_description"
            type="textarea"
            :rows="3"
            maxlength="300"
            show-word-limit
          />
        </ElFormItem>
        <ElFormItem label="分类" prop="category">
          <ElInput v-model="listingForm.category" maxlength="50" placeholder="例如：效率工具" />
        </ElFormItem>
        <ElFormItem label="图标地址">
          <ElInput v-model="listingForm.icon_url" placeholder="https://example.com/icon.png" />
        </ElFormItem>
        <ElFormItem label="定价方式">
          <ElRadioGroup v-model="listingForm.pricing_type">
            <ElRadioButton value="free">免费</ElRadioButton>
            <ElRadioButton value="one_time">一次性付费</ElRadioButton>
            <ElRadioButton value="subscription">按月订阅</ElRadioButton>
          </ElRadioGroup>
        </ElFormItem>
        <ElFormItem v-if="listingForm.pricing_type !== 'free'" label="价格（元）">
          <ElInputNumber v-model="listingForm.price_yuan" :min="0.01" :max="100000" :precision="2" />
        </ElFormItem>
        <ElFormItem label="状态">
          <ElRadioGroup v-model="listingForm.status">
            <ElRadioButton value="approved">上架</ElRadioButton>
            <ElRadioButton value="delisted">下架</ElRadioButton>
          </ElRadioGroup>
        </ElFormItem>
        <ElAlert type="info" :closable="false" show-icon>
          保存后直接按所选状态生效，不经过开发者提交或审核流程。
        </ElAlert>
      </ElForm>
      <template #footer>
        <ElButton @click="listingDialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="listingSaving" @click="saveListing">保存</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { ElMessage } from 'element-plus'
  import type { FormInstance, FormRules } from 'element-plus'
  import {
    createAdminBotMarketListing,
    createAdminMiniApp,
    getAdminBotMarketplace,
    getAdminMiniApps,
    getAIBots,
    updateAdminBotMarketListing,
    updateAdminMiniApp,
    type AIBotConfig,
    type BotMarketListing,
    type BotMiniApp,
    type SaveBotMarketListingParams,
    type SaveBotMiniAppParams
  } from '@/api/admin'

  defineOptions({ name: 'BotEcosystem' })

  interface MiniAppForm {
    bot_id: number | undefined
    name: string
    description: string
    start_url: string
    allowed_domains_text: string
  }

  interface MarketListingForm {
    bot_id: number | undefined
    mini_app_id: number | undefined
    name: string
    short_description: string
    category: string
    icon_url: string
    pricing_type: 'free' | 'one_time' | 'subscription'
    price_yuan: number
    status: 'approved' | 'delisted'
  }

  const loading = ref(false)
  const saving = ref(false)
  const listingSaving = ref(false)
  const listingStatus = ref('')
  const listings = ref<BotMarketListing[]>([])
  const miniApps = ref<BotMiniApp[]>([])
  const bots = ref<AIBotConfig[]>([])
  const dialogVisible = ref(false)
  const editingApp = ref<BotMiniApp>()
  const listingDialogVisible = ref(false)
  const editingListing = ref<BotMarketListing>()
  const listingFormRef = ref<FormInstance>()
  const formRef = ref<FormInstance>()
  const form = reactive<MiniAppForm>({
    bot_id: undefined,
    name: '',
    description: '',
    start_url: '',
    allowed_domains_text: ''
  })
  const formRules: FormRules = {
    bot_id: [{ required: true, message: '请选择所属机器人', trigger: 'change' }],
    name: [{ required: true, message: '请输入应用名称', trigger: 'blur' }],
    start_url: [{ required: true, message: '请输入 HTTPS 启动地址', trigger: 'blur' }]
  }

  const listingForm = reactive<MarketListingForm>({
    bot_id: undefined,
    mini_app_id: undefined,
    name: '',
    short_description: '',
    category: '',
    icon_url: '',
    pricing_type: 'free',
    price_yuan: 0,
    status: 'approved'
  })
  const listingFormRules: FormRules = {
    bot_id: [{ required: true, message: '请选择所属机器人', trigger: 'change' }],
    name: [{ required: true, message: '请输入市场名称', trigger: 'blur' }],
    category: [{ required: true, message: '请输入分类', trigger: 'blur' }]
  }

  const activeBots = computed(() => bots.value.filter((bot) => bot.bot_status === 'active'))
  const listingMiniApps = computed(() =>
    miniApps.value.filter((app) => app.bot_id === listingForm.bot_id)
  )

  const statusName = (value: string) =>
    ({ pending: '未上架', approved: '已上架', rejected: '已下架', delisted: '已下架' })[value] ||
    value
  const tagType = (value: string) => (value === 'approved' ? 'success' : 'info')
  const price = (row: BotMarketListing) =>
    row.pricing_type === 'free'
      ? '免费'
      : `¥${(row.price_cents / 100).toFixed(2)}${row.pricing_type === 'subscription' ? '/月' : ''}`

  function botName(botId: number) {
    const bot = bots.value.find((item) => item.bot_id === botId)
    return bot ? `${bot.nickname || bot.username}（@${bot.username}）` : `机器人 #${botId}`
  }

  function allowedDomains(app: BotMiniApp) {
    try {
      const values = JSON.parse(app.allowed_domains_json)
      return Array.isArray(values) ? values.map(String) : []
    } catch {
      return []
    }
  }

  async function load() {
    loading.value = true
    try {
      const [miniAppResult, botResult, listingResult] = await Promise.all([
        getAdminMiniApps(),
        getAIBots(),
        getAdminBotMarketplace(listingStatus.value || undefined)
      ])
      miniApps.value = miniAppResult.items || []
      bots.value = botResult.items || []
      listings.value = listingResult.items || []
    } finally {
      loading.value = false
    }
  }

  async function loadListings() {
    listings.value = (await getAdminBotMarketplace(listingStatus.value || undefined)).items || []
  }

  function resetForm() {
    form.bot_id = undefined
    form.name = ''
    form.description = ''
    form.start_url = ''
    form.allowed_domains_text = ''
  }

  function openCreate() {
    if (activeBots.value.length === 0) {
      ElMessage.warning('暂无可用机器人，请先在客户端创建并启用机器人')
      return
    }
    editingApp.value = undefined
    resetForm()
    dialogVisible.value = true
  }

  function openEdit(app: BotMiniApp) {
    editingApp.value = app
    form.bot_id = app.bot_id
    form.name = app.name
    form.description = app.description
    form.start_url = app.start_url
    form.allowed_domains_text = allowedDomains(app).join('\n')
    dialogVisible.value = true
  }

  function resetListingForm() {
    listingForm.bot_id = undefined
    listingForm.mini_app_id = undefined
    listingForm.name = ''
    listingForm.short_description = ''
    listingForm.category = ''
    listingForm.icon_url = ''
    listingForm.pricing_type = 'free'
    listingForm.price_yuan = 0
    listingForm.status = 'approved'
  }

  function openListingCreate() {
    if (activeBots.value.length === 0) {
      ElMessage.warning('暂无可用机器人，请先创建并启用机器人')
      return
    }
    editingListing.value = undefined
    resetListingForm()
    listingDialogVisible.value = true
  }

  function openListingEdit(row: BotMarketListing) {
    editingListing.value = row
    listingForm.bot_id = row.bot_id
    listingForm.mini_app_id = row.mini_app_id
    listingForm.name = row.name
    listingForm.short_description = row.short_description
    listingForm.category = row.category
    listingForm.icon_url = row.icon_url || ''
    listingForm.pricing_type = row.pricing_type
    listingForm.price_yuan = row.price_cents / 100
    listingForm.status = row.status === 'approved' ? 'approved' : 'delisted'
    listingDialogVisible.value = true
  }

  function buildListingParams(): SaveBotMarketListingParams | undefined {
    const botId = listingForm.bot_id
    if (!botId) return
    if (
      listingForm.mini_app_id &&
      !miniApps.value.some(
        (app) => app.id === listingForm.mini_app_id && app.bot_id === listingForm.bot_id
      )
    ) {
      ElMessage.warning('关联的 Mini App 必须属于同一个机器人')
      return
    }
    const iconURL = listingForm.icon_url.trim()
    if (iconURL) {
      try {
        const parsed = new URL(iconURL)
        if (parsed.protocol !== 'https:') throw new Error('invalid protocol')
      } catch {
        ElMessage.warning('图标地址必须是完整的 HTTPS 地址')
        return
      }
    }
    return {
      bot_id: botId,
      ...(listingForm.mini_app_id ? { mini_app_id: listingForm.mini_app_id } : {}),
      name: listingForm.name.trim(),
      short_description: listingForm.short_description.trim(),
      category: listingForm.category.trim(),
      icon_url: iconURL,
      pricing_type: listingForm.pricing_type,
      price_cents:
        listingForm.pricing_type === 'free' ? 0 : Math.round(listingForm.price_yuan * 100),
      status: listingForm.status
    }
  }

  function buildSaveParams(): SaveBotMiniAppParams | undefined {
    const startURL = form.start_url.trim()
    try {
      const parsed = new URL(startURL)
      if (
        parsed.protocol !== 'https:' ||
        !parsed.hostname.includes('.') ||
        (parsed.port && parsed.port !== '443')
      ) {
        ElMessage.warning('启动地址必须是 HTTPS 公网域名，且只能使用 443 端口')
        return
      }
    } catch {
      ElMessage.warning('请输入完整有效的 HTTPS 启动地址')
      return
    }
    const domains = [
      ...new Set(
        form.allowed_domains_text
          .split(/\r?\n|,/)
          .map((value) => value.trim().toLowerCase())
          .filter(Boolean)
      )
    ]
    if (domains.length > 20) {
      ElMessage.warning('安全域名最多配置 20 个')
      return
    }
    if (
      domains.some((domain) => domain.includes('/') || domain.includes(':') || domain.includes('*'))
    ) {
      ElMessage.warning('安全域名只填写域名本身，不要包含协议、端口、路径或通配符')
      return
    }
    return {
      bot_id: form.bot_id as number,
      name: form.name.trim(),
      description: form.description.trim(),
      start_url: startURL,
      allowed_domains: domains
    }
  }

  async function saveMiniApp() {
    const valid = await formRef.value?.validate().catch(() => false)
    if (!valid) return
    const params = buildSaveParams()
    if (!params) return
    saving.value = true
    try {
      if (editingApp.value) {
        await updateAdminMiniApp(editingApp.value.id, params)
      } else {
        await createAdminMiniApp(params)
      }
      ElMessage.success(editingApp.value ? 'Mini App 配置已更新' : 'Mini App 已创建')
      dialogVisible.value = false
      miniApps.value = (await getAdminMiniApps()).items || []
    } finally {
      saving.value = false
    }
  }

  async function saveListing() {
    const valid = await listingFormRef.value?.validate().catch(() => false)
    if (!valid) return
    const params = buildListingParams()
    if (!params) return
    listingSaving.value = true
    try {
      if (editingListing.value) {
        await updateAdminBotMarketListing(editingListing.value.id, params)
      } else {
        await createAdminBotMarketListing(params)
      }
      ElMessage.success(editingListing.value ? '市场应用已更新' : '市场应用已添加')
      listingDialogVisible.value = false
      await loadListings()
    } finally {
      listingSaving.value = false
    }
  }

  async function setListingStatus(row: BotMarketListing, status: 'approved' | 'delisted') {
    const params: SaveBotMarketListingParams = {
      bot_id: row.bot_id,
      ...(row.mini_app_id ? { mini_app_id: row.mini_app_id } : {}),
      name: row.name,
      short_description: row.short_description,
      category: row.category,
      icon_url: row.icon_url || '',
      pricing_type: row.pricing_type,
      price_cents: row.price_cents,
      status
    }
    await updateAdminBotMarketListing(row.id, params)
    ElMessage.success(status === 'approved' ? '市场应用已上架' : '市场应用已下架')
    await loadListings()
  }

  onMounted(load)
</script>

<style scoped lang="scss">
  .ecosystem-page {
    padding: 20px;
  }

  .panel {
    padding: 20px;
    margin-top: 20px;
    background: var(--art-main-bg-color);
    border: 1px solid var(--art-border-color);
    border-radius: 8px;
  }

  .panel-title {
    display: flex;
    gap: 20px;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 20px;

    h2 {
      margin: 0 0 6px;
    }

    p {
      margin: 0;
      color: var(--art-text-gray-600);
    }
  }

  .filters {
    display: flex;
    gap: 10px;
  }

  .muted,
  .form-help {
    margin-top: 4px;
    font-size: 12px;
    color: var(--art-text-gray-600);
  }

  .url-link {
    color: var(--el-color-primary);
  }

  .domain-tag {
    margin: 2px 4px 2px 0;
  }

  .version {
    margin-left: 6px;
    font-size: 12px;
    color: var(--art-text-gray-600);
  }

  .full-width {
    width: 100%;
  }

  @media (width <= 768px) {
    .panel-title {
      flex-direction: column;
      align-items: flex-start;
    }
  }
</style>
