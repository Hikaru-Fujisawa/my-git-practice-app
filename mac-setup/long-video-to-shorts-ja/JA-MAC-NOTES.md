# 日本語・macOS向けの変更点（upstream からの差分）

Upstream: https://github.com/joe-jns/long-video-to-shorts @ 61bd65f29b3e2a8b1062d6f0da4042451d796965 (MIT)

| ファイル | 変更 | 理由 |
|---|---|---|
| `scripts/ja_text.cjs` | 新規 | 日本語の単語再分割（Node内蔵 `Intl.Segmenter`）、スペースなし結合、全角=1emの幅計算 |
| `scripts/ass_from_words.cjs` | 日本語時のみ幅ベース改行・文節境界優先・はみ出し時縮小 | Whisperの日本語は「マ/レ/ー」と細切れ、元の実装は単語間にスペースを入れ、16文字固定で画面からはみ出す |
| `scripts/hook_ass.cjs` | 日本語タイトルの折り返し・自動縮小、強調語の判定修正 | 元はスペース区切りのみで折り返し、`\b` が日本語にマッチせず強調色が付かない |
| `scripts/probe.sh` | 動画全体から60コマを抽出、`-update 1` | `tile=6x0` が多くのffmpegで失敗し、先頭60秒しか見られなかった |
| `scripts/transcribe.py` | 既定言語 `fr` → `ja` | 日本語動画用 |
| `scripts/hook_title.sh` | フォントを元のファイル名でコピー | OTFフォントを `font.ttf` に改名しない |
| `scripts/lvs.sh` | 新規 | `local.env`（専用venv・ffmpeg/nodeの場所・モデル保存先）を読んで実行。システムのPATH/Python/Nodeは変更しない |
| `config.json` | フォントを Noto Sans JP Bold に | DejaVu Sans には日本語グリフがない |
| `SKILL.md` | 日本語・承認ゲート・投稿禁止・`lvs.sh` 経由・顔出しも `--caption-mode ass` | `embedded-captions` スキルは未導入のため |
| `requirements.txt` | `faster-whisper==1.2.1`, `av<16` | PyAV 16 以降で faster-whisper 1.2.1 が起動しない |

英語など日本語を含まない字幕・タイトルの出力は upstream とバイト単位で同一（検証済み）。
同梱の設定スキル `long-video-to-shorts-config/` は導入していない（フォントのDLを伴うため。必要なら手動で）。
