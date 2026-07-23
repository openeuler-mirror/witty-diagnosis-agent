import { defineConfig } from 'tsup'

export default defineConfig({
  entry: {
    // 净室插件是唯一生效实现；旧树 src/opencode 仅作参考，不参与构建。
    index: 'src/witty/index.ts',
    cli: 'src/witty/cli/index.ts',
  },
  format: ['esm'],
  outDir: 'dist',
  dts: true,
  // 提示词纯数据随构建产物分发（prompt-loader 按 dist/prompts/ 相对定位）；
  // README 是迁移规则文档，不进发布物
  onSuccess: 'cp -R src/witty/agents/prompts dist/prompts && rm -f dist/prompts/README.md',
})
