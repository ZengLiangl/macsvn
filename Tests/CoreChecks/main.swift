import Foundation
import SvnCore

func check(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("失败: \(message)\n", stderr)
        exit(1)
    }
}

let xml = """
<?xml version="1.0" encoding="UTF-8"?>
<status>
<target path="/wc">
<entry path="/wc/sub/a.txt">
<wc-status item="modified" revision="3" props="none"></wc-status>
</entry>
<entry path="/wc/new.txt">
<wc-status item="unversioned" props="none"></wc-status>
</entry>
</target>
</status>
"""
let entries = SvnXML.parseStatus(xml, cwd: URL(fileURLWithPath: "/wc"))
check(entries.count == 2, "status count")
let badges = BadgeMap.make(entries: entries, root: "/wc")
check(badges["/wc/sub/a.txt"] == "modified", "file badge")
check(badges["/wc/sub"] == "modified", "parent badge")
check(badges["/wc"] == "modified", "root badge")
check(badges["/wc/new.txt"] == "unversioned", "unversioned")

let infoXML = """
<info><entry path="/wc" revision="3" kind="dir">
<url>https://svn.example.com/repo/trunk</url>
<relative-url>^/trunk</relative-url>
<repository><root>https://svn.example.com/repo</root></repository>
<wc-info><wcroot-abspath>/wc</wcroot-abspath><schedule>normal</schedule><depth>infinity</depth></wc-info>
</entry></info>
"""
guard let info = SvnXML.parseInfo(infoXML) else { check(false, "info"); exit(1) }
check(info.url == "https://svn.example.com/repo/trunk", "url")
check(info.repositoryRoot == "https://svn.example.com/repo", "root")
check(info.wcRoot == "/wc", "wcroot")
check(info.revision == "3", "revision")

let logXML = """
<log><logentry revision="3"><author>ann</author><date>2020-01-01T00:00:00.000000Z</date>
<paths><path action="M" kind="file">/trunk/a.txt</path></paths><msg>hello</msg></logentry></log>
"""
let log = SvnXML.parseLog(logXML)
check(log.count == 1 && log[0].message == "hello" && log[0].paths == ["M /trunk/a.txt"], "log")

let invocation = CommandInvocation(action: .commit, paths: ["/版本/APP版本", "/tmp/a"], shift: true)
guard let url = CommandURLCodec.encode(invocation) else { check(false, "url"); exit(1) }
check(CommandURLCodec.decode(url) == invocation, "url roundtrip")

var status = StatusFile(roots: ["/wc"], scanned: ["/wc"], badges: [:])
let clean = MenuPolicy.flags(paths: ["/wc/a.txt"], status: status)
check(clean.inWorkingCopy && !clean.commit && clean.update && clean.deleteVersioned, "clean menu")
status.badges["/wc/a.txt"] = BadgeKind.modified.rawValue
let dirty = MenuPolicy.flags(paths: ["/wc/a.txt"], status: status)
check(dirty.commit && dirty.diffBase && !dirty.add, "dirty menu")
check(!MenuPolicy.flags(paths: ["/other"], status: status).inWorkingCopy, "outside")
check(RevisionInput.isValid("12") && RevisionInput.isValid("{2024-01-01}"), "revision ok")
check(!RevisionInput.isValid("HEAD") && !RevisionInput.isValid(""), "revision bad")

// 乱码还原：GBK 字节被当成 Latin-1 存进库的历史提交说明
check(TextRepair.repairMojibake("·¢²¼SQLÎÄ¼þ hk.sql") == "发布SQL文件 hk.sql", "mojibake repair")
check(TextRepair.repairMojibake("¸üÐÂSQLÎÄ¼þ ecp.sql") == "更新SQL文件 ecp.sql", "mojibake repair 2")
check(TextRepair.repairMojibake("ÖÐÎÄ") == "中文", "mojibake repair cjk")
// 正常文本必须原样保留，不能被误改
for safe in ["更新版本号", "1", "release 1.2.3", "修复 bug", "", "工作交接目录"] {
    check(TextRepair.repairMojibake(safe) == safe, "must keep: \(safe)")
}
for latin in ["Résumé", "Grüße", "Ångström", "naïve café", "Español", "£100"] {
    check(TextRepair.repairMojibake(latin) == latin, "must keep latin: \(latin)")
}
// ---- 文档要求：菜单可用性规则 ----
let wcStatus = StatusFile(
    roots: ["/wc"], scanned: ["/wc"],
    badges: [
        "/wc/mod.txt": "modified",
        "/wc/add.txt": "added",
        "/wc/del.txt": "deleted",
        "/wc/new.txt": "unversioned",
        "/wc/plain.txt": ""
    ],
    needsLock: ["/wc/plain.txt"]
)

// 提交：已修改 / 新添加 / 已删除 时可用
check(MenuPolicy.flags(paths: ["/wc/mod.txt"], status: wcStatus).commit, "commit on modified")
check(MenuPolicy.flags(paths: ["/wc/add.txt"], status: wcStatus).commit, "commit on added")
check(MenuPolicy.flags(paths: ["/wc/del.txt"], status: wcStatus).commit, "commit on deleted")
check(!MenuPolicy.flags(paths: ["/wc/plain.txt"], status: wcStatus).commit, "no commit on clean")

// 更新：受版本控制即可
check(MenuPolicy.flags(paths: ["/wc/plain.txt"], status: wcStatus).update, "update in wc")
check(!MenuPolicy.flags(paths: ["/outside"], status: wcStatus).update, "no update outside")

// 比较
check(MenuPolicy.flags(paths: ["/wc/mod.txt", "/wc/add.txt"], status: wcStatus).diffTwo, "diff two")
check(MenuPolicy.flags(paths: ["/wc/mod.txt"], status: wcStatus).diffBase, "diff base on modified")
check(!MenuPolicy.flags(paths: ["/wc/plain.txt"], status: wcStatus).diffBase, "no diff base on clean")

// 稍后比较 → 与…比较
let marked = MenuPolicy.flags(paths: ["/wc/plain.txt"], status: wcStatus)
check(marked.compareLater, "compare later available")
let withBase = MenuPolicy.flags(
    paths: ["/wc/mod.txt"],
    status: wcStatus,
    clipboard: ClipboardState(compareBase: "/wc/plain.txt")
)
check(withBase.compareWith, "compare with after later")
let sameBase = MenuPolicy.flags(
    paths: ["/wc/plain.txt"],
    status: wcStatus,
    clipboard: ClipboardState(compareBase: "/wc/plain.txt")
)
check(!sameBase.compareWith, "no compare with itself")

// 粘贴：复制后可用，且目标不能是来源本身
let emptyClip = MenuPolicy.flags(paths: ["/wc/plain.txt"], status: wcStatus)
check(!emptyClip.paste, "no paste without clipboard")
let copied = ClipboardState(paths: ["/wc/mod.txt"], isMove: false)
check(MenuPolicy.flags(paths: ["/wc/plain.txt"], status: wcStatus, clipboard: copied).paste, "paste after copy")
check(!MenuPolicy.flags(paths: ["/wc/mod.txt"], status: wcStatus, clipboard: copied).paste, "no paste onto source")

// 加锁：只有带 svn:needs-lock 的文件可用
check(MenuPolicy.flags(paths: ["/wc/plain.txt"], status: wcStatus).lock, "lock needs-lock file")
check(!MenuPolicy.flags(paths: ["/wc/mod.txt"], status: wcStatus).lock, "no lock without needs-lock")

// 设置：主菜单提升与路径选择按命令生效
var settings = AppSettings.detected
settings.promotedActions = ["commit", "paste"]
check(settings.promotes(.commit) && settings.promotes(.paste), "promote settings")
check(!settings.promotes(.update), "promote off")
settings.confirmCommands = ["lock"]
check(settings.asksForPaths(.lock) && !settings.asksForPaths(.add), "path pick settings")

// 旧配置迁移：promoteCommitAndUpdate 应转成 提交+更新
let legacyJSON = """
{"svnPath":"/usr/bin/svn","promoteCommitAndUpdate":true,"toolbarUsesSelection":false,
 "externalDiffTool":"","commitMessageHistory":[],"confirmCommands":["add"]}
"""
let migrated = try! JSONDecoder().decode(AppSettings.self, from: Data(legacyJSON.utf8))
check(migrated.promotedActions.sorted() == ["commit", "update"], "legacy migration")
check(migrated.confirmCommands == ["add"], "legacy confirm kept")

// 更新输出解析
let updateText = """
Updating '.':
U    a.txt
A    c.txt
D    d/b.txt
Updated to revision 3.
"""
let summary = UpdateOutput.parse(updateText, cwd: URL(fileURLWithPath: "/wc"))
check(summary.revision == "3", "update revision")
check(summary.entries.count == 3, "update entry count")
check(summary.entries.map(\.action) == ["U", "A", "D"], "update actions")
check(summary.entries[0].label == "已更新", "label U")
check(summary.entries[1].label == "新增", "label A")
check(summary.entries[2].label == "删除", "label D")
check(summary.entries[0].path == "/wc/a.txt", "path resolve")
check(summary.hasChanges, "has changes")
check(!summary.upToDate, "not up to date")

// 已是最新
let upToDate = """
Updating '.':
At revision 7.
"""
let fresh = UpdateOutput.parse(upToDate, cwd: URL(fileURLWithPath: "/wc"))
check(fresh.revision == "7", "up-to-date revision")
check(fresh.entries.isEmpty && fresh.upToDate, "up to date flag")

// 冲突行也算改动
let conflict = """
Updating '.':
   C   a.txt
Updated to revision 9.
"""
let conflicted = UpdateOutput.parse(conflict, cwd: URL(fileURLWithPath: "/wc"))
check(conflicted.entries.first?.label == "冲突", "conflict label")

// 提交输出解析
check(CommitOutput.revision(from: "Sending a.txt\nCommitted revision 12068.") == "12068", "commit revision")
check(CommitOutput.revision(from: "nothing to commit") == nil, "commit no revision")

// 默认交互：命令都放在子菜单（主菜单提升未经验证，默认关闭）；只有删除先问路径
let defaults = AppSettings.detected
check(defaults.promotedActions.isEmpty, "default no promotion")
check(!defaults.promotes(.commit), "commit stays in submenu by default")
check(defaults.asksForPaths(.deleteVersioned), "delete asks paths")
check(!defaults.asksForPaths(.add) && !defaults.asksForPaths(.revert), "add/revert no picker by default")

print("core checks passed")
