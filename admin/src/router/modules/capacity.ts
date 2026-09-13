import { AppRouteRecord } from '@/types/router'

export const capacityRoutes: AppRouteRecord = {
  name: 'Capacity',
  path: '/capacity',
  component: '/index/index',
  meta: {
    title: '容量评估',
    icon: 'ri:speed-up-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'overview',
      name: 'CapacityOverview',
      component: '/capacity/overview',
      meta: {
        title: '容量概览',
        icon: 'ri:dashboard-3-line',
        keepAlive: true
      }
    },
    {
      path: 'nodes',
      name: 'CapacityNodes',
      component: '/capacity/nodes',
      meta: {
        title: '节点检测',
        icon: 'ri:server-line',
        keepAlive: true
      }
    },
    {
      path: 'p2',
      name: 'CapacityP2',
      component: '/capacity/p2',
      meta: {
        title: '集群与扩容',
        icon: 'ri:stack-line',
        keepAlive: true
      }
    }
  ]
}
