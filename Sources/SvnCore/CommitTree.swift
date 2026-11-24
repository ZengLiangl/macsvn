import Foundation

/// 提交窗口里的一个节点。
///
/// `item` 取 svn status 的条目（modified/added/deleted/…），为 nil 表示**未版本化**，
/// 也就是磁盘上有、但还没 `svn add` 的文件或目录。
public struct CommitNode {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let item: String?
    public var children: [CommitNode]

    public var id: String { path }
    public var isUnversioned: Bool { item == nil }

    public init(path: String, name: String, isDirectory: Bool, item: String?, children: [CommitNode] = []) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.item = item
        self.children = children
    }

    /// 状态列显示的文字。
    public var label: String {
        switch item {
        case "added": return "新增"
        case "modified": return "已修改"
        case "deleted": return "已删除"
        case "replaced": return "已替换"
        case "conflicted": return "冲突"
        case "missing": return "丢失"
        case nil: return isDirectory ? "未加入（目录）" : "未加入"
        default: return item ?? ""
        }
    }
}

public enum CommitTree {
    /// 从工作副本目录 + svn status 结果构建可勾选的树。
    ///
    /// 为什么要走文件系统：`svn status` 对 depth=empty 的稀疏检出不会列出
    /// 未版本化的子项，光靠它看不到「还没加入」的文件；而提交窗口恰恰需要
    /// 让用户挑这些文件。
    public static func build(
        root: URL,
        entries: [StatusEntry],
        maxNodes: Int = 6000
    ) -> [CommitNode] {
        let rootPath = PathID.normalize(root.path)
        let fm = FileManager.default
        var budget = maxNodes

        // 路径 → (是否目录, 状态)
        var table: [String: (isDirectory: Bool, item: String?)] = [:]

        func walk(_ directory: URL, depth: Int) {
            guard depth < 24, budget > 0 else { return }
            guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
            for name in names.sorted() {
                if name == ".svn" || name == ".DS_Store" { continue }
                budget -= 1
                if budget <= 0 { return }
                let url = directory.appendingPathComponent(name)
                let path = PathID.normalize(url.path)
                var isDir: ObjCBool = false
                _ = fm.fileExists(atPath: path, isDirectory: &isDir)
                table[path] = (isDir.boolValue, nil)
                if isDir.boolValue { walk(url, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)

        let changed = ["added", "modified", "deleted", "replaced", "conflicted", "missing"]
        for entry in entries {
            let path = PathID.normalize(entry.path)
            guard PathID.isInside(path, root: rootPath) else { continue }
            if entry.item == "unversioned" {
                // 磁盘上一定有；保留磁盘记录，状态记为「未加入」
                if let existing = table[path] {
                    table[path] = (existing.isDirectory, nil)
                } else {
                    table[path] = (false, nil)
                }
                continue
            }
            guard changed.contains(entry.item) else { continue }
            // 已删除/丢失的文件磁盘上不存在，必须靠状态补进来
            let isDir = table[path]?.isDirectory ?? false
            table[path] = (isDir, entry.item)
        }

        // 按路径组装成树
        var children: [String: [String]] = [:]
        for path in table.keys {
            let parent = PathID.normalize((path as NSString).deletingLastPathComponent)
            children[parent, default: []].append(path)
        }

        func build(_ directory: String, depth: Int) -> [CommitNode] {
            guard depth < 32 else { return [] }
            let paths = (children[directory] ?? []).sorted()
            var nodes: [CommitNode] = []
            for path in paths {
                let info = table[path] ?? (false, nil)
                let name = (path as NSString).lastPathComponent
                if info.isDirectory {
                    let nested = build(path, depth: depth + 1)
                    if info.item != nil || !nested.isEmpty {
                        nodes.append(CommitNode(path: path, name: name, isDirectory: true, item: info.item, children: nested))
                    }
                } else {
                    nodes.append(CommitNode(path: path, name: name, isDirectory: false, item: info.item))
                }
            }
            return nodes
        }

        return build(rootPath, depth: 0)
    }

    /// 勾选后要提交的内容：
    /// - `versioned`：已有改动（含冲突），直接进提交列表
    /// - `unversioned`：未加入的路径，需要先 `svn add --parents`
    ///
    /// 未加入的目录只取最上层那个：`svn add --parents` 会把子项一并纳入，
    /// 重复加入会报「已在版本控制中」。
    public static func collect(selected: Set<String>, roots: [CommitNode]) -> (versioned: [String], unversioned: [String]) {
        var versioned: [String] = []
        var unversioned: [String] = []
        var claimed: [String] = []   // 已经由某个上级未加入目录覆盖

        func visit(_ node: CommitNode) {
            if selected.contains(node.path) {
                if node.isUnversioned {
                    let covered = claimed.contains { PathID.isInside(node.path, root: $0) }
                    if !covered {
                        unversioned.append(node.path)
                        if node.isDirectory { claimed.append(node.path) }
                    }
                } else if !node.isDirectory || node.item != nil {
                    versioned.append(node.path)
                }
            }
            node.children.forEach(visit)
        }

        roots.forEach(visit)
        return (versioned, unversioned)
    }
}
