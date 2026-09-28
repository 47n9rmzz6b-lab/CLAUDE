import Foundation

/// Profil de réponse choisi pour une conversation : consignes données au modèle et température.
struct ResponseProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: String
    let summary: String
    let instructions: String
    /// `nil` : température par défaut du modèle.
    let temperature: Double?

    static let balanced = ResponseProfile(
        id: "balanced",
        name: "Équilibré",
        icon: "circle.lefthalf.filled",
        summary: "Réglages par défaut du modèle.",
        instructions: "",
        temperature: nil
    )

    static let rigorous = ResponseProfile(
        id: "rigorous",
        name: "Rigoureux",
        icon: "checkmark.seal",
        summary: "Précis, prudent, distingue faits et suppositions.",
        instructions: """
        Réponds avec rigueur et précision. Distingue clairement les faits établis de tes suppositions. \
        Si tu n’es pas sûr ou si tu ne sais pas, dis-le explicitement plutôt que d’inventer. \
        N’invente jamais de chiffres, de citations, de références ni de sources. \
        Pour les questions complexes, raisonne étape par étape et vérifie tes calculs avant de conclure.
        """,
        temperature: 0.3
    )

    static let code = ResponseProfile(
        id: "code",
        name: "Code",
        icon: "chevron.left.forwardslash.chevron.right",
        summary: "Code complet et commenté, cas limites signalés.",
        instructions: """
        Tu es un assistant de programmation expérimenté. Donne du code complet et fonctionnel, \
        dans des blocs de code qui indiquent le langage. Explique brièvement tes choix, \
        signale les cas limites, les risques et les dépendances nécessaires.
        """,
        temperature: 0.2
    )

    static let creative = ResponseProfile(
        id: "creative",
        name: "Créatif",
        icon: "paintpalette",
        summary: "Idées originales, style imagé.",
        instructions: """
        Sois créatif, imagé et original. Quand c’est pertinent, propose plusieurs pistes \
        différentes plutôt qu’une seule.
        """,
        temperature: 1.0
    )

    static let concise = ResponseProfile(
        id: "concise",
        name: "Concis",
        icon: "text.alignleft",
        summary: "Réponses courtes, sans détour.",
        instructions: "Réponds de la façon la plus brève possible, sans préambule ni conclusion.",
        temperature: nil
    )

    static let all: [ResponseProfile] = [balanced, rigorous, code, creative, concise]

    static func profile(id: String) -> ResponseProfile {
        all.first { $0.id == id } ?? balanced
    }
}
