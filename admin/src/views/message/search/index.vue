<script setup lang="ts">
  import { ref, onMounted, watch } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { searchMessages } from '@/api/admin'
  import { getAvatarUrl } from '@/utils/url'

  defineOptions({ name: 'MessageSearch' })

  const route = useRoute()
  const router = useRouter()

  const loading = ref(false)
  const list = ref<any[]>([])
  const page = ref(1)
  const pageSize = 20
  const total = ref(0)
  const keyword = ref('')
  const chatId = ref('')
  const senderId = ref('')
  const msgType = ref('')
  const dateRange = ref<[Date, Date] | null>(null)
  const targetName = ref('')

  const typeOptions = [
    { label: '文本', value: '1' },
    { label: '图片', value: '2' },
    { label: '视频', value: '3' },
    { label: '语音', value: '4' },
    { label: '文件', value: '5' },
    { label: '位置', value: '6' },
    { label: '表情', value: '8' },
    { label: '名片', value: '10' },
    { label: '通话', value: '11' },
    { label: '红包', value: '12' },
    { label: '转账', value: '13' },
    { label: '合并转发', value: '14' },
    { label: '系统', value: '99' }
  ]

  const typeMap: Record<
    number,
    { label: string; type: 'success' | 'info' | 'warning' | 'danger' }
  > = {
    1: { label: '文本', type: 'success' },
    2: { label: '图片', type: 'info' },
    3: { label: '视频', type: 'warning' },
    4: { label: '语音', type: 'info' },
    5: { label: '文件', type: 'warning' },
    6: { label: '位置', type: 'success' },
    8: { label: '表情', type: 'info' },
    10: { label: '名片', type: 'success' },
    11: { label: '通话', type: 'warning' },
    12: { label: '红包', type: 'danger' },
    13: { label: '转账', type: 'warning' },
    14: { label: '合并转发', type: 'info' },
    99: { label: '系统', type: 'danger' }
  }

  const fallbackPreview: Record<number, string> = {
    2: '[图片]',
    3: '[视频]',
    4: '[语音]',
    5: '[文件]',
    6: '[位置]',
    8: '[表情]',
    10: '[名片]',
    11: '[通话]',
    12: '[红包]',
    13: '[转账]',
    14: '[合并转发]',
    99: '[系统]'
  }

  function getContentText(row: any): string {
    const content = row.content
    return typeof content === 'object' && content !== null
      ? content.text || ''
      : typeof content === 'string'
        ? content
        : ''
  }

  function getMessageTypeConfig(row: any) {
    if (row.type === 11) {
      const text = getContentText(row)
      return text.includes('视频通话')
        ? { label: '视频通话', type: 'warning' as const }
        : { label: '语音通话', type: 'warning' as const }
    }
    return typeMap[row.type] || { label: '未知', type: 'info' as const }
  }

  function formatDate(d: Date) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }

  function getMsgPreview(row: any) {
    const text = getContentText(row)
    return text || fallbackPreview[row.type] || '[消息]'
  }

  async function loadData() {
    loading.value = true
    try {
      const params: any = { page: page.value, page_size: pageSize }
      if (keyword.value) params.keyword = keyword.value
      if (chatId.value) params.chat_id = chatId.value
      if (senderId.value) params.sender_id = senderId.value
      if (msgType.value) params.type = msgType.value
      if (dateRange.value) {
        params.start_date = formatDate(dateRange.value[0])
        params.end_date = formatDate(dateRange.value[1])
      }
      const res = (await searchMessages(params)) as any
      list.value = res?.list || []
      total.value = res?.total || 0
    } catch (error) {
      console.error('Failed to search messages:', error)
    }
    loading.value = false
  }

  function handleSearch() {
    page.value = 1
    loadData()
  }

  function clearTarget() {
    chatId.value = ''
    senderId.value = ''
    targetName.value = ''
    router.replace({ query: {} })
    page.value = 1
    loadData()
  }

  function applyQueryParams() {
    const q = route.query
    chatId.value = q.chat_id ? String(q.chat_id) : ''
    senderId.value = q.sender_id ? String(q.sender_id) : ''
    targetName.value = q.name ? String(q.name) : ''
    page.value = 1
    loadData()
  }

  watch(() => route.query, applyQueryParams)
  onMounted(applyQueryParams)
</script>

<template>
  <ElCard>
    <template #header>
      <div style="display: flex; flex-wrap: wrap; gap: 8px; align-items: center">
        <ElAlert
          v-if="targetName"
          type="info"
          :closable="false"
          style="padding: 4px 12px; flex: none"
        >
          {{ targetName }} 的聊天记录
        </ElAlert>
        <ElInput
          v-model="keyword"
          placeholder="搜索消息内容"
          clearable
          style="width: 200px"
          @keyup.enter="handleSearch"
        />
        <ElInput v-model="chatId" placeholder="会话ID" clearable style="width: 160px" />
        <ElInput v-model="senderId" placeholder="发送者ID" clearable style="width: 160px" />
        <ElSelect v-model="msgType" placeholder="消息类型" clearable style="width: 120px">
          <ElOption v-for="o in typeOptions" :key="o.value" :label="o.label" :value="o.value" />
        </ElSelect>
        <ElDatePicker
          v-model="dateRange"
          type="daterange"
          range-separator="至"
          start-placeholder="开始日期"
          end-placeholder="结束日期"
          style="width: 260px"
          value-format="YYYY-MM-DD"
        />
        <ElButton type="primary" @click="handleSearch">搜索</ElButton>
        <ElButton v-if="targetName" @click="clearTarget">清除筛选</ElButton>
      </div>
    </template>

    <ElTable :data="list" v-loading="loading" stripe size="small">
      <ElTableColumn label="发送者" width="150">
        <template #default="{ row }">
          <div style="display: flex; align-items: center; gap: 8px">
            <ElAvatar
              :size="28"
              :src="getAvatarUrl(row.sender_avatar, row.sender_id || row.sender_name)"
            />
            <span>{{ row.sender_name || row.sender_id }}</span>
          </div>
        </template>
      </ElTableColumn>
      <ElTableColumn label="类型" width="100">
        <template #default="{ row }">
          <ElTag :type="getMessageTypeConfig(row).type" size="small">
            {{ getMessageTypeConfig(row).label }}
          </ElTag>
        </template>
      </ElTableColumn>
      <ElTableColumn label="内容" min-width="260">
        <template #default="{ row }">
          <div
            style="max-width: 250px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap"
          >
            {{ getMsgPreview(row) }}
          </div>
        </template>
      </ElTableColumn>
      <ElTableColumn prop="chat_id" label="会话ID" width="140" show-overflow-tooltip />
      <ElTableColumn prop="created_at" label="发送时间" width="170" />
    </ElTable>

    <div style="display: flex; justify-content: flex-end; margin-top: 16px">
      <ElPagination
        :current-page="page"
        :page-size="pageSize"
        :total="total"
        layout="total,prev,pager,next"
        @current-change="
          (p: number) => {
            page = p
            loadData()
          }
        "
      />
    </div>
  </ElCard>
</template>
