import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

const comfyuiUrl = process.env.COMFYUI_URL || 'http://127.0.0.1:8188'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:4080',
        changeOrigin: true,
      },
      '/generated_images': {
        target: comfyuiUrl,
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/generated_images/, '/view'),
      },
    },
    allowedHosts: [
      "gene.research-triangle.ai",
    ],
  },
})
