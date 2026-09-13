<template>
  <ElDialog
    v-model="visible"
    class="conversation-review-dialog"
    width="min(1440px, 94vw)"
    top="4vh"
    append-to-body
    destroy-on-close
    :close-on-click-modal="false"
    @closed="resetReviewState"
  >
    <template #header>
      <div class="review-dialog-head">
        <div>
          <p>隐私审计 / {{ reviewSessionId || '正在建立审阅会话' }}</p>
          <h2>会话审阅中心</h2>
        </div>
        <ElTag type="warning" effect="plain">只读审阅</ElTag>
      </div>
    </template>

    <div class="review-workbench" :style="{ '--review-watermark': `'${watermarkText}'` }">
      <aside class="review-sidebar">
        <div class="sidebar-search">
          <ElInput
            v-model="sidebarKeyword"
            clearable
            placeholder="搜索会话或成员"
            @keyup.enter="loadSidebar"
          >
            <template #prefix><ArtSvgIcon icon="ri:search-line" /></template>
          </ElInput>
          <ElButton :icon="Refresh" :loading="sidebarLoading" @click="loadSidebar" />
        </div>

        <div class="sidebar-summary">
          <span>当前列表</span>
          <strong>{{ sidebarTotal }}</strong>
          <small>个{{ isGroupReview ? '群聊' : '私聊会话' }}</small>
        </div>

        <div v-loading="sidebarLoading" class="review-chat-list">
          <button
            v-for="chat in sidebarChats"
            :key="chat.id"
            type="button"
            class="review-chat-item"
            :class="{ 'is-active': activeChat?.id === chat.id }"
            @click="selectChat(chat)"
          >
            <span class="chat-avatar-stack">
              <ElAvatar
                v-if="isGroupReview"
                :size="38"
                :src="getAvatarUrl(chat.avatar, chat.uuid || chat.name)"
                shape="square"
              >
                {{ chat.name?.slice(0, 1) || '群' }}
              </ElAvatar>
              <template v-else>
                <ElAvatar
                  v-for="member in (chat.members || []).slice(0, 2)"
                  :key="member.uuid"
                  :size="34"
                  :src="getAvatarUrl(member.avatar, member.uuid || member.nickname)"
                />
                <ElAvatar v-if="!chat.members?.length" :size="38">
                  {{ chat.name?.slice(0, 1) || '聊' }}
                </ElAvatar>
              </template>
            </span>
            <span class="chat-item-copy">
              <strong>{{ displayChatName(chat) }}</strong>
              <small>{{ memberSummary(chat) }}</small>
              <time>{{ formatShortTime(chat.createTime) }}</time>
            </span>
            <i :class="chat.status === 0 ? 'is-normal' : 'is-disabled'" aria-hidden="true" />
          </button>
          <ElEmpty
            v-if="!sidebarLoading && !sidebarChats.length"
            :description="isGroupReview ? '没有匹配的群聊' : '没有匹配的私聊'"
          />
        </div>
      </aside>

      <main class="review-main">
        <template v-if="activeChat">
          <header class="conversation-head">
            <div class="conversation-identity">
              <span class="chat-avatar-stack chat-avatar-stack--large">
                <ElAvatar
                  v-if="isGroupReview"
                  :size="40"
                  :src="getAvatarUrl(activeChat.avatar, activeChat.uuid || activeChat.name)"
                  shape="square"
                >
                  {{ activeChat.name?.slice(0, 1) || '群' }}
                </ElAvatar>
                <template v-else>
                  <ElAvatar
                    v-for="member in activeMembers.slice(0, 2)"
                    :key="member.uuid"
                    :size="40"
                    :src="getAvatarUrl(member.avatar, member.uuid || member.nickname)"
                  />
                </template>
              </span>
              <div>
                <h3>{{ displayChatName(activeChat) }}</h3>
                <p>{{ activeMemberText }}</p>
              </div>
            </div>
            <div class="conversation-controls">
              <ElSelect
                v-model="messageType"
                clearable
                placeholder="全部消息"
                @change="reloadMessages"
              >
                <ElOption
                  v-for="option in messageTypeOptions"
                  :key="option.value"
                  :label="option.label"
                  :value="option.value"
                />
              </ElSelect>
              <ElTag :type="cryptoTagType" effect="plain">{{ cryptoModeText }}</ElTag>
              <ElTag :type="activeChat.status === 0 ? 'success' : 'danger'" effect="light">
                {{ activeChat.status === 0 ? '正常' : '受限' }}
              </ElTag>
            </div>
          </header>

          <div class="review-notice">
            <ArtSvgIcon icon="ri:shield-keyhole-line" />
            <span>查看原因：{{ reviewReason }}</span>
            <small>已加载 {{ messages.length }} 条，本窗口不提供编辑、代发或删除操作</small>
          </div>

          <div ref="messageScrollRef" v-loading="messageLoading" class="message-scroll">
            <div class="load-older-wrap">
              <ElButton
                v-if="hasMore"
                link
                type="primary"
                :loading="olderLoading"
                @click="loadOlder"
              >
                向上加载更早消息
              </ElButton>
              <span v-else-if="messages.length">已到达当前保留记录起点</span>
            </div>

            <template v-for="(message, index) in messages" :key="message.msg_id || message.id">
              <div v-if="showDateDivider(message, index)" class="message-date-divider">
                <span>{{ formatMessageDate(message.created_at) }}</span>
              </div>
              <article class="message-row" :class="`message-row--${messageSide(message)}`">
                <ElAvatar
                  :size="34"
                  :src="
                    getAvatarUrl(message.sender_avatar, message.sender_id || message.sender_name)
                  "
                />
                <div class="message-column">
                  <div class="message-meta">
                    <strong>{{ message.sender_name || message.sender_id || '未知用户' }}</strong>
                    <time>{{ formatMessageTime(message.created_at) }}</time>
                    <span v-if="message.is_edited">已编辑</span>
                    <span>#{{ message.seq }}</span>
                  </div>
                  <div class="message-bubble" :class="messageBubbleClass(message)">
                    <template v-if="message.restricted_state">
                      <div class="restricted-message">
                        <ArtSvgIcon :icon="restrictedState(message).icon" />
                        <span>{{ restrictedState(message).text }}</span>
                      </div>
                    </template>

                    <template v-else-if="message.type === 2 && message.content.media?.url">
                      <ElImage
                        class="message-image"
                        :src="message.content.media.thumbnail || message.content.media.url"
                        :preview-src-list="[message.content.media.url]"
                        preview-teleported
                        fit="contain"
                      />
                      <small class="media-caption">
                        图片 · {{ formatBytes(message.content.media.size) }}
                      </small>
                    </template>

                    <template v-else-if="message.type === 3 && message.content.media?.url">
                      <video
                        class="message-video"
                        :src="message.content.media.url"
                        :poster="message.content.media.thumbnail"
                        controls
                        preload="metadata"
                      />
                      <small class="media-caption">
                        视频 · {{ formatDuration(message.content.media.duration) }} ·
                        {{ formatBytes(message.content.media.size) }}
                      </small>
                    </template>

                    <template v-else-if="message.type === 4 && message.content.voice?.url">
                      <div class="voice-message">
                        <ArtSvgIcon icon="ri:mic-line" />
                        <audio :src="message.content.voice.url" controls preload="metadata" />
                        <span>{{ formatDuration(message.content.voice.duration) }}</span>
                      </div>
                      <p v-if="message.content.voice.transcript" class="voice-transcript">
                        {{ message.content.voice.transcript }}
                      </p>
                    </template>

                    <template v-else-if="message.type === 5 && message.content.file">
                      <button
                        type="button"
                        class="file-message"
                        :disabled="!message.content.file.url"
                        @click="openMedia(message.content.file.url)"
                      >
                        <ArtSvgIcon icon="ri:file-3-line" />
                        <span>
                          <strong>{{ message.content.file.name || '未命名文件' }}</strong>
                          <small>
                            {{ message.content.file.mime_type || '未知格式' }} ·
                            {{ formatBytes(message.content.file.size) }}
                          </small>
                        </span>
                        <ArtSvgIcon icon="ri:external-link-line" />
                      </button>
                    </template>

                    <template v-else-if="message.type === 6 && message.content.location">
                      <div class="location-message">
                        <ArtSvgIcon icon="ri:map-pin-2-line" />
                        <span>
                          <strong>{{ message.content.location.title || '位置消息' }}</strong>
                          <small>{{
                            message.content.location.address || coordinateText(message)
                          }}</small>
                        </span>
                      </div>
                    </template>

                    <template v-else-if="message.type === 8 && message.content.sticker?.url">
                      <img class="sticker-image" :src="message.content.sticker.url" alt="表情" />
                    </template>

                    <template v-else-if="message.type === 10 && message.content.contact">
                      <div class="contact-message">
                        <ElAvatar
                          :size="42"
                          :src="
                            getAvatarUrl(
                              message.content.contact.avatar,
                              message.content.contact.user_id
                            )
                          "
                        />
                        <span>
                          <strong>{{ message.content.contact.nickname }}</strong>
                          <small>@{{ message.content.contact.username || '未设置账号' }}</small>
                        </span>
                      </div>
                    </template>

                    <template v-else-if="message.type === 14 && message.content.forward_bundle">
                      <div class="forward-message">
                        <strong>{{
                          message.content.forward_bundle.title || '合并转发消息'
                        }}</strong>
                        <span>
                          {{ message.content.forward_bundle.items?.length || 0 }} 条消息快照
                        </span>
                      </div>
                    </template>

                    <template v-else-if="message.type === 99">
                      <div class="system-message">
                        {{ message.content.text || message.content.system?.action || '系统消息' }}
                      </div>
                    </template>

                    <template v-else>
                      <p class="text-message">{{ messageText(message) }}</p>
                    </template>
                  </div>
                </div>
              </article>
            </template>

            <ElEmpty
              v-if="!messageLoading && !messages.length"
              description="当前筛选范围内没有可审阅的保留消息"
            />
          </div>
        </template>
        <ElEmpty v-else description="请选择左侧会话" />
      </main>
    </div>
  </ElDialog>
</template>

<script setup lang="ts">
  import { computed, nextTick, ref, watch } from 'vue'
  import { Refresh } from '@element-plus/icons-vue'
  import { ElMessage } from 'element-plus'
  import { getChatReviewMessages, type ChatReviewMember, type ChatReviewMessage } from '@/api/admin'
  import { fetchGetChatList, fetchGetGroupList, type ChatTableListItem } from '@/api/system-manage'
  import { getAvatarUrl } from '@/utils/url'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'ConversationReviewDialog' })

  const props = withDefaults(
    defineProps<{
      modelValue: boolean
      initialChat: ChatTableListItem | null
      reviewReason: string
      chatType?: 1 | 2
    }>(),
    { chatType: 1 }
  )

  const emit = defineEmits<{
    (event: 'update:modelValue', value: boolean): void
  }>()

  const visible = computed({
    get: () => props.modelValue,
    set: (value) => emit('update:modelValue', value)
  })

  const userStore = useUserStore()
  const sidebarLoading = ref(false)
  const messageLoading = ref(false)
  const olderLoading = ref(false)
  const sidebarKeyword = ref('')
  const sidebarChats = ref<ChatTableListItem[]>([])
  const sidebarTotal = ref(0)
  const activeChat = ref<ChatTableListItem | null>(null)
  const activeMembers = ref<ChatReviewMember[]>([])
  const messages = ref<ChatReviewMessage[]>([])
  const hasMore = ref(false)
  const nextBeforeSeq = ref(0)
  const reviewSessionId = ref('')
  const cryptoMode = ref<'plain' | 'compatible' | 'strict'>('plain')
  const messageType = ref<number | undefined>()
  const messageScrollRef = ref<HTMLElement>()
  const isGroupReview = computed(() => props.chatType === 2)

  const messageTypeOptions = [
    { label: '文字', value: 1 },
    { label: '图片', value: 2 },
    { label: '视频', value: 3 },
    { label: '语音', value: 4 },
    { label: '文件', value: 5 },
    { label: '位置', value: 6 },
    { label: '表情', value: 8 },
    { label: '名片', value: 10 },
    { label: '通话', value: 11 },
    { label: '红包', value: 12 },
    { label: '转账', value: 13 },
    { label: '合并转发', value: 14 },
    { label: '系统', value: 99 }
  ]

  const watermarkText = computed(() => {
    const actor = userStore.info.userName || userStore.info.userId || '管理员'
    return `${actor} · ${reviewSessionId.value || '隐私审阅'}`
  })
  const activeMemberText = computed(() =>
    activeMembers.value.length
      ? activeMembers.value
          .map((member) => member.nickname || member.username || member.uuid)
          .join(' · ')
      : '正在读取会话成员'
  )
  const cryptoModeText = computed(() =>
    cryptoMode.value === 'strict'
      ? '严格端到端加密'
      : cryptoMode.value === 'compatible'
        ? '兼容加密模式'
        : '服务端保留模式'
  )
  const cryptoTagType = computed(() => (cryptoMode.value === 'strict' ? 'warning' : 'info'))

  const loadSidebar = async () => {
    sidebarLoading.value = true
    try {
      const listParams = {
        current: 1,
        size: 30,
        keyword: sidebarKeyword.value
      }
      const response = isGroupReview.value
        ? await fetchGetGroupList(listParams)
        : await fetchGetChatList({ ...listParams, type: 1 })
      const rows = response.records
      if (props.initialChat && !rows.some((item) => item.id === props.initialChat?.id)) {
        rows.unshift(props.initialChat)
      }
      sidebarChats.value = rows
      sidebarTotal.value = response.total
    } catch {
      sidebarChats.value = props.initialChat ? [props.initialChat] : []
      ElMessage.error('读取私聊列表失败')
    } finally {
      sidebarLoading.value = false
    }
  }

  const fetchMessages = async (beforeSeq?: number) => {
    if (!activeChat.value) return
    const response = await getChatReviewMessages(
      activeChat.value.id,
      {
        limit: 50,
        before_seq: beforeSeq || undefined,
        type: messageType.value
      },
      props.reviewReason,
      reviewSessionId.value || undefined
    )
    reviewSessionId.value = response.review_session_id
    cryptoMode.value = response.chat.crypto_mode
    activeMembers.value = response.chat.members || []
    hasMore.value = response.has_more
    nextBeforeSeq.value = Number(response.next_before_seq || 0)
    return response.list || []
  }

  const selectChat = async (chat: ChatTableListItem) => {
    activeChat.value = chat
    messages.value = []
    hasMore.value = false
    nextBeforeSeq.value = 0
    messageType.value = undefined
    messageLoading.value = true
    try {
      messages.value = (await fetchMessages()) || []
      await nextTick()
      if (messageScrollRef.value)
        messageScrollRef.value.scrollTop = messageScrollRef.value.scrollHeight
    } catch {
      ElMessage.error('读取聊天记录失败，请确认账号权限和查看原因')
    } finally {
      messageLoading.value = false
    }
  }

  const reloadMessages = async () => {
    if (!activeChat.value) return
    messageLoading.value = true
    try {
      messages.value = (await fetchMessages()) || []
      await nextTick()
      if (messageScrollRef.value)
        messageScrollRef.value.scrollTop = messageScrollRef.value.scrollHeight
    } catch {
      ElMessage.error('筛选聊天记录失败')
    } finally {
      messageLoading.value = false
    }
  }

  const loadOlder = async () => {
    if (!nextBeforeSeq.value || !messageScrollRef.value) return
    olderLoading.value = true
    const scroll = messageScrollRef.value
    const previousHeight = scroll.scrollHeight
    try {
      const older = (await fetchMessages(nextBeforeSeq.value)) || []
      messages.value = [...older, ...messages.value]
      await nextTick()
      scroll.scrollTop = scroll.scrollHeight - previousHeight
    } catch {
      ElMessage.error('加载更早消息失败')
    } finally {
      olderLoading.value = false
    }
  }

  const resetReviewState = () => {
    sidebarKeyword.value = ''
    sidebarChats.value = []
    sidebarTotal.value = 0
    activeChat.value = null
    activeMembers.value = []
    messages.value = []
    reviewSessionId.value = ''
    messageType.value = undefined
    hasMore.value = false
    nextBeforeSeq.value = 0
  }

  const displayChatName = (chat: ChatTableListItem) => {
    if (chat.name) return chat.name
    const names = (chat.members || []).map((member) => member.nickname).filter(Boolean)
    return names.join(' · ') || `私聊 ${chat.uuid.slice(0, 8)}`
  }
  const memberSummary = (chat: ChatTableListItem) => {
    if (isGroupReview.value) {
      const owner = chat.ownerName ? `群主：${chat.ownerName}` : chat.description || chat.uuid
      return `${owner} · ${chat.memberCount || 0} 名成员`
    }
    const names = (chat.members || [])
      .map((member) => member.nickname || member.uuid)
      .filter(Boolean)
    return names.join(' · ') || chat.uuid
  }
  const messageSide = (message: ChatReviewMessage) =>
    isGroupReview.value || activeMembers.value[0]?.uuid === message.sender_id ? 'left' : 'right'
  const messageBubbleClass = (message: ChatReviewMessage) => ({
    'message-bubble--media': [2, 3, 8].includes(message.type) && !message.restricted_state,
    'message-bubble--system': message.type === 99
  })
  const restrictedState = (message: ChatReviewMessage) => {
    const states = {
      encrypted: { icon: 'ri:lock-2-line', text: '端到端加密消息，后台无法解密' },
      revoked: { icon: 'ri:arrow-go-back-line', text: '该消息已撤回，原内容不予恢复' },
      burn_after_read: { icon: 'ri:fire-line', text: '阅后即焚消息，内容不予恢复' },
      sensitive_transaction: {
        icon: 'ri:shield-check-line',
        text: message.type === 12 ? '红包消息（敏感详情已隐藏）' : '转账消息（敏感详情已隐藏）'
      }
    }
    return states[message.restricted_state || 'encrypted']
  }
  const messageText = (message: ChatReviewMessage) => {
    if (message.content.text) return message.content.text
    if (message.type === 11) return '通话记录'
    return '暂不支持展示的消息类型'
  }
  const coordinateText = (message: ChatReviewMessage) => {
    const location = message.content.location
    return location ? `${location.latitude.toFixed(6)}, ${location.longitude.toFixed(6)}` : ''
  }
  const openMedia = (url?: string) => {
    if (url) window.open(url, '_blank', 'noopener,noreferrer')
  }
  const formatBytes = (value?: number) => {
    const bytes = Number(value || 0)
    if (bytes <= 0) return '未知大小'
    const units = ['B', 'KB', 'MB', 'GB', 'TB']
    const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
    return `${(bytes / 1024 ** index).toFixed(index === 0 ? 0 : 1)} ${units[index]}`
  }
  const formatDuration = (seconds?: number) => {
    const total = Math.max(0, Number(seconds || 0))
    return `${Math.floor(total / 60)}:${String(Math.floor(total % 60)).padStart(2, '0')}`
  }
  const formatShortTime = (value: string) =>
    value ? new Date(value).toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' }) : '-'
  const formatMessageDate = (value: string) =>
    new Date(value).toLocaleDateString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    })
  const formatMessageTime = (value: string) =>
    new Date(value).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
  const showDateDivider = (message: ChatReviewMessage, index: number) =>
    index === 0 ||
    formatMessageDate(messages.value[index - 1].created_at) !==
      formatMessageDate(message.created_at)

  watch(
    () => props.modelValue,
    async (open) => {
      if (!open) return
      await loadSidebar()
      const target =
        sidebarChats.value.find((item) => item.id === props.initialChat?.id) ||
        props.initialChat ||
        sidebarChats.value[0]
      if (target) await selectChat(target)
    }
  )
</script>

<style scoped lang="scss">
  .review-dialog-head,
  .sidebar-search,
  .sidebar-summary,
  .review-chat-item,
  .conversation-head,
  .conversation-identity,
  .conversation-controls,
  .review-notice,
  .message-row,
  .message-meta,
  .voice-message,
  .file-message,
  .location-message,
  .contact-message,
  .restricted-message {
    display: flex;
    gap: 10px;
    align-items: center;
  }

  .review-dialog-head,
  .conversation-head {
    justify-content: space-between;
  }

  .review-dialog-head p,
  .review-dialog-head h2,
  .conversation-head h3,
  .conversation-head p,
  .text-message,
  .voice-transcript {
    margin: 0;
  }

  .review-dialog-head p {
    margin-bottom: 3px;
    font-size: 11px;
    color: var(--el-color-primary);
  }

  .review-dialog-head h2 {
    font-size: 19px;
  }

  .review-workbench {
    position: relative;
    display: grid;
    grid-template-columns: 330px minmax(0, 1fr);
    height: 100%;
    min-height: 0;
    overflow: hidden;
    background: var(--el-bg-color-page);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 10px;
  }

  .review-workbench::after {
    position: absolute;
    right: 24px;
    bottom: 20px;
    z-index: 5;
    font-size: 11px;
    color: rgb(100 116 139 / 24%);
    pointer-events: none;
    content: var(--review-watermark);
    transform: rotate(-12deg);
  }

  .review-sidebar {
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
    background: var(--el-bg-color-overlay);
    border-right: 1px solid var(--el-border-color-lighter);
  }

  .sidebar-search {
    padding: 14px;
    border-bottom: 1px solid var(--el-border-color-extra-light);
  }

  .sidebar-summary {
    padding: 10px 14px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    background: color-mix(in srgb, var(--el-color-primary) 4%, transparent);
  }

  .sidebar-summary strong {
    color: var(--el-color-primary);
  }

  .sidebar-summary small {
    margin-left: -5px;
  }

  .review-chat-list {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    scrollbar-gutter: stable;
    touch-action: pan-y;
  }

  .review-chat-item {
    position: relative;
    width: 100%;
    padding: 13px 14px;
    color: var(--el-text-color-primary);
    text-align: left;
    cursor: pointer;
    background: transparent;
    border: 0;
    border-bottom: 1px solid var(--el-border-color-extra-light);
    transition: background-color 0.16s ease;
  }

  .review-chat-item:hover,
  .review-chat-item.is-active {
    background: color-mix(in srgb, var(--el-color-primary) 8%, var(--el-bg-color-overlay));
  }

  .review-chat-item > i {
    flex: 0 0 auto;
    width: 7px;
    height: 7px;
    background: #ef4444;
    border-radius: 50%;
  }

  .review-chat-item > i.is-normal {
    background: #10b981;
  }

  .chat-avatar-stack {
    display: flex;
    flex: 0 0 auto;
    align-items: center;
  }

  .chat-avatar-stack :deep(.el-avatar + .el-avatar) {
    margin-left: -9px;
    border: 2px solid var(--el-bg-color-overlay);
  }

  .chat-avatar-stack--large :deep(.el-avatar + .el-avatar) {
    margin-left: -11px;
  }

  .chat-item-copy {
    display: grid;
    flex: 1;
    gap: 3px;
    min-width: 0;
  }

  .chat-item-copy strong,
  .chat-item-copy small {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .chat-item-copy strong {
    font-size: 13px;
  }

  .chat-item-copy small,
  .chat-item-copy time {
    font-size: 11px;
    color: var(--el-text-color-secondary);
  }

  .chat-item-copy time {
    position: absolute;
    top: 12px;
    right: 31px;
  }

  .review-main {
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
    overflow: hidden;
  }

  .conversation-head {
    min-height: 72px;
    padding: 12px 18px;
    background: var(--el-bg-color-overlay);
    border-bottom: 1px solid var(--el-border-color-lighter);
  }

  .conversation-head h3 {
    font-size: 15px;
  }

  .conversation-head p {
    max-width: 520px;
    margin-top: 4px;
    overflow: hidden;
    font-size: 11px;
    color: var(--el-text-color-secondary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .conversation-controls :deep(.el-select) {
    width: 128px;
  }

  .review-notice {
    padding: 8px 16px;
    font-size: 12px;
    color: #92400e;
    background: #fffbeb;
    border-bottom: 1px solid #fde68a;
  }

  .review-notice small {
    margin-left: auto;
    color: #a16207;
  }

  .message-scroll {
    flex: 1;
    min-height: 0;
    padding: 16px 24px 28px;
    overflow-y: auto;
    overscroll-behavior: contain;
    scrollbar-gutter: stable;
    touch-action: pan-y;
    background:
      radial-gradient(circle at 100% 0%, rgb(37 99 235 / 5%), transparent 340px),
      var(--el-bg-color-page);
  }

  .review-chat-list,
  .message-scroll {
    scrollbar-color: color-mix(in srgb, var(--el-text-color-placeholder) 58%, transparent)
      transparent;
    scrollbar-width: thin;
  }

  .review-chat-list::-webkit-scrollbar,
  .message-scroll::-webkit-scrollbar {
    width: 8px;
  }

  .review-chat-list::-webkit-scrollbar-thumb,
  .message-scroll::-webkit-scrollbar-thumb {
    background: color-mix(in srgb, var(--el-text-color-placeholder) 58%, transparent);
    background-clip: padding-box;
    border: 2px solid transparent;
    border-radius: 999px;
  }

  :global(.conversation-review-dialog) {
    display: flex;
    flex-direction: column;
    height: 92vh;
    max-height: 92vh;
    margin-bottom: 0;
  }

  :global(.conversation-review-dialog .el-dialog__header) {
    flex: 0 0 auto;
  }

  :global(.conversation-review-dialog .el-dialog__body) {
    flex: 1;
    min-height: 0;
    padding: 0 20px 20px !important;
    overflow: hidden;
  }

  .load-older-wrap {
    min-height: 26px;
    margin-bottom: 8px;
    font-size: 11px;
    color: var(--el-text-color-placeholder);
    text-align: center;
  }

  .message-date-divider {
    display: flex;
    align-items: center;
    justify-content: center;
    margin: 14px 0;
  }

  .message-date-divider span {
    padding: 4px 10px;
    font-size: 10px;
    color: var(--el-text-color-secondary);
    background: color-mix(in srgb, var(--el-fill-color-dark) 82%, transparent);
    border-radius: 999px;
  }

  .message-row {
    align-items: flex-start;
    margin: 13px 0;
  }

  .message-row--right {
    flex-direction: row-reverse;
  }

  .message-column {
    display: grid;
    gap: 5px;
    max-width: min(68%, 680px);
  }

  .message-row--right .message-column {
    justify-items: end;
  }

  .message-row--right .message-meta {
    flex-direction: row-reverse;
  }

  .message-meta {
    gap: 7px;
    font-size: 10px;
    color: var(--el-text-color-placeholder);
  }

  .message-meta strong {
    font-size: 11px;
    color: var(--el-text-color-secondary);
  }

  .message-bubble {
    min-width: 48px;
    padding: 10px 12px;
    overflow: hidden;
    background: var(--el-bg-color-overlay);
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 4px 13px 13px;
    box-shadow: 0 4px 12px rgb(15 23 42 / 4%);
  }

  .message-row--right .message-bubble {
    background: color-mix(in srgb, var(--el-color-primary) 9%, var(--el-bg-color-overlay));
    border-radius: 13px 4px 13px 13px;
  }

  .message-bubble--media,
  .message-bubble--system {
    padding: 0;
    background: transparent;
    border: 0;
    box-shadow: none;
  }

  .text-message {
    line-height: 1.65;
    overflow-wrap: anywhere;
    white-space: pre-wrap;
  }

  .message-image,
  .message-video {
    display: block;
    width: min(360px, 38vw);
    max-height: 360px;
    background: #0f172a;
    border-radius: 9px;
  }

  .message-video {
    object-fit: contain;
  }

  .media-caption {
    display: block;
    padding: 5px 3px 0;
    color: var(--el-text-color-secondary);
  }

  .voice-message audio {
    width: 230px;
    height: 32px;
  }

  .voice-message > span,
  .voice-transcript {
    font-size: 11px;
    color: var(--el-text-color-secondary);
  }

  .voice-transcript {
    padding-top: 7px;
    border-top: 1px solid var(--el-border-color-extra-light);
  }

  .file-message {
    min-width: 300px;
    padding: 2px;
    color: inherit;
    text-align: left;
    cursor: pointer;
    background: transparent;
    border: 0;
  }

  .file-message:disabled {
    cursor: not-allowed;
    opacity: 0.55;
  }

  .file-message > :deep(svg),
  .location-message > :deep(svg) {
    flex: 0 0 auto;
    width: 28px;
    height: 28px;
    color: var(--el-color-primary);
  }

  .file-message > span,
  .location-message > span,
  .contact-message > span {
    display: grid;
    flex: 1;
    gap: 3px;
  }

  .file-message small,
  .location-message small,
  .contact-message small {
    color: var(--el-text-color-secondary);
  }

  .sticker-image {
    display: block;
    width: 120px;
    height: 120px;
    object-fit: contain;
  }

  .forward-message {
    display: grid;
    gap: 7px;
    min-width: 220px;
  }

  .forward-message span,
  .system-message {
    font-size: 11px;
    color: var(--el-text-color-secondary);
  }

  .system-message {
    padding: 5px 11px;
    background: color-mix(in srgb, var(--el-fill-color-dark) 82%, transparent);
    border-radius: 999px;
  }

  .restricted-message {
    color: var(--el-text-color-secondary);
  }

  .restricted-message :deep(svg) {
    width: 18px;
    height: 18px;
    color: #d97706;
  }

  @media (width <= 900px) {
    .review-workbench {
      grid-template-columns: 250px minmax(0, 1fr);
    }

    .conversation-head,
    .review-notice {
      align-items: flex-start;
    }

    .conversation-head,
    .conversation-controls,
    .review-notice {
      flex-wrap: wrap;
    }

    .review-notice small {
      width: 100%;
      margin-left: 0;
    }

    .message-column {
      max-width: 82%;
    }
  }
</style>
