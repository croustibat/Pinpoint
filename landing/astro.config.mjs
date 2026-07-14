import { defineConfig } from 'astro/config';

// Tailwind CSS v4 is wired through PostCSS (postcss.config.mjs) rather than the
// @tailwindcss/vite plugin, which is currently incompatible with Astro 6's
// rolldown-based Vite.
// https://astro.build/config
export default defineConfig({
  site: 'https://pinpoint-ashy.vercel.app',
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'fr'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
});
