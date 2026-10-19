import toc from '../../../Docs/guide/toc.json';

export type GuideLocale = 'en' | 'zh';

export type GuideChapter = {
  id: string;
  title: string;
};

type TOC = Record<GuideLocale, GuideChapter[]>;

const chapters: TOC = toc;
const markdown = import.meta.glob<string>('../../../Docs/guide/{en,zh}/*.md', {
  eager: true,
  query: '?raw',
  import: 'default',
});

export function getChapters(locale: GuideLocale): GuideChapter[] {
  return chapters[locale] ?? [];
}

export function getChapterMarkdown(locale: GuideLocale, id: string): string {
  return markdown[`../../../Docs/guide/${locale}/${id}.md`]
    ?? `# Not found\n\nMissing \`${id}.md\` for ${locale}.`;
}

export function getAllChapterParams(locale: GuideLocale): { slug: string }[] {
  return getChapters(locale).map((c) => ({ slug: c.id }));
}
