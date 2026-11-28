import Foundation

/// Suggests a category for a payment from well-known (mostly Dutch) shops and companies.
/// A rule only applies when one of your categories matches its names (e.g. "Groceries" or "Boodschappen").
enum AutoCategory {
    struct Rule {
        /// Words that a matching category name contains.
        let categoryNames: [String]
        /// Shop or company names, matched as whole words (multi-word names allowed).
        let keywords: [String]
        /// Matched anywhere in the raw text (for names with symbols, like "h&m").
        var rawKeywords: [String] = []
    }

    static let rules: [Rule] = [
        Rule(categoryNames: ["subscription", "abonnement", "streaming"],
             keywords: ["netflix", "spotify", "disney", "videoland", "hbo", "apple com bill", "youtube premium",
                        "amazon prime", "icloud", "audible", "storytel", "nlziet", "viaplay"]),
        Rule(categoryNames: ["insurance", "verzeker"],
             keywords: ["verzekering", "verzekeringen", "insurance", "centraal beheer", "interpolis",
                        "nationale nederlanden", "ohra", "fbto", "zilveren kruis", "vgz", "menzis", "ditzo",
                        "unive", "allianz", "aegon", "inshared", "promovendum"]),
        Rule(categoryNames: ["utilit", "energy", "energie", "housing", "wonen", "home", "house"],
             keywords: ["eneco", "vattenfall", "essent", "greenchoice", "budget energie", "unitedconsumers",
                        "vandebron", "energiedirect", "oxxio", "engie", "vitens", "evides", "dunea", "pwn",
                        "brabant water", "waternet", "hypotheek", "hypotheken", "huur", "woonstichting"]),
        Rule(categoryNames: ["phone", "telecom", "internet", "mobile", "utilit", "housing"],
             keywords: ["kpn", "odido", "vodafone", "ziggo", "delta fiber", "tele", "simyo", "lebara",
                        "youfone", "hollandsnieuwe", "lycamobile"]),
        Rule(categoryNames: ["tax", "belasting"],
             keywords: ["belastingdienst", "bghu", "belastingen", "waterschap", "cjib"]),
        Rule(categoryNames: ["groceries", "grocery", "boodschappen", "supermar", "food"],
             keywords: ["albert heijn", "ah", "jumbo", "lidl", "aldi", "plus", "dirk", "coop", "spar", "vomar",
                        "hoogvliet", "dekamarkt", "deka", "poiesz", "nettorama", "ekoplaza", "picnic", "crisp",
                        "flink", "marqt", "odin", "jan linders", "boni", "troef", "makro", "sligro", "amazing oriental",
                        "slagerij", "bakkerij", "bakker", "groenteboer", "kaashandel"]),
        Rule(categoryNames: ["dining", "restaurant", "uit eten", "eating out", "food & drink", "horeca", "takeaway"],
             keywords: ["thuisbezorgd", "takeaway", "uber eats", "deliveroo", "mcdonalds", "mcdonald",
                        "burger king", "kfc", "subway", "dominos", "domino", "new york pizza", "starbucks", "febo",
                        "restaurant", "cafe", "eetcafe", "brasserie", "bistro", "pizzeria", "sushi", "snackbar",
                        "lunchroom", "coffee", "koffie", "bagels", "smullers", "la place", "vapiano", "wok"]),
        Rule(categoryNames: ["transport", "vervoer", "travel", "reizen", "car", "auto", "fuel", "brandstof"],
             keywords: ["ns", "ns groep", "gvb", "ret", "htm", "arriva", "connexxion", "qbuzz", "keolis", "ebs",
                        "ov chipkaart", "translink", "shell", "bp", "esso", "totalenergies", "total", "tango",
                        "tinq", "texaco", "gulf", "argos", "avia", "uber", "bolt", "swapfiets", "greenwheels",
                        "park", "parkmobile", "yellowbrick", "parkeren", "anwb", "tankstation", "fastned",
                        "ionity", "tesla supercharger", "allego", "vattenfall incharge"],
             rawKeywords: ["q-park", "q8"]),
        Rule(categoryNames: ["clothing", "clothes", "kleding", "fashion"],
             keywords: ["zara", "primark", "uniqlo", "zalando", "about you", "nike", "adidas", "jd sports",
                        "foot locker", "we fashion", "jack jones", "scotch soda", "pull bear", "bershka",
                        "mango", "hunkemoller", "sting", "costes", "america today", "van haren",
                        "omoda", "shoeby", "esprit", "tommy hilfiger", "levi"],
             rawKeywords: ["h&m", "h & m", "c&a", "c & a"]),
        Rule(categoryNames: ["health", "zorg", "gezond", "personal care", "verzorging", "drogist", "pharmacy"],
             keywords: ["kruidvat", "etos", "trekpleister", "apotheek", "da drogist", "holland barrett", "boots",
                        "huisarts", "tandarts", "fysiotherapie", "douglas", "ici paris"]),
        Rule(categoryNames: ["household", "huishoud", "home", "wonen", "housing"],
             keywords: ["action", "hema", "ikea", "gamma", "praxis", "karwei", "hornbach", "blokker", "kwantum",
                        "xenos", "leen bakker", "jysk", "intratuin", "coolblue", "mediamarkt", "bol com"]),
        Rule(categoryNames: ["leisure", "vrije tijd", "entertainment", "fun", "hobby", "uitjes"],
             keywords: ["pathe", "vue", "kinepolis", "steam", "playstation", "nintendo", "xbox", "museum",
                        "bioscoop", "efteling", "ticketmaster", "eventim", "paylogic", "bowling", "sauna",
                        "thermen", "dierentuin", "escape"]),
        Rule(categoryNames: ["sport", "gym", "fitness"],
             keywords: ["basic fit", "basicfit", "sportcity", "fit for free", "anytime fitness", "trainmore",
                        "sportcentrum", "decathlon", "intersport"]),
    ]

    /// The best matching category for a payment, or nil. Your own rules go first.
    static func suggest(for text: String, in categories: [BudgetCategory],
                        rules userRules: [CategoryRule] = []) -> BudgetCategory? {
        let lowerText = text.lowercased()
        let words = " " + MerchantKey.tokens(text).joined(separator: " ") + " "

        for rule in userRules.sorted(by: { $0.pattern.count > $1.pattern.count }) {
            guard !rule.pattern.isEmpty, let category = rule.category else { continue }
            if lowerText.contains(rule.pattern) || words.contains(" " + rule.pattern + " ") {
                return category
            }
        }

        for rule in rules {
            let matchesWord = rule.keywords.contains { words.contains(" " + $0 + " ") }
            let matchesRaw = rule.rawKeywords.contains { lowerText.contains($0) }
            guard matchesWord || matchesRaw else { continue }
            if let category = categories.first(where: { category in
                let name = category.name.lowercased()
                return rule.categoryNames.contains { name.contains($0) }
            }) {
                return category
            }
        }
        return nil
    }
}
