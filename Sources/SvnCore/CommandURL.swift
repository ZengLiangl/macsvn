import Foundation

public enum CommandURLCodec {
    public static func encode(_ invocation: CommandInvocation) -> URL? {
        var components = URLComponents()
        components.scheme = "macsvn"
        components.host = "run"
        var items = [URLQueryItem(name: "cmd", value: invocation.action.rawValue)]
        if invocation.shift {
            items.append(URLQueryItem(name: "shift", value: "1"))
        }
        for path in invocation.paths {
            items.append(URLQueryItem(name: "path", value: path))
        }
        components.queryItems = items
        return components.url
    }

    public static func decode(_ url: URL) -> CommandInvocation? {
        guard url.scheme == "macsvn" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard
            let raw = components?.queryItems?.first(where: { $0.name == "cmd" })?.value,
            let action = SvnAction(rawValue: raw)
        else {
            return nil
        }
        let paths = components?.queryItems?.filter { $0.name == "path" }.compactMap(\.value) ?? []
        let shift = components?.queryItems?.first(where: { $0.name == "shift" })?.value == "1"
        return CommandInvocation(action: action, paths: paths, shift: shift)
    }
}
