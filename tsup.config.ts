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
  // tsup 默认把 package.json 的 dependencies 当作 external，产物仍需 node_modules
  // 才能启动。RPM 只分发 dist/，不装依赖树，故必须把依赖全部内联。
  noExternal: [/.*/],
  // 内联进来的 CJS 依赖（commander 等）在自身代码里调用 require()，
  // 而 ESM 产物中没有该函数，会抛 "Dynamic require of ... is not supported"。
  // 注入 createRequire shim 补齐。
  banner: {
    js: 'import{createRequire as __cr}from"node:module";const require=__cr(import.meta.url);',
  },
  // 提示词纯数据随构建产物分发（prompt-loader 按 dist/prompts/ 相对定位）；
  // README 是迁移规则文档，不进发布物
  // 先清掉旧的 dist/prompts 再拷贝：`cp -R src dst` 在 dst 已存在时会拷成
  // dst/prompts 嵌套目录，导致重建后仍在用上一次的旧提示词（静默不报错）。
  onSuccess:
    'rm -rf dist/prompts && cp -R src/witty/agents/prompts dist/prompts && rm -f dist/prompts/README.md',
})
