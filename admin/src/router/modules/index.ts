import { AppRouteRecord } from '@/types/router'
import { dashboardRoutes } from './dashboard'
import { capacityRoutes } from './capacity'
import {
  userPermissionRoutes,
  messageCommunityRoutes,
  contentRiskRoutes,
  memberWalletRoutes,
  operationRoutes,
  systemRoutes,
} from './system'

/**
 * 即时通信后台管理路由
 */
export const routeModules: AppRouteRecord[] = [
  dashboardRoutes,
  capacityRoutes,
  userPermissionRoutes,
  messageCommunityRoutes,
  contentRiskRoutes,
  memberWalletRoutes,
  operationRoutes,
  systemRoutes
]
