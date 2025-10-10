# Commit message convention (categories required)

Use a leading category to indicate what part changed.

Format:

```
<Category>: <short summary>

<optional body>
```

Categories (prefix examples):
- iOS: changes under `apps/ios/**`
- API: changes under `apps/api-worker/**`（Workers）
- Web: changes under `apps/web/**`
- DB: schema/migrations under `db/**` or `supabase/**`
- Docs: documentation under `docs/**` or README
- CI: GitHub Actions/workflow/build settings

Examples:
- `iOS: 緊急モードのSOSアニメーションを追加`
- `API: 受信者検証完了でPush通知を送信`
- `Web: /auth/confirm でフラグメントを next に連結`
- `Docs: 仕様補遺にサインアップ後の挙動を追記`

Notes:
- Scope が複数にまたがる場合は `iOS/API:` のようにスラッシュで併記可。
- 英語/日本語どちらでも可ですが、先頭のカテゴリは必須です。

