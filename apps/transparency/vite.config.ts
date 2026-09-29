import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// A static site: `vite build` writes dist/, which any static host can serve. No backend (L5 section 5).
export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: { target: 'es2023', sourcemap: true },
});
