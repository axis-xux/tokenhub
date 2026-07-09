# TokenHub

macOSのメニューバーから、**Claude Code**と**Codex CLI**のレート制限使用状況をまとめて確認できるアプリです。

- Claude.ai: 5時間制限・7日間制限の残り%とリセット時刻
- Codex CLI: 5時間制限・週間制限の残り%とリセット時刻
- メニューバーのラベルに表示する指標は4種類から選択可能
- 背景色・不透明度をカスタマイズ可能

## スクリーンショット

メニューバーのアイコンをクリックすると、Claude.aiとCodex CLIそれぞれの使用状況がカード形式で表示されます。

## 仕組み（正直な説明）

このアプリは公式APIではなく、以下の方法でデータを取得しています。挙動が今後変わる可能性があることをご了承ください。

- **Claude.ai**: システム共有のWebKitデータストア（Safariのログイン状態）を使い、`https://claude.ai`の内部usage APIをWKWebView経由でポーリングします。ナビゲーションはclaude.aiドメインのみに制限しています。外部への送信は一切ありません。
- **Codex CLI**: `~/.codex/sessions/`配下のセッションログ（JSONL）に、ターン完了後の実際のレート制限スナップショットがそのまま記録されているため、それをローカルで読むだけです。ネットワーク通信は発生しません。

このアプリ自体はテレメトリを送信せず、認証情報も保存しません（claude.aiのログイン状態はmacOSの共有Cookieストアに委ねています）。

## インストール

コード署名・公証をしていない自前ビルドのため、Gatekeeperの警告が出ます。ソースからビルドして使ってください。

```bash
git clone <このリポジトリ>
cd tokenhub
./build.sh
cp -r TokenHub.app /Applications/
open /Applications/TokenHub.app
```

初回起動時にGatekeeperにブロックされた場合は、`システム設定 → プライバシーとセキュリティ`から許可するか、以下を実行してください。

```bash
xattr -d com.apple.quarantine /Applications/TokenHub.app
```

## 設定

メニューの歯車アイコンから以下を設定できます。

- メニューバー表示: Claude/Codexのどの指標を表示するか
- 背景色・不透明度
- 更新間隔（秒）

claude.aiにログインしていない場合は、メニューの人アイコンからログインしてください。

## 注意事項

- Anthropic/OpenAIの公式ツールではなく、非公式の個人プロジェクトです
- claude.aiの内部API仕様が変わると動作しなくなる可能性があります
- 自己責任でご利用ください

## License

MIT
