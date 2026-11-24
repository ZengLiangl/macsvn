import Foundation

public enum SvnXML {
    public static func parseStatus(_ xml: String, cwd: URL) -> [StatusEntry] {
        let parser = StatusXML(cwd: cwd)
        return parser.parse(xml)
    }

    public static func parseInfo(_ xml: String) -> RepositoryInfo? {
        let parser = InfoXML()
        let info = parser.parse(xml)
        if info.url.isEmpty, info.repositoryRoot.isEmpty {
            return nil
        }
        return info
    }

    public static func parseLog(_ xml: String) -> [LogEntry] {
        LogXML().parse(xml)
    }

    /// 解析 `svn propget -R --xml svn:needs-lock` 的输出，得到需加锁的路径列表。
    public static func parseNeedsLock(_ xml: String, cwd: URL) -> [String] {
        NeedsLockXML(cwd: cwd).parse(xml)
    }

}

public enum BadgeMap {
    public static func make(entries: [StatusEntry], root: String) -> [String: String] {
        var best: [String: BadgeKind] = [:]
        let root = PathID.normalize(root)
        for entry in entries {
            guard let badge = entry.badge else { continue }
            best[entry.path] = higher(best[entry.path], badge)
            var parent = URL(fileURLWithPath: entry.path).deletingLastPathComponent().path
            while PathID.isInside(parent, root: root) {
                best[parent] = higher(best[parent], badge)
                if parent == root {
                    break
                }
                let next = URL(fileURLWithPath: parent).deletingLastPathComponent().path
                if next == parent {
                    break
                }
                parent = next
            }
        }
        return best.mapValues(\.rawValue)
    }

    private static func higher(_ current: BadgeKind?, _ next: BadgeKind) -> BadgeKind {
        guard let current else { return next }
        return current.rank >= next.rank ? current : next
    }
}

private final class StatusXML: NSObject, XMLParserDelegate {
    private let cwd: URL
    private var entries: [StatusEntry] = []
    private var path: String?
    private var item: String?
    private var hasLock = false

    init(cwd: URL) {
        self.cwd = cwd
    }

    func parse(_ xml: String) -> [StatusEntry] {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        parser.parse()
        return entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if name == "entry" {
            path = attributes["path"]
            item = nil
            hasLock = false
        } else if name == "wc-status" {
            item = attributes["item"]
        } else if name == "lock" {
            hasLock = true
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "entry", let path, let item else { return }
        let absolute = PathID.resolve(path, cwd: cwd)
        entries.append(StatusEntry(path: absolute, item: item, badge: BadgeKind.from(item: item, hasLock: hasLock)))
    }
}

private final class InfoXML: NSObject, XMLParserDelegate {
    private var info = RepositoryInfo()
    private var stack: [String] = []
    private var text = ""

    func parse(_ xml: String) -> RepositoryInfo {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        parser.parse()
        return info
    }

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        stack.append(name)
        text = ""
        if name == "entry" {
            info.path = attributes["path"] ?? info.path
            info.revision = attributes["revision"] ?? info.revision
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last
        switch name {
        case "url" where parent == "entry":
            info.url = value
        case "relative-url":
            info.relativeURL = value
        case "root" where parent == "repository":
            info.repositoryRoot = value
        case "schedule":
            info.schedule = value
        case "depth" where parent == "wc-info":
            info.depth = value
        case "wcroot-abspath":
            info.wcRoot = value
        default:
            break
        }
        if !stack.isEmpty {
            stack.removeLast()
        }
        text = ""
    }
}

private final class LogXML: NSObject, XMLParserDelegate {
    private var entries: [LogEntry] = []
    private var stack: [String] = []
    private var text = ""
    private var revision = ""
    private var author = ""
    private var date = ""
    private var message = ""
    private var paths: [String] = []
    private var action = ""

    func parse(_ xml: String) -> [LogEntry] {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        parser.parse()
        return entries
    }

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        stack.append(name)
        text = ""
        if name == "logentry" {
            revision = attributes["revision"] ?? ""
            author = ""
            date = ""
            message = ""
            paths = []
        } else if name == "path" {
            action = attributes["action"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.dropLast().last
        switch name {
        case "author" where parent == "logentry":
            author = value
        case "date" where parent == "logentry":
            date = value
        case "msg" where parent == "logentry":
            message = TextRepair.repairMojibake(value)
        case "path" where parent == "paths":
            paths.append("\(action) \(value)")
        case "logentry":
            entries.append(LogEntry(revision: revision, author: author, date: date, message: message, paths: paths))
        default:
            break
        }
        if !stack.isEmpty {
            stack.removeLast()
        }
        text = ""
    }
}


/// 解析 `svn propget -R --xml svn:needs-lock` 的 target 路径。


/// 只关心 <target path="…">，且其中确实声明了 svn:needs-lock 属性。
private final class NeedsLockXML: NSObject, XMLParserDelegate {
    private let cwd: URL
    private var paths: [String] = []
    private var current: String?
    private var hasProperty = false

    init(cwd: URL) { self.cwd = cwd }

    func parse(_ xml: String) -> [String] {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        parser.parse()
        return paths
    }

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if name == "target" {
            current = attributes["path"]
            hasProperty = false
        } else if name == "property",
                  attributes["name"] == "svn:needs-lock" {
            hasProperty = true
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "target", let target = current else { return }
        if hasProperty {
            paths.append(PathID.resolve(target, cwd: cwd))
        }
        current = nil
        hasProperty = false
    }
}
