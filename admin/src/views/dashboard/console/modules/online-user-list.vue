<template>
  <section
    class="art-card online-panel"
    :class="{ 'is-empty': users.length === 0 }"
    v-loading="loading"
  >
    <header class="panel-head">
      <div>
        <div class="title-line">
          <h4>在线会话</h4>
          <span class="stream-state"><i></i>自动同步</span>
        </div>
        <p>{{ lastUpdatedText }}</p>
      </div>
      <ElButton
        text
        circle
        :loading="loading"
        aria-label="刷新在线会话"
        title="刷新在线会话"
        @click="loadUsers(true)"
      >
        <ArtSvgIcon icon="ri:refresh-line" />
      </ElButton>
    </header>

    <div class="online-summary">
      <div class="primary">
        <ArtCountTo :target="users.length" :duration="620" />
        <span>在线</span>
      </div>
      <div>
        <strong>{{ androidCount }}</strong>
        <span>Android</span>
      </div>
      <div>
        <strong>{{ iosCount }}</strong>
        <span>iOS</span>
      </div>
      <div>
        <strong>{{ webCount }}</strong>
        <span>Web</span>
      </div>
    </div>

    <div v-if="users.length === 0 && !loading" class="empty-state">
      <span class="empty-radar"><i></i></span>
      <strong>当前没有在线用户</strong>
      <span>有新会话时会自动显示</span>
    </div>

    <TransitionGroup v-else name="online-row" tag="div" class="online-list">
      <RouterLink
        v-for="row in users.slice(0, 5)"
        :key="row.id"
        :to="{ path: '/user/list', query: { keyword: row.username } }"
        class="online-row"
      >
        <div class="user-cell">
          <div class="avatar-wrap">
            <ElImage class="avatar" :src="getAvatarUrl(row.avatar, row.id)" fit="cover" lazy />
            <span class="online-dot"></span>
          </div>
          <div class="min-w-0">
            <div class="name-line truncate">{{ row.nickname || row.username }}</div>
            <div class="sub-line truncate">
              {{ row.device_name || deviceTypeText(row.device_type) }} ·
              {{ row.device_ip || 'IP 未上报' }}
            </div>
          </div>
        </div>
        <ArtSvgIcon :icon="getDeviceIcon(row.device_type)" class="device-icon" />
        <span class="time-text" :title="`最近活跃：${row.last_seen || '-'}`">{{
          formatActiveAge(row.last_seen)
        }}</span>
        <ArtSvgIcon icon="ri:arrow-right-s-line" class="row-arrow" />
      </RouterLink>
    </TransitionGroup>

    <RouterLink v-if="users.length > 5" to="/user/list?online_only=true" class="online-more">
      查看全部 {{ users.length }} 个在线会话
      <ArtSvgIcon icon="ri:arrow-right-line" />
    </RouterLink>
  </section>
</template>

<script setup lang="ts">
  import { getUserList } from '@/api/admin'
  import type { UserListItem } from '@/api/admin'
  import { fixImageUrl, getLocalAvatarDataUrl } from '@/utils/url'

  const props = withDefaults(defineProps<{ refreshToken?: number }>(), { refreshToken: 0 })

  const users = ref<UserListItem[]>([])
  const loading = ref(true)
  const requesting = ref(false)
  const initialized = ref(false)
  const lastUpdatedAt = ref<Date | null>(null)

  const normalizedDeviceType = (item: UserListItem) => (item.device_type || '').toLowerCase()
  const androidCount = computed(
    () => users.value.filter((item) => normalizedDeviceType(item).includes('android')).length
  )
  const iosCount = computed(
    () =>
      users.value.filter((item) => {
        const type = normalizedDeviceType(item)
        return type.includes('ios') || type.includes('iphone')
      }).length
  )
  const webCount = computed(
    () => users.value.filter((item) => normalizedDeviceType(item).includes('web')).length
  )
  const lastUpdatedText = computed(() => {
    if (!lastUpdatedAt.value) return '正在同步会话'
    return `${lastUpdatedAt.value.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    })} 更新`
  })

  const getAvatarUrl = (avatar: string | null, id: number): string => {
    if (avatar) return fixImageUrl(avatar)
    return getLocalAvatarDataUrl(id)
  }

  const loadUsers = async (showLoading = false) => {
    if (requesting.value) return
    requesting.value = true
    try {
      if (showLoading || !initialized.value) loading.value = true
      const response = await getUserList({ page: 1, page_size: 30, online_only: true })
      users.value = response.list
      lastUpdatedAt.value = new Date()
    } catch (error) {
      console.error('加载在线会话失败:', error)
    } finally {
      initialized.value = true
      loading.value = false
      requesting.value = false
    }
  }

  const getDeviceIcon = (deviceType: string | null) => {
    const type = deviceType?.toLowerCase() || ''
    if (type.includes('ios') || type.includes('iphone')) return 'ri:apple-line'
    if (type.includes('android')) return 'ri:android-line'
    if (type.includes('mac')) return 'ri:macbook-line'
    if (type.includes('windows')) return 'ri:windows-line'
    if (type.includes('web')) return 'ri:global-line'
    return 'ri:smartphone-line'
  }

  const deviceTypeText = (deviceType: string | null) => deviceType || '未知设备'

  const formatActiveAge = (timeStr?: string | null) => {
    if (!timeStr) return '活跃'
    const timestamp = new Date(timeStr).getTime()
    if (!Number.isFinite(timestamp)) return '活跃'
    const minutes = Math.floor(Math.max(0, Date.now() - timestamp) / 60000)
    if (minutes < 1) return '刚活跃'
    if (minutes < 60) return `${minutes} 分前`
    return `${Math.floor(minutes / 60)} 小时前`
  }

  watch(
    () => props.refreshToken,
    () => void loadUsers(false),
    { immediate: true }
  )
</script>

<style scoped lang="scss">
  .online-panel {
    padding: 0;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .online-panel.is-empty {
    min-height: 160px;

    .panel-head {
      min-height: 52px;
      padding-block: 8px;
    }

    .online-summary {
      min-height: 44px;

      > div {
        padding-block: 6px;
      }
    }

    .empty-state {
      min-height: 62px;
    }
  }

  .panel-head,
  .title-line,
  .stream-state,
  .user-cell,
  .online-more {
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
      font-size: 11px;
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-secondary);
    }
  }

  .title-line,
  .stream-state {
    gap: 7px;
  }

  .stream-state {
    font-size: 11px;
    color: var(--el-color-success);

    i {
      width: 6px;
      height: 6px;
      background: currentcolor;
      border-radius: 50%;
      animation: streamPulse 2.1s ease-in-out infinite;
    }
  }

  .online-summary {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    min-height: 62px;
    background: var(--el-fill-color-extra-light);
    border-bottom: 1px solid var(--el-border-color-lighter);

    > div {
      display: flex;
      flex-direction: column;
      justify-content: center;
      min-width: 0;
      padding: 10px 12px;
      border-right: 1px solid var(--el-border-color-lighter);

      &:last-child {
        border-right: 0;
      }
    }

    strong,
    :deep(.art-count-to) {
      font-size: 17px;
      font-weight: 700;
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-primary);
    }

    .primary :deep(.art-count-to) {
      color: var(--el-color-success);
    }

    span {
      margin-top: 4px;
      overflow: hidden;
      font-size: 10px;
      color: var(--el-text-color-secondary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  .online-list {
    min-height: 222px;
  }

  .online-row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 18px 58px 16px;
    gap: 8px;
    align-items: center;
    min-height: 48px;
    padding: 7px 14px 7px 16px;
    color: inherit;
    border-bottom: 1px solid var(--el-border-color-extra-light);
    transition: background-color 180ms ease;

    &:hover {
      background: color-mix(in srgb, var(--el-fill-color-light) 68%, transparent);
    }

    &:hover .row-arrow {
      color: var(--el-color-primary);
      transform: translateX(2px);
    }
  }

  .user-cell {
    gap: 9px;
    min-width: 0;
  }

  .avatar-wrap {
    position: relative;
    flex: 0 0 30px;
  }

  .avatar {
    width: 30px;
    height: 30px;
    border-radius: 50%;
  }

  .online-dot {
    position: absolute;
    right: -1px;
    bottom: -1px;
    width: 8px;
    height: 8px;
    background: var(--el-color-success);
    border: 2px solid var(--el-bg-color);
    border-radius: 50%;
    animation: streamPulse 2.1s ease-in-out infinite;
  }

  .name-line {
    font-size: 12px;
    font-weight: 600;
    color: var(--el-text-color-primary);
  }

  .sub-line,
  .time-text {
    font-size: 10px;
    color: var(--el-text-color-secondary);
  }

  .device-icon,
  .row-arrow {
    color: var(--el-text-color-placeholder);
  }

  .row-arrow {
    transition:
      color 180ms ease,
      transform 180ms ease;
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    gap: 5px;
    align-items: center;
    justify-content: center;
    min-height: 76px;
    color: var(--el-text-color-secondary);

    strong {
      margin-top: 7px;
      font-size: 12px;
      font-weight: 600;
      color: var(--el-text-color-regular);
    }

    > span:last-child {
      font-size: 10px;
    }
  }

  .empty-radar {
    position: relative;
    display: grid;
    place-items: center;
    width: 42px;
    height: 42px;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 50%;

    &::before,
    &::after {
      position: absolute;
      content: '';
      border: 1px solid var(--el-border-color-extra-light);
      border-radius: 50%;
    }

    &::before {
      inset: 7px;
    }

    &::after {
      inset: 14px;
    }

    i {
      width: 5px;
      height: 5px;
      background: var(--el-color-success);
      border-radius: 50%;
      animation: streamPulse 2.1s ease-in-out infinite;
    }
  }

  .online-more {
    gap: 5px;
    justify-content: center;
    min-height: 34px;
    font-size: 11px;
    color: var(--el-color-primary);
    border-top: 1px solid var(--el-border-color-lighter);
  }

  .online-row-enter-active,
  .online-row-leave-active,
  .online-row-move {
    transition: all 260ms cubic-bezier(0.22, 1, 0.36, 1);
  }

  .online-row-enter-from,
  .online-row-leave-to {
    opacity: 0;
    transform: translateY(5px);
  }

  .online-row-enter-active {
    animation: onlineRowHighlight 500ms ease-out;
  }

  @keyframes onlineRowHighlight {
    from {
      background: color-mix(in srgb, var(--el-color-primary) 12%, transparent);
    }

    to {
      background: transparent;
    }
  }

  @keyframes streamPulse {
    50% {
      box-shadow: 0 0 0 4px color-mix(in srgb, var(--el-color-success) 14%, transparent);
      opacity: 0.55;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .stream-state i,
    .online-dot,
    .empty-radar i,
    .online-row-enter-active,
    .online-row-leave-active,
    .online-row-move,
    .row-arrow {
      transition: none;
      animation: none;
    }
  }
</style>
