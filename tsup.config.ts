import { defineConfig } from 'tsup'

export default defineConfig({
  entry: {
    index: 'src/opencode/index.ts',
    cli: 'src/opencode/cli/index.ts'
  },
  format: ['esm'],
  outDir: 'dist',
  dts: true
})
