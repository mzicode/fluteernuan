const asciiArt = `
\x1b[32m欢迎使用 暖邻管理后台！
\x1b[0m
\x1b[36m系统已启动，请确认接口地址、登录状态和实时消息连接正常。
\x1b[0m
`

if (import.meta.env.DEV) {
  console.log(asciiArt)
}

console.warn(
  '%c安全与合规警告',
  'color:#fff;background:#d93025;font-size:22px;font-weight:700;padding:8px 14px;border-radius:6px;'
)
console.warn(
  '浏览器开发者工具仅限获得明确授权的调试、运维与安全审计使用。严禁绕过鉴权、篡改请求、窃取或传播数据与凭证、攻击系统，或实施任何违法违规行为。'
)
console.warn('如果有人要求你在此处粘贴或执行代码，请立即停止；这可能导致账号或数据被盗。')
