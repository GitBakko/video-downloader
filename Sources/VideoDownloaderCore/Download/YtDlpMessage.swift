import Foundation

/// Rewrites yt-dlp's two most misleading stderr lines into something actionable.
///
/// Both are actively harmful on X. An age-gated post reports "No video could be
/// found in this tweet" — the media is there, X just hides it from logged-out
/// visitors, and nothing in that sentence hints that the cookies setting exists.
/// Conversely, expired cookies report "Could not authenticate you" plus yt-dlp's
/// "please report this issue" boilerplate, which sends the user off to file a bug
/// about their own stale session.
///
/// ponytail: substring match on two strings, no host parsing — "in this tweet"
/// can only come from the Twitter extractor. Generalise when a third site needs it.
enum YtDlpMessage {
    static func explain(_ line: String) -> String {
        if line.contains("Could not authenticate you") {
            return "L’accesso a X non è più valido: rifai il login nel browser scelto in Impostazioni, "
                 + "oppure scegli “Nessuno” per tornare alle richieste anonime."
        }
        if line.contains("No video could be found in this tweet") {
            return "Questo post richiede l’accesso a X (contenuto sensibile o protetto): "
                 + "in Impostazioni scegli un browser in cui hai già fatto il login."
        }
        return line
    }
}
