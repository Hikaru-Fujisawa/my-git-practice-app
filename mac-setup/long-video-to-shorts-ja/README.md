# long-video-to-shorts（日本語・Mac向け）導入キット

[joe-jns/long-video-to-shorts](https://github.com/joe-jns/long-video-to-shorts) を、追加費用なし・ローカル処理だけで
日本語動画に使えるよう調整した Claude Code スキルのインストーラです。変更点は `JA-MAC-NOTES.md`。

## 前提（Mac）
- `/Users/fujisawaakira/Documents/Codex/tools/free-dev/python-env/bin/python`（Python 3.9+）
- libass 付き ffmpeg / ffprobe、Node.js 18+（見つからなければインストーラが止まって案内します）
- git, curl（macOS標準）

## 手順
```bash
bash mac-setup/long-video-to-shorts-ja/install.sh --check   # 何も書き込まずに確認だけ
bash mac-setup/long-video-to-shorts-ja/install.sh           # 導入
bash mac-setup/long-video-to-shorts-ja/selftest.sh          # 日本語音声で2本書き出して検証
```

導入先:
- スキル: `~/.claude/skills/long-video-to-shorts/`（既にあれば中止。上書きしません）
- Python依存: `free-dev/venvs/long-video-to-shorts/`（専用venv）
- Whisperモデル: `free-dev/cache/huggingface/`（初回 small ≈ 480MB を無料DL）

## 使い方（Claude Code で）
> ~/Movies/talk.mp4 からショート動画の候補を出して

→ 候補表が出る →「1と3で」→ `~/shorts-jobs/<名前>/shorts/*.mp4`（1080×1920・字幕付き）
SNSへの投稿・公開は一切しません。
