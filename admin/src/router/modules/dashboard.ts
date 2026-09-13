import { AppRouteRecord } from '@/types/router'

export const dashboardRoutes: AppRouteRecord = {
  name: 'Dashboard',
  path: '/dashboard',
  component: '/index/index',
  meta: {
    title: '仪表盘',
    icon: 'ri:pie-chart-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'console',
      name: 'Console',
      component: '/dashboard/console',
      meta: {
        title: '控制台',
        icon: 'ri:home-smile-2-line',
        keepAlive: false,
        fixedTab: true
      }
    },
    {
      path: '/system/health',
      name: 'SystemHealth',
      component: '/system/health',
      meta: {
        title: '实时监控',
        icon: 'ri:heart-pulse-line',
        keepAlive: true,
        preservePath: true
      }
    },
    {
      path: '/system/data-governance',
      name: 'DataGovernanceCenter',
      component: '/system/data-governance',
      meta: {
        title: '数据治理中心',
        icon: 'ri:database-2-line',
        keepAlive: true,
        preservePath: true
      }
    },
    {
      path: '/system/security',
      name: 'SystemSecurity',
      component: '/system/security',
      meta: {
        title: '安全审计',
        icon: 'ri:shield-keyhole-line',
        keepAlive: true,
        preservePath: true
      }
    },
    {
      path: '/system/push-report',
      alias: ['/operation/push-report'],
      name: 'PushReport',
      component: '/system/push-report',
      meta: {
        title: '推送报表',
        icon: 'ri:bar-chart-box-line',
        keepAlive: true,
        preservePath: true
      }
    },
    {
      path: '/system/push-config',
      alias: ['/operation/push-config'],
      name: 'PushConfig',
      component: '/system/push-config',
      meta: {
        title: '推送配置',
        icon: 'ri:notification-3-line',
        keepAlive: true,
        preservePath: true
      }
    }
  ]
}
