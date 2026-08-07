import { defineConfig } from 'tsup'

export default defineConfig({
  entry: {
    index: 'src/witty/index.ts',
    cli: 'src/witty/cli/index.ts',
    // 神农知识库检索的 stdio MCP server 入口（由 OpenCode 以子进程拉起，
    // 见 mcp/case-search-server/mcp-config.ts 的 resolveCliEntry）
    'case-search-cli': 'src/witty/mcp/case-search-server/cli.ts',
  },
  format: ['esm'],
  outDir: 'dist',
  dts: true,
  // 提示词纯数据随构建产物分发（prompt-loader 按 dist/prompts/ 相对定位）；
  // README 是迁移规则文档，不进发布物
  // 先清掉旧的 dist/prompts 再拷贝：`cp -R src dst` 在 dst 已存在时会拷成
  // dst/prompts 嵌套目录，导致重建后仍在用上一次的旧提示词（静默不报错）。
  onSuccess:
    'rm -rf dist/prompts && cp -R src/witty/agents/prompts dist/prompts && rm -f dist/prompts/README.md',
})
