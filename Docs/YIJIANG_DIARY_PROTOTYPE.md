# 一酱日记 — M0 离线原型

> 关联 Issue：[#67 一酱日记：本地隐私优先的每日活动日记](https://github.com/neardws/Octoshot/issues/67)  
> **不合并、不发布** — 仅用于评估本机 SmolVLM2 摘要质量。

## 输入格式

文件夹内包含带时间戳的 PNG（可选 `.meta.json` 侧车）：

| 文件 | 说明 |
|------|------|
| `2025-10-17T09-05-00+0800_Xcode.png` | 从文件名解析时间与前台应用 |
| `2025-10-17T09-05-00+0800.meta.json` | 可选：`timestamp`、`frontmostApp`、`accessibilityText` |

原型管线：**Accessibility 文本（侧车）优先** → Apple Vision OCR 回退 → 关键帧选择 → 每个 ~10 分钟窗口对代表关键帧做 VLM 摘要 → 生成「一酱今日吐槽日报」Markdown。

合成样本（无个人数据）：`Scripts/yijiang-diary-prototype/samples/`

## 构建

```bash
xcodegen generate --spec project.yml   # 或 CI: bash Scripts/ci-xcodegen.sh
xcodebuild -scheme octoshot-cli -configuration Debug build
```

CLI 产物：`build/Debug/octoshot` 或 DerivedData 中的 `octoshot`。

## 本机评测（Neil — Apple Silicon）

1. 在 Octoshot **设置 → AI** 下载 **SmolVLM2**（~292 MB）。
2. 使用完整 MLX 工程（非 CI stub）：`xcodegen generate --spec project.yml`。
3. **Stub 管线**（无模型，验证组装与速度）：

```bash
./build/Debug/octoshot yijiang-diary-prototype --developer \
  --input "$PWD/Scripts/yijiang-diary-prototype/samples" \
  --output /tmp/yijiang-digest-stub.md \
  --captioner stub
```

4. **真实 SmolVLM2 评测**：

```bash
/usr/bin/time -l ./build/Debug/octoshot yijiang-diary-prototype --developer \
  --input "$PWD/Scripts/yijiang-diary-prototype/samples" \
  --output /tmp/yijiang-digest-smolvlm.md \
  --captioner smolvlm \
  --window-minutes 10
```

### 建议关注的指标

| 指标 | 如何看 |
|------|--------|
| **延迟** | `time` 输出的 wall clock；CLI JSON 里的 `elapsedSeconds` |
| **内存** | `time -l` 的 `maximum resident set size`（bytes） |
| **可读性** | 打开 `/tmp/yijiang-digest-smolvlm.md`，看 ~10 分钟卡片与「一酱总结」是否准确、是否胡编 |
| **关键帧数量** | CLI JSON 的 `keyframes` vs `frames` — 过高可能浪费推理，过低可能漏上下文 |

CI 使用 `--captioner stub`；`OctoshotCoreTests` 覆盖关键帧、分窗与日报组装，**不下载模型权重**。

## 重新生成合成样本

```bash
python3 Scripts/yijiang-diary-prototype/generate_samples.py
```

## 后续（Issue 里程碑）

- M1：ScreenCaptureKit 事件采集  
- M3：`octoshot` MCP `get_timeline` / `search_activity`  
- 「Send to Codex」：`codex -i <image>`
