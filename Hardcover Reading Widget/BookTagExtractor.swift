import Foundation

// MARK: - Book Tag Extraction Utilities
// Separated from SearchBooksView for better organization and reusability

struct BookTagExtractor {
    
    // MARK: - Genre Extraction
    
    static func extractGenres(_ value: Any?) -> [String]? {
        guard let value else { return nil }
        
        func isGenreContext(_ v: Any?) -> Bool {
            guard let s = (v as? String)?.lowercased() else { return false }
            return s == "genre" || s == "genres"
        }
        
        func nameFrom(_ dict: [String: Any]) -> String? {
            for key in ["name", "label", "title", "tag"] {
                if let s = dict[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
            return nil
        }
        
        // 1) Already an array of strings
        if let arr = value as? [String] {
            return arr
        }
        
        // 2) Array of mixed items
        if let arrAny = value as? [Any] {
            var out: [String] = []
            for el in arrAny {
                if let s = el as? String { 
                    out.append(s)
                    continue 
                }
                if let d = el as? [String: Any] {
                    if isGenreContext(d["context"]) || isGenreContext(d["type"]) || 
                       isGenreContext(d["kind"]) || isGenreContext(d["category"]) || 
                       isGenreContext(d["group"]) {
                        if let n = nameFrom(d) { out.append(n) }
                        continue
                    }
                    if let t = d["tag"] as? [String: Any] {
                        if isGenreContext(t["context"]) || isGenreContext(t["type"]) || 
                           isGenreContext(t["kind"]) || isGenreContext(t["category"]) || 
                           isGenreContext(t["group"]) {
                            if let n = nameFrom(t) { out.append(n) }
                            continue
                        }
                    }
                }
            }
            return out.isEmpty ? nil : out
        }
        
        // 3) Dictionary shapes
        if let dict = value as? [String: Any] {
            // 3a) Uppercase bucket sometimes seen in curated payloads
            if let gAny = dict["Genre"] as? [Any] {
                var out: [String] = []
                for el in gAny {
                    if let s = el as? String {
                        out.append(s)
                    } else if let d = el as? [String: Any] {
                        if let cat = (d["categorySlug"] as? String)?.lowercased(), cat == "genre",
                           let tag = d["tag"] as? String, !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            out.append(tag)
                        } else if let tag = d["tag"] as? String, !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            out.append(tag)
                        }
                    }
                }
                if !out.isEmpty { return out }
            }
            
            // 3b) Lowercase "genres" bucket or similar
            if let g = dict["genres"] {
                if let arr = g as? [String] { return arr }
                if let arrAny = g as? [Any] {
                    var out: [String] = []
                    for el in arrAny {
                        if let s = el as? String { 
                            out.append(s)
                            continue 
                        }
                        if let d = el as? [String: Any] {
                            if let n = nameFrom(d) { 
                                out.append(n)
                                continue 
                            }
                            if let t = d["tag"] as? [String: Any], let n = nameFrom(t) { 
                                out.append(n)
                                continue 
                            }
                        }
                    }
                    return out.isEmpty ? nil : out
                }
            }
            
            // 3c) Generic "tags" bucket with genre context
            if let tags = dict["tags"] as? [Any] {
                var out: [String] = []
                for el in tags {
                    if let d = el as? [String: Any] {
                        if isGenreContext(d["context"]) || isGenreContext(d["type"]) || 
                           isGenreContext(d["kind"]) || isGenreContext(d["category"]) || 
                           isGenreContext(d["group"]) {
                            if let n = nameFrom(d) { out.append(n) }
                            continue
                        }
                        if let t = d["tag"] as? [String: Any] {
                            if isGenreContext(t["context"]) || isGenreContext(t["type"]) || 
                               isGenreContext(t["kind"]) || isGenreContext(t["category"]) || 
                               isGenreContext(t["group"]) {
                                if let n = nameFrom(t) { out.append(n) }
                                continue
                            }
                        }
                    }
                }
                return out.isEmpty ? nil : out
            }
        }
        return nil
    }
    
    static func extractGenres(fromCachedTags value: Any?) -> [String]? {
        extractGenres(value)
    }
    
    // MARK: - Mood Extraction
    
    static func extractMoods(_ value: Any?) -> [String]? {
        guard let value else { return nil }
        
        func isMoodContext(_ v: Any?) -> Bool {
            guard let s = (v as? String)?.lowercased() else { return false }
            return s == "mood" || s == "moods"
        }
        
        func nameFrom(_ dict: [String: Any]) -> String? {
            for key in ["name", "label", "title", "tag"] {
                if let s = dict[key] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
            }
            return nil
        }
        
        if let arr = value as? [String] {
            return arr
        }
        
        if let arrAny = value as? [Any] {
            var out: [String] = []
            for el in arrAny {
                if let s = el as? String { 
                    out.append(s)
                    continue 
                }
                if let d = el as? [String: Any] {
                    if isMoodContext(d["context"]) || isMoodContext(d["type"]) || 
                       isMoodContext(d["kind"]) || isMoodContext(d["category"]) || 
                       isMoodContext(d["group"]) {
                        if let n = nameFrom(d) { out.append(n) }
                        continue
                    }
                    if let t = d["tag"] as? [String: Any] {
                        if isMoodContext(t["context"]) || isMoodContext(t["type"]) || 
                           isMoodContext(t["kind"]) || isMoodContext(t["category"]) || 
                           isMoodContext(t["group"]) {
                            if let n = nameFrom(t) { out.append(n) }
                            continue
                        }
                    }
                }
            }
            return out.isEmpty ? nil : out
        }
        
        if let dict = value as? [String: Any] {
            if let m = dict["moods"] {
                if let arr = m as? [String] { return arr }
                if let arrAny = m as? [Any] {
                    var out: [String] = []
                    for el in arrAny {
                        if let s = el as? String { 
                            out.append(s)
                            continue 
                        }
                        if let d = el as? [String: Any] {
                            if let n = nameFrom(d) { 
                                out.append(n)
                                continue 
                            }
                            if let t = d["tag"] as? [String: Any], let n = nameFrom(t) { 
                                out.append(n)
                                continue 
                            }
                        }
                    }
                    return out.isEmpty ? nil : out
                }
            }
            
            if let tags = dict["tags"] as? [Any] {
                var out: [String] = []
                for el in tags {
                    if let d = el as? [String: Any] {
                        if isMoodContext(d["context"]) || isMoodContext(d["type"]) || 
                           isMoodContext(d["kind"]) || isMoodContext(d["category"]) || 
                           isMoodContext(d["group"]) {
                            if let n = nameFrom(d) { out.append(n) }
                            continue
                        }
                        if let t = d["tag"] as? [String: Any] {
                            if isMoodContext(t["context"]) || isMoodContext(t["type"]) || 
                               isMoodContext(t["kind"]) || isMoodContext(t["category"]) || 
                               isMoodContext(t["group"]) {
                                if let n = nameFrom(t) { out.append(n) }
                                continue
                            }
                        }
                    }
                }
                return out.isEmpty ? nil : out
            }
        }
        return nil
    }
    
    static func extractMoods(fromCachedTags value: Any?) -> [String]? {
        extractMoods(value)
    }
    
    // MARK: - Taggings Extraction
    
    static func extractGenresFromTaggings(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        var out: [String] = []
        for el in list {
            guard let row = el as? [String: Any],
                  let tag = row["tag"] as? [String: Any],
                  let name = tag["tag"] as? String,
                  let category = tag["tag_category"] as? [String: Any],
                  let slug = category["slug"] as? String else { continue }
            if slug.lowercased() == "genre" && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(name)
            }
        }
        return out.isEmpty ? nil : out
    }
    
    static func extractMoodsFromTaggings(_ value: Any?) -> [String]? {
        guard let list = value as? [Any] else { return nil }
        var out: [String] = []
        for el in list {
            guard let row = el as? [String: Any],
                  let tag = row["tag"] as? [String: Any],
                  let name = tag["tag"] as? String,
                  let category = tag["tag_category"] as? [String: Any],
                  let slug = category["slug"] as? String else { continue }
            if slug.lowercased() == "mood" && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(name)
            }
        }
        return out.isEmpty ? nil : out
    }
}