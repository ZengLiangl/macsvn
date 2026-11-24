import Foundation

/// 还原「GBK 字节被当成 Latin-1 存进版本库」的历史提交说明。
///
/// 一些老客户端把 GBK 编码的提交说明按 Latin-1 写进库，`svn log` 取回来就是
/// `·¢²¼SQLÎÄ¼þ` 这种乱码——库里存的就是坏数据，命令行同样显示乱码。
/// 这里在显示前尽力还原：把每个字符还原成它对应的单字节，再按 GBK 解码。
///
/// 为防止误伤正常的西文（`Résumé`、`Grüße`、`Ångström` 这类），要求：
/// - 只有高位字符（U+0080–U+00FF），不碰已经含中文的文本；
/// - 高位字符必须成对连续，因为 GBK 是双字节，整体被当成两个 Latin-1 字符；
/// - 还原后不能吞掉原文的任何 ASCII 字符；
/// - 还原结果能再编码回完全相同的字节。
public enum TextRepair {
    public static func repairMojibake(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        // 已含中文，说明不是这种双重编码
        if text.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) { return text }

        var bytes: [UInt8] = []
        var highOffsets: [Int] = []
        for scalar in text.unicodeScalars {
            guard scalar.value <= 0xFF else { return text }
            if scalar.value >= 0x80 { highOffsets.append(bytes.count) }
            bytes.append(UInt8(scalar.value))
        }
        guard highOffsets.count >= 2 else { return text }

        let offsets = Set(highOffsets)
        let paired = highOffsets.filter { offsets.contains($0 + 1) }.count
        guard Double(paired) >= Double(highOffsets.count) * 0.6 else { return text }

        let encoding = gb18030
        guard
            let decoded = String(bytes: bytes, encoding: encoding),
            decoded.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }),
            asciiScalars(of: text) == asciiScalars(of: decoded),
            let roundTrip = decoded.data(using: encoding),
            Array(roundTrip) == bytes
        else {
            return text
        }
        return decoded
    }

    private static var gb18030: String.Encoding {
        let cf = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String.Encoding(rawValue: cf)
    }

    private static func asciiScalars(of text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { $0.isASCII }
    }
}
