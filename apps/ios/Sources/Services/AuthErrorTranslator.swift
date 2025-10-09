import Foundation

enum AuthErrorTranslator {
    /// Translate common Supabase/Auth-related error messages into safe Japanese messages.
    static func message(for raw: String) -> String {
        let lower = raw.lowercased()
        // 資格情報不一致（存在しないユーザー/パスワード誤りを含む）
        if lower.contains("invalid login") || lower.contains("invalid credentials") || lower.contains("user not found") {
            return "メールアドレスまたはパスワードが正しくありません。"
        }
        // メール未確認
        if lower.contains("not confirmed") || lower.contains("email not confirmed") || lower.contains("confirm your email") {
            return "メール確認が未完了です。受信メールのリンクから確認を完了してください。"
        }
        // リセット関連
        if lower.contains("auth session missing") || lower.contains("session missing") {
            return "認証セッションが見つかりません。メールのリンクをもう一度開いてから、再度お試しください。"
        }
        if lower.contains("invalid token") || lower.contains("token is expired") || lower.contains("expired token") {
            return "リンクが無効または期限切れです。もう一度手続きをやり直してください。"
        }
        // パスワード強度/同一
        if lower.contains("new password should be different") || lower.contains("different from the old password") {
            return "新しいパスワードは以前と異なる必要があります。別のパスワードを入力してください。"
        }
        if lower.contains("weak password") || lower.contains("password should be") {
            return "パスワードが要件を満たしていません。英数字を組み合わせた十分に強いパスワードを入力してください。"
        }
        // レート制限
        if lower.contains("too many requests") || lower.contains("once every") || lower.contains("rate limit") {
            return "短時間に複数回リクエストされました。しばらく待ってからもう一度お試しください。"
        }
        // ネットワーク系（簡易）
        if lower.contains("timed out") || lower.contains("offline") || lower.contains("could not connect") {
            return "ネットワークに接続できません。通信状況を確認してから再度お試しください。"
        }
        // 既定：元の文言
        return raw
    }
}

