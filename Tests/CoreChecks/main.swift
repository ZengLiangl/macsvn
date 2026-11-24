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
print("core checks passed")
