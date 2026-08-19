import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [vue()],
  base: '/chamados/',
  server: {
    port: 5174,
    proxy: {
      '/chamados-api': 'http://127.0.0.1:4567'
    }
  }
});
