import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { publicDir } from 'astro:config/server';
import type { Locale } from '@/i18n/ui';

/** Marketing visual stems (generated — see public/screenshots/README.md). */
export const SCREENSHOT_STEMS = [
  'hero',
  'capture-modebar',
  'quick-access-stack',
  'annotate',
  'settings-shortcuts',
  'ocr',
] as const;

export type ScreenshotStem = (typeof SCREENSHOT_STEMS)[number];

export const GALLERY_SCREENSHOTS: ScreenshotStem[] = [
  'capture-modebar',
  'quick-access-stack',
  'annotate',
  'settings-shortcuts',
  'ocr',
];

function stemPath(locale: Locale, stem: ScreenshotStem, file: string): string {
  return path.join(fileURLToPath(publicDir), 'screenshots', locale, file);
}

export function screenshotExists(locale: Locale, stem: ScreenshotStem): boolean {
  return fs.existsSync(stemPath(locale, stem, `${stem}-web.webp`));
}

export function availableGalleryScreenshots(locale: Locale): ScreenshotStem[] {
  return GALLERY_SCREENSHOTS.filter((name) => screenshotExists(locale, name));
}

const baseUrl = import.meta.env.BASE_URL.replace(/\/?$/, '/');

export function screenshotWebSrc(locale: Locale, stem: ScreenshotStem): string {
  return `${baseUrl}screenshots/${locale}/${stem}-web.webp`;
}

export function screenshotSrcSet(locale: Locale, stem: ScreenshotStem): string {
  const web = screenshotWebSrc(locale, stem);
  const full = `${baseUrl}screenshots/${locale}/${stem}.webp`;
  return `${web} 1x, ${full} 2x`;
}
