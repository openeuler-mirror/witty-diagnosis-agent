import { defineConfig } from 'tsup'

export default defineConfig({
  entry: {
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
