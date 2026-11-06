# 自定义 compreface-fe：在官方 1.2.0 镜像基础上替换前端静态产物。
#
# 前置：ui 源码已完成「UI 美化 + 中英国际化」改造，并已执行生产构建：
#   cd build/CompreFace/ui
#   nvm use 16.20.2        # Angular 11 工具链需要 Node 12/14/16
#   npm install --legacy-peer-deps --registry=https://registry.npmmirror.com
#   npm run build:prod     # 产物输出 dist/compreface
#
# 本镜像保留官方镜像的 nginx 模板、envsubst 入口脚本与运行时环境变量约定
# （CLIENT_MAX_BODY_SIZE / PROXY_READ_TIMEOUT / PROXY_CONNECT_TIMEOUT），
# 仅覆盖 /usr/share/nginx/html 静态资源，其余行为与 exadel/compreface-fe:1.2.0 一致。
FROM exadel/compreface-fe:1.2.0

COPY dist/compreface/ /usr/share/nginx/html/
