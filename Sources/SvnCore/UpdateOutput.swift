import Foundation

/// 一条更新记录：svn 的动作字母 + 受影响路径。
public struct UpdateEntry: Equatable {
    /// 原始动作字母，如 U / G / A / D / C / UU。
    public var action: String
    public var path: String

    public init(action: String, path: String) {
        self.action = action
        self.path = path
    }

    /// 动作字母的中文说明，用于结果窗口展示。
    public var label: String {
        switch action {
        case "U", "UU", "UG": return "已更新"
        case "G", "GU": return "已合并"
        case "A": return "新增"
        case "D": return "删除"
        case "C": return "冲突"
        case "E": return "已替换"
        case "R": return "已替换"
        case "B": return "损坏"
        default: return action
        }
    }
}

public struct UpdateSummary: Equatable {
    /// 更新后（或已在）的修订版本号；取不到为 nil。
    public var revision: String?
    /// 没有任何改动，只是确认已是最新。
    public var upToDate: Bool
    /// 其它值得显示的行，如冲突汇总、跳过说明。
    public var notes: [String]
    public var entries: [UpdateEntry]

    public init(revision: String? = nil, upToDate: Bool = false, notes: [String] = [], entries: [UpdateEntry] = []) {
        self.revision = revision
        self.upToDate = upToDate
        self.notes = notes
        self.entries = entries
    }

    public var hasChanges: Bool { !entries.isEmpty }
}

/// 解析 `svn update` 的文本输出。
///
/// 实测格式：
///     Updating '.':
///     U    a.txt
///     A    c.txt
///     D    d/b.txt
///     Updated to revision 3.
/// 已是最新时只有：
///     Updating '.':
///     At revision 3.
public enum UpdateOutput {
    private static let actionLetters = Set("ADUGCERB".map { $0 })

    public static func parse(_ text: String, cwd: URL) -> UpdateSummary {
        var summary = UpdateSummary()
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).replacingOccurrences(of: "\r", with: "")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let revision = revisionNumber(from: trimmed) {
                summary.revision = revision
                if trimmed.lowercased().hasPrefix("at revision") {
                    summary.upToDate = true
                }
                continue
            }
            // 这些是过程说明，不是文件记录
            if trimmed.hasPrefix("Updating ")
                || trimmed.hasPrefix("Fetching ")
                || trimmed.hasPrefix("External")
                || trimmed.hasPrefix("Restored ")
                || trimmed.hasPrefix("Skipped ") {
                if trimmed.hasPrefix("Skipped ") { summary.notes.append(trimmed) }
                continue
            }
            if trimmed.hasPrefix("Summary of conflicts") {
                summary.notes.append(trimmed)
                continue
            }
            if trimmed.hasPrefix("Tree conflict") || trimmed.hasPrefix("Text conflicts") {
                summary.notes.append(trimmed)
                continue
            }

            if let entry = entry(from: trimmed, cwd: cwd) {
                summary.entries.append(entry)
            }
        }
        if summary.entries.isEmpty { summary.upToDate = summary.upToDate || summary.revision != nil }
        return summary
    }

    private static func revisionNumber(from line: String) -> String? {
        // "Updated to revision 3." / "At revision 3." / "Updated to revision 3 (…)."
        for marker in ["Updated to revision ", "At revision "] {
            if let range = line.range(of: marker) {
                let rest = line[range.upperBound...]
                let digits = rest.prefix { $0.isNumber }
                return digits.isEmpty ? nil : String(digits)
            }
        }
        return nil
    }

    private static func entry(from line: String, cwd: URL) -> UpdateEntry? {
        // 动作字母在前，随后是若干空格，再是路径
        let scalars = Array(line)
        var index = 0
        while index < scalars.count, scalars[index] != " " {
            index += 1
        }
        guard index > 0, index <= 4 else { return nil }
        let token = String(scalars[0..<index])
        guard token.allSatisfy({ actionLetters.contains($0) }) else { return nil }

        let rest = String(scalars[index...]).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        // 目录类的展示为 "path/'…'"，不影响解析
        return UpdateEntry(action: token, path: PathID.resolve(rest, cwd: cwd))
    }
}
