<!-- 快速操作 -->
<template>
  <div class="art-card action-panel">
    <div class="panel-head">
      <div>
        <h4>常用入口</h4>
        <p>高频配置与运营操作</p>
      </div>
    </div>

    <div class="action-list">
      <RouterLink v-for="item in actions" :key="item.path" :to="item.path" class="action-item">
        <ArtSvgIcon :icon="item.icon" class="action-icon" />
        <div class="action-copy">
          <div>{{ item.title }}</div>
          <p>{{ item.desc }}</p>
        </div>
        <ArtSvgIcon icon="ri:arrow-right-s-line" class="action-arrow" />
      </RouterLink>
    </div>
  </div>
</template>

<script setup lang="ts">
  const actions = [
    {
      title: '用户管理',
      desc: '查看和管理所有用户',
      icon: 'ri:user-line',
      path: '/user/list'
    },
    {
      title: '会话管理',
      desc: '管理群组和频道',
      icon: 'ri:chat-3-line',
      path: '/chat/list'
    },
    {
      title: '系统设置',
      desc: '基础信息、入口和开关',
      icon: 'ri:settings-3-line',
      path: '/system/settings'
    },
    {
      title: '推送配置',
      desc: '客户端通知与厂商通道',
      icon: 'ri:notification-3-line',
      path: '/system/push'
    }
  ]
</script>

<style scoped lang="scss">
  .action-panel {
    padding: 0;
    margin-bottom: 14px;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .panel-head {
    padding: 16px 18px 12px;
    border-bottom: 1px solid var(--el-border-color-lighter);

    h4 {
      margin: 0;
      font-size: 15px;
      font-weight: 650;
      color: var(--el-text-color-primary);
    }

    p {
      margin: 4px 0 0;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  .action-list {
    padding: 6px 0;
  }

  .action-item {
    display: grid;
    grid-template-columns: 22px minmax(0, 1fr) 18px;
    gap: 10px;
    align-items: center;
    min-height: 54px;
    padding: 9px 18px;
    color: inherit;
    border-bottom: 1px solid var(--el-border-color-extra-light);

    &:last-child {
      border-bottom: 0;
    }

    &:hover {
      background: var(--el-fill-color-extra-light);
    }

    &:hover .action-arrow {
      color: var(--el-color-primary);
      transform: translateX(3px);
    }
  }

  .action-icon {
    font-size: 17px;
    color: var(--el-text-color-secondary);
  }

  .action-copy {
    min-width: 0;

    div {
      font-size: 13px;
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    p {
      margin: 3px 0 0;
      overflow: hidden;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  .action-arrow {
    color: var(--el-text-color-placeholder);
    transition:
      color 180ms ease,
      transform 180ms ease;
  }
</style>
