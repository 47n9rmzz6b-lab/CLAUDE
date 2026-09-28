import Foundation

/// Estimation du nombre de jetons, sans tokeniseur : de l’ordre de 3,5 caractères par jeton
/// en français comme en anglais. Suffisant pour une jauge et un avertissement.
enum TokenEstimator {
    static let tokensPerImage = 768
    static let tokensPerMessage = 4

    static func tokens(in text: String) -> Int {
        tokens(forCharacterCount: text.unicodeScalars.count)
    }

    static func tokens(forCharacterCount count: Int) -> Int {
        count > 0 ? Int((Double(count) / 3.5).rounded(.up)) : 0
    }
}

/// Façon dont la recherche web est proposée au modèle.
enum WebSearchMode: Equatable {
    case none
    /// Le modèle appelle lui-même les outils web_search et web_fetch.
    case tools
    /// Modèle sans outils : l’app cherche d’abord et joint les résultats à la question.
    case preSearch
}

/// Éléments qui composent le prompt système d’une conversation.
struct PromptContext {
    var profile: ResponseProfile
    var aboutMe = ""
    var responseStyle = ""
    var memories: [String] = []
    var webSearch: WebSearchMode = .none
    var documentNames: [String] = []
    var now = Date()
}

enum PromptBuilder {
    /// Prompt système, ou `nil` s’il n’y a rien à dire : on laisse alors au modèle
    /// ses propres instructions par défaut.
    static func systemPrompt(_ context: PromptContext) -> String? {
        var sections: [String] = []

        let profile = context.profile.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty { sections.append(profile) }

        let aboutMe = context.aboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
        if !aboutMe.isEmpty {
            sections.append("""
            L’utilisateur se présente ainsi (quand il écrit « je », il parle de lui, pas de toi) :
            « \(aboutMe) »
            """)
        }

        let style = context.responseStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !style.isEmpty {
            sections.append("Préférences de l’utilisateur pour tes réponses :\n\(style)")
        }

        if !context.memories.isEmpty {
            let list = context.memories.map { "- \($0)" }.joined(separator: "\n")
            sections.append("Ce que tu sais déjà de l’utilisateur, retenu lors de conversations précédentes :\n\(list)")
        }

        switch context.webSearch {
        case .tools:
            sections.append("""
            Tu peux chercher sur Internet avec l’outil web_search et lire une page avec l’outil web_fetch. \
            Dès que la question porte sur l’actualité, des faits récents ou des données à vérifier \
            (météo, prix, dates, chiffres, personnes), appelle web_search avant de répondre, sans demander la permission. \
            Appuie ta réponse sur les résultats obtenus et cite-les avec leur numéro entre crochets, par exemple [1] ou [2].
            """)
        case .preSearch:
            sections.append("""
            Des résultats de recherche sur Internet accompagnent la question de l’utilisateur. \
            Appuie ta réponse sur ces résultats et cite-les avec leur numéro entre crochets, par exemple [1].
            """)
        case .none:
            break
        }

        if !context.documentNames.isEmpty {
            let names = context.documentNames.map { "« \($0) »" }.joined(separator: ", ")
            sections.append("""
            L’utilisateur a joint des documents : \(names). Les extraits utiles accompagnent sa question. \
            Appuie-toi sur eux, cite-les avec leur repère entre crochets, par exemple [D1], \
            et dis clairement quand l’information demandée n’y figure pas.
            """)
        }

        guard !sections.isEmpty else { return nil }
        sections.insert("Date du jour : \(dateText(context.now)).", at: 0)
        return sections.joined(separator: "\n\n")
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Demande envoyée par le bouton « Vérifier ».
    static let verificationRequest = """
    Relis attentivement ta réponse précédente. Vérifie les faits, les chiffres, les calculs et le raisonnement. \
    Liste les erreurs, les imprécisions ou les affirmations incertaines que tu y trouves, \
    puis donne une version corrigée si c’est nécessaire. Si tout est exact, dis-le simplement.
    """
}
