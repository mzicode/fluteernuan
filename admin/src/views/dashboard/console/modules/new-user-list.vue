<template>
  <section class="art-card activity-panel" v-loading="loading">
    <header class="panel-head">
      <div>
        <h4>用户动态</h4>
        <p>{{ activeTab === 'new' ? '最新注册记录' : '最近活跃用户' }}</p>
      </div>
      <div class="head-actions">
        <div class="activity-tabs" role="tablist" aria-label="用户动态类型">
          <button
            v-for="tab in tabs"
            :key="tab.value"
            type="button"
            role="tab"
            :aria-selected="activeTab === tab.value"
            :class="{ active: activeTab === tab.value }"
            @click="activeTab = tab.value"
          >
            {{ tab.label }}
          </button>
        </div>
        <ElButton
          text
          circle
          :loading="loading"
          aria-label="刷新用户动态"
          title="刷新用户动态"
          @click="loadUsers(true)"
        >
          <ArtSvgIcon icon="ri:refresh-line" />
        </ElButton>
        <RouterLink to="/user/list" class="panel-link">
          全部用户
          <ArtSvgIcon icon="ri:arrow-right-s-line" />
        </RouterLink>
      </div>
    </header>

    <div class="list-head">
      <span>用户</span>
      <span>注册方式</span>
      <span>手机号</span>
      <span>状态</span>
      <span>{{ activeTab === 'new' ? '注册时间' : '最近活跃' }}</span>
      <span></span>
    </div>

    <div v-if="visibleUsers.length === 0 && !loading" class="empty-state">
      <ArtSvgIcon icon="ri:user-search-line" />
      <span>暂无用户记录</span>
    </div>

    <TransitionGroup v-else name="activity-row" tag="div" class="user-list">
      <RouterLink
        v-for="row in visibleUsers"
        :key="`${activeTab}-${row.id}`"
        :to="{ path: '/user/list', query: { keyword: row.username } }"
        class="user-row"
      >
        <div class="user-cell">
          <div class="avatar-wrap">
            <ElImage class="avatar" :src="getAvatarUrl(row.avatar, row.id)" fit="cover" lazy />
            <span v-if="row.is_online" class="online-dot"></span>
          </div>
          <div class="min-w-0">
            <div class="name-line truncate">{{ row.nickname || row.username }}</div>
            <div class="sub-line truncate">@{{ row.username }}</div>
          </div>
        </div>
        <div class="cell source-cell">
          <ArtSvgIcon
            :icon="row.register_source === 'quick' ? 'ri:flashlight-line' : 'ri:user-add-line'"
          />
          {{ row.register_source === 'quick' ? '快捷注册' : '普通注册' }}
        </div>
        <div class="cell muted">{{ maskPhone(row.phone) }}</div>
        <div class="cell status-cell" :class="row.status === 1 ? 'normal' : 'disabled'">
          <span></span>
          {{ row.status === 1 ? '正常' : '禁用' }}
        </div>
        <div class="cell time-text">
          {{ formatTime(activeTab === 'new' ? row.created_at : row.last_seen) }}
        </div>
        <ArtSvgIcon icon="ri:arrow-right-s-line" class="row-arrow" />
      </RouterLink>
    </TransitionGroup>
  </section>
</template>

<script setup lang="ts">
  import { getUserList } from '@/api/admin'
  import type { UserListItem } from '@/api/admin'
  import { fixImageUrl, getLocalAvatarDataUrl } from '@/utils/url'

  const props = withDefaults(defineProps<{ refreshToken?: number }>(), { refreshToken: 0 })

  type ActivityTab = 'new' | 'active'

  const users = ref<UserListItem[]>([])
  const loading = ref(true)
  const requesting = ref(false)
  const initialized = ref(false)
  const activeTab = ref<ActivityTab>('new')
  const tabs: Array<{ label: string; value: ActivityTab }> = [
    { label: '最新注册', value: 'new' },
    { label: '最近活跃', value: 'active' }
  ]

  const visibleUsers = computed(() => {
    const timeValue = (value?: string | null) => {
      const timestamp = value ? new Date(value).getTime() : 0
      return Number.isFinite(timestamp) ? timestamp : 0
    }
    return [...users.value]
      .sort((left, right) => {
        if (activeTab.value === 'new') {
          return timeValue(right.created_at) - timeValue(left.created_at)
        }
        return timeValue(right.last_seen) - timeValue(left.last_seen)
      })
      .slice(0, 6)
  })

  const getAvatarUrl = (avatar: string | null, id: number): string => {
    if (avatar) return fixImageUrl(avatar)
    return getLocalAvatarDataUrl(id)
  }

  const maskPhone = (phone?: string | null) => {
    const value = (phone || '').trim()
    if (!value) return '-'
    if (value.length < 7) return value
    return `${value.slice(0, 3)}****${value.slice(-4)}`
  }

  const loadUsers = async (showLoading = false) => {
    if (requesting.value) return
    requesting.value = true
    try {
      if (showLoading || !initialized.value) loading.value = true
      const response = await getUserList({ page: 1, page_size: 20 })
      users.value = response.list
    } catch (error) {
      console.error('加载用户动态失败:', error)
    } finally {
      initialized.value = true
      loading.value = false
      requesting.value = false
    }
  }

  const formatTime = (timeStr?: string | null) => {
    if (!timeStr) return '-'
    const timestamp = new Date(timeStr).getTime()
    if (!Number.isFinite(timestamp)) return '-'
    const diff = Math.max(0, Date.now() - timestamp)
    const minutes = Math.floor(diff / 60000)
    const hours = Math.floor(diff / 3600000)
    const days = Math.floor(diff / 86400000)
    if (minutes < 1) return '刚刚'
    if (minutes < 60) return `${minutes} 分钟前`
    if (hours < 24) return `${hours} 小时前`
    if (days < 7) return `${days} 天前`
    return new Date(timeStr).toLocaleDateString('zh-CN')
  }

  watch(
    () => props.refreshToken,
    () => void loadUsers(false),
    { immediate: true }
  )
</script>

<style scoped lang="scss">
  .activity-panel {
    padding: 0;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .panel-head,
  .head-actions,
  .panel-link,
  .user-cell,
  .source-cell,
  .status-cell {
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
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  .head-actions {
    gap: 8px;
  }

  .activity-tabs {
    display: flex;
    gap: 2px;
    align-items: center;
    padding: 3px;
    background: var(--el-fill-color-light);
    border-radius: 7px;

    button {
      min-height: 28px;
      padding: 0 11px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      cursor: pointer;
      background: transparent;
      border: 0;
      border-radius: 5px;
      transition:
        color 180ms ease,
        background-color 180ms ease,
        box-shadow 180ms ease;

      &.active {
        font-weight: 600;
        color: var(--el-text-color-primary);
        background: var(--el-bg-color);
        box-shadow: 0 1px 3px rgb(15 23 42 / 10%);
      }
    }
  }

  .panel-link {
    gap: 2px;
    font-size: 12px;
    font-weight: 600;
    color: var(--el-color-primary);
  }

  .list-head,
  .user-row {
    display: grid;
    grid-template-columns: minmax(220px, 1.5fr) 120px minmax(110px, 0.8fr) 72px 100px 18px;
    gap: 14px;
    align-items: center;
  }

  .list-head {
    min-height: 35px;
    padding: 0 16px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    background: var(--el-fill-color-extra-light);
    border-bottom: 1px solid var(--el-border-color-extra-light);
  }

  .user-row {
    min-height: 58px;
    padding: 8px 16px;
    color: inherit;
    border-bottom: 1px solid var(--el-border-color-extra-light);
    transition:
      background-color 180ms ease,
      transform 180ms ease;

    &:last-child {
      border-bottom: 0;
    }

    &:hover {
      background: color-mix(in srgb, var(--el-fill-color-light) 68%, transparent);
    }

    &:hover .row-arrow {
      color: var(--el-color-primary);
      transform: translateX(3px);
    }
  }

  .user-cell,
  .source-cell,
  .status-cell {
    gap: 9px;
    min-width: 0;
  }

  .avatar-wrap {
    position: relative;
    flex: 0 0 34px;
  }

  .avatar {
    width: 34px;
    height: 34px;
    border-radius: 50%;
  }

  .online-dot {
    position: absolute;
    right: -1px;
    bottom: -1px;
    width: 9px;
    height: 9px;
    background: var(--el-color-success);
    border: 2px solid var(--el-bg-color);
    border-radius: 50%;
    animation: onlinePulse 2.3s ease-in-out infinite;
  }

  .name-line {
    font-size: 13px;
    font-weight: 600;
    color: var(--el-text-color-primary);
  }

  .sub-line,
  .cell {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .source-cell svg {
    font-size: 15px;
  }

  .status-cell {
    gap: 6px;

    span {
      width: 6px;
      height: 6px;
      background: var(--el-color-success);
      border-radius: 50%;
    }

    &.disabled {
      color: var(--el-color-danger);

      span {
        background: var(--el-color-danger);
      }
    }
  }

  .time-text {
    font-variant-numeric: tabular-nums;
  }

  .row-arrow {
    color: var(--el-text-color-placeholder);
    transition:
      color 180ms ease,
      transform 180ms ease;
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    gap: 8px;
    align-items: center;
    justify-content: center;
    min-height: 174px;
    font-size: 12px;
    color: var(--el-text-color-secondary);

    svg {
      font-size: 26px;
      color: var(--el-text-color-placeholder);
    }
  }

  .activity-row-enter-active,
  .activity-row-leave-active,
  .activity-row-move {
    transition: all 260ms cubic-bezier(0.22, 1, 0.36, 1);
  }

  .activity-row-enter-from,
  .activity-row-leave-to {
    opacity: 0;
    transform: translateY(6px);
  }

  .activity-row-enter-active {
    animation: activityRowHighlight 500ms ease-out;
  }

  @keyframes activityRowHighlight {
    from {
      background: color-mix(in srgb, var(--el-color-primary) 10%, transparent);
    }

    to {
      background: transparent;
    }
  }

  @keyframes onlinePulse {
    50% {
      box-shadow: 0 0 0 4px color-mix(in srgb, var(--el-color-success) 15%, transparent);
    }
  }

  @media (width <= 900px) {
    .list-head,
    .user-row {
      grid-template-columns: minmax(180px, 1fr) 110px 72px 92px 18px;
    }

    .list-head > :nth-child(3),
    .user-row > :nth-child(3) {
      display: none;
    }
  }

  @media (width <= 640px) {
    .panel-head {
      flex-direction: column;
      align-items: flex-start;
    }

    .head-actions {
      width: 100%;
    }

    .panel-link {
      margin-left: auto;
    }

    .list-head {
      display: none;
    }

    .user-row {
      grid-template-columns: minmax(0, 1fr) auto 18px;
    }

    .user-row > :nth-child(2),
    .user-row > :nth-child(3),
    .user-row > :nth-child(4) {
      display: none;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .online-dot,
    .activity-row-enter-active,
    .activity-row-leave-active,
    .activity-row-move,
    .user-row,
    .row-arrow {
      transition: none;
      animation: none;
    }
  }
</style>
