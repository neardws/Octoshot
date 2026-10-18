export type Locale = 'en' | 'zh';

export const locales: Locale[] = ['en', 'zh'];

export type MascotCardCopy = {
  cardTitle: string;
  ariaLabel: string;
  labelName: string;
  name: string;
  labelSpecies: string;
  species: string;
  speciesFact: string;
  labelPersonality: string;
  personality: string;
  labelCatchphrase: string;
  catchphrase: string;
  labelRole: string;
  role: string;
};

export type FeatureTile = {
  title: string;
  /** One-line grumpy-but-helpful quip in 一酱's voice */
  quip: string;
  body: string;
  wide?: boolean;
};

export type GalleryQuips = {
  'capture-modebar': string;
  'quick-access-stack': string;
  annotate: string;
  'settings-shortcuts': string;
  ocr: string;
};

export type LandingCopy = {
  lang: string;
  htmlLang: string;
  metaTitle: string;
  metaDescription: string;
  navFeatures: string;
  navAgent: string;
  navFaq: string;
  navDocs: string;
  navDownload: string;
  heroEyebrow: string;
  heroTitle: string;
  heroLead: string;
  heroCta: string;
  heroSecondary: string;
  heroFine: string;
  mascotCard: MascotCardCopy;
  galleryTitle: string;
  galleryLead: string;
  galleryQuips: GalleryQuips;
  galleryShotCapture: string;
  galleryShotQuickAccess: string;
  galleryShotAnnotate: string;
  galleryShotSettings: string;
  galleryShotOcr: string;
  heroScreenshotAlt: string;
  tilesTitle: string;
  tilesLead: string;
  tiles: FeatureTile[];
  agentTitle: string;
  agentLead: string;
  agentTerminal: string[];
  agentTiles: { title: string; body: string }[];
  stepsTitle: string;
  steps: { title: string; body: string }[];
  faqTitle: string;
  faqs: { q: string; a: string }[];
  finalTitle: string;
  finalLead: string;
  finalCta: string;
  footerTagline: string;
  footerDisclaimer: string;
  footerGitHub: string;
  footerIssues: string;
  langSwitch: string;
  skipToContent: string;
};

const en: LandingCopy = {
  lang: 'en',
  htmlLang: 'en',
  metaTitle: 'Octoshot — macOS capture with 一酱',
  metaDescription:
    'Meet 一酱 (Yijiang), Octoshot’s deadpan red-octopus mascot: open-source macOS screenshots, scroll stitch, recording, GIF, and on-device AI—local-first, with a menu-bar butler who grumbles and delivers.',
  navFeatures: 'Features',
  navAgent: 'Agent',
  navFaq: 'FAQ',
  navDocs: 'Docs',
  navDownload: 'Download',
  heroEyebrow: 'macOS · MIT · local-first',
  heroTitle: 'More screenshots? …Fine. Eight arms, one pass.',
  heroLead:
    'I’m 一酱—Octoshot’s mascot and your menu-bar screenshot butler. Native capture for region, window, and full screen; scroll stitch, MP4, GIF, annotate, OCR/LaTeX, and pin—complaining the whole time, actually doing the work.',
  heroCta: 'Download latest release',
  heroSecondary: 'View on GitHub',
  heroFine: 'Requires macOS 14+. Screen Recording permission for capture.',
  mascotCard: {
    cardTitle: 'Character card',
    ariaLabel: 'About 一酱, Octoshot’s mascot',
    labelName: 'Name',
    name: '一酱 (Yijiang)',
    labelSpecies: 'Species',
    species: 'East Pacific red octopus (Octopus rubescens), cartoon edition',
    speciesFact:
      'Real-life O. rubescens are small, very curious, and can flush red in a blink. Same here: tiny, nosy, and if you poke me I go full red—then do the job anyway.',
    labelPersonality: 'Personality',
    personality: 'Low-energy, a little grumpy; reliable when it counts',
    labelCatchphrase: 'Catchphrase',
    catchphrase: '“I’ll do it. Stop hovering.”',
    labelRole: 'Role',
    role: 'Your menu-bar screenshot butler',
  },
  galleryTitle: 'Yeah, I made these too',
  galleryLead:
    'Desktop-style previews from the real Octoshot UI—same tool, less attitude in the pixels.',
  galleryQuips: {
    'capture-modebar': 'Pick a mode before I have to guess.',
    'quick-access-stack': 'Copy, save, annotate—don’t make me repeat myself.',
    annotate: 'Yes, you can draw on it. No, I won’t judge your arrows.',
    'settings-shortcuts': 'Steal ⌘⇧3/4/5 if you want. I’m not your mom.',
    ocr: 'Text and LaTeX—read it yourself later if you insist.',
  },
  galleryShotCapture: 'Unified capture mode bar',
  galleryShotQuickAccess: 'Quick Access stack',
  galleryShotAnnotate: 'Annotation editor',
  galleryShotSettings: 'Shortcuts settings',
  galleryShotOcr: 'OCR from capture',
  heroScreenshotAlt: 'Octoshot capture on macOS, presented by 一酱',
  tilesTitle: 'Eight arms, separate jobs',
  tilesLead: 'I whine; the tentacles multitask. Facts below—snark above.',
  tiles: [
    {
      quip: 'Region, window, full screen—stop re-launching three apps.',
      title: 'Unified capture',
      body: 'Screenshot, scroll stitch, MP4, GIF, LaTeX, and figure/table helpers from a single mode bar (S / R / V / G / L / T).',
      wide: true,
    },
    {
      quip: 'Thumbnail floats. Suggestions stay on your Mac.',
      title: 'Quick Access & pin',
      body: 'Floating thumbnail with copy, save, annotate, pin, and smart top-1 suggestions—processed on your machine.',
    },
    {
      quip: 'Optional brains in Application Support—not my problem if you skip them.',
      title: 'Embedded AI',
      body: 'Optional SmolVLM2 MLX and pix2tex downloads stay in Application Support; Ollama remains an optional fallback.',
    },
    {
      quip: 'Record the screen. I’ll hold the stop button.',
      title: 'Recording & GIF',
      body: 'ScreenCaptureKit region or full-screen capture with a floating stop panel, GIF export, and menu-bar indicator.',
    },
    {
      quip: 'One sidebar for shortcuts, AI, and your agent drama.',
      title: 'Settings that scale',
      body: 'Shortcuts, capture, recording, annotation, AI, and developer/agent panes in one SwiftUI sidebar.',
    },
  ],
  agentTitle: 'Built for agents, not just humans',
  agentLead:
    'Same capture stack, CLI, stdio MCP, and URL hooks—so Cursor, Claude Code, and Shortcuts can boss me around locally.',
  agentTerminal: [
    '$ octoshot capture --mode region --output ~/Desktop/shot.png',
    '$ octoshot mcp   # stdio MCP for IDE integrations',
    '$ open "octoshot://capture?mode=fullscreen"',
  ],
  agentTiles: [
    {
      title: 'Local only',
      body: 'No cloud upload by default. Permissions stay on your Mac.',
    },
    {
      title: 'OctoshotCore',
      body: 'Shared framework between the GUI app and automation entry points.',
    },
    {
      title: 'Open source',
      body: 'MIT licensed. Inspect, fork, and wire your own workflows.',
    },
  ],
  stepsTitle: 'Get started in minutes',
  steps: [
    {
      title: 'Install & grant access',
      body: 'Download the release, open once, and allow Screen Recording (and Accessibility if you use auto-scroll).',
    },
    {
      title: 'Set your shortcuts',
      body: 'Optionally take over ⌘⇧3/4/5 or define custom keys in Settings → Shortcuts.',
    },
    {
      title: 'Capture & automate',
      body: 'Use the menu bar or `octoshot` CLI; enable embedded models in Settings → AI when you need vision or LaTeX.',
    },
  ],
  faqTitle: 'Questions',
  faqs: [
    {
      q: 'Is Octoshot free?',
      a: 'Yes. Octoshot is MIT-licensed open source. Releases are published on GitHub.',
    },
    {
      q: 'Does it upload screenshots to the cloud?',
      a: 'No. Capture and optional on-device models run locally unless you explicitly configure an external endpoint.',
    },
    {
      q: 'Who is 一酱?',
      a: 'Octoshot’s original mascot—a deadpan red cartoon octopus inspired by our app icon. Personality: complains with words, delivers with all eight arms (“grumbles aloud, ships quietly”). Your menu-bar screenshot butler.',
    },
    {
      q: 'Where is the documentation?',
      a: 'Guides will mirror the in-app Help Markdown (EN + 中文). A docs section on this site will sync from the repo.',
    },
  ],
  finalTitle: 'Fine. Download it.',
  finalLead: 'Latest build, eight arms on call—I’ll pretend I’m not happy you came back.',
  finalCta: 'Download Octoshot',
  footerTagline: 'Octoshot · 一酱 — grumbles aloud, captures quietly.',
  footerDisclaimer: 'Not affiliated with Apple Inc. macOS is a trademark of Apple Inc.',
  footerGitHub: 'GitHub',
  footerIssues: 'Issues',
  langSwitch: '中文',
  skipToContent: 'Skip to content',
};

const zh: LandingCopy = {
  lang: 'zh',
  htmlLang: 'zh-CN',
  metaTitle: '一酱 Octoshot — macOS 原生截图与录制',
  metaDescription:
    '一酱是 Octoshot 的原创红章鱼 IP：嘴上嫌弃、手上靠谱的菜单栏截图管家。开源 macOS 截图、滚动拼接、录屏与 GIF，本机优先，统一模式条、嵌入式 AI 与 Agent CLI。',
  navFeatures: '功能',
  navAgent: 'Agent',
  navFaq: '常见问题',
  navDocs: '文档',
  navDownload: '下载',
  heroEyebrow: '菜单栏截图管家 · macOS · MIT',
  heroTitle: '又要截图？……行吧，八只手给你一次截完。',
  heroLead:
    '我是一酱，Octoshot 的吉祥物，也是你菜单栏里那个不爱说话但手很快的管家：区域/窗口/全屏、滚动拼接、录屏与 GIF、标注、OCR/LaTeX、钉住——嘴上嫌麻烦，手上照做。',
  heroCta: '下载最新版本',
  heroSecondary: '在 GitHub 查看',
  heroFine: '需要 macOS 14+。捕获需授予屏幕录制权限。',
  mascotCard: {
    cardTitle: '角色卡',
    ariaLabel: '关于一酱',
    labelName: '名字',
    name: '一酱',
    labelSpecies: '物种',
    species: '东太平洋红章鱼（Octopus rubescens），卡通版',
    speciesFact:
      '现实里的东太平洋红章鱼个头小、好奇心重，一激动就能瞬间红透。我也一样：个子小、爱凑热闹，被戳了就整只泛红——红完照样把活干完。',
    labelPersonality: '性格',
    personality: '低能量、略嫌弃；嘴上吐槽，手上靠谱',
    labelCatchphrase: '口头禅',
    catchphrase: '「行了行了，我截。」',
    labelRole: '职责',
    role: '你的菜单栏截图管家',
  },
  galleryTitle: '界面预览',
  galleryLead: '桌面风营销图，来自真实 Octoshot 界面；我负责吐槽，像素负责老实。',
  galleryQuips: {
    'capture-modebar': '模式条在这，别让我猜你要截哪。',
    'quick-access-stack': '复制、保存、标注——别让我念第三遍。',
    annotate: '可以画箭头，我不评价审美。',
    'settings-shortcuts': '想接管 ⌘⇧3/4/5 就接管，我不拦。',
    ocr: '字和公式我认，认完你自己看。',
  },
  galleryShotCapture: '统一捕获模式条',
  galleryShotQuickAccess: '快速访问浮层',
  galleryShotAnnotate: '标注编辑器',
  galleryShotSettings: '快捷键设置',
  galleryShotOcr: 'OCR 识别',
  heroScreenshotAlt: '一酱展示的 Octoshot macOS 捕获界面',
  tilesTitle: '八只手，各干各的',
  tilesLead: '上面一句嫌弃，下面一句人话。',
  tiles: [
    {
      quip: '区域、窗口、全屏别来回换 App 了。',
      title: '统一捕获',
      body: '同一模式条支持截图、滚动拼接、MP4、GIF、LaTeX 与图/表助手（S / R / V / G / L / T）。',
      wide: true,
    },
    {
      quip: '缩略图飘着；建议留在本机。',
      title: '快速访问与钉住',
      body: '浮动缩略图：复制、保存、标注、钉住与本机智能建议（需点 Apply）。',
    },
    {
      quip: '模型下在 Application Support，不用别怪我慢。',
      title: '嵌入式 AI',
      body: '可选下载 SmolVLM2 MLX 与 pix2tex 至 Application Support；Ollama 为可选回退。',
    },
    {
      quip: '录屏我按着停止键，你别慌。',
      title: '录制与 GIF',
      body: 'ScreenCaptureKit 区域或全屏录制，浮动停止面板、GIF 导出与菜单栏指示。',
    },
    {
      quip: '快捷键、AI、Agent 设置都在侧栏，别东一块西一块。',
      title: '完整设置',
      body: '快捷键、捕获、录制、标注、AI 与开发者/Agent 面板，集中在 SwiftUI 侧栏。',
    },
  ],
  agentTitle: '为人也为 Agent 设计',
  agentLead:
    '同一套捕获能力提供 CLI、stdio MCP 与 URL——Cursor、Claude Code 和快捷指令可以在本机使唤我。',
  agentTerminal: [
    '$ octoshot capture --mode region --output ~/Desktop/shot.png',
    '$ octoshot mcp   # stdio MCP，供 IDE 集成',
    '$ open "octoshot://capture?mode=fullscreen"',
  ],
  agentTiles: [
    { title: '默认本机', body: '不上传云端；权限留在你的 Mac。' },
    { title: 'OctoshotCore', body: 'GUI 与自动化入口共享同一框架。' },
    { title: '开源', body: 'MIT 许可，可审查、分叉并接入自己的工作流。' },
  ],
  stepsTitle: '几分钟上手',
  steps: [
    {
      title: '安装与授权',
      body: '下载发行版，首次打开并允许屏幕录制（自动滚动需辅助功能）。',
    },
    {
      title: '设置快捷键',
      body: '可在设置中接管 ⌘⇧3/4/5 或自定义快捷键。',
    },
    {
      title: '捕获与自动化',
      body: '使用菜单栏或 `octoshot` CLI；需要视觉/LaTeX 时在设置 → AI 启用嵌入式模型。',
    },
  ],
  faqTitle: '常见问题',
  faqs: [
    { q: '一酱免费吗？', a: '是。MIT 开源，发行版在 GitHub 发布。' },
    { q: '会上传截图到云端吗？', a: '不会。捕获与可选本机模型均在本地运行，除非你自行配置外部接口。' },
    {
      q: '一酱是谁？',
      a: 'Octoshot 的原创吉祥物——一只低能量、略嫌弃的红色卡通章鱼，造型来自应用图标。人设是「嘴上嫌弃、手上靠谱」：吐槽归吐槽，八只手同时干区域/窗口/全屏捕获、标注、滚动截屏、录屏/GIF、OCR/LaTeX、钉住等活。你的菜单栏截图管家。',
    },
    { q: '文档在哪里？', a: '将与应用内帮助 Markdown（中英）同步；本站文档区将随仓库更新。' },
  ],
  finalTitle: '行，下吧。',
  finalLead: '最新构建在这；八只手随叫随到——我当没看见你又回来了。',
  finalCta: '下载一酱',
  footerTagline: 'Octoshot · 一酱 — 嘴上嫌弃，手上靠谱。',
  footerDisclaimer: '与 Apple Inc. 无关联。macOS 为 Apple Inc. 商标。',
  footerGitHub: 'GitHub',
  footerIssues: 'Issues',
  langSwitch: 'English',
  skipToContent: '跳到正文',
};

export function getCopy(locale: Locale): LandingCopy {
  return locale === 'zh' ? zh : en;
}

export const RELEASE_URL = 'https://github.com/neardws/Octoshot/releases/latest';
export const REPO_URL = 'https://github.com/neardws/Octoshot';
export const ISSUES_URL = 'https://github.com/neardws/Octoshot/issues';
