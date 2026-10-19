# Astro 7 / Tailwind CSS 4 migration

## Dependencies and commands

- Astro: 5.18.2 (previous lockfile) → 7.4.0 (`^7.4.0`).
- Tailwind CSS: 3.4.19 → 4.3.3, using `@tailwindcss/vite` 4.3.3.
- Removed `@astrojs/tailwind`; retained `@astrojs/sitemap` 3.7.4, the latest
  registry release, compatible with the migrated build.
- Sharp remains on the current, non-vulnerable 0.35.5 release, now deduplicated
  with Astro instead of retaining Astro's vulnerable nested Sharp version.
- Required engines: Node >=22.22.0 and npm >=9.6.5. Validation used Node
  22.23.3 and npm 11.8.0; the existing CI `node-version: '22'` satisfies this
  when resolving the latest Node 22 release.
- All 306 lockfile `resolved` URLs use `registry.npmjs.org`.

Run from `website/`:

```sh
export npm_config_cache="$PWD/.npm-cache-tmp"
npm ci --registry=https://registry.npmjs.org
npm run build --registry=https://registry.npmjs.org
npm audit --registry=https://registry.npmjs.org
rm -rf .npm-cache-tmp
```

## Compatibility decisions

- Kept `site`, `/Octoshot` base, trailing slashes, and sitemap i18n unchanged.
- Set `compressHTML: true` explicitly to retain the pre-Astro-7 inline
  whitespace behavior instead of the new JSX whitespace default.
- Guide Markdown and TOC are imported at build time. Runtime filesystem paths
  relative to bundled `import.meta.url` no longer locate the original sources
  under Astro 7's `.prerender/chunks` output layout.
- Screenshot discovery uses `publicDir` from `astro:config/server` rather than
  assuming the bundled module remains at its source location.
- `global.css` owns the former Tailwind theme: all `mb-*` colors, font stacks,
  content/narrow widths, tile/shot/pill radii, mb easing, and shot shadow.
  The JavaScript Tailwind config is removed. Dark colors remain media-driven;
  Tailwind's default `dark` variant also uses `prefers-color-scheme`.
- The Tailwind import includes Preflight. Compatibility base rules retain v3
  border color, placeholder color/opacity, and button/role-button cursors.
  Legacy default ring width/color are configured, although no ring utilities
  occur in the site's source.
- Source inspection covered all `.astro`, `.md`, and `.ts` files under `src`.
  `shadow-sm` becomes `shadow-xs`. The three `space-y-*` usages become
  `legacy-space-y-*` utilities retaining v3's following-sibling, hidden-aware,
  top-margin behavior. Other renamed blur/radius/outline utilities, bare rings,
  divide utilities, and placeholder utilities were not present.
- The hover variant retains unconditional v3 `:hover` behavior, including
  touch-device emulation. Existing component styles stay in `@layer components`:
  no variant-prefixed component utilities or `@apply` require conversion.
- Chinese heading tracking remains unlayered so the new CSS cascade layers do
  not let heading utilities override the previous higher-specificity rule.

## Validation results

- Clean `npm ci` followed by a production build passed on Node 22.23.3:
  17 static HTML pages plus the robots endpoint.
- Audit before: 11 vulnerabilities (1 critical, 6 high, 3 moderate, 1 low).
  Audit after clean installation: **0 vulnerabilities**; no overrides or forced
  audit fixes were needed.
- Both asset scripts pass `node --check`. Playwright, Sharp, and the scenes
  module import successfully; all six scenes generate HTML in both locales,
  and Sharp successfully encodes a PNG. Asset scripts were not run to completion
  because doing so would overwrite the intentionally preserved public files.
- Development HTTP smoke checks returned 200 with expected page titles and no
  Astro error overlay for `/Octoshot/en/`, `/Octoshot/zh/`,
  `/Octoshot/en/docs/capture/`, and `/Octoshot/zh/docs/ai/`.
- All 17 HTML documents match the supplied old build's normalized content and
  structure after excluding scripts/styles, generated download IDs, scoped
  compiler IDs, and the intentional utility renames. Metadata and non-CSS
  resource/navigation URLs match; no broken `/Octoshot/` file links were found.
- Every public file is copied byte-for-byte. Both sitemap XML files and
  `robots.txt` also match the old build byte-for-byte. The source and built
  `appcast.xml` SHA-256 is
  `0b7ab6bd9b64e11692fd96e645c6ec896725c15123a8a4a63644eb1227c7a311`.

## Dist inventory comparison

Compared against the read-only `~/Developer/site-old-dist` baseline:

- Before: 70 files. After: 70 files.
- Removed: `_astro/_slug_.DObeSHcV.css`.
- Added: `_astro/BaseLayout.CH701g-t.css`.
- All other file paths remain unchanged, including every English/Chinese docs
  page, favicon, OG image, screenshot, sitemap, and appcast.
- Sixteen localized HTML files change bytes because of the CSS reference,
  compiler/script serialization, generated download IDs, and utility renames.
  The root redirect HTML is byte-identical. Scoped brand CSS is now bundled
  into the external stylesheet instead of an inline style element. The CSS
  basename/hash change is normal compiler output, not a page or asset-route move.

## Remaining acceptance gap

Pixel parity and runtime interactions are **not independently verified** here.
The available browser tool failed initialization with
`sandboxCwd must be an absolute file URI`; local Playwright Chromium then failed
at launch with `bootstrap_check_in ... Permission denied (1100)` under the
filesystem/process sandbox. No browser restrictions were bypassed. Before
merging, compare both locales' landing/docs pages in desktop/mobile light/dark
states, open the language menu and FAQ, and check console errors, focus states,
and hover states against the old build. Static comparison is not a substitute
for this rendered check. Tailwind v4 also raises browser requirements to Safari
16.4+, Chrome 111+, and Firefox 128+; very old browsers are outside its support.
