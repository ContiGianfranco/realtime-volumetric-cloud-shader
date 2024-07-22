import glsl from 'vite-plugin-glsl';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [ glsl() ],
  base: '/realtime-volumetric-cloud-shader/',
})
