import Cocoa
import Carbon.HIToolbox

// MARK: - 语言

/// 当前界面语言：zh 或 en。所有界面上的字都经过 T(中文, English) 取
var lang = "zh"
func T(_ zh: String, _ en: String) -> String { lang == "en" ? en : zh }
/// 还没选过语言时，按系统语言猜一个
func systemLang() -> String { (Locale.preferredLanguages.first ?? "zh").hasPrefix("zh") ? "zh" : "en" }

// MARK: - 配置

struct Config: Decodable {
    var stocks: [String] = ["sh000001", "600519", "00700", "AAPL", "NVDA", "hf_XAU"]
    var aliases: [String: String] = [:]
    var refreshSeconds: Double = 3
    var opacity: Double = 0.95
    var hoverOpacity: Double = 0.95
    var fontSize: Double = 11
    var color: Bool = true
    var theme: String = "dark"          // dark / light / none
    var label: String = "name"          // name / code
    var menuBarIcon: Bool = true
    var hideFromScreenShare: Bool = false
    var detailAutoCloseSeconds: Double = 5   // 详情展开后鼠标离开多久自动收起，0 = 不自动收
    var maxVisibleRows: Int = 8              // 小窗最多同时显示几行，超出的在列表里滚动
    var upColor: String = "red"              // A 股、港股页：涨用什么颜色，red 或 green
    var usGreenUp: Bool = true               // 美股页按当地习惯绿涨红跌
    var miniStyle: String = "cheer"          // 收起后的样子：cheer 啦啦队员 / face 笑脸
    var language: String = ""                // 界面语言：zh / en；空着表示还没选，先跟系统
    var tabOrder: [String] = ["a", "hk", "us"]      // 市场标签从左到右的顺序
    var uiSize: String = "m"                 // 面板整体大小：s / m / l / xl（文字、间距、图标一起等比放大）
    var mascotSize: String = "m"             // 收起后小人的大小：s / m / l
    var restSchedule: String = "auto"        // 小人什么时候休息：auto 跟随当前标签页的市场 / a / hk / us / never 永不休息
    var pomColor: String = "auto"            // 花球颜色：auto 跟随当前市场的涨色 / red / green / yellow / blue / white

    init() {}

    enum Keys: String, CodingKey {
        case stocks, aliases, refreshSeconds, opacity, hoverOpacity, fontSize
        case color, theme, label, menuBarIcon, hideFromScreenShare, detailAutoCloseSeconds, maxVisibleRows, upColor, usGreenUp, miniStyle, language, mascotSize, tabOrder, uiSize, pomColor, restSchedule
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = Config()
        stocks = try c.decodeIfPresent([String].self, forKey: .stocks) ?? d.stocks
        aliases = try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? d.aliases
        refreshSeconds = try c.decodeIfPresent(Double.self, forKey: .refreshSeconds) ?? d.refreshSeconds
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        hoverOpacity = try c.decodeIfPresent(Double.self, forKey: .hoverOpacity) ?? d.hoverOpacity
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        color = try c.decodeIfPresent(Bool.self, forKey: .color) ?? d.color
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? d.theme
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? d.label
        menuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarIcon) ?? d.menuBarIcon
        hideFromScreenShare = try c.decodeIfPresent(Bool.self, forKey: .hideFromScreenShare) ?? d.hideFromScreenShare
        detailAutoCloseSeconds = try c.decodeIfPresent(Double.self, forKey: .detailAutoCloseSeconds) ?? d.detailAutoCloseSeconds
        maxVisibleRows = try c.decodeIfPresent(Int.self, forKey: .maxVisibleRows) ?? d.maxVisibleRows
        upColor = try c.decodeIfPresent(String.self, forKey: .upColor) ?? d.upColor
        usGreenUp = try c.decodeIfPresent(Bool.self, forKey: .usGreenUp) ?? d.usGreenUp
        miniStyle = try c.decodeIfPresent(String.self, forKey: .miniStyle) ?? d.miniStyle
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        mascotSize = try c.decodeIfPresent(String.self, forKey: .mascotSize) ?? d.mascotSize
        tabOrder = (try? c.decodeIfPresent([String].self, forKey: .tabOrder)) ?? d.tabOrder
        uiSize = try c.decodeIfPresent(String.self, forKey: .uiSize) ?? d.uiSize
        pomColor = try c.decodeIfPresent(String.self, forKey: .pomColor) ?? d.pomColor
        restSchedule = try c.decodeIfPresent(String.self, forKey: .restSchedule) ?? d.restSchedule
    }
}

let testHome = ProcessInfo.processInfo.environment["PEEK_HOME"]      // 测试用：换一个配置目录，不碰正式配置
let configDir = testHome.map { URL(fileURLWithPath: $0) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cheerup")
let configURL = configDir.appendingPathComponent("config.json")
let store = testHome == nil ? UserDefaults.standard : (UserDefaults(suiteName: "local.cheerup.test") ?? .standard)
let maxStocks = 50
let pomColors = ["auto", "red", "green", "yellow", "blue", "white"]
/// 测试用：测试目录里有 offline 文件时，把请求指到一个连不上的地址，模拟断网
func host(_ real: String) -> String {
    if let t = testHome, FileManager.default.fileExists(atPath: t + "/offline") { return "https://127.0.0.1:9/" }
    return real
}
var requestCount = 0     // 测试用：发出过多少次网络请求

let defaultConfigText = """
{
  "stocks": ["sh000001", "600519", "00700", "AAPL", "NVDA", "hf_XAU"],
  "aliases": {},
  "refreshSeconds": 3,
  "opacity": 0.95,
  "hoverOpacity": 0.95,
  "fontSize": 11,
  "color": true,
  "theme": "dark",
  "label": "name",
  "menuBarIcon": true,
  "hideFromScreenShare": false,
  "detailAutoCloseSeconds": 5,
  "maxVisibleRows": 8
}
"""

extension Config {
    /// 把写错范围的数值拉回安全区间，避免出现「透明度 0 找不到窗口」这类自己把自己锁在外面的情况
    func sanitized() -> Config {
        var c = self
        var seen = Set<String>()
        c.stocks = stocks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(isValidCode($0) ? apiSymbol($0) : $0).inserted }
        c.opacity = min(max(opacity, 0.08), 1)
        c.hoverOpacity = min(max(hoverOpacity, max(c.opacity, 0.3)), 1)
        c.fontSize = min(max(fontSize, 8), 22)
        c.refreshSeconds = max(refreshSeconds, 2)
        c.detailAutoCloseSeconds = max(detailAutoCloseSeconds, 0)
        c.maxVisibleRows = min(max(maxVisibleRows, 3), 20)
        if !["dark", "light", "none"].contains(theme) { c.theme = "dark" }
        if !["name", "code"].contains(label) { c.label = "name" }
        if !["red", "green"].contains(upColor) { c.upColor = "red" }
        if !["cheer", "face"].contains(miniStyle) { c.miniStyle = "cheer" }
        if !["zh", "en"].contains(language) { c.language = "" }
        if !["s", "m", "l"].contains(mascotSize) { c.mascotSize = "m" }
        if !["s", "m", "l", "xl"].contains(uiSize) { c.uiSize = "m" }
        var order: [String] = []                       // 顺序里只认三个市场，各出现一次；漏掉的补在后面
        for id in tabOrder + ["a", "hk", "us"] where ["a", "hk", "us"].contains(id) && !order.contains(id) { order.append(id) }
        c.tabOrder = order
        if !pomColors.contains(pomColor) { c.pomColor = "auto" }
        if !["auto", "a", "hk", "us", "never"].contains(restSchedule) { c.restSchedule = "auto" }
        return c
    }
}

func decodeConfig(_ data: Data) -> Config? {
    (try? JSONDecoder().decode(Config.self, from: data))?.sanitized()
}

/// 返回 nil 表示配置文件存在但格式有误：调用方应保留上一份可用配置，而不是换成默认股票
func loadConfig() -> Config? {
    if !FileManager.default.fileExists(atPath: configURL.path) {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? defaultConfigText.write(to: configURL, atomically: true, encoding: .utf8)
    }
    guard let data = try? Data(contentsOf: configURL) else { return nil }
    return decodeConfig(data)
}

// MARK: - 行情

struct Quote {
    var name: String
    var code: String
    var price: Double
    var prevClose: Double
    var open: Double
    var high: Double
    var low: Double
    var time: String
    var stamp: Date? = nil             // 最新一笔行情的时刻（已按所在市场的时区换算）
    var f: [String] = []
    func str(_ i: Int) -> String { i < f.count ? f[i] : "" }
    func num(_ i: Int) -> Double? { i < f.count ? Double(f[i]) : nil }
    var live: Bool { price > 0 }       // 集合竞价前、停牌时接口给的现价是 0，不能当成跌了 100%
    var change: Double { live ? price - prevClose : 0 }
    var pct: Double { live && prevClose > 0 ? (price - prevClose) / prevClose * 100 : 0 }
    var dir: Int { pct > 0.0001 ? 1 : (pct < -0.0001 ? -1 : 0) }
}

/// 三个市场的规则不一样：交易时段、时区、币种、有没有涨跌停、成交量单位都不同
enum Market {
    case aStock, aIndex, hk, us, cmdty        // cmdty：黄金、白银、原油这类国际商品（接口代码以 hf_ 开头）

    var currency: String { self == .hk ? T("港元", "HKD") : (self == .us || self == .cmdty ? T("美元", "USD") : "") }
    var zone: TimeZone {
        TimeZone(identifier: self == .us ? "America/New_York" : (self == .hk ? "Asia/Hong_Kong" : "Asia/Shanghai")) ?? .current
    }
    /// 常规交易时段（当地时间的分钟数，含首尾）
    var sessions: [(Int, Int)] {
        switch self {
        case .aStock, .aIndex: return [(570, 690), (780, 900)]     // 9:30–11:30、13:00–15:00
        case .hk: return [(570, 720), (780, 960)]                  // 9:30–12:00、13:00–16:00
        case .us: return [(570, 960)]                              // 美东 9:30–16:00
        case .cmdty: return [(0, 1439)]                            // 国际商品工作日几乎全天交易
        }
    }
    static func of(_ key: String, type: String = "") -> Market {
        if key.hasPrefix("hf_") { return .cmdty }
        if key.hasPrefix("r_hk") || key.hasPrefix("hk") { return .hk }
        if key.hasPrefix("sh") || key.hasPrefix("sz") || key.hasPrefix("bj") { return type.contains("ZS") ? .aIndex : .aStock }
        return .us
    }
    /// 现在这个市场处在什么状态。stamp 是最新一笔行情的时间：日程上该交易却很久没有新行情，说明是节假日休市
    func status(now: Date = Date(), stamp: Date?) -> (text: String, live: Bool) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let c = cal.dateComponents([.weekday, .hour, .minute], from: now)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let closedDay = (T("休市", "Closed"), false), pre = (T("未开盘", "Opens later"), false), auction = (T("集合竞价", "Auction"), true)
        let open = (T("交易中", "Open"), true), lunch = (T("午休", "Lunch break"), false), closed = (T("已收盘", "Closed"), false)
        if c.weekday == 1 || c.weekday == 7 { return closedDay }
        var r: (String, Bool)
        switch self {
        case .aStock, .aIndex:
            r = m < 555 ? pre : m < 570 ? auction : m <= 690 ? open : m < 780 ? lunch : m <= 900 ? open : closed
        case .hk:
            r = m < 540 ? pre : m < 570 ? auction : m <= 720 ? open : m < 780 ? lunch : m <= 960 ? open : m < 970 ? auction : closed
        case .cmdty:
            r = open                   // 工作日全天；真休市时靠下面「很久没有新行情」来判断
        case .us:
            r = m < 240 ? closed : m < 570 ? (T("盘前", "Pre-market"), false) : m <= 960 ? open : m < 1200 ? (T("盘后", "After hours"), false) : closed
        }
        if r.1, let s = stamp, now.timeIntervalSince(s) > 1800 { return closedDay }
        return r
    }
}

/// 代码只能是字母、数字、点、下划线；中文名或带空格的写法接口不认，还会让整条请求失败
func isValidCode(_ raw: String) -> Bool {
    let ok = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._")
    return !raw.isEmpty && raw.count <= 16 && raw.unicodeScalars.allSatisfy { ok.contains($0) }
}

/// 把用户写的代码转成接口用的代码：600519 → sh600519，00700 → r_hk00700，AAPL → usAAPL
func apiSymbol(_ raw: String) -> String {
    let s = raw.trimmingCharacters(in: .whitespaces)
    let digits = CharacterSet.decimalDigits
    func allDigits(_ t: Substring) -> Bool { !t.isEmpty && t.unicodeScalars.allSatisfy { digits.contains($0) } }

    if s.lowercased().hasPrefix("hf_") && s.count > 3 { return "hf_" + s.dropFirst(3).uppercased() }       // 国际商品：hf_XAU 伦敦金、hf_GC 纽约黄金…
    for p in ["sh", "sz", "bj"] where s.hasPrefix(p) && s.count == 8 && allDigits(s.dropFirst(2)) { return s }
    if s.hasPrefix("hk") {
        let rest = s.dropFirst(2)
        if allDigits(rest) { return "r_hk" + String(repeating: "0", count: max(0, 5 - rest.count)) + rest }
        return "r_hk" + rest.uppercased()
    }
    if s.hasPrefix("us") && s.count > 2 { return "us" + s.dropFirst(2).uppercased() }
    if allDigits(Substring(s)) {
        if s.count == 6 {
            if s.hasPrefix("92") || s.hasPrefix("4") || s.hasPrefix("8") { return "bj" + s }
            if s.hasPrefix("6") || s.hasPrefix("9") || s.hasPrefix("5") { return "sh" + s }
            return "sz" + s
        }
        if s.count <= 5 { return "r_hk" + String(repeating: "0", count: 5 - s.count) + s }
    }
    return "us" + s.uppercased()
}

private var stampFormatters: [String: DateFormatter] = [:]
private let stampLock = NSLock()
/// 三个市场各用一种时间写法和时区。格式化对象创建很慢，建一次反复用（解析在后台线程，所以加锁）
func stampFormatter(_ m: Market, _ sample: String) -> DateFormatter {
    let fmt = sample.contains("/") ? "yyyy/MM/dd HH:mm:ss" : (sample.contains("-") ? "yyyy-MM-dd HH:mm:ss" : "yyyyMMddHHmmss")
    let key = m.zone.identifier + fmt
    stampLock.lock(); defer { stampLock.unlock() }
    if let f = stampFormatters[key] { return f }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = m.zone; f.dateFormat = fmt
    stampFormatters[key] = f
    return f
}

let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
    CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

func parseQuotes(_ text: String) -> [String: Quote] {
    var out: [String: Quote] = [:]
    for line in text.split(separator: ";") {
        guard let eq = line.firstIndex(of: "="),
              let v = line.range(of: "v_") else { continue }
        let key = String(line[v.upperBound..<eq])
        let body = line[line.index(after: eq)...].trimmingCharacters(in: CharacterSet(charactersIn: "\"\n\r "))
        if key.hasPrefix("hf_") {
            // 国际商品：现价, 涨跌幅, 买价, 卖价, 最高, 最低, 时间, 昨结, 开盘, …, 日期, 名称（时间是北京时间）
            let c = body.components(separatedBy: ",")
            guard c.count > 13, let price = Double(c[0]), let prev = Double(c[7]) else { continue }
            let stamp = stampFormatter(.aStock, c[12] + " " + c[6]).date(from: c[12] + " " + c[6])
            let cname = c[13].components(separatedBy: "（")[0]              // 「伦敦金（现货黄金）」只留「伦敦金」
            out[key] = Quote(name: cname, code: String(key.dropFirst(3)), price: price, prevClose: prev,
                             open: Double(c[8]) ?? 0, high: Double(c[4]) ?? 0, low: Double(c[5]) ?? 0, time: String(c[6].prefix(5)), stamp: stamp, f: [])
            continue
        }
        let f = body.components(separatedBy: "~")
        guard f.count > 34, let price = Double(f[3]), let prev = Double(f[4]) else { continue }
        // 三个市场的时间写法各不相同，时区也不同
        let stamp = stampFormatter(Market.of(key), f[30]).date(from: f[30])
        var time = f[30]
        if time.count == 14, !time.contains(":") {           // 20261125104627
            let t = Array(time); time = "\(t[8])\(t[9]):\(t[10])\(t[11])"
        } else if let sp = time.firstIndex(of: " ") {         // 2026/11/25 10:46:25
            time = String(time[time.index(after: sp)...].prefix(5))
        }
        out[key] = Quote(name: f[1], code: f[2], price: price, prevClose: prev,
                         open: Double(f[5]) ?? 0, high: Double(f[33]) ?? 0, low: Double(f[34]) ?? 0, time: time, stamp: stamp, f: f)
    }
    return out
}

func fmt(_ v: Double) -> String {
    String(format: abs(v) < 1 ? "%.3f" : "%.2f", v)
}
/// 价格类字段：0 表示没有数据，显示成「—」
func fmtP(_ v: Double) -> String { v > 0 ? fmt(v) : "—" }

/// 把用户敲进搜索框的东西整理成接口能认的关键词。返回 nil 表示没有可搜的内容
/// - 全角转半角；去掉接口不认的符号（引号、尖括号等会让接口直接报错）
/// - 中文里的空格全部去掉（「茅 台」接口搜不到）；英文只把连续空格并成一个
/// - 「sh600519」「hk00700」这种带市场前缀的写法，接口不认：拆成关键词 + 只看这个市场
func cleanQuery(_ raw: String) -> (q: String, market: String?)? {
    var t = (raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
    t = String(t.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == " " || $0 == "*" })
    let hasCJK = t.unicodeScalars.contains { $0.value >= 0x2E80 }
    if hasCJK { t = t.replacingOccurrences(of: " ", with: "") }
    else { t = t.split(separator: " ").joined(separator: " ") }
    t = String(t.prefix(24))
    guard !t.isEmpty else { return nil }
    let lower = t.lowercased()
    for m in ["sh", "sz", "bj", "hk"] where lower.hasPrefix(m) {
        let rest = String(t.dropFirst(2))
        let digits = !rest.isEmpty && rest.allSatisfy { $0.isNumber }
        if digits || (m == "hk" && rest.count >= 2 && rest == rest.uppercased() && rest.allSatisfy({ $0.isLetter })) { return (rest, m) }
    }
    if t.hasPrefix("us"), t.count > 2 {            // 只认「us」小写 + 后面全大写（usAAPL、us.IXIC），免得把 usb 这种词拆错
        let rest = String(t.dropFirst(2))
        if rest == rest.uppercased(), rest.contains(where: { $0.isLetter }) { return (rest.hasPrefix(".") ? String(rest.dropFirst()) : rest, "us") }
    }
    return (t, nil)
}

/// 解析搜索接口：v_hint="sh~600519~贵州茅台~gzmt~GP-A^hk~00700~…"
/// 只留 A 股 / 港股 / 美股里能看行情的品种，去掉基金、权证、人民币柜台这些干扰项，再按和关键词的贴近程度排序
func parseSearch(_ text: String, query: String = "", market: String? = nil) -> [AppDelegate.SearchHit] {
    guard let a = text.range(of: "\""), let b = text.range(of: "\"", options: .backwards), a.upperBound < b.lowerBound else { return [] }
    var out: [(hit: AppDelegate.SearchHit, score: Int)] = []
    let marketName = ["sh": T("沪", "SH"), "sz": T("深", "SZ"), "bj": T("北", "BJ"), "hk": T("港股", "HK"), "us": T("美股", "US")]
    let q = query.lowercased()
    for (n, item) in text[a.upperBound..<b.lowerBound].components(separatedBy: "^").enumerated() {
        let f = item.components(separatedBy: "~")
        guard f.count >= 3, let mk = marketName[f[0]] else { continue }          // jj（场外基金）等不在三个市场里的直接跳过
        if let m = market, m != f[0], !(m == "sh" && false) { continue }
        let type = f.count > 4 ? f[4] : ""
        if type == "QZ" { continue }                                             // 权证 / 牛熊证
        // 名称里的中文是 \uXXXX 转义，借 JSON 解码还原
        var name = ((try? JSONSerialization.jsonObject(with: Data("\"\(f[2])\"".utf8), options: .fragmentsAllowed)) as? String) ?? f[2]
        if f[0] == "hk", f[1].count == 5, f[1].hasPrefix("8"), name.lowercased().hasSuffix("r") { continue }   // 港股人民币柜台，和港币的那只是同一家
        // 接口给的英文全是小写：纯英文名按单词首字母大写；中英混排的（腾讯音乐sw、xx etf）把英文部分整个大写
        if name == name.lowercased(), name.contains(where: { $0.isASCII && $0.isLetter }) {
            name = name.unicodeScalars.allSatisfy({ $0.isASCII }) ? name.capitalized : name.uppercased()
        }
        var code: String, short: String
        switch f[0] {
        case "hk": code = "hk" + f[1]; short = f[1].uppercased()
        case "us":
            var parts = f[1].components(separatedBy: ".")
            if parts.count > 1 { parts.removeLast() }                            // 去掉交易所后缀：aapl.oq → AAPL，brk.b.n → BRK.B
            short = parts.joined(separator: ".").uppercased()
            if type == "ZS" { short = "." + short }                              // 美股指数：ixic → .IXIC
            code = "us" + short
        default: code = apiSymbol(f[1]) == f[0] + f[1] ? f[1] : f[0] + f[1]; short = f[1]     // 能自动认出市场的就只写数字
        }
        guard isValidCode(code) else { continue }
        let tag = type == "ZS" ? T("指数", "Index") : (type.contains("ETF") ? "ETF" : (type.contains("LOF") ? "LOF" : mk))
        // 分数越小越靠前：先按接口给的顺序，再把「代码或名称完全一致」的提到最前，把衍生品、场外品种往后放
        var score = n * 2
        let lname = name.lowercased()
        if !q.isEmpty {
            func noLead(_ x: String) -> String { String(x.drop { $0 == "0" }) }       // 「700」和「00700」算同一个代码
            let digits = q.allSatisfy { $0.isNumber }
            if short.lowercased() == q || f[1].lowercased() == q || (digits && f[0] == "hk" && noLead(short) == noLead(q)) { score -= 100 }
            let otc = f[0] == "us" && f[1].hasSuffix(".ps")
            if lname == q, !otc { score -= 90 } else if lname.hasPrefix(q) { score -= 10 }
            if type == "ZS", lname != q { score += 3 }                           // 名字只是沾边的指数，排在同名的股票后面
        }
        if type.contains("ETF") || type.contains("LOF") || type == "FJ" { score += 14 }
        if f[0] == "us", f[1].hasSuffix(".ps") { score += 30 }                   // 美股场外（粉单）
        if ["做多", "做空", "倍", "期权", "etf", "c/wts", "unit", "warrant"].contains(where: { lname.contains($0) }) { score += 24 }
        out.append((.init(code: code, name: name, shortCode: short, market: mk, tag: tag), score))
    }
    var seen = Set<String>()
    return out.sorted { $0.score < $1.score }.map { $0.hit }.filter { seen.insert(apiSymbol($0.code)).inserted }
}

/// 常用的大盘指数。搜索接口对「恒生」「纳指」「标普」这类口头叫法经常搜不到指数本身，这里直接认
let commonIndexes: [(keys: [String], code: String, zh: String, en: String, short: String)] = [
    (["上证", "沪指", "大盘", "sse", "shanghai"], "sh000001", "上证指数", "SSE Composite", "000001"),
    (["深证", "深成", "szse", "shenzhen"], "sz399001", "深证成指", "SZSE Component", "399001"),
    (["创业板", "chinext"], "sz399006", "创业板指", "ChiNext", "399006"),
    (["科创", "star50", "star 50"], "sh000688", "科创50", "STAR 50", "000688"),
    (["沪深300", "csi300", "csi 300"], "sh000300", "沪深300", "CSI 300", "000300"),
    (["恒生", "恒指", "hang seng", "hangseng", "hsi"], "hkHSI", "恒生指数", "Hang Seng", "HSI"),
    (["恒生科技", "恒科", "hstech", "hang seng tech"], "hkHSTECH", "恒生科技指数", "Hang Seng Tech", "HSTECH"),
    (["纳斯达克", "纳指", "nasdaq", "ixic"], "us.IXIC", "纳斯达克", "Nasdaq Composite", ".IXIC"),
    (["道琼斯", "道指", "dow", "dji"], "us.DJI", "道琼斯", "Dow Jones", ".DJI"),
    (["标普", "s&p", "sp500", "sp 500", "spx", "inx"], "us.INX", "标普500", "S&P 500", ".INX"),
]
/// 黄金 ETF、白银基金、原油基金这类产品，背后跟的是哪个国际价格。展开它们的详情时把这个价格一起显示出来：
/// 想看金价的人，多半是因为手里拿着这类产品
func referencePrice(forName name: String) -> (code: String, zh: String, en: String)? {
    let n = name.lowercased()
    if n.contains("黄金") || n.contains("上海金") || n.contains("金etf") || n.contains("gold") { return ("hf_XAU", "金价", "Gold") }
    if n.contains("白银") || n.contains("silver") { return ("hf_XAG", "银价", "Silver") }
    if n.contains("原油") || n.contains("石油") || n.contains("crude") || n.contains(" oil") { return ("hf_CL", "油价", "Oil") }
    return nil
}

/// 黄金、白银、原油这类商品。搜索接口搜不到它们，这里直接认常见的叫法
let commonCommodities: [(keys: [String], code: String, zh: String, en: String, short: String)] = [
    (["黄金", "金价", "伦敦金", "现货黄金", "国际金价", "gold", "xau"], "hf_XAU", "伦敦金", "Gold (spot)", "XAU"),
    (["黄金", "金价", "纽约黄金", "comex", "黄金期货", "gold", "gc"], "hf_GC", "纽约黄金", "Gold futures", "GC"),
    (["白银", "银价", "伦敦银", "现货白银", "silver", "xag"], "hf_XAG", "伦敦银", "Silver (spot)", "XAG"),
    (["原油", "油价", "纽约原油", "wti", "oil", "crude"], "hf_CL", "纽约原油", "Crude oil (WTI)", "CL"),
    (["铜", "铜价", "美铜", "copper"], "hf_HG", "美铜", "Copper", "HG"),
]
func indexHits(_ raw: String, market: String?) -> [AppDelegate.SearchHit] {
    let q = raw.lowercased().trimmingCharacters(in: .whitespaces)
    guard q.count >= 2 else { return [] }
    return commonIndexes.filter { e in e.keys.contains { $0.hasPrefix(q) || q.hasPrefix($0) } }
        .filter { e in market.map { e.code.hasPrefix($0) } ?? true }
        .map { .init(code: $0.code, name: T($0.zh, $0.en), shortCode: $0.short, market: "", tag: T("指数", "Index")) }
        + (q.count >= 1 ? commonCommodities.filter { e in e.keys.contains { $0.hasPrefix(q) || q.hasPrefix($0) } }
            .filter { _ in market == nil }
            .map { .init(code: $0.code, name: T($0.zh, $0.en), shortCode: $0.short, market: "", tag: T("国际行情", "Global price")) } : [])
}

/// 看起来像一个代码（不是名称）的输入，可能对应哪些行情代码。搜索服务不通或搜不到时，直接拿去问行情接口
func codeCandidates(_ q: String) -> [String] {
    let t = q.replacingOccurrences(of: " ", with: "")
    if t.allSatisfy({ $0.isNumber }) {
        if t.count == 6 { return ["sh" + t, "sz" + t, "bj" + t] }
        if t.count >= 1, t.count <= 5 { return ["r_hk" + String(repeating: "0", count: 5 - t.count) + t] }
        return []
    }
    if t.count <= 6, t.allSatisfy({ ($0.isASCII && $0.isLetter) || $0 == "." }), t.contains(where: { $0.isLetter }) { return ["us" + t.uppercased()] }
    return []
}

/// 东方财富的证券编号：沪市 1.xxxxxx，深市 / 北交所 0.xxxxxx，港股 116.xxxxx，美股按交易所 105 / 106 / 107
func eastmoneySecid(key: String, market: Market, code: String) -> String? {
    switch market {
    case .cmdty: return nil
    case .aStock, .aIndex: return (key.hasPrefix("sh") ? "1." : "0.") + key.dropFirst(2)
    case .hk:
        let c = String(key.dropFirst(4))
        return c.allSatisfy(\.isNumber) ? "116." + c : nil
    case .us:
        let parts = code.components(separatedBy: ".")
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let ex = ["OQ": "105", "N": "106", "AM": "107", "A": "107"][parts[1]]
        return ex.map { $0 + "." + parts[0] }
    }
}

/// 解析东方财富分时：每行「2026-11-25 09:30,价格,这一分钟的量,这一分钟的额,均价」
func parseEastmoneyMinutes(_ data: Data) -> MinuteData {
    var m = MinuteData()
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let lines = (root["data"] as? [String: Any])?["trends"] as? [String] else { return m }
    var avgOK = true
    for l in lines {
        let p = l.components(separatedBy: ",")
        guard p.count >= 3, let price = Double(p[1]), price > 0, p[0].count >= 16 else { continue }
        m.prices.append(price); m.vols.append(max(0, Double(p[2]) ?? 0))
        m.times.append(String(p[0].suffix(5)).replacingOccurrences(of: ":", with: ""))
        if avgOK, p.count > 4, let a = Double(p[4]), a > 0, abs(a / price - 1) < 0.2 { m.avg.append(a) } else { avgOK = false }
    }
    if !avgOK || m.avg.count != m.prices.count { m.avg = [] }
    return m
}

struct MinuteData { var prices: [Double] = [], vols: [Double] = [], times: [String] = [], avg: [Double] = [] }

/// 解析分时接口。每行是「时间 价格 累计成交量 [累计成交额]」；美股没有成交额，所以没有均价线
func parseMinutes(_ data: Data, code: String, market: Market) -> MinuteData {
    var m = MinuteData()
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let d = (root["data"] as? [String: Any])?[code] as? [String: Any],
          let lines = (d["data"] as? [String: Any])?["data"] as? [String] else { return m }
    let unit = market == .aStock ? 100.0 : 1.0       // A 股成交量单位是手（100 股），港股是股
    var lastCum = 0.0, avgOK = market == .aStock || market == .hk
    for l in lines {
        let p = l.split(separator: " ")
        guard p.count > 2, let price = Double(p[1]), price > 0 else { continue }
        let cum = Double(p[2]) ?? lastCum
        m.prices.append(price); m.vols.append(max(0, cum - lastCum)); m.times.append(String(p[0]))
        lastCum = cum
        if avgOK, p.count > 3, let amt = Double(p[3]), cum > 0 {
            let a = amt / (cum * unit)
            if abs(a / price - 1) < 0.2 { m.avg.append(a) } else { avgOK = false }     // 算出来离谱（比如指数）就不画均价线
        } else { avgOK = false }
    }
    if !avgOK || m.avg.count != m.prices.count { m.avg = [] }
    return m
}

// MARK: - 啦啦队动作

/// 小人的一个姿势。角度是手臂相对水平线的仰角（度）：-50 垂在身侧，0 平举，90 笔直向上
/// 被拖着走时站不稳：窗口一动，它因为惯性往反方向微微一歪，松手后轻轻晃一两下才站稳。
/// 幅度很小：手脚都留在原来的位置，只是跟着微微晃，像在默默调整平衡；眼睛不变，只有嘴微微往下一点（丧丧地有点不高兴）。
/// 全程用弹簧算，所以开始、结束都是连着的，不会硬切
struct Wobble {
    var tilt: CGFloat = 0, tiltV: CGFloat = 0        // 歪了多少（正 = 往右歪）和歪的速度
    var squash: CGFloat = 0, squashV: CGFloat = 0    // 被往上提时身子往下一沉
    var amount: CGFloat = 0                          // 这套反应现在有多少成（0 = 没有，1 = 完全）
    var isCalm: Bool { amount < 0.005 && abs(tilt) < 0.01 && abs(tiltV) < 0.05 }
    /// vx、vy 是窗口这一刻的速度（点 / 秒，右、上为正）；dragging 是不是正被拖着
    mutating func step(vx: CGFloat, vy: CGFloat, dragging: Bool, dt: CGFloat) {
        let goalT: CGFloat = dragging ? min(max(-vx / 520, -1.5), 1.5) : 0
        let goalS: CGFloat = dragging ? min(max(vy / 700, -0.4), 1.0) : 0
        var left = dt
        while left > 0 {
            let h = min(left, 1.0 / 120); left -= 1.0 / 120
            tiltV += (64 * (goalT - tilt) - 6.4 * tiltV) * h; tilt += tiltV * h          // 松手后还会轻轻来回晃一两下
            squashV += (90 * (goalS - squash) - 9 * squashV) * h; squash += squashV * h
        }
        let unsettled = dragging || abs(tilt) > 0.07 || abs(tiltV) > 0.5
        amount += ((unsettled ? 1 : 0) - amount) * min(1, dt * (unsettled ? 9 : 4))      // 来得快，去得慢
        if !unsettled, amount < 0.004 { amount = 0 }
    }
    /// 把这套反应叠到姿势上（都是在原来的姿势上加一点点），返回嘴往下的程度
    func apply(to p: inout Pose) -> CGFloat {
        guard amount > 0.001 else { return 0 }
        let t = min(max(tilt, -1.5), 1.5) * amount
        p.lean += t * 0.55                              // 身子微微歪
        p.aL += 6 * t; p.aR -= 6 * t                    // 两只手留在原位，一只略抬、一只略沉
        p.liftL += -0.5 * max(0, t); p.liftR += -0.5 * max(0, -t)      // 脚跟略微离地
        p.hop += 0.35 * squash * amount
        return amount
    }
}

/// 喝茶休息：每跳完几轮，它把花球收到身后，拿出一个杯子，喝两口，再把花球拿出来接着跳。
let teaSeconds = 10.0
let teaEveryLoops = 3                 // 跳几轮歇一次
struct TeaFrame { var pose = Pose(); var behind: CGFloat = 0; var cup = false; var sip: CGFloat = 0; var thumb: CGFloat = 0; var done = false
    var live: CGFloat = 0 }       // 有多少成已经交还给后面的动作（最后把花球拿出来的那一段，从 0 到 1）
/// 一杯咖啡的全过程：花球收到身后 → 右手端出杯子 → 喝第一口 → 深吸一口气 → 精神一振，左手比个赞 → 再喝一口 → 杯子收回去、花球拿出来
func teaFrame(_ t: Double, from: Pose) -> TeaFrame {
    func ease(_ a: Double, _ b: Double) -> CGFloat { let c = CGFloat(min(max((t - a) / (b - a), 0), 1)); return c * c * (3 - 2 * c) }
    var f = TeaFrame()
    var stand = Pose(); stand.aL = -58; stand.aR = -28; stand.leg = 3.3; stand.face = 1          // 端着杯子站着：右手抬在胸前，左手垂着
    stand.hop = 0.35 + 0.3 * CGFloat(sin(t * 2 * .pi / 3.2))                                    // 轻轻呼吸
    f.cup = t >= 0.72 && t < teaSeconds - 0.78
    // 花球收到身后 → 右手端着杯子出来；最后反过来
    f.behind = t < 1.45 ? ease(0, 0.5) * (1 - ease(0.95, 1.45)) : ease(teaSeconds - 1.5, teaSeconds - 1.0) * (1 - ease(teaSeconds - 0.55, teaSeconds))
    f.pose = t < 0.5 ? from.mix(stand, ease(0, 0.5)) : stand
    // 喝两口：举到嘴边、停一会儿、放下。中间隔着比赞的那一下
    let sips: [(Double, Double)] = [(2.0, 3.2), (6.3, 7.5)]
    for (a, b) in sips where t >= a && t <= b + 0.5 { f.sip = ease(a, a + 0.5) * (1 - ease(b, b + 0.5)) }
    if f.sip > 0.01 {
        f.pose.lean -= 0.35 * f.sip                    // 头微微往后仰
        if f.sip > 0.6 { f.pose.face = 0 }             // 喝的时候闭眼
    }
    // 第一口下去：精神一振——人轻轻往上一踮、淡淡一笑，左手抬起来比个赞，停一下再放下
    // 喝完第一口，先深吸一口气：身子慢慢往上提、头微微后仰，嘴张成小 o（就是用力时那个小 o，不比它大），然后呼出来落回去
    let inAt = 3.72, inTop = 4.3, outAt = 4.55
    let breath = ease(inAt, inTop) * (1 - ease(inTop + 0.06, outAt))
    if breath > 0.01 {
        f.pose.hop -= 0.9 * breath; f.pose.lean -= 0.3 * breath
        f.pose.aL -= 5 * breath; f.pose.aR += 3 * breath            // 肩膀带着手微微抬一点
        if breath > 0.35 { f.pose.face = 2 }
    }
    let upAt = 4.5, downAt = 5.65
    f.thumb = ease(upAt, upAt + 0.22) * (1 - ease(downAt, downAt + 0.3))
    if f.thumb > 0.01 {
        // 手只微微抬起一点（从垂着抬到斜下方），让比赞的小手套离开身体、看得清；不举到胸前（手套的画法见 drawCheerPass）
        f.pose.aL += (-26 - f.pose.aL) * f.thumb
        let pop = CGFloat(max(0, sin(.pi * min(1, max(0, (t - upAt) / 0.34)))))        // 一振：只在刚开始那一下
        f.pose.hop -= 1.1 * pop
        if f.thumb > 0.4 { f.pose.face = 4 }
    }
    f.live = ease(teaSeconds - 0.55, teaSeconds)       // 手往外拿花球的同时，后面的动作就接上了；不然会先站定、停一下，再突然换成下一个姿势
    f.done = t >= teaSeconds
    return f
}

/// 「隐藏」的过场：它弯腰把花球轻轻放在脚边，直起身淡淡一笑，微微一蓄力，哧溜一下往右滑出画面；原地只剩那个花球。
/// 点花球它再走回来：从右边走进来，弯腰把花球捡起来，站好。
let leaveSeconds = 1.12, returnSeconds = 1.5
let loosePomSpot = NSPoint(x: 15.6, y: 30.6)          // 花球落在哪（38 格坐标，正好搁在脚下那块板上）
struct AwayFrame { var pose = Pose(); var x: CGFloat = 0; var fade: CGFloat = 1; var held = true; var loose: NSPoint? = nil; var rot: CGFloat = 0; var gazeY: CGFloat = 0; var gazeX: CGFloat = 0
    var live: CGFloat = 0 }       // 有多少成已经交还给后面的动作（0 = 完全是过场的姿势，1 = 完全是后面的动作）
private func awayEase(_ x: Double) -> CGFloat { let c = CGFloat(min(max(x, 0), 1)); return c * c * (3 - 2 * c) }
/// 走路：两只脚轮流抬，身子微微一颠一颠，手垂着轻轻摆；dir 是往哪边走（1 右，-1 左）
func walkPose(_ t: Double, dir: CGFloat) -> Pose {
    let ph = t / 0.36 * 2 * Double.pi, sn = CGFloat(sin(ph))
    var p = Pose()
    p.aL = -66 + 8 * sn; p.aR = -66 - 8 * sn
    p.liftL = -1.5 * max(0, sn); p.liftR = -1.5 * max(0, -sn)
    p.hop = 0.35 * abs(sn); p.lean = 0.7 * dir; p.leg = 3.0; p.face = 1
    return p
}
func leaveFrame(_ t: Double, from: Pose, hand: NSPoint) -> AwayFrame {
    // 弯腰把花球轻轻放在脚边 → 直起身，淡淡一笑 → 微微一蓄力，哧溜一下滑出画面。（hand 参数留着没用：花球是放下的，不是扔出去的）
    var bend = Pose(); bend.aL = -84; bend.aR = -56; bend.hop = 2.3; bend.lean = -0.7; bend.leg = 3.6; bend.face = 1     // 弯腰，左手够到脚边（和捡起来时是同一个姿势）
    var up = Pose(); up.aL = -50; up.aR = -46; up.face = 4                                                                // 直起身，淡淡一笑
    var wind = Pose(); wind.aL = -50; wind.aR = -50; wind.hop = 0.9; wind.lean = -0.5; wind.leg = 3.6; wind.face = 4      // 蓄力：往反方向微微一沉
    wind.tuck = 0.35
    var zip = Pose(); zip.aL = -46; zip.aR = -40; zip.hop = -0.5; zip.lean = 1.4; zip.leg = 4.0                            // 滑出去：身子前倾。两只手都弯着收在身侧——伸直了横在身后会显得手特别长
    zip.tuck = 0.55
    zip.liftL = -1.4; zip.liftR = -0.4; zip.face = 4
    var f = AwayFrame()
    let putAt = 0.4, upAt = 0.64, goAt = 0.78
    if t < putAt { f.pose = from.mix(bend, awayEase(t / putAt)); f.gazeY = 0.7 * awayEase(t / putAt); return f }      // 花球还在手里，跟着手下去
    f.held = false; f.loose = loosePomSpot
    if t < upAt { f.pose = bend.mix(up, awayEase((t - putAt) / (upAt - putAt))); f.pose.face = t > putAt + 0.1 ? 4 : 1; return f }
    if t < goAt { f.pose = up.mix(wind, awayEase((t - upAt) / (goAt - upAt))); return f }
    // 滑出去：越来越快，一下子就没了；没有一步一步走的过程
    let u = min(1, (t - goAt) / (leaveSeconds - goAt))
    f.pose = wind.mix(zip, awayEase(u / 0.35))
    f.x = 29 * CGFloat(u * u)
    f.fade = 1 - awayEase((u - 0.62) / 0.38)
    return f
}
/// 跑：比走路步子快、抬脚高、身子往前倾、手臂前后摆得开
func runPose(_ t: Double, dir: CGFloat) -> Pose {
    let ph = t / 0.2 * 2 * Double.pi, sn = CGFloat(sin(ph))
    var p = Pose()
    p.aL = -54 + 13 * sn; p.aR = -54 - 13 * sn; p.tuck = 0.5        // 手肘弯着在身侧小幅摆；伸直了前后甩会显得手很长
    p.liftL = -2.2 * max(0, sn); p.liftR = -2.2 * max(0, -sn)
    p.hop = 0.3 + 0.5 * abs(sn); p.lean = 1.25 * dir; p.leg = 3.4; p.face = 1
    return p
}
/// 「回来」的过场，一气呵成：
///   1. 从右边一下子冲回来，冲得太猛，差点冲过了头
///   2. 刹住：身子往后一仰，顺势滑回到花球旁边
///   3. 弯腰把花球捡起来
///   4. 边直起身，边接上后面的动作
/// 花球全程待在原地不动。
func returnFrame(_ t: Double) -> AwayFrame {
    func seg(_ a: Double, _ b: Double) -> CGFloat { awayEase((t - a) / (b - a)) }
    func outCubic(_ x: Double) -> CGFloat { let c = CGFloat(min(max(x, 0), 1)); return 1 - pow(1 - c, 3) }
    let stopAt = 0.4, backAt = 0.62, pickAt = 0.98
    let over: CGFloat = -5.2, reachX: CGFloat = -1.4          // 冲过头冲到哪；弯腰时人该在哪（手才够得着花球）
    var f = AwayFrame(); f.held = false; f.loose = loosePomSpot
    var brake = Pose(); brake.aL = -40; brake.aR = -46; brake.lean = 1.1; brake.hop = 0.9; brake.leg = 4.2; brake.face = 2; brake.tuck = 0.3       // 刹车：身子往后仰，两脚撑开
    var bend = Pose(); bend.aL = -84; bend.aR = -56; bend.hop = 2.3; bend.lean = -0.9; bend.leg = 3.6; bend.face = 1                               // 弯腰去够
    if t < stopAt {                                   // 1. 冲进来：很快，到头才慢下来，所以冲过了
        let k = outCubic(t / stopAt)
        f.x = 27 + (over - 27) * k; f.fade = awayEase(t / 0.14)
        f.pose = runPose(t, dir: -1).mix(brake, awayEase((t - stopAt + 0.14) / 0.14))        // 最后一小段已经开始往后仰
        return f
    }
    f.gazeX = 0.3 * seg(stopAt, backAt); f.gazeY = 0.6 * seg(stopAt, backAt)                   // 回头往下看花球
    if t < backAt { f.x = over + (reachX - over) * seg(stopAt, backAt + 0.1); f.pose = brake; return f }      // 2. 刹住，滑回来
    if t < pickAt {                                   // 3. 弯腰
        f.x = over + (reachX - over) * seg(stopAt, backAt + 0.1)
        f.pose = brake.mix(bend, seg(backAt, pickAt - 0.06)); return f
    }
    f.held = true; f.loose = nil                      // 4. 捡起来了：边起身、边回到原位、边接上后面的动作
    f.x = reachX * (1 - seg(pickAt, returnSeconds - 0.05))
    f.pose = bend
    f.live = seg(pickAt, returnSeconds)
    f.gazeX *= 1 - f.live; f.gazeY *= 1 - f.live
    return f
}

/// 背手换花球的时间轴（x 从 0 到 1，整段 swapSeconds 秒）：
/// 手收到身后 → 在身后微微掏一下 → 找到了，顿一下 → 拿出新的
let swapSeconds = 1.6
let swapIn = 0.26, swapFound = 0.58, swapOut = 0.68       // 时间轴上的几个节点：手到身后 / 找到了 / 开始拿出来
func swapState(_ x: Double) -> (behind: CGFloat, dig: CGFloat, found: Bool) {
    func ease(_ t: Double) -> CGFloat { let c = CGFloat(min(max(t, 0), 1)); return c * c * c * (c * (c * 6 - 15) + 10) }   // 起止都很缓
    if x < swapIn { return (ease(x / swapIn), 0, false) }
    if x < swapFound {
        let t = (x - swapIn) / (swapFound - swapIn)
        return (1, CGFloat(sin(t * 2 * .pi) * sin(t * .pi)), false)          // 只搓两下：一上一下，就一个来回
    }
    if x < swapOut { return (1, 0, true) }
    return (1 - ease((x - swapOut) / (1 - swapOut)), 0, true)
}

struct Pose: Equatable {
    var aL: CGFloat = -50      // 左臂
    var aR: CGFloat = -50      // 右臂
    var leg: CGFloat = 3.4     // 两脚各离中线多远
    var liftL: CGFloat = 0     // 左脚抬起多高（负数是抬起）
    var liftR: CGFloat = 0     // 右脚
    var hop: CGFloat = 0       // 离地多高：负数是跳起来，正数是下蹲
    var lean: CGFloat = 0      // 上身往哪边倾
    var spin: CGFloat = 0      // 星号转了几格（1 格 = 60°，转满一格看起来和没转一样）
    var toss: CGFloat = 0      // 花球抛到哪了：0 在手里，0→1 是抛起、在空中转、落回手里
    var face = 1               // 表情：0 闭眼  1 平时（半垂眼、平嘴）  2 用力（嘴张成小 o）  3 偷看（睁一只眼）  4 淡淡一笑
    var blink = false          // 这一瞬间在眨眼
    var z: CGFloat = 0         // 睡着时头边飘的 z：0 是没有，其余是飘到哪了（0–1 循环）
    var tuck: CGFloat = 0      // 手往脸边收多少：0 是伸直，1 是手肘弯下来、花球贴在脸颊旁（「举手手」）

    func mix(_ o: Pose, _ t: CGFloat) -> Pose {
        func m(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return Pose(aL: m(aL, o.aL), aR: m(aR, o.aR), leg: m(leg, o.leg), liftL: m(liftL, o.liftL), liftR: m(liftR, o.liftR),
                    hop: m(hop, o.hop), lean: m(lean, o.lean), spin: m(spin, o.spin), toss: m(toss, o.toss),
                    face: t < 0.35 ? face : o.face,       // 表情不渐变：动作做到三分之一时换成下一个
                    z: o.z, tuck: m(tuck, o.tuck))
    }

    /// 休息时也不是一动不动：慢慢呼吸、轻轻晃；睡着（市场休息）时头边飘 z，每隔一阵睁一只眼偷看一下
    static func resting(at t: Double, asleep: Bool) -> Pose {
        var p = Pose.rest
        let breath = CGFloat(sin(t * 2 * .pi / 3.4))                 // 3.4 秒一次呼吸
        p.hop = 1.2 + 0.7 * breath                                   // 歇着时也微微一蹲一起
        p.aL = -32 - 2.5 * breath; p.aR = -32 - 2.5 * breath        // 吸气时肩膀带着手微微抬一点
        p.lean = 0.45 * CGFloat(sin(t * 2 * .pi / 7.8))             // 很慢地左右晃
        if !asleep { p.face = 1 }                                    // 醒着歇：睁着眼
        if asleep {
            p.z = CGFloat((t / 4.2).truncatingRemainder(dividingBy: 1)) * 0.98 + 0.01      // 一个 z 从冒出来到消失 4.2 秒
            let c = t.truncatingRemainder(dividingBy: 11)
            if c > 9.6, c < 10.5 { p.face = 3 }                     // 偷看：睁开一只眼
        }
        return p
    }
    static let rest = Pose(aL: -32, aR: -32, leg: 3.2, hop: 0.9, lean: 0, spin: 0, face: 0)      // 休息：手松松地垂在身侧，闭眼歇着
}

/// 一整套动作：每一步是「用多久摆到这个姿势」和「停多久」。主题是上涨——
/// 开场跳起举高、左右交替上举、平举展开、摆出一条往右上的斜线、像台阶一样一级级举高、最后大跳收在高举
let cheerRoutine: [(pose: Pose, move: Double, hold: Double)] = [
    (Pose(), 0.40, 0.45),                                                                    // 预备，微笑
    (Pose(aL: -52, aR: -52, leg: 4.4, hop: 1.9, face: 2, tuck: 0.7), 0.24, 0.10),                       // 深蹲蓄力
    (Pose(aL: 34, aR: 44, leg: 3.1, liftL: -1.2, liftR: -1.2, hop: -3.3, lean: -0.4, spin: 1, face: 2), 0.34, 0.16),   // 跳起，收腿，双手举成 V，在最高处停一下
    (Pose(aL: 28, aR: 28, leg: 4.2, hop: 1.8, spin: 1), 0.24, 0.08),                         // 落地，蹲一下缓冲
    (Pose(aL: 33, aR: 33, spin: 1), 0.16, 0.25),                                             // 站直定住
    (Pose(aL: 38, aR: 38, toss: 1, face: 2), 0.70, 0.12),                                    // 把花球抛起来，在空中转，接住
    (Pose(aL: -12, aR: 44, liftL: -2.2, lean: 0.8, spin: 1), 0.30, 0.30),                    // 右手上举，左手斜伸，抬左脚
    (Pose(aL: 44, aR: -12, liftR: -2.2, lean: -0.8, spin: 1), 0.30, 0.30),                   // 换边，抬右脚
    (Pose(aL: 0, aR: 0, leg: 5.6, hop: 1.9, spin: 1), 0.28, 0.14),                           // 双手平举，扎个马步
    (Pose(aL: 0, aR: 0, leg: 5.6, hop: 1.0, spin: 1), 0.14, 0.00),                           // 弹一下
    (Pose(aL: 0, aR: 0, leg: 5.6, hop: 1.9, spin: 1), 0.14, 0.18),                           // 再蹲
    (Pose(aL: -18, aR: 47, leg: 4.6, lean: 1.5, spin: 1), 0.30, 0.60),                       // 左手压低、右手高举，身体跟着倾：上涨的手势，但两臂不连成一条直线
    (Pose(aL: -50, aR: -50, leg: 4.2, hop: 1.8, spin: 1, face: 2, tuck: 0.7), 0.28, 0.12),              // 收回并蹲到底，用力
    (Pose(aL: -15, aR: -15, leg: 4.0, hop: 1.1, spin: 1, face: 2, tuck: 0.3), 0.16, 0.12),              // 台阶一：一级级站起来、把手举高
    (Pose(aL: 12, aR: 12, leg: 3.6, hop: 0.4, spin: 1, face: 2), 0.16, 0.12),                // 台阶二
    (Pose(aL: 33, aR: 33, hop: -1.2, spin: 1, face: 2), 0.16, 0.12),                         // 台阶三
    (Pose(aL: 50, aR: 36, leg: 6.4, hop: -3.6, lean: 0.6, spin: 4, face: 2), 0.36, 0.26),               // 大跳，手脚全打开成一个 X，在空中多停一会儿，花球跟着转
    (Pose(aL: 26, aR: 26, leg: 4.4, hop: 1.5, spin: 4), 0.26, 0.08),                         // 落地，蹲一下
    (Pose(aL: 40, aR: 16, leg: 4.0, hop: 1.1, lean: 0.8, spin: 4), 0.20, 0.30),                 // 一手高一手低，微蹲，歪头
    (Pose(aL: 38, aR: 38, toss: 1, face: 2), 0.85, 0.00),                                    // 再抛一次，抛得更高
    (Pose(aL: 16, aR: 40, leg: 4.0, hop: 1.1, lean: -0.8, face: 4), 0.16, 0.85),                // 接住，换一边，微蹲歪头，淡淡一笑
    (Pose(face: 0), 0.50, 1.20),                                                    // 放下，闭眼歇一口气再来
]
let cheerRoutineLength: Double = cheerRoutine.reduce(0) { $0 + $1.move + $1.hold }

/// 这套动作播到第 time 秒时的姿势（循环）
func cheerPose(at time: Double) -> Pose {
    var t = time.truncatingRemainder(dividingBy: cheerRoutineLength)
    if t < 0 { t += cheerRoutineLength }
    var prev = cheerRoutine[cheerRoutine.count - 1].pose
    prev.spin = 0                                   // 上一轮结束时星号转了整数格，看起来和 0 一样，从 0 接上
    for step in cheerRoutine {
        if t < step.move {
            let x = CGFloat(t / step.move)
            let smooth = x * x * (3 - 2 * x)                       // 起步和收尾都缓一点
            var r = prev.mix(step.pose, smooth)
            func lerp(_ a: CGFloat, _ b: CGFloat, _ k: CGFloat) -> CGFloat { a + (b - a) * k }
            // 高度单独算：往上是先快后慢（冲上去、到顶减速），从空中往下是先慢后快（在顶上停一下再掉下来），这样才有腾空感
            let rising = step.pose.hop < prev.hop - 0.5, falling = prev.hop < -0.5 && step.pose.hop > prev.hop
            let eh = rising ? 1 - pow(1 - x, 3) : (falling ? x * x * x : smooth)
            r.hop = lerp(prev.hop, step.pose.hop, eh)
            r.leg = lerp(prev.leg, step.pose.leg, rising ? 1 - pow(1 - x, 2) : smooth)
            // 手臂甩过头一点再回来，动作更脆
            let k: CGFloat = 1.4, y = x - 1
            let ea = 1 + (k + 1) * y * y * y + k * y * y
            r.aL = lerp(prev.aL, step.pose.aL, ea); r.aR = lerp(prev.aR, step.pose.aR, ea)
            return r
        }
        t -= step.move
        if t < step.hold {
            var r = step.pose
            // 定住的时候也不是僵着：脚不离地，轻轻弹两下（闭眼歇气和腾空的那几拍除外）
            if step.hold >= 0.25, r.hop > -0.5, r.face != 0, r.aL > 0 || r.aR > 0 {      // 只在举着手的定格上弹
                r.hop += 0.35 * CGFloat(abs(sin(.pi * t / 0.3)) * sin(.pi * t / step.hold))
            }
            return r
        }
        t -= step.hold
        prev = step.pose
        if prev.toss >= 1 { prev.toss = 0 }        // 抛完已经接住了，下一个动作从「在手里」接上
    }
    return prev
}

/// 手势诊断日志：最多留最近 200 行，写在配置目录里
var glogLines: [String] = ((try? String(contentsOf: configDir.appendingPathComponent("gesture.log"), encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
func glog(_ s0: String) {}      // 手势诊断日志：问题已定位，不再记录

// MARK: - 视图

struct Cell {
    var text: String
    var right = false    // 数值右对齐，文字左对齐
    var tint = false     // 跟随涨跌上色
    var dim = false      // 次要信息，颜色淡一点
    var whole = false    // 整句提示，不截断
}

struct Row {
    var cells: [Cell]
    var direction: Int   // 1 涨 / -1 跌 / 0 平
}

struct Stat {
    var id = ""                // 用来查解释，和语言无关
    var label: String
    var value: String
    var tint: Int? = nil       // 1 按涨色 / -1 按跌色
}

struct Detail {
    var name = ""
    var code = ""              // 代码，港美股后面带币种
    var statusText = ""        // 交易中 11:45 / 已收盘 美东 16:00
    var live = false
    var direction = 0
    var price = 0.0, prevClose = 0.0, open = 0.0, high = 0.0, low = 0.0
    var buy = 0.0, sell = 0.0  // 主动买 / 主动卖（外盘 / 内盘），都是 0 就不画
    var core: [Stat] = []      // 默认显示的指标
    var more: [Stat] = []      // 点「更多」才显示的指标
    var spark: [Double] = []
    var avg: [Double] = []     // 均价线，和 spark 一一对应；没有就是空
    var vols: [Double] = []    // 每分钟成交量，和 spark 一一对应
    var times: [String] = []   // 每分钟的时间 "0930"，和 spark 一一对应
    var chartNote: String?     // 走势图没数据时显示的一句话
    var sessions: [(Int, Int)] = []    // 交易时段，用来推算还没走到的时间
    var sparkTotal = 1         // 全天应有的分钟数，用来让走势线按时间铺开
}

/// 鼠标指到哪个指标，标题行就显示它的一句解释
func gloss(_ id: String) -> String? {
    switch id {
    case "open": return T("今天的开盘价", "Today's opening price")
    case "prev": return T("昨天的收盘价，涨跌幅按它算", "Yesterday's close. Change is measured from it")
    case "amount": return T("今天成交的总金额", "Total value traded today")
    case "turnover": return T("今天成交的股数占流通股的比例", "Share of the float traded today")
    case "#range": return T("横线是今天最低到最高，色块是开盘到现价", "Line: today's low to high. Block: open to now")
    case "#flow": return T("主动买入和主动卖出各占多少", "Buyer-initiated vs seller-initiated volume")
    default: return nil
    }
}

/// 拉拉队的右键气泡：像它说出来的一句话，右边一个小尖角指着它的脑袋；底色、字、悬停高亮和面板一致
final class BubbleView: NSView {
    var items: [(icon: String, text: String)] = [] { didSet { needsDisplay = true } }
    var onPick: ((Int) -> Void)?
    var theme = "dark" { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 11
    var tailY: CGFloat = 20                 // 尖角指向的高度（拉拉队脑袋的位置）
    var hover: Int? { didSet { if hover != oldValue { needsDisplay = true } } }
    var pressed: Int? { didSet { if pressed != oldValue { needsDisplay = true } } }      // 按下去还没松手的那一项
    static let tail: CGFloat = 6
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    private var font: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular) }
    var maxH: CGFloat = 0                   // 气泡最高能有多高（拉拉队那一块的高度）；放不下三行时把行压紧一点
    private var rowH: CGFloat { let full = ceil(fontSize * 1.85); return maxH > 0 && !items.isEmpty ? max(ceil(fontSize * 1.5), min(full, floor((maxH - 8) / CGFloat(rowsN)))) : full }       // 地方不够时把行压紧，但不压到字都挤在一起；再不够就让气泡往下多伸一点
    private var cap: CGFloat { min(ceil(fontSize * 1.28), rowH - 3) }        // 字母按键帽的边长
    private var ink: NSColor { theme == "light" ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.88, alpha: 1) }
    var selected: Int? { didSet { if selected != oldValue { needsDisplay = true } } }      // 当前所处的那一项（加油或休息）
    private var cols: Int { 1 }                                      // 四项排成一列
    private var rowsN: Int { (items.count + cols - 1) / cols }
    private var colW: CGFloat {
        let w = (items.map { ($0.text as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
        return ceil(6 + cap + 6 + w + 9)
    }
    func fittingSize() -> NSSize {
        NSSize(width: CGFloat(cols) * colW + 6 + BubbleView.tail, height: rowH * CGFloat(rowsN) + 8)
    }
    private func rowRect(_ i: Int) -> NSRect { NSRect(x: 3 + CGFloat(i % cols) * colW, y: 4 + CGFloat(i / cols) * rowH, width: colW, height: rowH) }
    /// 这个点（本视图坐标）落在第几项上
    func row(at p: NSPoint) -> Int? { items.indices.first { rowRect($0).contains(p) } }
    // 悬停不靠鼠标事件（气泡是在鼠标不动的时候冒出来的，收不到移动事件），由外面每帧按鼠标位置设 hover
    override func mouseDown(with event: NSEvent) { pressed = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { if pressed != nil, row(at: convert(event.locationInWindow, from: nil)) != pressed { pressed = nil } }
    override func mouseUp(with event: NSEvent) {
        let i = row(at: convert(event.locationInWindow, from: nil))
        guard let k = pressed, k == i else { pressed = nil; return }
        // 松手后那一项的按下效果多留一瞬再执行，看得出点中了
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in self?.pressed = nil; self?.onPick?(k) }
    }
    override func draw(_ dirtyRect: NSRect) {
        // 外形是一笔画成的：圆角和面板一样大，右边的小尖角是从边上平滑鼓出来的一个小弧，不是硬贴上去的三角
        let bodyW = bounds.width - BubbleView.tail, h = bounds.height, r: CGFloat = 7
        let ty = min(max(tailY, r + 7), h - r - 7), tw: CGFloat = 5.5, tip = bounds.width - 0.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: r, y: 0))
        path.appendArc(from: NSPoint(x: bodyW, y: 0), to: NSPoint(x: bodyW, y: r), radius: r)
        path.line(to: NSPoint(x: bodyW, y: ty - tw))
        path.curve(to: NSPoint(x: tip, y: ty), controlPoint1: NSPoint(x: bodyW, y: ty - tw * 0.45), controlPoint2: NSPoint(x: tip - 1.5, y: ty - 1.6))
        path.curve(to: NSPoint(x: bodyW, y: ty + tw), controlPoint1: NSPoint(x: tip - 1.5, y: ty + 1.6), controlPoint2: NSPoint(x: bodyW, y: ty + tw * 0.45))
        path.appendArc(from: NSPoint(x: bodyW, y: h), to: NSPoint(x: bodyW - r, y: h), radius: r)
        path.appendArc(from: NSPoint(x: 0, y: h), to: NSPoint(x: 0, y: h - r), radius: r)
        path.appendArc(from: NSPoint(x: 0, y: 0), to: NSPoint(x: r, y: 0), radius: r)
        path.close()
        (theme == "light" ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 0.08, alpha: 0.8)).setFill()
        path.fill()
        for (i, it) in items.enumerated() {
            let r = rowRect(i).insetBy(dx: 1, dy: 1), down = pressed == i, sel = selected == i, on = hover == i || down || sel
            // 三种状态各不一样：选中的（当前模式）一直有一层底；鼠标指着的再亮一点；按下去最深
            let bg: CGFloat = down ? 0.34 : (hover == i ? (sel ? 0.26 : 0.16) : (sel ? 0.18 : 0))
            if bg > 0 { ink.withAlphaComponent(bg).setFill(); NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill() }
            let tint = on ? ink : ink.withAlphaComponent(0.6)
            let box = NSRect(x: r.minX + 5, y: r.midY - cap / 2, width: cap, height: cap)
            if let letter = ["rest": "R", "cheer": "C", "hide": "H"][it.icon] {
                // 字母画成一个小键帽：一看就知道是可以按的键（休息 R、加油 C、隐藏 H）
                let key = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
                ink.withAlphaComponent(sel ? 0.85 : (on ? 0.2 : 0.1)).setFill(); key.fill()        // 选中的那一项键帽是实心的
                ink.withAlphaComponent(on ? 0.55 : 0.3).setStroke(); key.lineWidth = 1; key.stroke()
                let la: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize * 0.78, weight: .semibold), .foregroundColor: sel ? (theme == "light" ? NSColor(white: 1, alpha: 1) : NSColor(white: 0.12, alpha: 1)) : tint]
                let ls = (letter as NSString).size(withAttributes: la)
                (letter as NSString).draw(at: NSPoint(x: box.midX - ls.width / 2, y: box.midY - ls.height / 2), withAttributes: la)
            } else {                                            // 退出：电源符号，没有键帽（它没有快捷键）。叉留给看板的「收起」
                let k = fontSize * 0.32, g = NSBezierPath()
                g.appendArc(withCenter: NSPoint(x: box.midX, y: box.midY + 0.3), radius: k, startAngle: -50, endAngle: 230, clockwise: false)
                g.move(to: NSPoint(x: box.midX, y: box.midY - k - 0.5)); g.line(to: NSPoint(x: box.midX, y: box.midY))
                g.lineWidth = 1.2; g.lineCapStyle = .round
                tint.setStroke(); g.stroke()
            }
            let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: on ? ink : ink.withAlphaComponent(0.8)]
            let th = (it.text as NSString).size(withAttributes: a).height
            (it.text as NSString).draw(at: NSPoint(x: box.maxX + 7, y: r.midY - th / 2), withAttributes: a)
        }
    }
}

/// 窗口里的两块：上面右角站着拉拉队，下面是面板。收起时只剩拉拉队那一块，所以它在屏幕上的位置不动
final class StageView: NSView {
    var board: NSView?
    var mascot: NSView?
    var top: CGFloat = 0 { didSet { relayout() } }       // 面板上沿离窗口顶部多远（拉拉队的脚踩在这条线上）
    var side: CGFloat = 0 { didSet { relayout() } }      // 拉拉队那一块的边长
    var scale: CGFloat = 1 { didSet { relayout() } }     // 面板整体放大多少倍（拉拉队不跟着变，它有自己的大小设置）
    override var isFlipped: Bool { true }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); relayout() }
    func relayout() {
        mascot?.frame = NSRect(x: bounds.width - side, y: 0, width: side, height: side)
        board?.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        if let b = board { b.setBoundsSize(NSSize(width: b.frame.width / scale, height: b.frame.height / scale)) }     // 面板里面按原来的尺寸画，整体放大
    }
}

final class BoardView: NSView, NSTextFieldDelegate {
    // —— 页面（添加 / 菜单 / 引导）——
    var page: Page = .list
    var pageTitle = ""
    var pageRows: [PRow] = []
    var pageMinRows = 0                 // 至少留这么多行的高度，结果多少都不让小窗忽高忽低
    var pageFoot = ""                   // 页面底部的一句话
    var pageFootAccent = false
    var pageNav: [(String, () -> Void)] = []     // 页面底部右侧的文字按钮
    var pageDots: (Int, Int)?           // 引导的进度点：第几步 / 共几步
    /// 页面标题条右侧、关闭按钮左边的一个图标按钮（设置页的「恢复默认」）。armed 表示已点过一次、等确认
    var pageAction: (tip: String, armed: Bool, action: () -> Void)?
    var keySel = 0                      // 键盘选中的是第几个可点的行
    var onBack: (() -> Void)?
    /// 设置项的下拉列表：浮在那一行的值下面，盖住后面的行，不改变小窗高度
    struct Dropdown { var row: Int; var options: [String]; var current: Int; var anchor: NSPoint? = nil; var pick: (Int) -> Void }
    var dropdown: Dropdown? { didSet { needsDisplay = true } }
    var dropSel = 0
    private func dropGeometry() -> (box: NSRect, rows: [NSRect]) {
        guard let d = dropdown else { return (.zero, []) }
        let rowH = layout().rowH
        let w = max(72, (d.options.map { UI.width($0, font) }.max() ?? 0) + padX * 2 + 2)
        let h = rowH * CGFloat(d.options.count) + 6
        var x = bounds.width - 4 - w, y: CGFloat
        if let a = d.anchor {                    // 行的右键菜单：出现在鼠标点的地方
            x = min(max(a.x, 4), bounds.width - 4 - w); y = a.y
        } else {
            let L = pageLayout()
            guard d.row < L.rows.count else { return (.zero, []) }
            y = L.rows[d.row].maxY + 1
        }
        if y + h > bounds.height - 3 { y = bounds.height - 3 - h }       // 下面放不下就往上顶，始终留在小窗里
        y = max(3, y)
        let box = NSRect(x: x, y: y, width: w, height: h)
        return (box, d.options.indices.map { NSRect(x: box.minX, y: box.minY + 3 + CGFloat($0) * rowH, width: w, height: rowH) })
    }
    private func drawDropdown() {
        guard let d = dropdown else { return }
        let g = dropGeometry()
        let path = NSBezierPath(roundedRect: g.box, xRadius: 5, yRadius: 5)
        (cfg.theme == "light" ? NSColor(white: 0.94, alpha: 0.99) : NSColor(white: 0.17, alpha: 0.99)).setFill(); path.fill()
        dimColor.withAlphaComponent(0.35).setStroke(); path.lineWidth = 0.5; path.stroke()
        for (i, r) in g.rows.enumerated() {
            if i == dropSel {
                textColor.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 3, dy: 0), xRadius: 3, yRadius: 3).fill()
            }
            (d.options[i] as NSString).draw(at: NSPoint(x: r.minX + padX, y: r.minY), withAttributes: [.font: font, .foregroundColor: i == d.current ? textColor : dimColor])
        }
    }
    var onArrow: ((Int) -> Void)?       // 列表页按了 ↑(-1) / ↓(+1)
    var keyNav = false                  // 菜单 / 设置页里用过方向键：显示键盘选中的那一行
    override var acceptsFirstResponder: Bool { true }
    var onKey: ((String) -> Bool)?        // 外面想先接的按键（比如气泡开着时的 R / C）；返回 true 表示已经处理了
    override func keyDown(with event: NSEvent) {
        if let h = onKey, !event.modifierFlags.contains(.command), let ch = event.charactersIgnoringModifiers?.lowercased(), h(ch) { return }
        if let d = dropdown {        // 下拉列表开着：方向键在选项里移动
            switch event.keyCode {
            case 125: dropSel = (dropSel + 1) % d.options.count; needsDisplay = true
            case 126: dropSel = (dropSel + d.options.count - 1) % d.options.count; needsDisplay = true
            case 36, 76, 49: dropdown = nil; d.pick(dropSel)
            case 53: dropdown = nil
            default: break
            }
            return
        }
        let live = pageRows.filter { $0.action != nil }.count
        switch (event.keyCode, page) {
        case (125, .list): onArrow?(1)
        case (126, .list): onArrow?(-1)
        case (53, .list): onClickRow?(nil)                    // Esc：收起详情
        case (24, .list), (69, .list): keyZoom(0.6)           // = / +：放大走势图
        case (27, .list), (78, .list): keyZoom(1 / 0.6)       // -：缩小
        case (123, .list): keyPan(-1)                         // ← →：放大后左右挪
        case (124, .list): keyPan(1)
        case (29, .list): resetZoom()                         // 0：回到全天
        case (51, .list), (117, .list): if detail != nil { onRemove?() }     // 删除键：移除正在看的这只
        case (125, _): if live > 0 { keySel = keyNav ? (keySel + 1) % live : 0; keyNav = true; needsDisplay = true }
        case (126, _): if live > 0 { keySel = keyNav ? (keySel + live - 1) % live : live - 1; keyNav = true; needsDisplay = true }
        case (36, _), (76, _), (49, _): if keyNav, let i = keyRow { pageRows[i].action?() }     // 回车 / 空格：执行选中的那一行
        case (53, _): onBack?()
        default: super.keyDown(with: event)
        }
    }
    var onMenu: (() -> Void)?
    var onSearch: ((String) -> Void)?
    let searchField = NSTextField()
    private var hoverPRow: Int?
    private var hoverNav: Int?
    private var hoverBack = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        searchField.isBordered = false; searchField.drawsBackground = false; searchField.focusRingType = .none
        searchField.cell?.usesSingleLineMode = true; searchField.cell?.isScrollable = true
        searchField.delegate = self
        searchField.isHidden = true
        addSubview(searchField)
        allowedTouchTypes = [.indirect]            // 接收触控板上手指的原始位置
    }
    required init?(coder: NSCoder) { fatalError() }

    func ink(_ dir: Int) -> NSColor { color(for: dir) }       // 给外面画图例用
    var inkText: NSColor { textColor }
    var inkDim: NSColor { dimColor }

    var rows: [Row] = [] { didSet { layoutCache = nil } }
    var cfg = Config() { didSet { layoutCache = nil } }
    var detail: Detail?
    var selectedRow: Int?
    private var layoutCache: (widths: [CGFloat], gaps: [CGFloat], rowH: CGFloat)?
    var onHoverRow: ((Int?) -> Void)?   // 鼠标指到某一行：提前把它的分时数据拉好
    var status = ""                     // 标题条左侧：更新时间 / 断线 / 配置有误
    var expanded = false
    var mini = false                    // 收成一个笑脸
    var onHover: ((Bool) -> Void)?
    var onClickRow: ((Int?) -> Void)?
    var onToggleExpand: (() -> Void)?
    var onToggleMini: (() -> Void)?
    var onClose: (() -> Void)?
    var onQuit: (() -> Void)?           // 标题条第四个按钮（叉）：退出程序。叉在哪里都只表示退出，和拉拉队气泡里的一致
    var onAdd: (() -> Void)?
    var onContextMenu: ((Int?) -> Void)?
    var tabs: [String] = []             // 顶部的市场标签（只有一个市场时不显示）
    var tabIndex = 0
    var onSelectTab: ((Int) -> Void)?
    var greenUp = false                 // 这一页是不是绿涨红跌（美股页）
    private var hoverTab: Int?
    var showMore = false                // 详情里是否展开「更多」指标
    var onToggleMore: (() -> Void)?
    private var hint: String?           // 鼠标指着某个指标时，标题行显示的解释
    private var hoverToggle = false
    var onChartHover: ((Bool) -> Void)?       // 鼠标进了 / 出了走势图
    private var overChart = false
    var onRemove: (() -> Void)?
    var onReorder: ((Int, Int) -> Void)?     // 把第几行拖到了第几行
    private var dragFrom: Int?
    private var dragTo: Int?                 // 松手后插到第几行前面
    var onReorderTab: ((Int, Int) -> Void)?  // 把第几个市场标签拖到了第几个
    var onTabMenu: ((Int) -> Void)?          // 在第几个市场标签上点了右键
    private var tabDragFrom: Int?
    private var tabDragTo: Int?              // 松手后插到第几个标签前面
    private var tipReady = false        // 鼠标在同一行停够了时间，可以显示全名
    private var tipTimer: Timer?
    var debugRow: Int?                  // 调试用：固定显示某一行的悬停效果，不被真实鼠标冲掉
    func debugHover(row: Int) { debugRow = row; hoverRow = row; tipReady = true; needsDisplay = true }
    private var scrollY: CGFloat = 0    // 列表滚动了多少像素

    private let padX: CGFloat = 8, padY: CGFloat = 5, gap: CGFloat = 10
    private let headerTop: CGFloat = 5  // 标题条上方留白
    private let headerH: CGFloat = 16   // 顶部标题条：左边市场标签，右边四个按钮
    private let headerGap: CGFloat = 6  // 标题条和列表之间的空隙
    private let btnW: CGFloat = 18
    private let volH: CGFloat = 16      // 成交量柱的高度
    private let axisH: CGFloat = 11     // 时间刻度那一行
    private var zoom: (lo: Double, hi: Double)?   // 走势图当前显示的分钟范围，nil = 全天
    private var hoverSlot: Int?         // 鼠标在走势图上指着第几分钟
    private var resetRect = NSRect.zero
    private let sparkH: CGFloat = 46, pairGap: CGFloat = 8, colGap: CGFloat = 16
    let miniSize: CGFloat = 38
    var detailAlpha: CGFloat = 1        // 详情区的透明度，过渡动画用
    var pose = Pose() { didSet { stepSecondary() } }      // 啦啦队员现在的姿势
    // 跟随动作：花球和头不是钉死在手上、脖子上，而是被带着走，会慢半拍、甩过头再晃回来
    private var pomPos: [NSPoint] = []         // 两个花球现在在哪（以小人的 38 格为单位）
    private var pomVel: [NSPoint] = [.zero, .zero]
    private var headOff = NSPoint.zero         // 头相对脖子偏了多少
    private var headVel = NSPoint.zero
    private var lastHead: NSPoint?
    private var flutter: CGFloat = 0           // 花球穗子抖动的相位
    private var lastStep = 0.0
    var fixedStep: Double?                     // 调试用：离屏画连环画时每次姿势更新算多长时间

    /// 画的时候用的姿势：腿比原来短一点（胯以上整体往下放），显得更圆更可爱；脚的位置不变
    private let legCut: CGFloat = 0.9
    private var drawnPose: Pose { var q = pose; q.hop += legCut; return q }

    /// 手臂的三个点（肩、肘、手），以 38 格为单位
    private func armPoints(_ p: Pose) -> [(sh: NSPoint, elbow: NSPoint, h: NSPoint)] {
        let shoulder = NSPoint(x: 19 + p.lean, y: 17.4 + p.hop)
        let sides: [(CGFloat, CGFloat)] = [(-1.0, p.aL), (1.0, p.aR)]
        var out: [(sh: NSPoint, elbow: NSPoint, h: NSPoint)] = []
        for (side, deg) in sides {
            // 背手换花球时：手收到后腰，手肘往外撑开
            let a = (deg + (-78 - deg) * behind) * .pi / 180
            let full: CGFloat = 10.0 * (side < 0 ? 1 - 0.17 * emptyL : 1)      // 手臂伸直有多长；空着的那只手短一截（没有花球挡着，整条手臂露在外面会显得特别长）
            let reach = full - 4.9 * behind - 3.2 * p.tuck * (1 - behind)
            // 两个肩膀左右错开一点
            let sh = NSPoint(x: shoulder.x + side * 1.0, y: shoulder.y)
            let d = dig * side                       // 翻找时两只手反着动：一只往上够，另一只往下探
            var h = NSPoint(x: sh.x + side * cos(a) * reach, y: sh.y - sin(a) * reach + d * 0.5)
            // 手举到头边时花球挨着脸颊，但不盖到脸上
            let headC = NSPoint(x: 19 + p.lean * 1.25, y: 10.4 + p.hop), keep: CGFloat = 5.4 + 4.0
            let gx = h.x - headC.x, gy = h.y - headC.y, gd = max(hypot(gx, gy), 0.001)
            if gd < keep, behind < 0.01 {
                let ox = abs(gx) < 0.5 ? side : gx / gd, oy = abs(gx) < 0.5 ? -0.3 : gy / gd, on = hypot(ox, oy)
                h = NSPoint(x: headC.x + ox / on * keep, y: headC.y + oy / on * keep)
            }
            // 喝茶：右手把杯子举到嘴边
            if side > 0, sip > 0.001, behind < 0.01 {
                let mouth = NSPoint(x: headC.x + 3.9, y: headC.y + 5.4)
                h = NSPoint(x: h.x + (mouth.x - h.x) * sip, y: h.y + (mouth.y - h.y) * sip)
            }
            // 「嗯？」：右手抬到下巴旁边（花球挨着下颌，不盖住脸），手肘自然垂下去
            if side > 0, curious > 0.001, behind < 0.01 {
                let chin = NSPoint(x: headC.x + 6.0, y: headC.y + 6.6)
                h = NSPoint(x: h.x + (chin.x - h.x) * curious, y: h.y + (chin.y - h.y) * curious)
            }
            // 手肘：手离肩膀比臂长近多少，手肘就弯出去多少（朝下、朝外），所以收手时是弯的，伸直时是直的
            let ax: CGFloat = h.x - sh.x, ay: CGFloat = h.y - sh.y
            let al: CGFloat = max(hypot(ax, ay), 0.01)
            // 手肘一律朝外、略微朝下弯。不能按「垂直于手臂」来算：手垂在身侧时那个方向是朝上的，
            // 手肘会耸到肩膀上面去，手臂像从脖子横着长出来，还会蹭到头的下沿
            let nx: CGFloat = side * 0.92, ny: CGFloat = 0.39
            let slack: CGFloat = max(0, full * full - al * al)
            let bendOut: CGFloat = sqrt(slack) / 2 * 0.95 * (1 - behind)
            let sag: CGFloat = (0.5 + 1.2 * abs(cos(a))) * (1 - behind) * (1 - p.tuck)      // 伸直时也微微往下坠一点，不是直棍
            let ex: CGFloat = (sh.x + h.x) / 2 + nx * bendOut + side * (0.5 * sin(a) + (2.2 - d * 0.4) * behind)
            let ey: CGFloat = (sh.y + h.y) / 2 + ny * bendOut + sag + d * 0.35
            var elbow = NSPoint(x: ex, y: ey)
            // 举起的手臂如果贴着头的边缘过去，会把头的轮廓线盖掉一段：手肘往外弓，让整条手臂离头远一点
            if behind < 0.01 {
                let vx: CGFloat = h.x - sh.x, vy: CGFloat = h.y - sh.y
                let tt: CGFloat = min(max(((headC.x - sh.x) * vx + (headC.y - sh.y) * vy) / max(vx * vx + vy * vy, 0.01), 0.25), 1)
                let qx: CGFloat = sh.x + vx * tt - headC.x, qy: CGFloat = sh.y + vy * tt - headC.y
                let qd: CGFloat = max(hypot(qx, qy), 0.01), need: CGFloat = 5.4 + 2.3        // 手臂连描边有 1.9 宽：离头这么远才不会把头的轮廓线盖掉；再多就会弓成方方的 U 形
                if qd < need { elbow.x += qx / qd * (need - qd) * 1.25; elbow.y += qy / qd * (need - qd) * 1.25 }
            }
            out.append((sh, elbow, h))
        }
        return out
    }
    /// 花球该在的位置：平时在手上，抛起来时沿一条弧线离开手
    private func pomTargets(_ p: Pose) -> [NSPoint] {
        let arc = 4 * p.toss * (1 - p.toss)                          // 0 → 1 → 0 的抛物线
        return armPoints(p).enumerated().map { i, a in NSPoint(x: a.h.x + (i == 0 ? -1 : 1) * 1.0 * arc, y: a.h.y - 7 * arc) }
    }
    /// 姿势没变的那些帧也要让花球和头的弹簧接着走（不然定格、站定换花球时它们会卡在半路，等姿势再变才突然动一下）。
    /// 返回它们是不是还在动，还在动就需要重画
    var debugPomY: CGFloat { pomPos.count == 2 ? pomPos[0].y : -1 }      // 调试用：左边花球弹簧记的高度
    var debugPomTargetY: CGFloat { pomTargets(drawnPose)[0].y }
    func stepIdle() -> Bool {
        guard fixedStep == nil else { return false }
        stepSecondary()
        let moving = pomVel.contains { hypot($0.x, $0.y) > 0.15 } || hypot(headVel.x, headVel.y) > 0.15
        let off = pomPos.count == 2 ? zip(pomPos, pomTargets(drawnPose)).contains { hypot($0.x - $1.x, $0.y - $1.y) > 0.03 } : false
        return moving || off || (emptyL > 0 && emptyL < 1)
    }
    /// 花球和头按弹簧往该在的位置追一步（姿势每变一次、以及姿势不变的每一帧都会调）
    private func stepSecondary() {
        let now = CACurrentMediaTime()
        var dt = fixedStep ?? min(max(now - lastStep, 1.0 / 120), 1.0 / 15)
        emptyL += ((heldLeft ? 0 : 1) - emptyL) * CGFloat(min(1, dt * 9))        // 手里有没有花球之间是渐变的，手臂不会突然变长变短
        if abs(emptyL - (heldLeft ? 0 : 1)) < 0.01 { emptyL = heldLeft ? 0 : 1 }
        lastStep = now
        let targets = pomTargets(drawnPose), head = NSPoint(x: 19 + pose.lean * 1.25, y: 10.4 + pose.hop)
        if pomPos.count != 2 { pomPos = targets; lastHead = head; return }
        if behind > 0.02 {                         // 背手换花球时花球牢牢握在手里，不晃；同时记住手的速度，交还给弹簧的那一刻才不会突然顿住
            let h = CGFloat(max(dt, 1.0 / 120))
            pomVel = zip(targets, pomPos).map { NSPoint(x: ($0.x - $1.x) / h, y: ($0.y - $1.y) / h) }
            pomPos = targets; lastHead = head; return
        }
        let headMove = NSPoint(x: head.x - (lastHead ?? head).x, y: head.y - (lastHead ?? head).y)
        lastHead = head
        headOff.x -= headMove.x * 0.5; headOff.y -= headMove.y * 0.5          // 身子一动，头先留在原地一点，再追上来
        while dt > 0 {
            let h = CGFloat(min(dt, 1.0 / 120)); dt -= 1.0 / 120
            for i in 0..<2 {                                   // 花球：弹一点，甩过头再晃回来
                let w: CGFloat = 24, z: CGFloat = 0.42
                pomVel[i].x += (w * w * (targets[i].x - pomPos[i].x) - 2 * z * w * pomVel[i].x) * h
                pomVel[i].y += (w * w * (targets[i].y - pomPos[i].y) - 2 * z * w * pomVel[i].y) * h
                pomPos[i].x += pomVel[i].x * h; pomPos[i].y += pomVel[i].y * h
                let dx = pomPos[i].x - targets[i].x, dy = pomPos[i].y - targets[i].y, d = hypot(dx, dy), lim: CGFloat = 1.4
                if d > lim { pomPos[i] = NSPoint(x: targets[i].x + dx / d * lim, y: targets[i].y + dy / d * lim) }      // 花球是握在手里的，不会甩太远
            }
            let w: CGFloat = 30, z: CGFloat = 0.5              // 头：轻轻点一下
            headVel.x += (-w * w * headOff.x - 2 * z * w * headVel.x) * h; headVel.y += (-w * w * headOff.y - 2 * z * w * headVel.y) * h
            headOff.x += headVel.x * h; headOff.y += headVel.y * h
            // 头只许轻轻点一下：往上、往旁边偏多了，头和肩膀之间会露出一小截带黑边的脖子，动起来就是脖子的线条忽隐忽现
            headOff.x = min(max(headOff.x, -0.45), 0.45); headOff.y = min(max(headOff.y, -0.2), 0.7)
            flutter += h * 34 * min(1, (hypot(pomVel[0].x, pomVel[0].y) + hypot(pomVel[1].x, pomVel[1].y)) / 30)
        }
    }
    var zFade: CGFloat = 1              // 睡着时 z 的淡入程度
    var facing = false                  // 鼠标停在它身上：转过来面对你，脚尖朝前
    var onBoard = false                 // 站在展开的面板上沿：脚下不用再画那道横线
    var behind: CGFloat = 0             // 换花球：手背到身后的程度（0 没有，1 完全背过去，花球收在身后看不见）
    var dig: CGFloat = 0                // 在身后翻找：-1…1，两只手一上一下
    // 「隐藏」相关：它走开时整个人往旁边平移、淡掉；扔下的那个花球单独画
    var offsetX: CGFloat = 0            // 整个人往右挪了多少（38 格）
    var fade: CGFloat = 1               // 整个人的不透明度（0 = 已经走掉）
    var heldLeft = true                 // 左手里还有没有花球
    private var emptyL: CGFloat = 0     // 左手空着的程度（0 拿着花球，1 空手）。空着的手画得短一点：没有花球挡着，整条手臂露在外面会显得特别长
    var loosePom: NSPoint?              // 扔在地上的那个花球在哪（38 格）
    var loosePomRot: CGFloat = 0
    var isAway = false                  // 它不在，只剩花球：点花球叫它回来
    var cup = false                     // 喝茶休息：右手拿的是杯子，不是花球
    var frown: CGFloat = 0              // 被拖着走时有点不高兴的程度：嘴从横线微微张成扁扁的小 o；眼睛眉毛不变
    var sip: CGFloat = 0                // 杯子举到嘴边的程度（0 端在胸前，1 在嘴边）
    var thumb: CGFloat = 0              // 左手比赞的程度（0 没有，1 完全比出来）
    var steam: CGFloat = 0              // 热气飘到哪了（0–1 循环），和睡觉的 z 一样是随时间往上飘的
    var pillHot = false                 // 鼠标指着脚下那块板
    var passBelow: CGFloat?             // 这条线以下的点击不归它管，让给下面的看板（它和看板上沿重叠的那一小条）
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let y = passBelow, let sv = superview, convert(point, from: sv).y >= y { return nil }
        return super.hitTest(point)
    }
    var onReturn: (() -> Void)?
    private var uu: CGFloat { min(bounds.width, bounds.height) / 38 }
    /// 脚下那块板：收起后的面板就缩在这儿，点它展开
    var pillRect: NSRect { NSRect(x: 11.5 * uu, y: 32.4 * uu, width: 15 * uu, height: 3.4 * uu) }
    var loosePomRect: NSRect { let c = loosePom ?? loosePomSpot; return NSRect(x: (c.x - 4.2) * uu, y: (c.y - 4.2) * uu, width: 8.4 * uu, height: 8.4 * uu) }
    /// 左手现在在哪（38 格），扔花球时从这儿出手
    var leftHand: NSPoint { armPoints(drawnPose)[0].h }
    private var pomAccent: NSColor {
        switch cfg.pomColor {
        case "red": return NSColor(red: 0.90, green: 0.45, blue: 0.42, alpha: 1)
        case "green": return NSColor(red: 0.42, green: 0.74, blue: 0.53, alpha: 1)
        case "yellow": return NSColor(red: 0.90, green: 0.74, blue: 0.36, alpha: 1)
        case "blue": return NSColor(red: 0.42, green: 0.62, blue: 0.95, alpha: 1)
        case "white": return NSColor(white: 0.93, alpha: 1)
        default: return cfg.color ? color(for: 1) : NSColor(white: 0.93, alpha: 1)          // 跟随当前这一页的涨色：A 股、港股红，美股绿
        }
    }
    var curious: CGFloat = 0            // 鼠标停在它身上时的「嗯？」：0 没有，1 完全摆好（一只手抬到下巴边、头边冒个问号）
    var fold: CGFloat?                  // 面板正在收成拉拉队脚下那道横线：0 刚开始，1 收完；nil = 没在收
    var foldScale: CGFloat = 1          // 面板整体放大的倍数
    var foldTop: CGFloat = 76           // 面板上沿离窗口顶多远（拉拉队不站在面板上时是 0）
    var foldSide: CGFloat = 88          // 拉拉队那一块的边长，用来算横线最后落在哪
    var gaze = NSPoint.zero             // 眼睛往哪边看（-1…1）：鼠标停在它身上时看向鼠标
    private var stableW: [Bool: CGFloat] = [:]   // 每种模式用过的最大宽度，只增不减，避免数字位数变化时抖动
    private var stableSig = ""
    private var hoverRow: Int?          // 鼠标所在的行，用来高亮提示可点击
    private var hoverBtn: Int?          // 鼠标指着第几个按钮
    private var downAt: NSPoint?
    private var dragging = false
    private var fitCache: [String: String] = [:]

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var listTop: CGFloat { headerTop + headerH + headerGap }
    private var tabFont: NSFont { .monospacedDigitSystemFont(ofSize: max(CGFloat(cfg.fontSize) - 1, 8), weight: .regular) }
    private var smallFont: NSFont { .monospacedDigitSystemFont(ofSize: max(CGFloat(cfg.fontSize) - 2.5, 7), weight: .regular) }

    /// 按钮从左往右：添加、设置、收起、退出（退出只在面板上没有拉拉队时才有；有拉拉队时退出在它的气泡里）
    private var btnCount: Int { cfg.miniStyle == "face" ? 4 : 3 }      // 面板上有拉拉队时是三个，没有时多一个「退出」
    private func btnRect(_ i: Int) -> NSRect {
        let right = bounds.width - 5
        return NSRect(x: right - btnW * CGFloat(btnCount - i), y: headerTop, width: btnW, height: headerH)     // 等宽、等距
    }
    private func buttonAt(_ p: NSPoint) -> Int? { (0..<btnCount).first { btnRect($0).contains(p) } }
    private func tabRect(_ i: Int) -> NSRect {
        var x = padX - 5
        for k in 0..<i { x += UI.width(tabs[k], tabFont) + 12 }
        return NSRect(x: x, y: headerTop, width: UI.width(tabs[i], tabFont) + 12, height: headerH)
    }
    private func tabAt(_ p: NSPoint) -> Int? { tabs.count > 1 ? tabs.indices.first { tabRect($0).contains(p) } : nil }
    private var btnTips: [String] { [T("添加", "Add"), T("设置", "Settings"), T("收起看板", "Collapse"), T("退出", "Quit")] }

    // 列表：最多显示 maxVisibleRows 行，多的滚动
    private var visibleRows: Int { max(1, min(rows.count, cfg.maxVisibleRows)) }
    private func listHeight(_ rowH: CGFloat) -> CGFloat { rowH * CGFloat(visibleRows) }
    private func maxScroll(_ rowH: CGFloat) -> CGFloat { max(0, rowH * CGFloat(rows.count) - listHeight(rowH)) }
    private func listRect() -> NSRect { NSRect(x: 0, y: listTop, width: bounds.width, height: listHeight(layout().rowH)) }
    private func rowAt(_ p: NSPoint) -> Int? {
        guard listRect().contains(p) else { return nil }
        let i = Int(floor((p.y - listTop + scrollY) / layout().rowH))
        return (0..<rows.count).contains(i) ? i : nil
    }
    /// 把某一行滚到看得见的位置
    func reveal(row: Int) {
        let rowH = layout().rowH
        let top = CGFloat(row) * rowH
        if top < scrollY { scrollY = top }
        if top + rowH > scrollY + listHeight(rowH) { scrollY = top + rowH - listHeight(rowH) }
        scrollY = min(max(0, scrollY), maxScroll(rowH))
        needsDisplay = true
    }

    // 自己区分「拖动」和「点击」：移动超过 3px 算拖窗口，否则算点击
    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow; dragging = false
        dragFrom = (page == .list && !mini && dropdown == nil) ? rowAt(convert(event.locationInWindow, from: nil)) : nil
        dragTo = nil
        tabDragFrom = (page == .list && !mini && dropdown == nil) ? tabAt(convert(event.locationInWindow, from: nil)) : nil
        tabDragTo = nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let d = downAt else { return }
        let p = event.locationInWindow
        if !dragging, abs(p.x - d.x) <= 3, abs(p.y - d.y) <= 3 { return }
        if tabDragFrom != nil, tabs.count > 1 {       // 拖市场标签：调整标签的顺序
            dragging = true
            let x = convert(p, from: nil).x
            let t = tabs.indices.filter { tabRect($0).midX < x }.count
            if t != tabDragTo { tabDragTo = t; needsDisplay = true }
            return
        }
        if dragFrom != nil, rows.count > 1 {          // 在列表里拖：调整顺序
            dragging = true
            let y = convert(p, from: nil).y
            let t = Int(((y - listTop + scrollY) / layout().rowH).rounded())
            let clamped = min(max(t, 0), rows.count)
            if clamped != dragTo { dragTo = clamped; needsDisplay = true }
            return
        }
        if !dragging { dragging = true; window?.performDrag(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        if let from = dragFrom, let to = dragTo, dragging {
            dragFrom = nil; dragTo = nil; needsDisplay = true
            if to != from, to != from + 1 { onReorder?(from, to > from ? to - 1 : to) }
            return
        }
        dragFrom = nil; dragTo = nil
        if let from = tabDragFrom, let to = tabDragTo, dragging {
            tabDragFrom = nil; tabDragTo = nil; needsDisplay = true
            if to != from, to != from + 1 { onReorderTab?(from, to > from ? to - 1 : to) }
            return
        }
        tabDragFrom = nil; tabDragTo = nil
        guard downAt != nil, !dragging else { return }
        if mini, isAway {
            let q = convert(event.locationInWindow, from: nil)
            if loosePomRect.contains(q) { onReturn?() }                       // 点花球：它走回来
            else if !onBoard, pillRect.insetBy(dx: -3, dy: -3).contains(q) { onToggleMini?() }      // 点脚下那块板：展开看板
            return
        }
        if mini { onToggleMini?(); return }
        let p = convert(event.locationInWindow, from: nil)
        if let d = dropdown {         // 下拉列表开着：点选项就选，点别处就收起
            let i = dropGeometry().rows.firstIndex { $0.contains(p) }
            dropdown = nil
            if let i = i { d.pick(i) }
            return
        }
        if page != .list {
            if p.y < listTop {
                if let a = pageAction, btnRect(btnCount - 2).contains(p) { a.action() }
                else if btnRect(btnCount - 1).contains(p) { onToggleMini?() }
                else if backRect.contains(p) { onBack?() }
                return
            }
            let L = pageLayout()
            if let i = L.nav.firstIndex(where: { $0.contains(p) }) { pageNav[i].1(); return }
            if let i = L.rows.firstIndex(where: { $0.contains(p) }), let a = pageRows[i].action { a() }
            return
        }
        if let b = buttonAt(p) {
            [onAdd, onMenu, onToggleMini, onQuit][b]?()
            return
        }
        if let t = tabAt(p) { if t != tabIndex { onSelectTab?(t) }; return }
        if p.y < listTop { return }                       // 标题条空白处：只用来拖动
        if let L = detailLayout() {
            if L.all.insetBy(dx: 0, dy: -3).contains(p) {
                if zoom != nil, resetRect.contains(p) { resetZoom() }
                else if event.clickCount == 2 { toggleZoom() }
                return
            }
            if let t = L.toggle, t.contains(p) { onToggleMore?(); return }
        }
        if let i = rowAt(p) {
            if event.clickCount >= 2 { return }           // 双击不当成「开了又关」
            onClickRow?(i)                                // 再点一次已展开的那一行就是收起
        }
    }

    /// 文字太长就截断加省略号，保证不把小窗撑宽
    private func fit(_ s: String, maxW: CGFloat) -> String {
        let key = "\(s)|\(maxW)|\(cfg.fontSize)"
        if let c = fitCache[key] { return c }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var out = s
        if (s as NSString).size(withAttributes: attrs).width > maxW {
            var chars = Array(s)
            while chars.count > 1, ((String(chars) + "…") as NSString).size(withAttributes: attrs).width > maxW { chars.removeLast() }
            out = String(chars) + "…"
        }
        if fitCache.count > 200 { fitCache.removeAll() }
        fitCache[key] = out
        return out
    }
    private var maxLabelW: CGFloat { CGFloat(cfg.fontSize) * 7 }
    private func cellText(_ c: Cell, _ ci: Int) -> String { ci == 0 && !c.whole ? fit(c.text, maxW: maxLabelW) : c.text }

    private var dimColor: NSColor { textColor.withAlphaComponent(0.55) }

    private var font: NSFont { .monospacedDigitSystemFont(ofSize: CGFloat(cfg.fontSize), weight: .regular) }

    private var textColor: NSColor {
        switch cfg.theme {
        case "light": return NSColor(white: 0.15, alpha: 1)
        case "none": return NSColor(white: 0.5, alpha: 1)
        default: return NSColor(white: 0.88, alpha: 1)
        }
    }

    private func color(for d: Int) -> NSColor {
        guard cfg.color, d != 0 else { return textColor }
        let dir = greenUp ? -d : d
        return dir > 0 ? NSColor(red: 0.85, green: 0.42, blue: 0.40, alpha: 1)
                       : NSColor(red: 0.40, green: 0.70, blue: 0.50, alpha: 1)
    }

    private func layout() -> (widths: [CGFloat], gaps: [CGFloat], rowH: CGFloat) {
        if let c = layoutCache { return c }
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var widths: [CGFloat] = [], gaps: [CGFloat] = []
        for r in rows {
            for (i, c) in r.cells.enumerated() {
                let w = ceil((cellText(c, i) as NSString).size(withAttributes: attrs).width)
                if i >= widths.count {
                    widths.append(w)
                    gaps.append(c.dim && !c.right ? 4 : gap)   // 「开」「高」这类小标签紧贴后面的数值
                } else { widths[i] = max(widths[i], w) }
            }
        }
        let r = (widths, gaps, ceil(font.ascender - font.descender + font.leading) + 3)
        layoutCache = r
        return r
    }

    private func naturalListWidth(_ widths: [CGFloat], _ gaps: [CGFloat]) -> CGFloat {
        widths.reduce(0, +) + gaps.dropLast().reduce(0, +) + padX * 2
    }

    /// 详情区里每一块的位置。画图、算高度、判断鼠标指着什么，都用这一份，保证三者一致
    private struct DL {
        var titleY: CGFloat = 0
        var spark = NSRect.zero, vol = NSRect.zero, all = NSRect.zero
        var range: NSRect?
        var flow: NSRect?
        var stats: [(rect: NSRect, stat: Stat)] = []
        var toggle: NSRect?
        var bottom: CGFloat = 0
    }
    private func detailLayout(width: CGFloat? = nil) -> DL? {
        guard let d = detail, !mini else { return nil }
        let rowH = layout().rowH
        let cw = (width ?? bounds.width) - padX * 2
        var L = DL()
        var y = listTop + listHeight(rowH) + 7
        L.titleY = y; y += rowH
        L.spark = NSRect(x: padX, y: y, width: cw, height: sparkH)
        L.vol = NSRect(x: padX, y: L.spark.maxY + 4, width: cw, height: volH)
        L.all = L.spark.union(L.vol)
        y = L.vol.maxY + 2 + axisH + 5
        if d.high > d.low, d.low > 0 { L.range = NSRect(x: padX, y: y, width: cw, height: rowH); y += rowH }
        if d.buy + d.sell > 0 { L.flow = NSRect(x: padX, y: y, width: cw, height: rowH); y += rowH }
        y += 2
        let colW = (cw - colGap) / 2
        func grid(_ stats: [Stat]) {
            for (i, st) in stats.enumerated() {
                L.stats.append((NSRect(x: padX + CGFloat(i % 2) * (colW + colGap), y: y + CGFloat(i / 2) * rowH, width: colW, height: rowH), st))
            }
            y += rowH * CGFloat((stats.count + 1) / 2)
        }
        grid(d.core)
        if !d.more.isEmpty {
            if showMore { grid(d.more) }
            L.toggle = NSRect(x: padX, y: y, width: cw, height: 12)      // 底部居中的小箭头，像抽屉把手
            y += 12
            L.bottom = y + 2
        } else {
            L.bottom = y + padY
        }
        return L
    }

    /// 小窗应有的大小。宽度在同一种模式下固定：列表和详情共用一个宽度，切换股票不会变宽变窄
    func size(withDetail: Bool) -> NSSize {
        if mini { let m: CGFloat = cfg.miniStyle == "face" ? miniSize : (["s": 68, "l": 112][cfg.mascotSize] ?? 88); return NSSize(width: m, height: m) }
        if page != .list {
            let w = max(ceil(CGFloat(cfg.fontSize) * 21), stableW[false] ?? 0)
            return NSSize(width: w, height: pageLayout(width: w).bottom)
        }
        let (widths, gaps, rowH) = layout()
        let sig = cfg.stocks.joined(separator: ",") + "|\(cfg.fontSize)|\(cfg.label)"
        if sig != stableSig { stableSig = sig; stableW = [:] }
        let w = max(naturalListWidth(widths, gaps), ceil(CGFloat(cfg.fontSize) * 21), stableW[expanded] ?? 0)
        stableW[expanded] = w
        scrollY = min(scrollY, maxScroll(rowH))
        var h = listTop + listHeight(rowH) + padY
        if withDetail, let L = detailLayout(width: w) { h = L.bottom }
        return NSSize(width: w, height: h)
    }

    // MARK: 页面（添加 / 菜单 / 引导）

    private var backRect: NSRect { NSRect(x: 0, y: headerTop, width: padX + 12 + UI.width(pageTitle, tabFont) + 8, height: headerH) }
    private func textH(_ t: String, _ w: CGFloat, _ f: NSFont) -> CGFloat {
        ceil((t as NSString).boundingRect(with: NSSize(width: w, height: 1000), options: [.usesLineFragmentOrigin], attributes: [.font: f]).height)
    }
    private struct PL { var field = NSRect.zero; var rows: [NSRect] = []; var footY: CGFloat = 0; var nav: [NSRect] = []; var bottom: CGFloat = 0 }
    private func pageLayout(width: CGFloat? = nil) -> PL {
        let rowH = layout().rowH
        let W = width ?? bounds.width, cw = W - padX * 2
        var L = PL()
        var y = listTop
        if page == .add { L.field = NSRect(x: padX, y: y, width: cw, height: rowH + 2); y += rowH + 2 + 5 }
        for r in pageRows {
            var h = rowH
            if r.sep { h = 7 }
            else if r.wrap { h = max(textH(r.text, cw - (r.art != nil ? 40 : 0), font) + 5, r.art != nil ? 26 : 0) }
            L.rows.append(NSRect(x: 0, y: y, width: W, height: h)); y += h
        }
        if pageRows.count < pageMinRows { y += rowH * CGFloat(pageMinRows - pageRows.count) }
        if !pageFoot.isEmpty || !pageNav.isEmpty || pageDots != nil {
            y += 5; L.footY = y
            var x = W - padX + 5
            for (t, _) in pageNav.reversed() {
                let w = UI.width(t, tabFont) + 12
                x -= w
                L.nav.insert(NSRect(x: x, y: y, width: w, height: rowH + 2), at: 0)
                x -= 2
            }
            y += rowH + 2
        }
        L.bottom = y + padY
        return L
    }
    /// 可点的行里第 keySel 个，对应 pageRows 的下标
    private var keyRow: Int? {
        let live = pageRows.indices.filter { pageRows[$0].action != nil }
        return live.isEmpty ? nil : live[min(max(keySel, 0), live.count - 1)]
    }

    private func drawPage() {
        let rowH = layout().rowH
        let L = pageLayout()
        let headMid = headerTop + headerH / 2
        // 标题条：左边「‹ 页面名」点一下返回，右边一个 × 也是返回
        let back = NSBezierPath(); let bx = padX + 3
        back.move(to: NSPoint(x: bx + 2, y: headMid - 3.5)); back.line(to: NSPoint(x: bx - 2, y: headMid)); back.line(to: NSPoint(x: bx + 2, y: headMid + 3.5))
        back.lineWidth = 1.2; back.lineCapStyle = .round; back.lineJoinStyle = .round
        (hoverBack ? textColor : dimColor).setStroke(); back.stroke()
        (pageTitle as NSString).draw(at: NSPoint(x: padX + 12, y: headMid - (tabFont.ascender - tabFont.descender) / 2 - 0.5),
                                     withAttributes: [.font: tabFont, .foregroundColor: textColor])
        if let a = pageAction {           // 恢复默认：一个转回去的箭头；指着它或等确认时，左边显示一句话
            let r = btnRect(btnCount - 2), on = hoverBtn == btnCount - 2 || a.armed
            if on { textColor.withAlphaComponent(a.armed ? 0.24 : 0.16).setFill(); NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 0), xRadius: 4, yRadius: 4).fill() }
            let c = NSPoint(x: r.midX, y: headMid + 0.3), rad: CGFloat = 3.5
            // 逆时针回转的箭头：从正上方出发，经右、下、左绕大半圈，停在左上方，末端的箭头指回顶部
            let arc = NSBezierPath()
            func ap(_ deg: CGFloat) -> NSPoint { NSPoint(x: c.x - rad * cos(deg * .pi / 180), y: c.y + rad * sin(deg * .pi / 180)) }   // 水平镜像，所以是逆时针
            var first = true
            for d in stride(from: CGFloat(-60), through: 215, by: 11) { first ? arc.move(to: ap(d)) : arc.line(to: ap(d)); first = false }
            let tip = ap(-60)                                    // 箭头画在起点：缺口右边，指向缺口
            arc.move(to: NSPoint(x: tip.x + 2.7, y: tip.y - 0.2)); arc.line(to: tip); arc.line(to: NSPoint(x: tip.x + 0.3, y: tip.y + 2.7))
            arc.lineWidth = 1.2; arc.lineCapStyle = .round; arc.lineJoinStyle = .round
            (on ? textColor : dimColor).setStroke(); arc.stroke()
            if on {
                let t = a.tip as NSString
                let ta: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: textColor.withAlphaComponent(0.85)]
                let tw = t.size(withAttributes: ta).width
                t.draw(at: NSPoint(x: r.minX - 5 - tw, y: headMid - (smallFont.ascender - smallFont.descender) / 2 - 0.5), withAttributes: ta)
            }
        }
        let cr = btnRect(btnCount - 1)
        if hoverBtn == btnCount - 1 { textColor.withAlphaComponent(0.16).setFill(); NSBezierPath(roundedRect: cr.insetBy(dx: 1, dy: 0), xRadius: 4, yRadius: 4).fill() }
        // 页面右上角是「收起」（和列表页的收起同一个图标：叉）；回上一页用左上角的箭头
        let x = NSBezierPath(); let c = NSPoint(x: cr.midX, y: headMid), k: CGFloat = 3.5
        x.move(to: NSPoint(x: c.x - k, y: c.y - k)); x.line(to: NSPoint(x: c.x + k, y: c.y + k))
        x.move(to: NSPoint(x: c.x + k, y: c.y - k)); x.line(to: NSPoint(x: c.x - k, y: c.y + k))
        x.lineWidth = 1.2; x.lineCapStyle = .round; x.lineJoinStyle = .round
        (hoverBtn == btnCount - 1 ? textColor : dimColor).setStroke(); x.stroke()

        // 搜索行：放大镜 + 输入框 + 底下一条细线，不另外套框
        if page == .add {
            let f = L.field
            dimColor.setStroke()
            let g = NSBezierPath(ovalIn: NSRect(x: f.minX + 1, y: f.midY - 4, width: 6.5, height: 6.5))
            g.move(to: NSPoint(x: f.minX + 6.6, y: f.midY + 1.7)); g.line(to: NSPoint(x: f.minX + 9.2, y: f.midY + 4.3))
            g.lineWidth = 1.1; g.lineCapStyle = .round; g.stroke()
            dimColor.withAlphaComponent(0.35).setFill()
            NSRect(x: f.minX, y: f.maxY + 1, width: f.width, height: 1).fill()
        }
        let kr = page == .add || keyNav ? keyRow : nil
        for (i, r) in pageRows.enumerated() {
            let rect = L.rows[i]
            if r.sep {
                dimColor.withAlphaComponent(0.3).setFill()
                NSRect(x: padX, y: rect.midY, width: rect.width - padX * 2, height: 1).fill()
                continue
            }
            if r.action != nil, hoverPRow == i || kr == i {
                textColor.withAlphaComponent(hoverPRow == i ? 0.10 : 0.07).setFill()
                NSBezierPath(roundedRect: NSRect(x: 3, y: rect.minY - (r.wrap ? 0 : 1), width: rect.width - 6, height: rect.height), xRadius: 3, yRadius: 3).fill()
            }
            var tx = padX + r.indent
            if r.check == true {        // 选中的行：和列表里展开的那一行同一种底色
                textColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(roundedRect: NSRect(x: 3, y: rect.minY - 1, width: rect.width - 6, height: rect.height), xRadius: 3, yRadius: 3).fill()
            }
            if let art = r.art { art(NSRect(x: tx, y: rect.minY + 3, width: 32, height: rect.height - 8)); tx += 40 }
            let f: NSFont = r.bold ? .monospacedDigitSystemFont(ofSize: CGFloat(cfg.fontSize), weight: .semibold) : font
            let col = r.dim ? dimColor : textColor
            var rightW: CGFloat = 0
            if !r.right.isEmpty {
                let ra: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: r.rightAccent ? color(for: 1) : dimColor]
                rightW = ceil((r.right as NSString).size(withAttributes: ra).width)
                (r.right as NSString).draw(at: NSPoint(x: rect.maxX - padX - rightW, y: rect.minY), withAttributes: ra)
                rightW += 8
            }
            let ps = NSMutableParagraphStyle()
            ps.lineBreakMode = r.wrap ? .byWordWrapping : .byTruncatingTail
            (r.text as NSString).draw(with: NSRect(x: tx, y: rect.minY, width: rect.maxX - padX - rightW - tx, height: rect.height),
                                      options: [.usesLineFragmentOrigin], attributes: [.font: f, .foregroundColor: col, .paragraphStyle: ps])
        }
        // 底部：进度点 / 一句提示，右边是文字按钮
        if L.footY > 0 {
            let y = L.footY
            dimColor.withAlphaComponent(0.3).setFill()
            NSRect(x: padX, y: y - 2.5, width: bounds.width - padX * 2, height: 1).fill()
            var fx = padX
            if let (cur, total) = pageDots {
                for i in 0..<total {
                    textColor.withAlphaComponent(i == cur ? 0.9 : 0.25).setFill()
                    NSBezierPath(ovalIn: NSRect(x: fx + CGFloat(i) * 8, y: y + (rowH + 2) / 2 - 2, width: 4, height: 4)).fill()
                }
                fx += CGFloat(total) * 8 + 4
            }
            let navLeft = L.nav.first?.minX ?? bounds.width - padX
            if !pageFoot.isEmpty {
                let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
                (pageFoot as NSString).draw(in: NSRect(x: fx, y: y + 2.5, width: navLeft - fx - 4, height: rowH),
                                            withAttributes: [.font: smallFont, .foregroundColor: pageFootAccent ? textColor : dimColor, .paragraphStyle: ps])
            }
            for (i, r) in L.nav.enumerated() {
                let last = i == L.nav.count - 1
                if hoverNav == i { textColor.withAlphaComponent(0.16).setFill(); NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 0), xRadius: 4, yRadius: 4).fill() }    // 和标题条按钮同款悬停底
                let t = pageNav[i].0 as NSString
                let a: [NSAttributedString.Key: Any] = [.font: tabFont, .foregroundColor: last || hoverNav == i ? textColor : dimColor]
                t.draw(at: NSPoint(x: r.midX - t.size(withAttributes: a).width / 2, y: r.midY - (tabFont.ascender - tabFont.descender) / 2 - 0.5), withAttributes: a)
            }
        }
        drawDropdown()
    }

    /// 进入 / 离开「添加」页时摆好输入框
    func placeSearchField() {
        searchField.isHidden = page != .add
        guard page == .add else { return }
        searchField.font = font; searchField.textColor = textColor
        searchField.placeholderAttributedString = NSAttributedString(string: T("名称、拼音首字母或代码", "Name or ticker"),
            attributes: [.font: font, .foregroundColor: textColor.withAlphaComponent(0.35)])
        let f = pageLayout().field
        let h = ceil(font.ascender - font.descender) + 3
        searchField.frame = NSRect(x: f.minX + 13, y: f.minY + (f.height - h) / 2 + 0.5, width: f.width - 14, height: h)
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); placeSearchField() }

    func controlTextDidChange(_ obj: Notification) { keySel = 0; onSearch?(searchField.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        let n = pageRows.filter { $0.action != nil }.count
        switch sel {
        case #selector(NSResponder.moveDown(_:)): if n > 0 { keySel = (keySel + 1) % n; needsDisplay = true }; return true
        case #selector(NSResponder.moveUp(_:)): if n > 0 { keySel = (keySel + n - 1) % n; needsDisplay = true }; return true
        case #selector(NSResponder.insertNewline(_:)): if let i = keyRow { pageRows[i].action?() }; return true
        case #selector(NSResponder.cancelOperation(_:)): onBack?(); return true
        default: return false
        }
    }

    // MARK: 走势图

    func resetZoom() { zoom = nil; hoverSlot = nil; hint = nil; needsDisplay = true }

    private func chartGeometry() -> (spark: NSRect, vol: NSRect, all: NSRect)? {
        detailLayout().map { ($0.spark, $0.vol, $0.all) }
    }

    private func totalSlots(_ d: Detail) -> Double { Double(max(d.sparkTotal, d.spark.count) - 1) }
    private func visibleRange(_ d: Detail) -> (lo: Double, hi: Double) { zoom ?? (0, totalSlots(d)) }

    /// 第 i 分钟对应的时间（分钟数）。有数据用数据里的，没有的（还没走到的时段）A 股按交易时间推算
    private func slotMinutes(_ d: Detail, _ i: Int) -> Int? {
        if i >= 0, i < d.times.count, d.times[i].count == 4, let v = Int(d.times[i]) { return v / 100 * 60 + v % 100 }
        var k = i
        for (a, b) in d.sessions where k >= 0 {
            if k <= b - a { return a + k }
            k -= b - a + 1
        }
        return nil
    }
    private func clock(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    private func zoomBy(_ factor: Double, atX x: CGFloat) {
        guard let d = detail, let g = chartGeometry() else { return }
        let total = totalSlots(d)
        let (lo, hi) = visibleRange(d)
        let span = hi - lo
        let newSpan = min(max(span * factor, 10), total)          // 最多放大到 10 分钟
        if factor >= 1, newSpan >= total - 0.5 { zoom = nil; needsDisplay = true; return }
        if factor < 1, zoom == nil, total - newSpan < 0.01 { return }
        let anchor = lo + Double((x - g.all.minX) / g.all.width) * span   // 以鼠标所在的时间点为中心
        var nlo = anchor - (anchor - lo) * newSpan / span
        nlo = min(max(nlo, 0), total - newSpan)
        zoom = (nlo, nlo + newSpan)
        needsDisplay = true
    }

    private func panBy(_ slots: Double) {
        guard let d = detail, let z = zoom else { return }
        let span = z.hi - z.lo
        let nlo = min(max(z.lo + slots, 0), totalSlots(d) - span)
        zoom = (nlo, nlo + span)
        needsDisplay = true
    }

    /// 鼠标（屏幕坐标换成本视图坐标）是不是在走势图上
    func chartPoint() -> NSPoint? {
        guard let w = window, w.isVisible, page == .list, let g = chartGeometry() else { return nil }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        return g.all.insetBy(dx: 0, dy: -3).contains(p) ? p : nil
    }
    /// 滚动缩放 / 平移。返回 true 表示这次滚动被走势图用掉了
    func chartScroll(dx: Double, dy: Double, precise: Bool) -> Bool {
        guard let p = chartPoint(), let d = detail, let g = chartGeometry() else { return false }
        if abs(dy) >= abs(dx) {
            zoomBy(exp(-dy * (precise ? 0.03 : 0.2)), atX: p.x)       // 上滑放大，下滑缩小
        } else {
            let (lo, hi) = visibleRange(d)
            panBy(-dx * (precise ? 1 : 8) / Double(g.all.width) * (hi - lo))
        }
        return true
    }

    override func scrollWheel(with event: NSEvent) {
        glog("scroll dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY) precise=\(event.hasPreciseScrollingDeltas) phase=\(event.phase.rawValue) onChart=\(chartGeometry().map { $0.all.insetBy(dx: 0, dy: -3).contains(convert(event.locationInWindow, from: nil)) } ?? false)")
        if page != .list { return }
        let p = convert(event.locationInWindow, from: nil)
        if !mini, listRect().contains(p), maxScroll(layout().rowH) > 0 {      // 在列表上滚动：翻看更多股票
            let rowH = layout().rowH
            let dy = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : rowH)
            scrollY = min(max(scrollY - dy, 0), maxScroll(rowH))
            needsDisplay = true
            updateHover(event)
            return
        }
        guard let g = chartGeometry(), let d = detail, g.all.insetBy(dx: 0, dy: -3).contains(p) else { super.scrollWheel(with: event); return }
        _ = chartScroll(dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY), precise: event.hasPreciseScrollingDeltas)
        updateHover(event)
    }

    /// 捏合手势没直接发到小窗时（小窗所在的应用不在前台），从全局监听转过来：鼠标在走势图上就缩放
    func externalMagnify(_ magnification: CGFloat) {
        glog("magnify(global) m=\(magnification)")
        guard let w = window, page == .list else { return }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        guard let g = chartGeometry(), g.all.insetBy(dx: 0, dy: -3).contains(p) else { return }
        zoomBy(exp(-Double(magnification) * 1.6), atX: p.x)
    }
    /// 一键放大 / 恢复：全天时放大到鼠标附近的一小时，已放大则回到全天
    func toggleZoom() {
        if zoom != nil { resetZoom(); return }
        guard let p = chartPoint(), let d = detail else { return }
        zoomBy(60 / max(totalSlots(d), 60), atX: p.x)
    }
    /// 键盘缩放和平移：以图的中间为准
    func keyZoom(_ factor: Double) { if let g = chartGeometry() { zoomBy(factor, atX: g.all.midX) } }
    func keyPan(_ dir: Double) { if let d = detail { let (lo, hi) = visibleRange(d); panBy(dir * (hi - lo) * 0.25) } }

    // 系统的捏合事件在这个小窗上收不到（日志里一次都没有），所以直接读触控板上手指的位置，自己算两指间距的变化
    private var pinchDist: CGFloat?
    private func twoFingerDistance(_ event: NSEvent) -> CGFloat? {
        let ts = Array(event.touches(matching: .touching, in: self))
        guard ts.count == 2 else { return nil }
        let a = ts[0].normalizedPosition, b = ts[1].normalizedPosition
        return hypot(a.x - b.x, a.y - b.y)
    }
    override func touchesBegan(with event: NSEvent) { pinchDist = twoFingerDistance(event) }
    override func touchesEnded(with event: NSEvent) { pinchDist = twoFingerDistance(event) }
    override func touchesCancelled(with event: NSEvent) { pinchDist = nil }
    override func touchesMoved(with event: NSEvent) {
        guard let d = twoFingerDistance(event) else { pinchDist = nil; return }
        guard let last = pinchDist, last > 0.02, d > 0.02 else { pinchDist = d; return }
        let ratio = last / d                       // 两指张开：间距变大，比值小于 1，放大
        guard abs(ratio - 1) > 0.012, let p = chartPoint() else { return }     // 两指同向滑动时间距基本不变，不会误触发
        pinchDist = d
        glog(String(format: "pinch(touch) ratio=%.3f", ratio))
        zoomBy(Double(pow(ratio, 1.6)), atX: p.x)
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        glog("magnify(view) m=\(event.magnification)")
        let p = convert(event.locationInWindow, from: nil)
        guard let g = chartGeometry(), g.all.insetBy(dx: 0, dy: -3).contains(p) else { return }
        zoomBy(exp(-Double(event.magnification) * 1.6), atX: p.x)      // 张开放大，捏合缩小
        updateHover(event)
    }

    private func drawDetail(_ d: Detail, rowH: CGFloat) {
        guard let L = detailLayout() else { return }
        let g = (spark: L.spark, vol: L.vol, all: L.all)
        let contentW = bounds.width - padX * 2
        let small = smallFont
        dimColor.withAlphaComponent(0.3).setFill()
        NSRect(x: padX, y: L.titleY - 4, width: contentW, height: 1).fill()

        // 标题行有三种内容：鼠标在图上 → 那一分钟的时间 价格 涨跌幅；指着某个指标 → 大白话解释；平时 → 名称 代码 + 市场状态
        let titleY = L.titleY
        let tail = NSMutableParagraphStyle(); tail.lineBreakMode = .byTruncatingTail
        if let hs = hoverSlot, hs < d.spark.count, d.prevClose > 0 {
            (fit(d.name, maxW: contentW * 0.4) as NSString).draw(at: NSPoint(x: padX, y: titleY), withAttributes: [.font: font, .foregroundColor: dimColor])
            let v = d.spark[hs], pct = (v - d.prevClose) / d.prevClose * 100
            let t = slotMinutes(d, hs).map(clock) ?? ""
            let txt = "\(t)  \(fmt(v))  " + String(format: "%+.2f%%", pct) as NSString
            let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(for: pct > 0.0001 ? 1 : (pct < -0.0001 ? -1 : 0))]
            txt.draw(at: NSPoint(x: padX + contentW - txt.size(withAttributes: a).width, y: titleY), withAttributes: a)
        } else if let h = hint {
            (h as NSString).draw(in: NSRect(x: padX, y: titleY + 1.5, width: contentW, height: rowH),
                                 withAttributes: [.font: small, .foregroundColor: textColor.withAlphaComponent(0.85), .paragraphStyle: tail])
        } else {
            let sa: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: d.live ? textColor.withAlphaComponent(0.85) : dimColor]
            let sw = ceil((d.statusText as NSString).size(withAttributes: sa).width)
            (d.statusText as NSString).draw(at: NSPoint(x: padX + contentW - sw, y: titleY + 1.5), withAttributes: sa)
            if d.live {      // 正在交易：前面点一个小圆点
                color(for: 1).withAlphaComponent(0.9).setFill()
                NSBezierPath(ovalIn: NSRect(x: padX + contentW - sw - 8, y: titleY + rowH / 2 - 3.5, width: 4, height: 4)).fill()
            }
            let left = contentW - sw - 16
            let nameW = min(ceil((d.name as NSString).size(withAttributes: [.font: font]).width), left * 0.62)
            (d.name as NSString).draw(in: NSRect(x: padX, y: titleY, width: nameW, height: rowH),
                                      withAttributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: tail])
            (d.code as NSString).draw(in: NSRect(x: padX + nameW + 6, y: titleY + 1.5, width: max(0, left - nameW - 6), height: rowH),
                                      withAttributes: [.font: small, .foregroundColor: dimColor, .paragraphStyle: tail])
        }

        let (lo, hi) = visibleRange(d)
        let span = max(hi - lo, 1)
        func px(_ i: Double) -> CGFloat { g.all.minX + CGFloat((i - lo) / span) * g.all.width }

        // 时间刻度：根据当前范围挑一个合适的间隔，图里画淡竖线，图下标时间
        let interval = [5, 10, 15, 30, 60, 120].first { span / Double($0) <= 4.5 } ?? 120
        let la: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: dimColor]
        var lastMaxX = -CGFloat.infinity
        for i in max(0, Int(ceil(lo)))...max(0, Int(floor(hi))) {
            guard let m = slotMinutes(d, i), m % interval == 0 else { continue }
            let x = px(Double(i))
            dimColor.withAlphaComponent(0.16).setFill()
            NSRect(x: x, y: g.spark.minY, width: 0.5, height: g.all.height).fill()
            let label = clock(m) as NSString
            let lw = label.size(withAttributes: la).width
            let lx = min(max(x - lw / 2, g.all.minX), g.all.maxX - lw)
            if lx > lastMaxX + 4 {
                label.draw(at: NSPoint(x: lx, y: g.vol.maxY + 1), withAttributes: la)
                lastMaxX = lx + lw
            }
        }

        let i0 = max(0, Int(floor(lo))), i1 = min(d.spark.count - 1, Int(ceil(hi)))
        if d.spark.count > 1, i0 <= i1 {
            // 纵轴按可见区间撑满：放大后波形会跟着变大
            let hasAvg = d.avg.count == d.spark.count
            var vmin = d.spark[i0...i1].min()!, vmax = d.spark[i0...i1].max()!
            if hasAvg { vmin = min(vmin, d.avg[i0...i1].min()!); vmax = max(vmax, d.avg[i0...i1].max()!) }
            if zoom == nil, d.prevClose > 0 { vmin = min(vmin, d.prevClose); vmax = max(vmax, d.prevClose) }
            if vmax - vmin < 0.0001 { vmax += 0.01; vmin -= 0.01 }
            func py(_ v: Double) -> CGFloat { g.spark.maxY - 1 - CGFloat((v - vmin) / (vmax - vmin)) * (g.spark.height - 2) }

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: g.all).addClip()
            if d.prevClose >= vmin, d.prevClose <= vmax {       // 昨收参考线
                let base = NSBezierPath()
                base.move(to: NSPoint(x: g.all.minX, y: py(d.prevClose))); base.line(to: NSPoint(x: g.all.maxX, y: py(d.prevClose)))
                base.setLineDash([2, 3], count: 2, phase: 0); base.lineWidth = 0.5
                dimColor.withAlphaComponent(0.4).setStroke(); base.stroke()
            }
            if hasAvg {          // 均价线：比价格线细、颜色偏黄，看盘软件的通行画法
                let al = NSBezierPath()
                for i in i0...i1 {
                    let p = NSPoint(x: px(Double(i)), y: py(d.avg[i]))
                    i == i0 ? al.move(to: p) : al.line(to: p)
                }
                al.lineWidth = 0.8; al.lineJoinStyle = .round
                (cfg.color ? NSColor(red: 0.86, green: 0.72, blue: 0.36, alpha: 0.85) : dimColor).setStroke(); al.stroke()
            }
            let line = NSBezierPath()
            for i in i0...i1 {
                let p = NSPoint(x: px(Double(i)), y: py(d.spark[i]))
                i == i0 ? line.move(to: p) : line.line(to: p)
            }
            line.lineWidth = 1; line.lineJoinStyle = .round
            color(for: d.direction).withAlphaComponent(0.9).setStroke(); line.stroke()

            // 分时成交量柱：这一分钟价格比上一分钟高（或持平）算涨色，低算跌色
            if d.vols.count == d.spark.count, let vm = d.vols[i0...i1].max(), vm > 0 {
                let bw = max(g.all.width / CGFloat(span + 1) - 0.4, 0.5)
                for i in i0...i1 where d.vols[i] > 0 {
                    let prev = i == 0 ? d.prevClose : d.spark[i - 1]
                    let bh = max(CGFloat(d.vols[i] / vm) * g.vol.height, 0.5)
                    color(for: d.spark[i] >= prev ? 1 : -1).withAlphaComponent(0.85).setFill()
                    NSRect(x: px(Double(i)) - bw / 2, y: g.vol.maxY - bh, width: bw, height: bh).fill()
                }
            }
            // 十字线
            if let hs = hoverSlot, hs >= i0, hs <= i1 {
                let x = px(Double(hs))
                textColor.withAlphaComponent(0.45).setFill()
                NSRect(x: x - 0.25, y: g.all.minY, width: 0.5, height: g.all.height).fill()
                textColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 2, y: py(d.spark[hs]) - 2, width: 4, height: 4)).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if d.spark.count <= 1, let note = d.chartNote {
            let ns = (note as NSString).size(withAttributes: la)
            (note as NSString).draw(at: NSPoint(x: g.spark.midX - ns.width / 2, y: g.spark.midY - ns.height / 2), withAttributes: la)
        }

        // 放大后右上角出现「恢复」，点一下回到全天
        if zoom != nil {
            let txt = T("全天", "All day") as NSString
            let a: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: textColor]
            let ts = txt.size(withAttributes: a)
            resetRect = NSRect(x: g.spark.maxX - ts.width - 8, y: g.spark.minY, width: ts.width + 8, height: ts.height + 3)
            (cfg.theme == "light" ? NSColor(white: 0.85, alpha: 0.95) : NSColor(white: 0.28, alpha: 0.95)).setFill()
            NSBezierPath(roundedRect: resetRect, xRadius: 3, yRadius: 3).fill()
            txt.draw(at: NSPoint(x: resetRect.minX + 4, y: resetRect.minY + 1), withAttributes: a)
        } else {
            resetRect = .zero
        }

        // 今日区间条：横线 = 最低到最高，色块 = 开盘到现价（其实就是一根横着放的 K 线），小竖线 = 昨收
        if let r = L.range {
            let lt = T("低 ", "L ") as NSString, ht = T(" 高", " H") as NSString
            let lv = fmt(d.low) as NSString, hv = fmt(d.high) as NSString
            let da: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dimColor]
            let va: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            var x = r.minX
            lt.draw(at: NSPoint(x: x, y: r.minY), withAttributes: da); x += lt.size(withAttributes: da).width
            lv.draw(at: NSPoint(x: x, y: r.minY), withAttributes: va); x += lv.size(withAttributes: va).width
            let hvw = hv.size(withAttributes: va).width, htw = ht.size(withAttributes: da).width
            hv.draw(at: NSPoint(x: r.maxX - htw - hvw, y: r.minY), withAttributes: va)
            ht.draw(at: NSPoint(x: r.maxX - htw, y: r.minY), withAttributes: da)
            let x0 = x + 9, x1 = r.maxX - htw - hvw - 9, cy = r.minY + rowH / 2 - 1
            if x1 - x0 > 20 {
                func bx(_ v: Double) -> CGFloat { x0 + CGFloat((min(max(v, d.low), d.high) - d.low) / (d.high - d.low)) * (x1 - x0) }
                dimColor.withAlphaComponent(0.55).setFill()
                NSRect(x: x0, y: cy - 0.5, width: x1 - x0, height: 1).fill()
                if d.open > 0, d.price > 0 {
                    let a = min(bx(d.open), bx(d.price)), b = max(bx(d.open), bx(d.price))
                    color(for: d.direction).setFill()
                    NSBezierPath(roundedRect: NSRect(x: a, y: cy - 2.5, width: max(b - a, 2), height: 5), xRadius: 1, yRadius: 1).fill()
                }
                if d.prevClose >= d.low, d.prevClose <= d.high {
                    dimColor.setFill(); NSRect(x: bx(d.prevClose) - 0.5, y: cy - 5, width: 1, height: 10).fill()
                }
                if d.price > 0 { textColor.setFill(); NSBezierPath(ovalIn: NSRect(x: bx(d.price) - 2.5, y: cy - 2.5, width: 5, height: 5)).fill() }
            }
        }
        // 买卖力道条：主动买 vs 主动卖
        if let r = L.flow {
            let total = d.buy + d.sell
            let bt = String(format: T("买 %.0f%%", "Buy %.0f%%"), d.buy / total * 100) as NSString, st = String(format: T("%.0f%% 卖", "%.0f%% Sell"), d.sell / total * 100) as NSString
            let ba: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(for: 1)]
            let sa2: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(for: -1)]
            bt.draw(at: NSPoint(x: r.minX, y: r.minY), withAttributes: ba)
            let stw = st.size(withAttributes: sa2).width
            st.draw(at: NSPoint(x: r.maxX - stw, y: r.minY), withAttributes: sa2)
            let x0 = r.minX + bt.size(withAttributes: ba).width + 9, x1 = r.maxX - stw - 9, cy = r.minY + rowH / 2 - 1
            if x1 - x0 > 20 {
                let mid = x0 + (x1 - x0) * CGFloat(d.buy / total)
                color(for: 1).withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: NSRect(x: x0, y: cy - 2, width: max(mid - x0 - 1, 1), height: 4), xRadius: 1.5, yRadius: 1.5).fill()
                color(for: -1).withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: NSRect(x: mid + 1, y: cy - 2, width: max(x1 - mid - 1, 1), height: 4), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        // 指标格子
        for (r, st) in L.stats {
            (st.label as NSString).draw(at: NSPoint(x: r.minX, y: r.minY), withAttributes: [.font: font, .foregroundColor: dimColor])
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: st.tint.map { color(for: $0) } ?? textColor]
            let vw = (st.value as NSString).size(withAttributes: attrs).width
            (st.value as NSString).draw(at: NSPoint(x: r.maxX - vw, y: r.minY), withAttributes: attrs)
        }
        // 底部小箭头：朝下 = 还有更多指标，朝上 = 收起
        if let r = L.toggle {
            if hoverToggle {
                textColor.withAlphaComponent(0.10).setFill()
                NSBezierPath(roundedRect: NSRect(x: r.midX - 16, y: r.minY, width: 32, height: r.height), xRadius: 4, yRadius: 4).fill()
            }
            let ch = NSBezierPath(); let cx = r.midX, cy = r.midY, sgn: CGFloat = showMore ? -1 : 1
            ch.move(to: NSPoint(x: cx - 5, y: cy - sgn * 2)); ch.line(to: NSPoint(x: cx, y: cy + sgn * 2)); ch.line(to: NSPoint(x: cx + 5, y: cy - sgn * 2))
            ch.lineWidth = 1.2; ch.lineCapStyle = .round; ch.lineJoinStyle = .round
            (hoverToggle ? textColor : dimColor).setStroke(); ch.stroke()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let t = fold { drawFold(t); return }
        if mini, cfg.miniStyle != "face" {       // 啦啦队员没有底色，像桌宠一样直接站在桌面上
            drawCheer()
            return
        }
        if cfg.theme != "none" {
            (cfg.theme == "light" ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 0.08, alpha: 0.8)).setFill()
            let r: CGFloat = mini ? miniSize / 2 : 7
            NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill()
        }
        if mini { drawFace(); return }
        if page != .list { drawPage(); return }
        let (widths, gaps, rowH) = layout()

        // 标题条：左边状态，右边 更多列 / 收成笑脸 / 退出
        var sx = padX
        let headMid = headerTop + headerH / 2
        func baseline(_ f: NSFont) -> CGFloat { headMid - (f.ascender - f.descender) / 2 - 0.5 }      // 让文字和按钮图标对齐在同一条水平线上
        if tabs.count > 1 {       // 市场标签：当前页亮一点，下面一条短线
            for (i, t) in tabs.enumerated() {
                let r = tabRect(i)
                let on = i == tabIndex
                let a: [NSAttributedString.Key: Any] = [.font: tabFont, .foregroundColor: on || hoverTab == i ? textColor : dimColor]
                (t as NSString).draw(at: NSPoint(x: r.minX + 6, y: baseline(tabFont)), withAttributes: a)
                if on { textColor.withAlphaComponent(0.8).setFill(); NSRect(x: r.minX + 6, y: r.maxY, width: r.width - 12, height: 1).fill() }
                sx = r.maxX + 4
            }
        }
        if let to = tabDragTo, dragging, tabs.count > 1 {        // 拖标签时：一条竖线标出松手后会插到哪
            let x = to < tabs.count ? tabRect(to).minX + 2 : tabRect(tabs.count - 1).maxX - 2
            textColor.setFill(); NSRect(x: x - 0.75, y: headerTop + 1, width: 1.5, height: headerH - 1).fill()
        }
        let statusW = btnRect(0).minX - sx - 6
        if statusW > 20 {
            let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
            ps.alignment = tabs.count > 1 ? .right : .left
            var a: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: dimColor, .paragraphStyle: ps]
            let r = NSRect(x: sx, y: baseline(smallFont), width: statusW, height: headerH)
            if let b = hoverBtn { a[.foregroundColor] = textColor.withAlphaComponent(0.8); (btnTips[b] as NSString).draw(in: r, withAttributes: a) }
            else { (status as NSString).draw(in: r, withAttributes: a) }
        }
        // 四个按钮：图标都画在同样大的 7×7 格子里，中心在同一条水平线上
        for i in 0..<btnCount {
            let r = btnRect(i)
            if hoverBtn == i {
                textColor.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 0), xRadius: 4, yRadius: 4).fill()
            }
            (hoverBtn == i ? textColor : dimColor).setStroke()
            let c = NSPoint(x: r.midX, y: headMid), k: CGFloat = 3.5
            let path = NSBezierPath()
            switch i {
            case 0:     // 添加
                path.move(to: NSPoint(x: c.x - k, y: c.y)); path.line(to: NSPoint(x: c.x + k, y: c.y))
                path.move(to: NSPoint(x: c.x, y: c.y - k)); path.line(to: NSPoint(x: c.x, y: c.y + k))
            case 1:     // 设置：两条滑杆，各带一个旋钮
                for (dy, kx) in [(-2.2, 1.6), (2.2, -1.6)] as [(CGFloat, CGFloat)] {
                    path.move(to: NSPoint(x: c.x - k - 0.5, y: c.y + dy)); path.line(to: NSPoint(x: c.x + kx - 1.5, y: c.y + dy))
                    path.move(to: NSPoint(x: c.x + kx + 1.5, y: c.y + dy)); path.line(to: NSPoint(x: c.x + k + 0.5, y: c.y + dy))
                    path.appendOval(in: NSRect(x: c.x + kx - 1.4, y: c.y + dy - 1.4, width: 2.8, height: 2.8))
                }
            case 2:     // 收起：一个叉。看板的「关」就是收到拉拉队脚下，不是退出程序
                path.move(to: NSPoint(x: c.x - k, y: c.y - k)); path.line(to: NSPoint(x: c.x + k, y: c.y + k))
                path.move(to: NSPoint(x: c.x + k, y: c.y - k)); path.line(to: NSPoint(x: c.x - k, y: c.y + k))
            default:    // 退出：电源符号（叉已经是「收起」了，不能两个意思共用）
                path.appendArc(withCenter: c, radius: k, startAngle: -50, endAngle: 230, clockwise: false)
                path.move(to: NSPoint(x: c.x, y: c.y - k - 0.6)); path.line(to: NSPoint(x: c.x, y: c.y - 0.4))
            }
            path.lineWidth = 1.2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.stroke()
        }

        if let d = detail, detailAlpha > 0.01, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setAlpha(detailAlpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            drawDetail(d, rowH: rowH)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        // 列表区：只画看得见的行，超出的靠滚动
        let lr = NSRect(x: 0, y: listTop - 1, width: bounds.width, height: listHeight(rowH) + 2)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: lr).addClip()
        func rowY(_ i: Int) -> CGFloat { listTop + CGFloat(i) * rowH - scrollY }
        if let h = hoverRow, h < rows.count, !(detail != nil && h == selectedRow) {
            textColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: rowY(h) - 1, width: bounds.width - 6, height: rowH), xRadius: 3, yRadius: 3).fill()
        }
        if let s = selectedRow, detail != nil, s < rows.count {
            textColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: NSRect(x: 3, y: rowY(s) - 1, width: bounds.width - 6, height: rowH), xRadius: 3, yRadius: 3).fill()
        }
        // 小窗比列表本身宽时，多出来的空隙放在名称和数值之间：名称贴左，数值贴右
        let extra = max(0, bounds.width - naturalListWidth(widths, gaps))
        for (ri, r) in rows.enumerated() {
            let y = rowY(ri)
            if y + rowH < lr.minY || y > lr.maxY { continue }
            var x = padX
            for (ci, c) in r.cells.enumerated() {
                if ci == 1 { x += extra }
                var col: NSColor = c.tint ? color(for: r.direction) : (c.dim ? dimColor : textColor)
                if dragTo != nil, ri == dragFrom { col = col.withAlphaComponent(0.35) }
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col]
                let text = cellText(c, ci) as NSString
                let w = text.size(withAttributes: attrs).width
                text.draw(at: NSPoint(x: x + (c.right ? widths[ci] - w : 0), y: y), withAttributes: attrs)
                x += widths[ci] + gaps[ci]
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        // 名称被省略的行：鼠标指着时，在它上面浮出全名
        if tipReady, let h = hoverRow, h < rows.count, let c0 = rows[h].cells.first, !c0.whole, cellText(c0, 0) != c0.text {
            let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let tw = min(ceil((c0.text as NSString).size(withAttributes: a).width), bounds.width - 20)
            let ty = max(1, rowY(h) - rowH - 3)          // 统一浮在这一行的正上方；第一行则盖在标题条上
            let box = NSRect(x: 4, y: ty, width: tw + 10, height: rowH + 2)
            let bp = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
            (cfg.theme == "light" ? NSColor(white: 0.94, alpha: 0.99) : NSColor(white: 0.2, alpha: 0.99)).setFill(); bp.fill()
            dimColor.withAlphaComponent(0.35).setStroke(); bp.lineWidth = 0.5; bp.stroke()
            let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
            var a2 = a; a2[.paragraphStyle] = ps
            (c0.text as NSString).draw(in: NSRect(x: box.minX + 5, y: box.minY + 1, width: tw, height: rowH), withAttributes: a2)
        }
        // 拖动排序：一条横线标出松手后会落在哪
        if let t = dragTo {
            textColor.withAlphaComponent(0.9).setFill()
            NSRect(x: 4, y: listTop + CGFloat(t) * rowH - scrollY - 1.5, width: bounds.width - 8, height: 2).fill()
        }
        drawDropdown()
        // 滚动条：有更多行时在右边画一小段
        let ms = maxScroll(rowH)
        if ms > 0 {
            let lh = listHeight(rowH)
            let barH = max(10, lh * lh / (rowH * CGFloat(rows.count)))
            textColor.withAlphaComponent(0.35).setFill()
            NSBezierPath(roundedRect: NSRect(x: bounds.width - 3.5, y: listTop + (lh - barH) * scrollY / ms, width: 2, height: barH),
                         xRadius: 1, yRadius: 1).fill()
        }
    }

    /// 收起的过程：面板不是一下子消失，底板一边缩一边变成拉拉队脚下那道横线
    private func drawFold(_ e: CGFloat) {
        // 面板可能整体放大了：这一段按屏幕上的点来画，才能和拉拉队脚下的横线对上
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        let zoom = NSAffineTransform(); zoom.scale(by: 1 / foldScale); zoom.concat()
        let bw = bounds.width * foldScale, bh = bounds.height * foldScale
        let u = foldSide / 38, sw = pow(u, 0.85), top = foldTop
        // 终点：小人脚下那块板（和 pillRect 同一个位置），颜色就是面板的底色，所以只变形状
        let outerEnd = NSRect(x: bw - foldSide + 11.5 * u, y: 32.4 * u - top, width: 15 * u, height: 3.4 * u)
        func m(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
        let r = NSRect(x: m(0, outerEnd.minX), y: m(0, outerEnd.minY), width: m(bw, outerEnd.width), height: m(bh, outerEnd.height))
        let rad = min(m(7, r.height / 2), r.height / 2)
        _ = sw
        (cfg.theme == "light" ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 0.08, alpha: cfg.theme == "none" ? 0 : 0.8)).setFill()
        NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad).fill()
    }

    /// 收起后的啦啦队员：和标题条图标同一套笔画的小符号（像终端里的 \o/）。
    /// 没有底色，直接站在桌面上；线条外面有一圈很淡的反色描边，深色浅色桌面上都看得清。
    private func drawCheer() {
        let u = uu, sw = pow(u, 0.85)
        if !onBoard {
            // 脚下那块板：就是收起来的看板，颜色和面板一样，点它展开；鼠标指着时亮一点
            let r = pillRect, path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
            (cfg.theme == "light" ? NSColor(white: 1, alpha: 0.85) : NSColor(white: 0.08, alpha: 0.8)).setFill(); path.fill()
            if pillHot { (cfg.theme == "light" ? NSColor(white: 0.15, alpha: 0.16) : NSColor(white: 0.88, alpha: 0.22)).setFill(); path.fill() }
        }
        if fade > 0.01, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.translateBy(x: offsetX * u, y: 0)
            if fade < 0.99 { ctx.setAlpha(fade); ctx.beginTransparencyLayer(auxiliaryInfo: nil) }
            drawCheerPass(1)
            if fade < 0.99 { ctx.endTransparencyLayer() }
            ctx.restoreGState()
        }
        if let c = loosePom {                // 扔在地上的那个花球
            let star = NSBezierPath()
            for k in 0..<3 {
                let a = CGFloat(k) * .pi / 3 + loosePomRot
                star.move(to: NSPoint(x: (c.x - cos(a) * 2.8) * u, y: (c.y - sin(a) * 2.8) * u)); star.line(to: NSPoint(x: (c.x + cos(a) * 2.8) * u, y: (c.y + sin(a) * 2.8) * u))
            }
            star.lineCapStyle = .round
            star.lineWidth = 3.5 * sw; NSColor(white: 0.17, alpha: 1).setStroke(); star.stroke()
            star.lineWidth = 2.0 * sw; pomAccent.setStroke(); star.stroke()
        }
    }

    private func drawCheerPass(_ pass: Int) {
        let u = min(bounds.width, bounds.height) / 38
        let p = drawnPose
        let lift = min(pose.hop, 0)                                    // 跳起来时整个人离地；下蹲时脚不动
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * u, y: y * u) }
        let light = false                              // 小人永远是白线加深色描边，不随浅色主题变黑
        let ink = light ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        // 描边是不透明的深灰：每个部件画自己的描边再画本体，前面的部件能完整压住后面的；
        // 因为不透明，重叠的地方也不会叠出更深的颜色
        let halo = NSColor(white: 0.17, alpha: 1)
        let accent = pomAccent
        // 线宽不跟着大小等比放大：小号时线要相对粗一点才看得清，大号时相对细一点才不笨重
        let sw = pow(u, 0.85)
        func stroke(_ path: NSBezierPath, _ w: CGFloat, _ color: NSColor) {
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.lineWidth = (w + 1.5) * sw; halo.setStroke(); path.stroke()
            path.lineWidth = w * sw; color.setStroke(); path.stroke()
        }
        // 脚下一道短横线，像终端里的光标；人跳起来时它留在原地
        let ground = NSBezierPath(); ground.move(to: pt(13.5, 33.4)); ground.line(to: pt(24.5, 33.4))
        _ = ground                                   // 脚下那块板在外层画（drawCheer），这里不再画横线

        // 不穿衣服，就是线条小人。比例上躯干短、腿长：肩膀紧挨着头，胯在身体中间偏上，不会显得脖子一根到底
        let hipY = 21.6 + p.hop, shoulder = pt(19 + p.lean, 17.4 + p.hop)
        let body = NSBezierPath()
        body.move(to: pt(19 + p.lean, 14.4 + p.hop)); body.line(to: pt(19, hipY))                 // 躯干（顶上伸进头里一点，头晃的时候脖子不会断）
        for (side, footLift) in [(-1.0, p.liftL), (1.0, p.liftR)] as [(CGFloat, CGFloat)] {
            let ax = 19 + side * p.leg, ay = 30.4 + lift + footLift
            let airborne = lift + footLift < -0.4          // 离地时脚尖往下压，落地时脚掌放平
            // 脚尖默认朝前（画面里是斜着朝下的一小段）；只有两脚叉得很开的马步、大跳才朝外
            let wide = p.leg > 5.0
            let ft: CGFloat = airborne ? (wide ? 0.75 : 0.9) : (wide ? 0.6 : 1.0)
            let fl: CGFloat = 1.7
            body.move(to: pt(19, hipY)); body.line(to: pt(ax, ay))
            body.line(to: pt(ax + side * cos(ft) * fl, ay + sin(ft) * fl))
        }
        // 手臂和花球的路径先算好。手臂在头之前画，花球在最后画（花球永远在最上面）
        var hands: [NSPoint] = []
        let arms = NSBezierPath()
        let armGeo = armPoints(p)
        for g in armGeo {
            let h = pt(g.h.x, g.h.y), e = pt(g.elbow.x, g.elbow.y)
            arms.move(to: pt(g.sh.x, g.sh.y)); arms.curve(to: h, controlPoint1: e, controlPoint2: e)
            hands.append(h)
        }
        let star = NSBezierPath()
        let targets = pomTargets(p)
        if behind > 0.02, pomPos.count == 2 { pomPos = targets }      // 背手时花球跟手；弹簧记的位置也跟上，免得手拿出来后花球跳回身后
        for i in 0..<2 {
            if i == 0, !heldLeft { continue }        // 左手的花球扔出去了（或收在身后）
            if i == 1, cup { continue }              // 右手拿着杯子
            let dir: CGFloat = i == 0 ? -1 : 1
            // 花球跟着手走但慢半拍；位置限制在画面里，抛得再高、甩得再开也不会被裁掉
            var c = pomPos.count == 2 && behind <= 0.02 ? pomPos[i] : targets[i]
            // 花球晃的时候也不许压到头上：一压上去，头的轮廓线就被花球盖掉了
            let hcx = 19 + p.lean * 1.25, hcy = 10.4 + p.hop, clear: CGFloat = 5.4 + 3.7
            let qx = c.x - hcx, qy = c.y - hcy, qd = max(hypot(qx, qy), 0.001)
            if qd < clear, behind <= 0.02, p.toss <= 0.001, !(i == 1 && curious > 0.3) { c = NSPoint(x: hcx + qx / qd * clear, y: hcy + qy / qd * clear) }
            let lagX = c.x - targets[i].x, speed = min(1, hypot(pomVel[i].x, pomVel[i].y) / 26)
            let cx = min(max(c.x, 4.1), 33.9) * u, cy = max(c.y, 4.1) * u
            // 背手时花球一直是原来的大小跟着手走，到了身后才收起来（而不是一路缩小，那样像东西没握在手里）
            let hide = min(max((behind - 0.34) / 0.3, 0), 1)             // 手到胯边时开始收，换层之前收完
            let size = 2.8 * u * (1 - hide * hide * (3 - 2 * hide))
            for k in 0..<3 {
                // 抛起来时在空中转，跳起来时也跟着转（spin）；被甩的时候顺着歪一点，穗子长短跟着抖
                let a = (CGFloat(k) + (p.toss * 5 + p.spin) * dir) * .pi / 3 + lagX * 0.2
                let len = size * (1 + 0.13 * speed * sin(flutter + CGFloat(k) * 2.1 + CGFloat(i) * 1.3))
                star.move(to: NSPoint(x: cx - cos(a) * len, y: cy - sin(a) * len))
                star.line(to: NSPoint(x: cx + cos(a) * len, y: cy + sin(a) * len))
            }
        }

        // 手背到身后时（换花球）：手臂和花球真的在身体后面，先画它们，再画躯干和腿盖上去
        let armsBehind = behind > 0.66              // 这时花球已经收起来了（见上面的 hide），换层看不出来
        if armsBehind {
            stroke(arms, 2.2, ink)
            if behind < 0.95 { stroke(star, 2.0, accent) }
        }
        stroke(body, 2.2, ink)                       // 躯干和腿
        if !armsBehind {
            // 平时：手臂压在躯干上，但在头之前画。这样肩头那一圈描边伸到下巴、脖子上的部分会被头盖住；
            // 以前是头画完才画手臂，那圈线压在下巴上，手一背到身后（改成先画手臂）它又被头盖掉，看起来就是脖子和脸上的线忽然出现、忽然消失
            stroke(arms, 2.2, ink)
            let patch = NSBezierPath()                 // 手臂的描边会在肩膀处横切过躯干，用一段躯干本体盖回去
            let neckT = 1.9 / max(hipY - 14.4 - p.hop, 0.1)
            patch.move(to: pt(19 + p.lean * (1 - neckT), 16.3 + p.hop)); patch.line(to: pt(19, hipY))       // 盖整段躯干：只盖肩膀那一小截的话，剩下的描边会在身体里留下尖尖的线头
            patch.lineWidth = 2.2 * sw; patch.lineCapStyle = .round; ink.setStroke(); patch.stroke()
        }
        if armsBehind {
            // 手在身后时，肩膀这一块要画得和平时一模一样，不然手一背过去、一拿出来，脖子两侧的线就会跳一下：
            // 平时是手臂压在躯干上，肩头一圈深色描边、里面是白的。这里照着补：肩头的圆、手臂从肩膀出来的前三成（带描边），再把躯干中间盖回白色。
            // 再往下，手臂才是被躯干挡住的
            let roots = NSBezierPath()
            for g in armGeo {
                let shp = pt(g.sh.x, g.sh.y), rr = (2.2 + 1.5) / 2 * sw
                halo.setFill(); NSBezierPath(ovalIn: NSRect(x: shp.x - rr, y: shp.y - rr, width: rr * 2, height: rr * 2)).fill()
                roots.move(to: shp)
                for t in [0.1, 0.2, 0.3] as [CGFloat] {          // 沿着手臂的曲线取前三成
                    let a = (1 - t) * (1 - t) * (1 - t), b = 3 * (1 - t) * t, c = t * t * t
                    roots.line(to: pt(a * g.sh.x + b * g.elbow.x + c * g.h.x, a * g.sh.y + b * g.elbow.y + c * g.h.y))
                }
            }
            roots.lineJoinStyle = .round
            roots.lineCapStyle = .butt; roots.lineWidth = (2.2 + 1.5) * sw; halo.setStroke(); roots.stroke()       // 描边：末端平着收，不在手臂上留一道横线
            roots.lineCapStyle = .round; roots.lineWidth = 2.2 * sw; ink.setStroke(); roots.stroke()
            let cover = NSBezierPath()
            let nT = 1.9 / max(hipY - 14.4 - p.hop, 0.1)
            cover.move(to: pt(19 + p.lean * (1 - nT), 16.3 + p.hop)); cover.line(to: pt(19, hipY))
            cover.lineWidth = 2.2 * sw; cover.lineCapStyle = .round; ink.setStroke(); cover.stroke()
        }

        // 睡着时的 z：漫画里那种一串斜体小 z，从头边冒出来，越飘越高、越大，然后淡掉。线很细，不抢戏
        if p.z > 0 {
            for k in 0..<3 {
                let t = (p.z + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
                let a = pow(sin(.pi * t), 1.6) * zFade                              // 淡入、淡出：刚冒出来和快消失的都很淡，不会糊成一团
                let r = (0.45 + 0.8 * t) * u                                        // 越高越大
                let cx = (19 + p.lean * 1.25 + 5.8 + 8.2 * t + 0.4 * sin(t * 2 * .pi)) * u    // 沿一条微微摆动的斜线往右上飘，三个 z 之间留出空隙
                let cy = (10.4 + p.hop - 1.6 - 6.6 * t) * u
                let sk = r * 0.35                                                   // 斜体：上横往右偏、下横往左偏
                let zp = NSBezierPath()
                zp.move(to: NSPoint(x: cx - r + sk, y: cy - r)); zp.line(to: NSPoint(x: cx + r + sk, y: cy - r))
                zp.line(to: NSPoint(x: cx - r - sk, y: cy + r)); zp.line(to: NSPoint(x: cx + r - sk, y: cy + r))
                zp.lineCapStyle = .round; zp.lineJoinStyle = .round
                zp.lineWidth = 1.35 * sw; halo.withAlphaComponent(0.36 * a).setStroke(); zp.stroke()
                zp.lineWidth = 0.65 * sw; ink.withAlphaComponent(a).setStroke(); zp.stroke()
            }
        }

        // 「嗯？」的问号：从头的右上角冒出来，线条和睡觉的 z 是同一种（细线加一圈淡淡的深色）
        if curious > 0.05, behind < 0.01 {
            let k = curious * curious * (3 - 2 * curious)
            let qx = (19 + p.lean * 1.25 + 7.6) * u, qy = (10.4 + p.hop - 5.6 - 0.6 * k) * u, q = 1.25 * u * (0.6 + 0.4 * k)
            let mark = NSBezierPath()
            mark.move(to: NSPoint(x: qx - q, y: qy - q * 0.9))
            mark.curve(to: NSPoint(x: qx + q, y: qy - q * 0.9), controlPoint1: NSPoint(x: qx - q, y: qy - q * 2.3), controlPoint2: NSPoint(x: qx + q, y: qy - q * 2.3))
            mark.curve(to: NSPoint(x: qx, y: qy + q * 0.7), controlPoint1: NSPoint(x: qx + q, y: qy - q * 0.1), controlPoint2: NSPoint(x: qx, y: qy - q * 0.1))
            let dot = NSBezierPath(ovalIn: NSRect(x: qx - 0.34 * u, y: qy + q * 1.5, width: 0.68 * u, height: 0.68 * u))
            mark.lineCapStyle = .round; mark.lineJoinStyle = .round
            mark.lineWidth = 1.9 * sw; halo.withAlphaComponent(0.45 * k).setStroke(); mark.stroke()
            mark.lineWidth = 0.95 * sw; ink.withAlphaComponent(k).setStroke(); mark.stroke()
            ink.withAlphaComponent(k).setFill(); dot.fill()
        }

        // 脑袋：实心圆，五官用深色刻在上面
        let hc = NSPoint(x: (19 + p.lean * 1.25 + headOff.x) * u, y: (10.4 + p.hop + headOff.y) * u), hr = 5.4 * u
        let head = NSBezierPath(ovalIn: NSRect(x: hc.x - hr, y: hc.y - hr, width: hr * 2, height: hr * 2))
        head.lineWidth = 1.5 * sw; halo.setStroke(); head.stroke()
        ink.setFill(); head.fill()
        let feat = light ? NSColor(white: 0.97, alpha: 1) : NSColor(white: 0.10, alpha: 1)
        feat.setStroke(); feat.setFill()
        // 五官不是贴死在脸上的：身体往哪边倾，脸就往哪边看；跳起来时抬头，蹲下去时低头
        let ox = p.lean * 0.55 + gaze.x * 0.75, oy = min(max(p.hop * 0.15, -0.4), 0.4) + gaze.y * 0.55
        func fp(_ dx: CGFloat, _ dy: CGFloat) -> NSPoint { NSPoint(x: hc.x + (dx + ox) * u, y: hc.y + (dy + oy) * u) }
        // 表情走丧萌路线：身体跳得很卖力，脸上没什么波澜
        let f = NSBezierPath()
        f.lineWidth = 1.05 * sw; f.lineCapStyle = .round; f.lineJoinStyle = .round
        // 机器坏人式的豆豆眼：一道细细的平眉毛，眼睛是挂在眉毛下面的半颗豆子，两者连在一起；眉毛细、眼睛大
        let ex: CGFloat = 2.35, ey: CGFloat = -2.3, my: CGFloat = 2.75
        func lid(_ dx: CGFloat, _ half: CGFloat = 0.95, closed: Bool = true) {
            let l = NSBezierPath()
            if closed {       // 闭着的眼睛：比眉毛短，中间微微往下兜的一小段弧（‿），画得稍粗一点
                l.move(to: fp(dx - half, ey + 0.1))
                l.curve(to: fp(dx + half, ey + 0.1), controlPoint1: fp(dx - half * 0.5, ey + 0.55), controlPoint2: fp(dx + half * 0.5, ey + 0.55))
                l.lineWidth = 0.95 * sw; l.lineCapStyle = .round; l.stroke()
                return
            }
            l.move(to: fp(dx - half, ey)); l.line(to: fp(dx + half, ey))
            l.lineWidth = 0.7 * sw; l.lineCapStyle = .round; l.stroke()
        }
        func halfEye(_ dx: CGFloat) {
            lid(dx, 1.25, closed: false)                       // 眉毛
            let e = NSBezierPath()
            // 眼睛是一个圆，上面一小部分被眉毛遮住，露出大半个
            e.move(to: fp(dx - 1.0, ey))
            e.curve(to: fp(dx + 1.0, ey), controlPoint1: fp(dx - 1.1, ey + 2.05), controlPoint2: fp(dx + 1.1, ey + 2.05))
            e.close(); e.fill()
        }
        func flatMouth(_ w: CGFloat) { f.move(to: fp(0.3 - w, my)); f.line(to: fp(0.3 + w, my)) }
        switch p.face {
        case 2:     // 用力：眼神不变，嘴张成一个小小的 o
            halfEye(-ex); halfEye(ex)
            f.stroke()
            let o = NSBezierPath(ovalIn: NSRect(x: fp(0.3, my).x - 0.8 * u, y: fp(0.3, my).y - 0.58 * u, width: 1.6 * u, height: 1.16 * u))    // 线稿的小椭圆，不填实
            o.lineWidth = 0.6 * sw; o.stroke()
        case 4:     // 淡淡一笑：嘴是一小段往右上翘的弧
            halfEye(-ex); halfEye(ex)
            f.stroke()
            let smile = NSBezierPath()               // 嘴的形状不变，线比眼睛细一点
            smile.move(to: fp(-0.7, my + 0.25)); smile.curve(to: fp(1.4, my - 0.35), controlPoint1: fp(0.0, my + 0.6), controlPoint2: fp(0.9, my + 0.35))
            smile.lineWidth = 0.8 * sw; smile.lineCapStyle = .round; smile.stroke()
        case 0:     // 放松：眼睛闭上，只剩两道眼皮
            lid(-ex); lid(ex); flatMouth(0.6)
            f.stroke()
        case 3:     // 偷看：一只眼闭着，一只半睁
            lid(-ex); flatMouth(0.6)
            halfEye(ex)
            f.stroke()
        default:    // 平时：半垂眼，嘴是一条短横线；偶尔眨一下
            if p.blink { lid(-ex); lid(ex) } else { halfEye(-ex); halfEye(ex) }
            if frown > 0.03 {
                // 被拖着走时有点不高兴：嘴还是那条横线的位置，只是慢慢张成一个扁扁的小 o（和用力时的小 o 同一种画法，更小、更扁）。
                // 从一条线连续变过去，所以不会突然换嘴型
                f.stroke()
                let hw = (0.85 - 0.22 * frown) * u, hh = (0.05 + 0.36 * frown) * u, c = fp(0.3, my)
                let o = NSBezierPath(ovalIn: NSRect(x: c.x - hw, y: c.y - hh, width: hw * 2, height: hh * 2))
                o.lineWidth = (1.05 - 0.45 * frown) * sw; o.stroke()
            } else {
                flatMouth(0.85)
                f.stroke()
            }
        }

        // 最上面一层：花球（手背在身后时它已经在前面画过了）。手臂在头之前就画好了，见上面
        if !armsBehind, behind < 0.95 { stroke(star, 2.0, accent) }
        // 比赞：手留在原位，末端变成一只小小的连指手套——一个圆鼓鼓的小拳头，上面冒出一截短短的拇指（像圣诞老人的小手套）。
        // 手套和手臂是连成一体的：先画手套的描边和本体，再把手臂末端那一段白色补回去，盖掉两者之间的线
        if thumb > 0.02, behind < 0.5, hands.count == 2 {
            let g = armGeo[0], hp = hands[0], k = thumb
            let pop = k < 1 ? k * (1 + 0.35 * sin(.pi * k)) : 1                                  // 冒出来时带一点回弹
            let fr = 1.3 * u * pop                                                               // 小拳头，只比手臂粗一点
            let nub = NSBezierPath()                                                             // 拇指：短短一截，从拳头顶上冒出来
            nub.move(to: NSPoint(x: hp.x + 0.25 * u, y: hp.y - fr * 0.55)); nub.line(to: NSPoint(x: hp.x + 0.35 * u, y: hp.y - fr * 0.55 - 1.05 * u * pop))
            nub.lineCapStyle = .round
            let fist = NSBezierPath(ovalIn: NSRect(x: hp.x - fr, y: hp.y - fr * 0.9, width: fr * 2, height: fr * 1.8))
            nub.lineWidth = (1.35 + 1.5) * sw; halo.setStroke(); nub.stroke()
            fist.lineWidth = 1.5 * sw; halo.setStroke(); fist.stroke()
            nub.lineWidth = 1.35 * sw; ink.setStroke(); nub.stroke()
            ink.setFill(); fist.fill()
            let join = NSBezierPath()                                                            // 手臂末端补回白色：手套和手臂之间不留线
            let e = pt(g.elbow.x, g.elbow.y)
            join.move(to: NSPoint(x: hp.x + (e.x - hp.x) * 0.45, y: hp.y + (e.y - hp.y) * 0.45)); join.line(to: hp)
            join.lineWidth = 2.2 * sw; join.lineCapStyle = .round; ink.setStroke(); join.stroke()
        }
        // 喝茶的杯子：白色的小杯子带一个把手，线条和小人是同一套；端在胸前时冒两缕热气，举到嘴边时往里倾
        if cup, behind < 0.66, hands.count == 2 {
            let hpt = hands[1], cw = 3.0 * u, chh = 3.1 * u
            let ctx = NSGraphicsContext.current?.cgContext
            ctx?.saveGState()
            ctx?.translateBy(x: hpt.x, y: hpt.y - 0.9 * u)
            ctx?.rotate(by: -0.55 * sip)
            ctx?.scaleBy(x: 1 - behind, y: 1 - behind)
            let body = NSBezierPath(roundedRect: NSRect(x: -cw / 2, y: -chh / 2, width: cw, height: chh), xRadius: 0.7 * u, yRadius: 0.7 * u)
            let handle = NSBezierPath()
            handle.appendArc(withCenter: NSPoint(x: cw / 2, y: 0.1 * u), radius: 1.05 * u, startAngle: -80, endAngle: 80, clockwise: false)
            handle.lineWidth = 2.1 * sw; halo.setStroke(); handle.stroke()
            handle.lineWidth = 0.8 * sw; accent.setStroke(); handle.stroke()         // 杯子和花球一个颜色
            body.lineWidth = 1.5 * sw; halo.setStroke(); body.stroke()
            accent.setFill(); body.fill()
            ctx?.restoreGState()
            if sip < 0.35 {
                // 热气：和睡觉的 z 是同一种做法——从杯口冒出来，一缕接一缕往上飘，越高越淡、越宽，飘到头消失。
                // 以前是两条固定在杯子上方的波浪线，不动，杯子一挪它就像被吊着走
                let vis = (1 - sip / 0.35) * (1 - behind)
                let topY = hpt.y - 0.9 * u - chh / 2 - 0.5 * u
                for k in 0..<3 {
                    let t = (steam + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
                    let a = pow(sin(.pi * t), 1.5) * vis                                // 刚冒出来和快消失的都很淡
                    let x = hpt.x + (CGFloat(k) - 1) * 0.8 * u + 0.55 * u * sin(t * 2 * .pi + CGFloat(k) * 2.1)      // 一边升一边轻轻左右飘
                    let y = topY - 4.6 * u * t, hgt = (0.9 + 0.9 * t) * u, wd = (0.45 + 0.35 * t) * u
                    let st = NSBezierPath(); st.move(to: NSPoint(x: x, y: y))
                    st.curve(to: NSPoint(x: x, y: y - hgt), controlPoint1: NSPoint(x: x + wd, y: y - hgt * 0.33), controlPoint2: NSPoint(x: x - wd, y: y - hgt * 0.66))
                    st.lineCapStyle = .round
                    st.lineWidth = 1.35 * sw; halo.withAlphaComponent(0.36 * a).setStroke(); st.stroke()
                    st.lineWidth = 0.65 * sw; ink.withAlphaComponent(a).setStroke(); st.stroke()
                }
            }
        }
    }

    /// 收起后的笑脸：嘴是一条往右上翘的线，末端带箭头，像一根上涨的走势
    private func drawFace() {
        let u = miniSize / 26
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * u, y: y * u) }
        textColor.setFill(); textColor.setStroke()
        // 机器坏人的豆豆眼：一条水平的眼皮线，下面挂着半颗豆子。两只眼之间留足空隙
        let ey: CGFloat = 8.4
        for ex in [8.3, 16.3] as [CGFloat] {
            let lid = NSBezierPath()
            lid.move(to: pt(ex - 2.3, ey))
            lid.line(to: pt(ex + 2.3, ey))
            lid.lineWidth = 1.0 * u; lid.lineCapStyle = .round
            lid.stroke()
            let bean = NSBezierPath()
            bean.move(to: pt(ex - 1.1, ey))
            bean.curve(to: pt(ex + 1.5, ey), controlPoint1: pt(ex - 1.2, ey + 3.9), controlPoint2: pt(ex + 1.7, ey + 3.9))
            bean.close()
            bean.fill()
        }
        // 嘴：一条往右上翘的线，末端带箭头，整体压在下半张脸，不碰眼睛
        (cfg.color ? NSColor(red: 0.85, green: 0.42, blue: 0.40, alpha: 1) : textColor).setStroke()
        let tip = pt(19.4, 15.0)
        let c2 = pt(15.6, 21.4)
        let mouth = NSBezierPath()
        mouth.move(to: pt(7.0, 16.4))
        mouth.curve(to: tip, controlPoint1: pt(9.0, 21.4), controlPoint2: c2)
        mouth.lineWidth = 1.5 * u; mouth.lineCapStyle = .round
        mouth.stroke()
        let ang = atan2(tip.y - c2.y, tip.x - c2.x)
        let head = NSBezierPath()
        head.move(to: NSPoint(x: tip.x - cos(ang - 0.7) * 3.3 * u, y: tip.y - sin(ang - 0.7) * 3.3 * u))
        head.line(to: tip)
        head.line(to: NSPoint(x: tip.x - cos(ang + 0.7) * 3.3 * u, y: tip.y - sin(ang + 0.7) * 3.3 * u))
        head.lineWidth = 1.5 * u; head.lineCapStyle = .round; head.lineJoinStyle = .round
        head.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    private func updateHover(_ event: NSEvent?) {
        if dropdown != nil {
            if let e = event, let i = dropGeometry().rows.firstIndex(where: { $0.contains(convert(e.locationInWindow, from: nil)) }), i != dropSel {
                dropSel = i; needsDisplay = true
            }
            if hoverPRow != nil { hoverPRow = nil; needsDisplay = true }
            return
        }
        if page != .list {
            var pr: Int? = nil, nv: Int? = nil, bk = false, bt: Int? = nil
            if let e = event {
                let p = convert(e.locationInWindow, from: nil)
                let L = pageLayout()
                pr = L.rows.firstIndex { $0.contains(p) }.flatMap { pageRows[$0].action != nil ? $0 : nil }
                nv = L.nav.firstIndex { $0.contains(p) }
                bk = backRect.contains(p)
                if btnRect(btnCount - 1).contains(p) { bt = btnCount - 1 }
                if pageAction != nil, btnRect(btnCount - 2).contains(p) { bt = btnCount - 2 }
            }
            if pr != hoverPRow || nv != hoverNav || bk != hoverBack || bt != hoverBtn { hoverPRow = pr; hoverNav = nv; hoverBack = bk; hoverBtn = bt; needsDisplay = true }
            return
        }
        var row: Int? = nil, btn: Int? = nil, slot: Int? = nil, tip: String? = nil, tog = false, tab: Int? = nil
        if let e = event, !mini {
            let p = convert(e.locationInWindow, from: nil)
            if let g = chartGeometry(), let d = detail, g.all.contains(p), !d.spark.isEmpty, !resetRect.contains(p) {
                let (lo, hi) = visibleRange(d)
                let v = Int((lo + Double((p.x - g.all.minX) / g.all.width) * (hi - lo)).rounded())
                if v >= 0, v < d.spark.count { slot = v }
            }
            btn = buttonAt(p)
            tab = tabAt(p)
            if btn == nil { row = rowAt(p) }
            if let L = detailLayout() {       // 指着指标 / 区间条 / 买卖条：给一句解释
                if let st = L.stats.first(where: { $0.rect.contains(p) }) { tip = gloss(st.stat.id) }
                else if let r = L.range, r.contains(p) { tip = gloss("#range") }
                else if let r = L.flow, r.contains(p) { tip = gloss("#flow") }
                tog = L.toggle?.contains(p) ?? false
            }
        }
        if tip != hint || tog != hoverToggle || tab != hoverTab { hint = tip; hoverToggle = tog; hoverTab = tab; needsDisplay = true }
        let oc = event != nil && !mini && page == .list && chartPoint() != nil
        if oc != overChart { overChart = oc; onChartHover?(oc) }
        if let d = debugRow { row = d }
        if row != hoverRow {            // 换了一行：全名提示先收起，在新的一行停 0.6 秒再出
            tipTimer?.invalidate(); tipReady = false
            if row != nil {
                let t = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in self?.tipReady = true; self?.needsDisplay = true }
                RunLoop.main.add(t, forMode: .common); tipTimer = t
            }
        }
        if row != hoverRow { onHoverRow?(row) }
        if row != hoverRow || btn != hoverBtn || slot != hoverSlot {
            hoverRow = row; hoverBtn = btn; hoverSlot = slot; needsDisplay = true
        }
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true); updateHover(event) }
    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { updateHover(nil); onHover?(false) }
    override func rightMouseDown(with event: NSEvent) {
        if page != .list { onBack?(); return }
        if !mini, let t = tabAt(convert(event.locationInWindow, from: nil)) { onTabMenu?(t); return }
        onContextMenu?(mini ? nil : rowAt(convert(event.locationInWindow, from: nil)))
    }
}

// MARK: - 自绘浮层（菜单、添加面板）：和小窗一个风格，不用系统弹窗；还能跟着小窗一起不被截图

enum UI {
    static var theme = "dark"
    static var fontSize: CGFloat = 11
    static var color = true
    static var text: NSColor { theme == "light" ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.90, alpha: 1) }
    static var dim: NSColor { text.withAlphaComponent(0.5) }
    static var bg: NSColor { theme == "light" ? NSColor(white: 0.98, alpha: 0.98) : NSColor(white: 0.09, alpha: 0.96) }

    static var line: NSColor { text.withAlphaComponent(0.13) }
    static var hl: NSColor { text.withAlphaComponent(0.13) }
    static var field: NSColor { text.withAlphaComponent(0.08) }
    static var accent: NSColor { color ? NSColor(red: 0.87, green: 0.45, blue: 0.42, alpha: 1) : text }
    static func font(_ d: CGFloat = 0, _ w: NSFont.Weight = .regular) -> NSFont { .monospacedDigitSystemFont(ofSize: fontSize + d, weight: w) }
    static func chrome(_ b: NSRect) {
        let p = NSBezierPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        bg.setFill(); p.fill()
        line.setStroke(); p.lineWidth = 1; p.stroke()
    }
    static func width(_ s: String, _ f: NSFont) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: f]).width) }
}

/// 小窗平时不抢键盘焦点；只有在「添加」页要打字时才允许成为键盘焦点
final class KeyPanel: NSPanel {
    var allowKey = false
    override var canBecomeKey: Bool { allowKey }
}

/// 小窗里除了股票列表以外的页面：添加、菜单、引导。都画在同一块地方，用和列表一样的行
enum Page { case list, add, menu, guide }

struct PRow {
    var text = ""
    var right = ""             // 右侧淡色小字
    var dim = false
    var bold = false
    var check: Bool? = nil     // 行首带一个勾选框
    var sep = false            // 分隔线
    var wrap = false           // 多行说明文字
    var rightAccent = false
    var indent: CGFloat = 0    // 缩进（展开的选项用）
    var art: ((NSRect) -> Void)? = nil     // 行首的小图例
    var action: (() -> Void)? = nil
}

// MARK: - 应用

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    var panel: NSPanel!
    var board = BoardView()
    var folding = false              // 面板正在收成拉拉队脚下的横线
    let bubble = BubbleView()        // 对着拉拉队右键冒出来的气泡
    var bubbleOpen = false
    var bubbleLeftAt = 0.0           // 气泡开着时鼠标是什么时候离开的（0 = 还在上面）
    var bubbleHoverAt = 0.0          // 鼠标是什么时候停到拉拉队身上的（0 = 不在）
    var bubbleMuted = false          // 刚点过气泡里的选项：鼠标离开之前先别再冒出来
    var nearLatch = false            // 上一拍鼠标算不算在它身边（用来做进出的缓冲带）
    // 喝茶休息：正在跳的时候每跳完 teaEveryLoops 轮歇一次
    var teaStart = 0.0               // 这次喝茶是什么时候开始的（0 = 没在喝）
    var teaFrom = Pose()
    var teaLoopBase = 0              // 上次喝完茶（或开始跳）时已经跳到第几轮
    var teaRestarted = false         // 这一杯快喝完、往外拿花球时，后面的动作是不是已经接上了
    var teaInRest = false            // 这一杯是休息模式下喝的（喝完去睡），还是跳的间隙喝的（喝完接着跳）
    var restCoffeeAt = 0.0           // 休息模式下，下一杯什么时候喝（0 = 还没定）
    var coffeeDecided = false        // 这次进入休息是点出来的（或者只是切了标签），喝不喝已经定了
    var swapPending = false          // 正在喝咖啡时要换花球：先记着，等杯子收到身后再换
    var lastActEnd = 0.0             // 上一段特别的动作（换花球、喝咖啡、走回来）是什么时候做完的
    let actGap = 10.0                // 一段做完之后，至少隔这么久才会自己去喝咖啡
    var lastModeCheer = true, modeKnown = false
    // 「隐藏」：0 它在；1 正在扔下花球走开；2 不在，只剩花球；3 正在走回来
    var awayState = 0
    var awayStart = 0.0
    var awayFrom = Pose()            // 开始走开那一刻它的姿势
    var awayHand = NSPoint.zero      // 花球出手的位置
    var returnRestarted = false      // 走回来捡起花球时，后面的动作是不是已经接上了
    func startLeaving() {
        guard awayState == 0, cheerTimer != nil else { return }
        awayFrom = mascot.pose; awayHand = mascot.leftHand
        awayState = 1; awayStart = CACurrentMediaTime()
        store.set(true, forKey: "away")
    }
    func startReturning() {
        guard awayState == 2 else { return }
        awayState = 3; awayStart = CACurrentMediaTime(); returnRestarted = false
        store.set(false, forKey: "away")
        bubbleMuted = true                    // 它走回来的时候鼠标正好在这儿，别马上冒气泡
    }
    var muteZone = NSRect.zero       // 点气泡选项那一刻，它和气泡占的那一片（屏幕坐标）
    var muteOutAt = 0.0              // 鼠标是什么时候离开那一片的（0 = 还在里面）
    var nearMuted = false            // 刚在气泡里切了休息 / 加油：这一次悬停不再算「在看它」，它马上去做该做的事；鼠标离开再回来才恢复
    var bubbleShrinkPending = false  // 按下时气泡已经藏了，但窗口等松手后再缩回去（拖动途中改窗口大小会让它跳一下）
    // ───────── 拉拉队的状态：谁说了算，按什么顺序 ─────────
    // 输入有四个：
    //   1. 作息：设置里「拉拉队作息」跟哪个市场（或永不休息），加上那个市场现在开没开盘 → marketLive
    //   2. 手动：用户在气泡里点了「休息」或「加油」 → manual（nil = 没点过，按作息来）
    //   3. 鼠标：在它身边（展开时也包括面板上）→ near；气泡开着也算
    //   4. 换花球：正在换 → swapStart > 0
    // 先得出「它该是哪种模式」：mode = manual ?? marketLive（true 加油，false 休息）
    // 再得出「它现在在干什么」，上面的压过下面的：
    //   换花球中 → 站定换花球
    //   鼠标在身边 / 气泡开着 → 醒着歇着，看着鼠标（或气泡）
    //   模式是加油 → 跳整套动作
    //   模式是休息 → 先犯困，再睡着
    // 气泡里第一项永远写的是「换成另一种模式」：模式是加油就显示「休息」，是休息就显示「加油」。和鼠标在不在身边无关。
    // manual 什么时候自动清掉（回到按作息来）：
    //   · 跟的那个市场开盘或收盘了
    //   · 用户在设置里改了「拉拉队作息」
    //   · 手动选的和作息本来的结果一样（比如休市时点了「休息」）
    //   切换市场标签不清：用户说了歇着，换个标签看看不该把它吵醒。
    //
    // ───────── 特别的动作：一次只做一件，做完留空档 ─────────
    // 三种：隐藏 / 回来、换花球、喝咖啡。谁压谁：隐藏 / 回来 > 换花球 > 喝咖啡。
    //
    // 换花球什么时候做：换到涨色不同的市场，或者在设置里改了花球配色。马上做（它是对用户操作的回应）。
    //   正在喝咖啡时要换：不把杯子变没——等这一口放下，把杯子收到身后，就地换出新花球（swapPending）。
    //
    // 喝咖啡什么时候做：
    //   加油模式：每跳完 teaEveryLoops 轮喝一杯，喝完接着跳。
    //   休息模式：每次点「休息」有一半的机会先喝一杯再睡（已经在休息时点也算）；收盘自己歇下来时先喝一杯；
    //             睡着之后每隔 50 到 85 秒醒来喝一杯，喝完接着睡。
    //   不喝的情况：
    //     · 上一段特别的动作做完还不到 actGap 秒（刚换完花球、刚走回来、刚喝完）——自己点「休息」掷中的除外。
    //     · 只是切了市场标签而进入休息——这时多半刚换过花球，不再接一杯。
    //     · 到点时正在换花球或它不在——不排队，往后推 12 到 25 秒。
    //   喝到一半改主意：休息着喝时点了「加油」→ 杯子收起来开始跳；跳着喝时改成休息 → 把这杯喝完直接去睡；被隐藏 → 杯子收起来。
    //
    // ───────── 屏幕上有什么：三个开关，各管各的 ─────────
    //   小窗显不显示  →  panel.isVisible   （⌃⌥S、顶部栏图标。同事过来时一键全藏）
    //   看板开不开    →  mini              （看板右上角的叉收起；点它脚下那块板、点它本人、⌃⌥D 展开）
    //   拉拉队在不在  →  awayState         （气泡里的「隐藏」让它扔下花球走开；点花球它走回来）
    // 这三个互不影响：看板收起时它还在；它走开了看板照样能开关；全藏起来再叫出来，前两个保持原样。
    // 看板收起后并没有消失，就是它脚下那块板。它走开后也没有消失，就是地上那个花球。所以每一样东西藏起来之后，屏幕上都留着把它叫回来的那个东西。
    // 退出程序只有两处：气泡里的「退出」、设置页最后一行。
    var manual: Bool?
    var modeCheer: Bool { manual ?? marketLive }
    var resting0: Bool { !modeCheer }               // 不看鼠标的话，它现在该不该歇着
    var scheduleKey = ""                            // 上次算 marketLive 时跟的是哪个市场、用的哪个作息设置
    /// 重新算一遍作息，并按上面的规则清 manual。每 5 秒一次；改了设置、换了标签、点了气泡之后立刻再算一次
    func refreshMode() {
        let which = cfg.restSchedule == "auto" ? tab : cfg.restSchedule
        let mk: Market = which == "us" ? .us : (which == "hk" ? .hk : .aStock)
        let live = which == "never" || mk.status(stamp: nil).live || ProcessInfo.processInfo.environment["PEEK_FORCE_LIVE"] != nil
        let key = cfg.restSchedule + "|" + which
        let sameMarket = key == scheduleKey
        let settingChanged = !scheduleKey.isEmpty && !scheduleKey.hasPrefix(cfg.restSchedule + "|")
        if settingChanged { manual = nil }                              // 改了作息设置
        else if sameMarket, live != marketLive { manual = nil }         // 同一个市场开盘 / 收盘了
        scheduleKey = key
        marketLive = live
        if manual == live { manual = nil }                              // 手动的和作息一样，就不用记了
        syncBubble()
    }
    /// 气泡开着时，里面的字跟着当前模式走
    func syncBubble() {
        guard bubbleOpen else { return }
        // 四项一直都在：加油、休息、隐藏、退出
        let want = [("cheer", T("加油", "Cheer")), ("rest", T("休息", "Rest")), ("hide", T("隐藏", "Hide")), ("quit", T("退出", "Quit"))]
        if bubble.items.map({ $0.icon + $0.text }) != want.map({ $0.0 + $0.1 }) { bubble.items = want }
        bubble.selected = nil          // 不标「当前是哪个」：四项都是普通按钮，点哪个都行，只有悬停和按下的反馈
    }
    var bubbleTuck: CGFloat { floor(mascotSide * 0.22) }           // 气泡的尖角伸进拉拉队那一块多少：脑袋左边本来是空的，贴近一点才像它说的话
    var bubbleWidth: CGFloat { bubbleOpen ? max(0, bubble.fittingSize().width + 3 - bubbleTuck) : 0 }

    func openBubble() {
        // 气泡是拉拉队说的话，大小跟着它走：界面放大时气泡也放大，但不超过拉拉队撑得起的程度（小号拉拉队配特大界面时气泡会比它还高、压到面板上）
        bubble.theme = cfg.theme; bubble.fontSize = CGFloat(cfg.fontSize) * min(uiScale, max(1, mascotSide / 68))
        bubbleOpen = true; bubbleLeftAt = 0
        bubble.items = []; refreshMode()                           // 打开前先按最新的状态算一遍，里面的字才对
        let room = max(44, (mini ? mascotSide : stageTop) - 2)       // 气泡能用的高度：收起时是拉拉队那一块，展开时是面板上方那一截
        bubble.maxH = room
        let sz = bubble.fittingSize(), u = mascotSide / 38
        render()                                                   // 收起状态下窗口要先往左伸出一块给气泡
        let headY = (10.4 + 0.9) * u                               // 脑袋中心的高度
        let y = min(max(1, headY - sz.height * 0.42), max(1, room - sz.height))
        bubble.tailY = headY - y
        bubble.autoresizingMask = [.minXMargin]                    // 钉在拉拉队左边，窗口变宽变窄都跟着右边走
        bubble.frame = NSRect(x: stage.bounds.width - mascotSide + bubbleTuck - sz.width, y: y, width: sz.width, height: sz.height)
        bubble.hover = nil; bubble.isHidden = false; bubble.needsDisplay = true
        mascot.needsDisplay = true
    }
    func closeBubble() {
        guard bubbleOpen else { return }
        bubbleOpen = false; bubble.isHidden = true
        render()
    }
    let debugFold = ProcessInfo.processInfo.environment["PEEK_FOLD"].flatMap { Double($0) }   // 调试用：收起的过渡停在这个进度
    var swapStart = 0.0              // 正在背手换花球：从什么时候开始的（0 = 没在换）
    var swapFrom: Pose?              // 开始换的那一刻它是什么姿势
    var swapRestarted = false        // 往外拿的时候，后面的动作是不是已经接上了
    let debugTea = ProcessInfo.processInfo.environment["PEEK_TEA"] != nil      // 调试用：一开始就喝茶
    var traceUntil = 0.0, traceStart = 0.0
    let evtOn = ProcessInfo.processInfo.environment["PEEK_EVT"] != nil       // 调试用：把一次操作里窗口发生的每件事按时间打印出来，查闪动
    var evtT0 = 0.0
    func evt(_ what: @autoclosure () -> String) {
        guard evtOn, evtT0 > 0 else { return }
        print(String(format: "  %6.0fms  ", (CACurrentMediaTime() - evtT0) * 1000) + what()); fflush(stdout)
    }
    var mascot = BoardView()         // 只用来画拉拉队：收起时是它，展开时它站在面板上沿
    let stage = StageView()
    var cheerStyle: Bool { cfg.miniStyle != "face" }
    var uiScale: CGFloat { ["s": 0.9, "l": 1.2, "xl": 1.4][cfg.uiSize] ?? 1 }
    var mascotSide: CGFloat { ["s": 68, "l": 112][cfg.mascotSize] ?? 88 }
    var stageTop: CGFloat { cheerStyle ? floor(mascotSide * 33.0 / 38) : 0 }
    var mascotVisible: Bool { cheerStyle }
    var lastStageTop: CGFloat = -1   // 上一次排版时面板上沿离窗口顶多远
    var lastMetrics = ""             // 上一次排版用的尺寸设置（界面大小、拉拉队大小）
    var snapNext = false             // 这一次窗口直接到位，不播变大变小的过渡
    /// 拉拉队那一块在屏幕上的位置：始终是窗口的右上角
    var mascotScreenRect: NSRect { let f = panel.frame, m = mascotSide; return NSRect(x: f.maxX - m, y: f.maxY - m, width: m, height: m) }
    /// 鼠标是不是在看得见的东西上（面板或拉拉队）；窗口左上那块透明的空白不算
    func mouseInside() -> Bool {
        let m = NSEvent.mouseLocation, f = panel.frame
        guard cheerStyle else { return f.contains(m) }
        if mascotVisible, mascotScreenRect.contains(m) { return true }
        if bubbleOpen, let w = bubble.window, w.convertToScreen(bubble.convert(bubble.bounds, to: nil)).contains(m) { return true }
        return !mini && NSRect(x: f.minX, y: f.minY, width: f.width, height: max(0, f.height - stageTop)).contains(m)
    }
    var cfg = Config()
    var configBad = false            // 配置文件格式有误（此时沿用上一份可用配置）
    var configMTime: Date?
    var cacheSavedAt = Date.distantPast
    var quotes: [String: Quote] = [:]
    var hovering = false
    var failed = false
    var everLoaded = false           // 至少成功拿到过一次行情
    var lastOK: Date?
    var lastFetchAt = Date.distantPast
    var selected: String?            // 当前展开详情的那只（配置里的原始写法）
    var minutes: [String: [Double]] = [:]
    var minuteVols: [String: [Double]] = [:]
    var minuteTimes: [String: [String]] = [:]
    var minuteAvg: [String: [Double]] = [:]
    var hoverFetch: DispatchWorkItem?
    var blockedUntil: [String: Date] = [:]        // 哪个分时地址被拦截了、拦到什么时候
    var detailMore = false           // 详情里「更多」是否展开
    var minuteFetchedAt: [String: Date] = [:]
    var autoCloseTimer: Timer?
    var anchorRight: CGFloat = 0     // 小窗右上角钉在哪：按钮在右上角，变大变小时按钮不离开鼠标
    var anchorTop: CGFloat = 0
    var resizing = false
    var animTimer: Timer?
    var animTarget = NSRect.zero
    var animAlphaTarget: CGFloat = 1
    var animDone: (() -> Void)?
    var closing = false              // 详情正在收起（内容要留到动画结束再清）
    var lastDetailKey: String?
    var mini = false                 // 收成笑脸
    var expanded = false             // 是否显示开盘 / 最高 / 最低等更多列
    var timer: Timer?
    var statusItem: NSStatusItem?
    var hotKeyRef: EventHotKeyRef?
    var boardKeyRef: EventHotKeyRef?        // ⌃⌥D：展开 / 收起看板
    var hotKeyHandlerInstalled = false
    var bubbleKeyRefs: [EventHotKeyRef?] = []      // 气泡开着时临时登记的字母键
    var bubbleKeyCodes: [UInt32] = []
    var hotKeyOK = true
    var lastHits: [SearchHit] = []   // 「添加」页当前的搜索结果
    var adding = false               // 正在确认某只能不能加（防止连点加两次）
    var borrowedFrom: NSRunningApplication?      // 为了接捏合手势临时切到前台时，原来在前台的是谁
    var lastNearAt = 0.0             // 鼠标最后一次在拉拉队旁边是什么时候
    var gazeHeld = NSPoint.zero            // 鼠标离开那一刻眼睛看着的方向
    var searchSeq = 0
    var searchTimer: Timer?
    var guideStep = 0
    var guideMarkets: Set<String> = ["a"]
    var guidePicked: [SearchHit] = []
    var pageIdle: Timer?             // 菜单页没人碰时自己收回
    var cheerTimer: Timer?           // 啦啦队动作的节拍
    var cheerStart = CACurrentMediaTime()     // 这一轮动作从什么时候开始算
    var cheerBlendFrom: Pose?        // 从哪个姿势过渡过来（进入 / 离开休息时用）
    var cheerBlendStart = 0.0
    var cheerResting = false
    var marketLive = true
    var marketCheckedAt = 0.0
    var confirmReset = false         // 「恢复默认」点过一次，等第二次确认
    var menuOpen: String?            // 菜单里哪个设置项的选项正展开着
    var guideReplaces = false        // 第一次使用：引导里选的替换掉示例列表；以后再走引导：只往里加
    var flashText: String?           // 标题条上临时显示几秒的一句话
    var flashTimer: Timer?

    func displayName(_ q: Quote, key: String) -> String {
        let en = q.str(46)
        if lang == "en", Market.of(key) == .hk || Market.of(key) == .us, !en.isEmpty, en.unicodeScalars.allSatisfy({ $0.isASCII }), Double(en) == nil { return en }
        return q.name
    }

    /// 这个程序早期叫 Peek。第一次以新名字运行时，把旧的配置、偏好和开机启动项搬过来，之后就不再看旧位置
    func migrateFromOldName() {
        guard testHome == nil else { return }
        let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
        let oldDir = home.appendingPathComponent(".peek")
        if !fm.fileExists(atPath: configDir.path), fm.fileExists(atPath: oldDir.path) { try? fm.moveItem(at: oldDir, to: configDir) }
        if store.object(forKey: "migrated") == nil {
            if let old = UserDefaults(suiteName: "local.peek")?.dictionaryRepresentation() {
                for k in ["right", "top", "mini", "tab", "onboarded", "detailMore"] { if let v = old[k], store.object(forKey: k) == nil { store.set(v, forKey: k) } }
            }
            store.set(true, forKey: "migrated")
        }
        let oldAgent = home.appendingPathComponent("Library/LaunchAgents/local.peek.plist")
        if fm.fileExists(atPath: oldAgent.path) {          // 旧的开机启动项指向旧程序：删掉，按新路径重新建一个
            try? fm.removeItem(at: oldAgent)
            if !loginItemOn { toggleLoginItem() }
        }
    }

    /// 实际显示的自选股：最多 maxStocks 只，免得小窗比屏幕还高
    var allStocks: [String] { Array(cfg.stocks.prefix(maxStocks)) }
    /// 某只股票属于哪一页：a / hk / us。写错的代码归到 A 股页，方便看到并改掉
    static func tabOf(_ raw: String) -> String {
        guard isValidCode(raw) else { return "a" }
        switch Market.of(apiSymbol(raw)) { case .hk: return "hk"; case .us: return "us"; default: return "a" }       // 金价这类商品不单开一页，和黄金 ETF 这些放在 A 股页一起看
    }
    static var tabNames: [String: String] { ["a": T("A股", "CN"), "hk": T("港股", "HK"), "us": T("美股", "US")] }
    /// 有股票的市场才有标签页
    var tabIDs: [String] { cfg.tabOrder.filter { id in allStocks.contains { AppDelegate.tabOf($0) == id } } }
    var tab = "a" { didSet { if tab != oldValue { store.set(tab, forKey: "tab") } } }
    /// 当前这一页显示的股票
    var shown: [String] {
        let ids = tabIDs
        let cur = ids.contains(tab) ? tab : (ids.first ?? "a")
        return allStocks.filter { AppDelegate.tabOf($0) == cur }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        migrateFromOldName()
        let firstRun = !FileManager.default.fileExists(atPath: configURL.path)      // 还没有配置文件 = 第一次用
        if let c = loadConfig() { cfg = c } else { configBad = true }

        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.allowsToolTipsWhenApplicationIsInactive = true
        stage.mascot = mascot; stage.board = board
        stage.addSubview(board); stage.addSubview(mascot)        // 拉拉队在上层：它的脚、扔下的花球压在看板的上沿上，不会被挡住一截
        panel.contentView = stage
        mascot.mini = true
        mascot.onToggleMini = { [weak self] in self?.toggleMini() }
        mascot.onReturn = { [weak self] in self?.startReturning() }
        bubble.isHidden = true
        stage.addSubview(bubble)
        bubble.onPick = { [weak self] i in
            guard let self = self else { return }
            if i == 3 { NSApp.terminate(nil); return }
            self.bubbleMuted = true
            if i == 2 {
                // 隐藏：它把花球一扔走掉，原地只剩一个花球；点花球它再走回来。展开、收起时都是这一个意思
                self.closeBubble()
                self.startLeaving()
                return
            }
            // 加油（0）或休息（1）。点的就是当前的模式：什么都不用变，收起气泡就行
            let wantCheer = i == 0
            if !wantCheer, self.teaStart == 0 {
                // 每次点「休息」都掷一次：一半的机会先喝杯咖啡再睡，另一半直接去睡。已经在休息时点也算
                let coffee = Bool.random() || ProcessInfo.processInfo.environment["PEEK_COFFEE"] != nil
                self.restCoffeeAt = CACurrentMediaTime() + (coffee ? 0.25 : Double.random(in: 50...85))
                self.coffeeDecided = true
                if coffee { self.lastActEnd = 0 }            // 自己点的，不用等空档
            }
            if wantCheer == self.modeCheer {
                // 模式没变。点的是「休息」：这次悬停也先不算，让它马上去喝或者接着睡
                if !wantCheer {
                    var zone = self.mascotScreenRect.insetBy(dx: -40, dy: -40)
                    if let w = self.bubble.window { zone = zone.union(w.convertToScreen(self.bubble.convert(self.bubble.bounds, to: nil)).insetBy(dx: -24, dy: -24)) }
                    self.muteZone = zone; self.muteOutAt = 0; self.nearMuted = true
                    self.lastNearAt = CACurrentMediaTime() - 4.5
                }
                self.closeBubble(); return
            }
            self.manual = wantCheer
            self.refreshMode()
            // 鼠标这时还停在它身上。如果照旧算「在看它」，它会一直保持看着你的样子，等于点了没反应。
            // 所以这一次悬停先不算：点加油就马上开跳；点休息就马上犯困，两秒左右睡着（不是瞬间闭眼，也不用等平时那六七秒）
            self.nearMuted = true
            // 解除的条件是鼠标离开「它 + 气泡」这一整片超过半秒。不能只看它身边那一圈：
            // 气泡的选项正好压在那一圈的边线上，鼠标稍微一动就在线内外来回，它会在「看着你」和「去休息 / 加油」之间来回闪
            var zone = self.mascotScreenRect.insetBy(dx: -40, dy: -40)
            if let w = self.bubble.window { zone = zone.union(w.convertToScreen(self.bubble.convert(self.bubble.bounds, to: nil)).insetBy(dx: -24, dy: -24)) }
            self.muteZone = zone; self.muteOutAt = 0
            self.lastNearAt = CACurrentMediaTime() - 4.5
            self.closeBubble()
        }
        mascot.onHover = { [weak self] inside in self?.board.onHover?(inside) }

        board.onHover = { [weak self] raw in
            guard let self = self else { return }
            let inside = raw || self.mouseInside()      // 从面板挪到拉拉队身上不算离开
            self.hovering = inside
            self.applyConfig()
            self.render()
            self.scheduleAutoClose()
            self.schedulePageClose()
            if !inside { self.returnFocus() }
            if inside, Date().timeIntervalSince(self.lastFetchAt) > 1 { self.refresh() }   // 鼠标一移上来就拉最新的
        }
        board.onHoverRow = { [weak self] i in
            guard let self = self else { return }
            self.hoverFetch?.cancel()
            guard let i = i, i < self.shown.count else { return }
            let raw = self.shown[i]
            // 鼠标在某一行停住 0.25 秒才预拉它的分时：点开时走势图直接出来，又不会因为划过一排就连发请求
            let w = DispatchWorkItem { [weak self] in self?.fetchMinutes(for: raw, force: false) }
            self.hoverFetch = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
        }
        board.onContextMenu = { [weak self] row in
            guard let self = self else { return }
            let list = self.shown
            guard let r = row, r < list.count else { self.openMenu(row: nil); return }
            let raw = list[r]
            let name = self.cfg.aliases[raw] ?? self.quotes[apiSymbol(raw)].map { self.displayName($0, key: apiSymbol(raw)) } ?? raw
            var opts = [T("移除", "Remove")]
            if r > 0 { opts.append(T("移到最前", "Move to top")) }
            let at = self.board.convert(self.panel.mouseLocationOutsideOfEventStream, from: nil)
            self.board.dropSel = -1
            self.board.dropdown = BoardView.Dropdown(row: r, options: opts, current: -1, anchor: NSPoint(x: at.x, y: at.y + 2)) { i in
                if i == 0 {
                    if self.selected == raw { self.selected = nil }
                    if self.mutateConfig({ $0.removeAll { $0 == raw } }) { self.flash(T("已移除「\(name)」", "Removed \(name)")) }
                    else { self.flash(T("配置文件有误，没保存", "Config file error. Not saved")) }
                } else {
                    self.edit { $0.removeAll { $0 == raw }; $0.insert(raw, at: 0) }
                }
            }
        }
        board.onReorderTab = { [weak self] from, to in
            guard let self = self else { return }
            var ids = self.tabIDs
            guard from < ids.count, to < ids.count, from != to else { return }
            ids.insert(ids.remove(at: from), at: to)
            let order = ids + self.cfg.tabOrder.filter { !ids.contains($0) }        // 现在没有股票的市场排在后面
            if !self.mutateConfigObject({ $0["tabOrder"] = order }) { self.flash(T("配置文件有误，没保存", "Config file error. Not saved")) }
        }
        board.onTabMenu = { [weak self] i in
            guard let self = self, i < self.tabIDs.count, self.tabIDs.count > 1 else { return }
            let id = self.tabIDs[i], name = AppDelegate.tabNames[id] ?? id
            let n = self.allStocks.filter { AppDelegate.tabOf($0) == id }.count
            let at = self.board.convert(self.panel.mouseLocationOutsideOfEventStream, from: nil), anchor = NSPoint(x: at.x, y: at.y + 2)
            self.board.dropSel = -1
            self.board.dropdown = BoardView.Dropdown(row: 0, options: [T("移除\(name)", "Remove \(name)")], current: -1, anchor: anchor) { _ in
                // 这一页的股票会一起移除，所以再确认一次
                DispatchQueue.main.async {
                    self.board.dropSel = -1
                    self.board.dropdown = BoardView.Dropdown(row: 0, options: [T("确认移除 \(n) 只", "Remove \(n) stocks"), T("取消", "Cancel")], current: -1, anchor: anchor) { k in
                        guard k == 0 else { return }
                        if self.selected.map({ AppDelegate.tabOf($0) == id }) == true { self.selected = nil }
                        if self.mutateConfig({ $0.removeAll { AppDelegate.tabOf($0) == id } }) { self.flash(T("已移除\(name)", "Removed \(name)")) }
                        else { self.flash(T("配置文件有误，没保存", "Config file error. Not saved")) }
                    }
                }
            }
        }
        board.onReorder = { [weak self] from, to in
            guard let self = self else { return }
            let list = self.shown
            guard from < list.count, to < list.count else { return }
            let moving = list[from], target = list[to]
            // 只在当前这一页里换位置：在整份列表里把它挪到目标那只的前面或后面
            self.edit { (all: inout [String]) in
                all.removeAll { $0 == moving }
                if let ti = all.firstIndex(of: target) { all.insert(moving, at: to > from ? ti + 1 : ti) } else { all.append(moving) }
            }
        }
        board.onMenu = { [weak self] in self?.openMenu(row: nil) }
        board.onBack = { [weak self] in self?.closePage() }

        board.onRemove = { [weak self] in
            guard let self = self, let raw = self.selected else { return }
            let name = self.cfg.aliases[raw] ?? self.quotes[apiSymbol(raw)].map { self.displayName($0, key: apiSymbol(raw)) } ?? raw
            self.selected = nil
            if self.mutateConfig({ $0.removeAll { $0 == raw } }) { self.flash(T("已移除「\(name)」", "Removed \(name)")) }
            else { self.flash(T("配置文件有误，没保存", "Config file error. Not saved")) }
        }
        board.onArrow = { [weak self] d in
            guard let self = self, let cur = self.selected else { return }
            let list = self.shown
            guard var i = list.firstIndex(of: cur) else { return }
            repeat { i += d } while i >= 0 && i < list.count && self.quotes[apiSymbol(list[i])] == nil      // 跳过没有行情的行
            guard i >= 0, i < list.count else { return }            // 到头了就停住
            self.selected = list[i]
            self.board.reveal(row: i)
            self.board.resetZoom()
            self.fetchMinutes(for: list[i], force: false)
            self.render()
            self.scheduleAutoClose()
        }
        board.onSearch = { [weak self] q in self?.searchChanged(q) }
        board.onAdd = { [weak self] in self?.addStock() }
        expanded = false        // 「更多列」功能已去掉：想看更多，点一行看详情就够了
        board.onToggleExpand = { [weak self] in
            guard let self = self else { return }
            self.expanded.toggle()
            store.set(self.expanded, forKey: "expanded")
            self.render()
        }
        board.onSelectTab = { [weak self] i in
            guard let self = self, i < self.tabIDs.count else { return }
            // 花球跟随市场时，换到涨色不同的市场才背手换一副（A 股和港股都是红的，不用换）
            let goGreen = self.tabIDs[i] == "us" ? self.cfg.usGreenUp : self.cfg.upColor == "green"
            self.coffeeDecided = true          // 切标签带来的「进入休息」不算数：不因此先喝一杯（不然刚换完花球又要喝）
            if self.tab != self.tabIDs[i], goGreen != self.mascot.greenUp, self.cfg.color, self.cfg.pomColor == "auto", self.cheerTimer != nil, !self.mini, !self.mascot.isHidden {
                let now = CACurrentMediaTime(), x = (now - self.swapStart) / swapSeconds
                if self.teaStart > 0 { self.swapPending = true }                     // 正在喝：等杯子收好再换
                else if self.swapStart == 0 { self.swapStart = now }
                else if x > swapIn, x < swapOut { self.swapStart = now - swapIn * swapSeconds; self.swapRestarted = false }      // 手已经在身后：接着再掏一次，不用先拿出来
                else if x >= swapOut, x < 1 {           // 正在往外拿：从同样的位置把手收回去，再换一次（不然只会看到颜色变了）
                    self.swapStart = now - swapIn * (1 - (x - swapOut) / (1 - swapOut)) * swapSeconds
                    self.swapFrom = self.mascot.pose    // 从它现在的样子收手
                    self.swapRestarted = false
                }
            }
            self.tab = self.tabIDs[i]
            self.refreshMode()
            self.selected = nil
            self.board.detail = nil; self.closing = false      // 换页时详情直接关掉，不播收起动画
            self.render()
            self.refresh()
        }
        detailMore = store.bool(forKey: "detailMore")
        board.onToggleMore = { [weak self] in
            guard let self = self else { return }
            self.detailMore.toggle()
            store.set(self.detailMore, forKey: "detailMore")
            self.render()
        }
        mini = store.bool(forKey: "mini")
        if store.bool(forKey: "away") { awayState = 2 }        // 上次退出时它是藏着的：这次还是只有花球
        board.onToggleMini = { [weak self] in self?.toggleMini() }
        board.onQuit = { NSApp.terminate(nil) }
        board.onClose = { [weak self] in self?.closePage(); self?.panel.orderOut(nil); self?.updateCheer() }     // 只是藏起来，⌃⌥S 或菜单栏小圆点叫回
        board.onClickRow = { [weak self] i in
            guard let self = self else { return }
            let list = self.shown
            if let i = i, i < list.count, self.quotes[apiSymbol(list[i])] != nil, self.selected != list[i] {
                self.selected = list[i]
                self.board.reveal(row: i)
                self.board.resetZoom()
                self.fetchMinutes(for: list[i], force: false)
            } else {
                self.selected = nil      // 再点一次同一行，或点详情区域，收起
            }
            self.render()
            self.scheduleAutoClose()
        }

        // 位置：记住右上角钉在哪里，第一次放右下角
        if store.object(forKey: "right") != nil {
            anchorRight = CGFloat(store.double(forKey: "right")); anchorTop = CGFloat(store.double(forKey: "top"))
        } else if store.object(forKey: "left") != nil {        // 旧版本记的是左上角
            anchorRight = CGFloat(store.double(forKey: "left")) + ceil(CGFloat(cfg.fontSize) * 21)
            anchorTop = CGFloat(store.double(forKey: "top"))
        } else if let vf = NSScreen.main?.visibleFrame {
            anchorRight = vf.maxX - 20; anchorTop = vf.minY + 150
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: nil) { [weak self] _ in
            guard let self = self, !self.resizing else { return }    // 只认用户自己拖的
            let f = self.panel.frame
            self.anchorRight = f.maxX; self.anchorTop = f.maxY
            store.set(Double(f.maxX), forKey: "right"); store.set(Double(f.maxY), forKey: "top")
        }
        // 拔掉外接屏、改分辨率后重新摆一次，别留在看不见的地方
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.render()
        }

        tab = store.string(forKey: "tab") ?? "a"
        for id in ["a", "hk", "us"] {       // 先把上次存的行情读出来，小窗一出现就有数，不用等网络
            if let t = try? String(contentsOf: configDir.appendingPathComponent("cache_\(id).txt"), encoding: .utf8) {
                for (k, v) in parseQuotes(t) { quotes[k] = v }
            }
        }
        applyConfig()
        render()
        panel.orderFrontRegardless()
        if let v = ProcessInfo.processInfo.environment["PEEK_CHEER_T"].flatMap({ Double($0) }) { mascot.pose = v < 0 ? Pose.resting(at: -v, asleep: true) : cheerPose(at: v) }   // 调试用：定在这套动作的第几秒（负数 = 休息姿势）
        else { updateCheer() }
        if let g = ProcessInfo.processInfo.environment["PEEK_GAZE"]?.split(separator: ",").compactMap({ Double($0) }), g.count == 2 {
            mascot.gaze = NSPoint(x: g[0], y: g[1]); mascot.facing = true; mascot.pose = Pose.resting(at: 0.8, asleep: false)
        }
        // 捏合手势：系统只发给前台应用的窗口。小窗不在前台时从这里接
        NSEvent.addGlobalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] e in
            guard let self = self else { return }
            if e.type == .magnify { self.board.externalMagnify(e.magnification) }
            else if self.board.chartPoint() != nil {
                glog("scroll(global) dx=\(e.scrollingDeltaX) dy=\(e.scrollingDeltaY)")
                _ = self.board.chartScroll(dx: Double(e.scrollingDeltaX), dy: Double(e.scrollingDeltaY), precise: e.hasPreciseScrollingDeltas)
            }
        }
        // 智能缩放手势（双指轻点两下）也接上：在走势图上轻点两下，放大 / 回到全天
        NSEvent.addLocalMonitorForEvents(matching: [.smartMagnify]) { [weak self] e in
            if let b = self?.board, b.chartPoint() != nil { glog("smartMagnify"); b.toggleZoom() }
            return e
        }
        if testHome == nil { registerHotKey() }
        // 另一个 Peek 被启动时会发这个通知：把藏起来的小窗叫出来
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.cheerup.show"), object: nil, queue: .main) { [weak self] _ in
            self?.show()
        }
        refresh()
        if firstRun && !store.bool(forKey: "onboarded") {
            guideReplaces = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.showOnboarding() }
        }
        // 调试用（不模拟键鼠）：PEEK_SHOW=menu / add / guide 启动后自己翻到对应页面；PEEK_QUERY 填入搜索词；PEEK_PICK 点第几条结果
        let env = ProcessInfo.processInfo.environment
        if let what = env["PEEK_SHOW"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                guard let self = self else { return }
                if what == "menu" { self.openMenu(row: env["PEEK_ROW"].flatMap { Int($0) }) }
                if what == "menu", env["PEEK_RESET"] != nil, let i = self.board.pageRows.lastIndex(where: { $0.action != nil }), i > 0 { self.board.pageRows[i - 1].action?() }
                if what == "guide" { self.guideMarkets = ["a", "hk"]; self.guidePicked = [AppDelegate.popular[0].1[1]]; self.openGuide(env["PEEK_STEP"].flatMap { Int($0) } ?? 0) }
                if what == "add" {
                    self.addStock()
                    if let q = env["PEEK_QUERY"] {       // 通过输入框自己的编辑器填字，走和真实打字一样的路径
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { (self.board.searchField.currentEditor() as? NSTextView)?.insertText(q, replacementRange: NSRange(location: 0, length: 0)) }
                    }
                    if let n = env["PEEK_PICK"].flatMap({ Int($0) }) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { if n < self.board.pageRows.count { self.board.pageRows[n].action?() } }
                    }
                }
            }
        }
        for (n, code) in (ProcessInfo.processInfo.environment["PEEK_KEYS"] ?? "").split(separator: ",").compactMap({ UInt16($0) }).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2 + 0.4 * Double(n)) { [weak self] in
                guard let self = self, let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: self.panel.windowNumber,
                                                              context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code) else { return }
                let fr = self.panel.firstResponder === self.board
                (self.panel.firstResponder as? NSResponder ?? self.board).keyDown(with: e)
                FileHandle.standardError.write("key \(code): responder=board \(fr), selected=\(self.selected ?? "nil"), page=\(self.board.page)\n".data(using: .utf8)!)
            }
        }
        if let r = ProcessInfo.processInfo.environment["PEEK_RCLICK"].flatMap({ Int($0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.board.onContextMenu?(r) }
        }
        if let mv = ProcessInfo.processInfo.environment["PEEK_MOVE"]?.split(separator: ",").compactMap({ Int($0) }), mv.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.board.onReorder?(mv[0], mv[1]) }
        }
        if let h = ProcessInfo.processInfo.environment["PEEK_HOVER"].flatMap({ Int($0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.board.debugHover(row: h) }
        }
        // 调试用：PEEK_TABMOVE=0,2 启动 3 秒后把第 1 个市场标签拖到第 3 个；PEEK_TABMENU=1 在第 2 个标签上开右键菜单，PEEK_TABMENU=1,go 一路点到确认
        if let v = ProcessInfo.processInfo.environment["PEEK_TABMOVE"]?.split(separator: ",").compactMap({ Int($0) }), v.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                self.board.onReorderTab?(v[0], v[1])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { print("tabs=\(self.tabIDs) order=\(self.cfg.tabOrder)"); fflush(stdout) }
            }
        }
        if let v = ProcessInfo.processInfo.environment["PEEK_TABMENU"]?.split(separator: ","), let i = v.first.flatMap({ Int($0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                self.board.onTabMenu?(i)
                guard v.count > 1 else { return }
                self.board.dropdown?.pick(0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let d = self.board.dropdown; self.board.dropdown = nil; d?.pick(0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { print("tabs=\(self.tabIDs) stocks=\(self.cfg.stocks.count) tab=\(self.tab) shown=\(self.shown.count) boardTabs=\(self.board.tabs.count) selected=\(String(describing: self.selected))"); fflush(stdout) }
                }
            }
        }
        // 调试用：PEEK_POM=green 启动 3 秒后把花球配色改成这个，并打印换的过程
        if let v = ProcessInfo.processInfo.environment["PEEK_POM"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                _ = self.mutateConfigObject { $0["pomColor"] = v }
                for d in [0.05, 0.6, 1.0, 1.8] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                        print("cfg=\(self.cfg.pomColor) shown=\(self.mascot.cfg.pomColor) swapping=\(self.swapStart > 0) behind=\(String(format: "%.2f", Double(self.mascot.behind)))"); fflush(stdout)
                    }
                }
            }
        }
        // 调试用：PEEK_SETTING=mascotSize=l 启动 3 秒后改一项设置，前后打印面板上沿和右边在屏幕上的位置
        if let kv = ProcessInfo.processInfo.environment["PEEK_SETTING"]?.split(separator: "=").map(String.init), kv.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                func where_(_ t: String) { let f = self.panel.frame; print("\(t): 面板上沿=\(f.maxY - self.stageTop) 右边=\(f.maxX) 窗口=\(f.size)"); fflush(stdout) }
                where_("改之前")
                var v: Any = kv[1]
                if kv[1] == "true" { v = true } else if kv[1] == "false" { v = false }
                _ = self.mutateConfigObject { $0[kv[0]] = v }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { where_("改之后") }
            }
        }
        // 调试用：PEEK_AWAY=leave 启动 3 秒后让它走开；PEEK_AWAY=return 以「只剩花球」启动，3 秒后叫它回来
        if let v = ProcessInfo.processInfo.environment["PEEK_AWAY"] {
            if v == "return" { awayState = 2 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                if v == "return" { self.startReturning() } else { self.startLeaving() }
                for d in [0.1, 1.2, 2.6] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { print(String(format: "  +%.1fs 状态=%d 淡出=%.2f 位移=%.1f 左手有花球=%@ 地上花球=%@", d, self.awayState, Double(self.mascot.fade), Double(self.mascot.offsetX), self.mascot.heldLeft ? "是" : "否", self.mascot.loosePom != nil ? "有" : "无")); fflush(stdout) } }
            }
        }
        // 调试用：PEEK_PICKSET=行号,选项号 启动 3 秒后打开设置、展开那一行的下拉、点那个选项，配合 PEEK_EVT 看这期间发生了什么
        if let v = ProcessInfo.processInfo.environment["PEEK_PICKSET"]?.split(separator: ",").compactMap({ Int($0) }), v.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                self.openMenu(row: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.board.pageRows[v[0]].action?()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        print("—— 点选项 ——"); self.evtT0 = CACurrentMediaTime()
                        let d = self.board.dropdown; self.board.dropdown = nil; d?.pick(v[1])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.evt("结束 窗口=\(Int(self.panel.frame.width))x\(Int(self.panel.frame.height))"); self.evtT0 = 0 }
                    }
                }
            }
        }
        // 调试用：PEEK_COMBO=1 把「看板 / 拉拉队 / 全部」三个开关交叉着走一遍并打印
        if ProcessInfo.processInfo.environment["PEEK_COMBO"] != nil {
            func show(_ t: String) { print("\(t): 小窗=\(self.panel.isVisible ? "显示" : "藏") 看板=\(self.mini ? "收起" : "展开") 拉拉队=\(["在", "走开中", "不在", "回来中"][self.awayState]) 气泡=\(self.bubbleOpen) 窗口=\(Int(self.panel.frame.width))x\(Int(self.panel.frame.height)) 计时器=\(self.cheerTimer != nil)"); fflush(stdout) }
            let steps: [(Double, String, () -> Void)] = [
                (3.0, "1 起始", {}),
                (3.1, "2 点隐藏", { self.startLeaving() }),
                (5.6, "3 走完了", {}),
                (5.7, "4 收起看板（它不在）", { self.toggleMini() }),
                (6.3, "5 ⌃⌥D 展开", { self.hotkeyToggleBoard() }),
                (6.9, "6 ⌃⌥S 全藏", { self.toggle() }),
                (7.2, "7 藏着时按 ⌃⌥D", { self.hotkeyToggleBoard() }),
                (7.8, "8 点花球", { self.startReturning() }),
                (9.8, "9 回来了", {}),
                (9.9, "10 走开途中收起再展开", { self.startLeaving(); self.toggleMini() }),
                (10.4, "11", { self.toggleMini() }),
                (12.6, "12 走完", {}),
                (12.7, "13 回来途中全藏", { self.startReturning(); self.toggle() }),
                (15.0, "14 叫出来", { self.toggle() }),
                (15.6, "15 最后", {}),
            ]
            for (at, name, act) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + at) { act(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { show(name) } } }
        }
        // 调试用：PEEK_FLOW=场景 把换花球和喝咖啡撞在一起的几种情况走一遍并打印
        if let sc = ProcessInfo.processInfo.environment["PEEK_FLOW"] {
            func show(_ t: String) { print(String(format: "%@: 模式=%@ 换花球=%@ 待换=%@ 喝咖啡=%@ 杯子=%@ 绿=%@", t, self.modeCheer ? "加油" : "休息", self.swapStart > 0 ? "是" : "否", self.swapPending ? "是" : "否", self.teaStart > 0 ? "是" : "否", self.mascot.cup ? "有" : "无", self.mascot.greenUp ? "是" : "否")); fflush(stdout) }
            let usIdx = { self.tabIDs.firstIndex(of: "us") ?? 0 }
            var steps: [(Double, String, () -> Void)] = []
            if sc == "tab" {            // 切到美股：只换花球，不接咖啡
                steps = [(3.0, "切到美股", { self.board.onSelectTab?(usIdx()) }), (4.0, "1 秒后", {}), (5.2, "换完", {}), (7.5, "再过 2 秒", {}), (11, "再过 6 秒", {})]
            } else {                    // 喝到一半切到美股：杯子收到身后，就地换
                steps = [(3.0, "开始喝", { self.teaStart = CACurrentMediaTime(); self.teaFrom = self.mascot.pose; self.teaInRest = !self.modeCheer }), (5.6, "喝着时切到美股", { self.board.onSelectTab?(usIdx()) }),
                         (6.0, "0.4 秒后", {}), (7.0, "1.4 秒后", {}), (7.6, "2 秒后", {}), (8.6, "3 秒后", {}), (9.6, "4 秒后", {})]
            }
            for (at, name, act) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + at) { act(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { show(name) } } }
        }
        // 调试用：PEEK_FSM=1 启动 3 秒后把作息状态机的几条规则走一遍并打印
        if ProcessInfo.processInfo.environment["PEEK_FSM"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                func show(_ t: String) { print("\(t): schedule=\(self.cfg.restSchedule) tab=\(self.tab) live=\(self.marketLive) manual=\(String(describing: self.manual)) modeCheer=\(self.modeCheer)") }
                self.refreshMode(); show("1 起始")
                self.manual = !self.modeCheer; self.refreshMode(); show("2 手动切换")
                let before = self.manual
                self.board.onSelectTab?(1); show("3 换标签后（手动应保留=\(String(describing: before))）")
                _ = self.mutateConfigObject { $0["restSchedule"] = "never" }; self.refreshMode(); show("4 作息改成永不休息（手动应清掉）")
                self.manual = false; self.refreshMode(); show("5 永不休息时手动休息")
                _ = self.mutateConfigObject { $0["restSchedule"] = "auto" }; self.refreshMode(); show("6 作息改回跟随（手动应清掉）")
                self.manual = self.marketLive; self.refreshMode(); show("7 手动和作息一样（应清掉）")
                fflush(stdout)
            }
        }
        // 调试用：PEEK_BUBBLE=1 启动 3 秒后打开拉拉队的右键气泡；PEEK_BUBBLE=pick 再点第一项并打印状态
        if let v = ProcessInfo.processInfo.environment["PEEK_BUBBLE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                self.openBubble(); self.bubble.hover = 0
                if v == "click" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let inView = NSPoint(x: 20, y: 5 + 8)                       // 第一项里的一个点
                        let w = self.bubble.convert(inView, to: nil)
                        func ev(_ t: NSEvent.EventType) -> NSEvent { NSEvent.mouseEvent(with: t, location: w, modifierFlags: [], timestamp: 0, windowNumber: self.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)! }
                        print("hit=\(String(describing: self.stage.hitTest(self.stage.superview?.convert(w, from: nil) ?? w).map { type(of: $0) })) before modeCheer=\(self.modeCheer)")
                        self.bubble.mouseDown(with: ev(.leftMouseDown)); print("pressed=\(String(describing: self.bubble.pressed))")
                        self.bubble.mouseUp(with: ev(.leftMouseUp))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { print("after modeCheer=\(self.modeCheer) manual=\(String(describing: self.manual)) bubbleOpen=\(self.bubbleOpen)"); fflush(stdout) }
                    }
                    return
                }
                if v == "key" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let fr = self.panel.firstResponder
                        print("key=\(self.panel.isKeyWindow) firstResponder=\(String(describing: fr.map { type(of: $0) })) before modeCheer=\(self.modeCheer)")
                        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: self.panel.windowNumber, context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15)!
                        (fr ?? self.board).keyDown(with: e)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { print("after modeCheer=\(self.modeCheer) bubbleOpen=\(self.bubbleOpen)"); fflush(stdout) }
                    }
                    return
                }
                if v == "hide" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        print("before 收起=\(self.mini) 小窗可见=\(self.panel.isVisible) 状态=\(self.awayState)")
                        self.bubble.onPick?(2)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { print("after  收起=\(self.mini) 小窗可见=\(self.panel.isVisible) 状态=\(self.awayState) 气泡=\(self.bubbleOpen)"); fflush(stdout) }
                    }
                    return
                }
                guard v == "pick" else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("before manual=\(String(describing: self.manual)) resting0=\(self.resting0)")
                    self.bubble.onPick?(ProcessInfo.processInfo.environment["PEEK_PICKREST"] != nil ? 1 : (self.modeCheer ? 1 : 0))
                    print("after  manual=\(String(describing: self.manual)) resting0=\(self.resting0) bubbleOpen=\(self.bubbleOpen)"); fflush(stdout)
                    for d in [0.5, 3.0, 7.0, 9.0, 12.5] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                            let p = self.mascot.pose
                            print(String(format: "  +%.1fs 模式=%@ 喝咖啡=%@ 杯子=%@ 表情=%d z=%.2f", d, self.modeCheer ? "加油" : "休息", self.teaStart > 0 ? "是" : "否", self.mascot.cup ? "有" : "无", p.face, Double(p.z))); fflush(stdout)
                        }
                    }
                }
            }
        }
        // 调试用：PEEK_TOGGLE=1 启动 3 秒后自动收起（或展开）一次
        if ProcessInfo.processInfo.environment["PEEK_TOGGLE"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                self.toggleMini()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    print("mini=\(self.mini) folding=\(self.folding) fold=\(String(describing: self.board.fold)) boardHidden=\(self.board.isHidden) onBoard=\(self.mascot.onBoard) frame=\(self.panel.frame.size)"); fflush(stdout)
                }
            }
        }
        // 调试用：PEEK_TAB=2 启动 3 秒后自动切到第 3 个市场页
        if let s = ProcessInfo.processInfo.environment["PEEK_TAB"], let i = Int(s) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                if ProcessInfo.processInfo.environment["PEEK_TRACE"] != nil { self.traceStart = CACurrentMediaTime(); self.traceUntil = self.traceStart + 4.2 }
                self.board.onSelectTab?(i)
                for d in [0.0, 0.4, 0.7, 1.4] {       // 打印换花球的过程，方便不看屏幕也能核对
                    DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                        print("tab=\(self.tab) swapping=\(self.swapStart > 0) behind=\(String(format: "%.2f", Double(self.mascot.behind))) pomGreen=\(self.mascot.greenUp) frame=\(self.panel.frame.size) mascotHidden=\(self.mascot.isHidden) boardHidden=\(self.board.isHidden)")
                        fflush(stdout)
                    }
                }
            }
        }
        // 调试用：PEEK_SELECT=2 启动后自动展开第 3 行
        if let s = ProcessInfo.processInfo.environment["PEEK_SELECT"], let i = Int(s) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.board.onClickRow?(i) }
        }
    }

    func applyConfig() {
        evt("applyConfig")
        board.cfg = cfg
        // 在设置里换了花球配色：也背手换一副，新颜色等手在身后时才换上
        var mc = cfg
        if mascot.cfg.pomColor != cfg.pomColor {
            let now = CACurrentMediaTime()
            if teaStart > 0, cheerTimer != nil, !mascot.isHidden, panel.isVisible { swapPending = true }
            else if swapStart == 0, cheerTimer != nil, !mascot.isHidden, panel.isVisible { swapStart = now }
            if swapPending || (swapStart > 0 && !swapState(min((now - swapStart) / swapSeconds, 1)).found) { mc.pomColor = mascot.cfg.pomColor }
        }
        mascot.cfg = mc
        if !mascotVisible, bubbleOpen { bubbleOpen = false; bubble.isHidden = true }
        if cheerTimer != nil || mascotVisible { DispatchQueue.main.async { [weak self] in self?.updateCheer() } }
        UI.theme = cfg.theme; UI.fontSize = CGFloat(cfg.fontSize); UI.color = cfg.color
        lang = cfg.language.isEmpty ? systemLang() : cfg.language
        // 默认截图和屏幕共享里都能看到；配置里打开 hideFromScreenShare 后只有鼠标停在上面时才看得到
        panel.sharingType = (cfg.hideFromScreenShare && !hovering) ? .none : .readOnly
        // 快捷键没注册上时必须留着菜单栏小圆点，不然隐藏后就叫不回来了
        let wantIcon = cfg.menuBarIcon || !hotKeyOK
        if wantIcon, statusItem == nil {
            // 新图标默认排在最左边，在带刘海的 MacBook 屏幕上会被刘海挡住看不见。
            // 第一次创建时把它排到靠右的位置（系统图标旁边）；之后用户按住 ⌘ 拖动过就以用户的为准
            let posKey = "NSStatusItem Preferred Position WatchUp"
            if UserDefaults.standard.object(forKey: posKey) == nil { UserDefaults.standard.set(360.0, forKey: posKey) }
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.autosaveName = "WatchUp"
            statusItem?.button?.image = AppDelegate.barIcon()
            statusItem?.button?.toolTip = "CheerUp"
            statusItem?.button?.target = self
            statusItem?.button?.action = #selector(statusClicked)
        } else if !wantIcon, let s = statusItem {
            NSStatusBar.system.removeStatusItem(s); statusItem = nil
        }
        let interval = cfg.refreshSeconds
        if timer?.timeInterval != interval {
            timer?.invalidate()
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh(auto: true) }
            t.tolerance = interval * 0.1
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    // MARK: 小窗里的页面：菜单 / 添加 / 引导（都在小窗这一块里完成，不另开窗口）

    func setPage(_ p: Page, title: String, rows: [PRow], foot: String = "", nav: [(String, () -> Void)] = [], dots: (Int, Int)? = nil, minRows: Int = 0) {
        selected = nil; board.detail = nil; closing = false
        if mini { mini = false; store.set(false, forKey: "mini") }
        if !panel.isVisible { panel.orderFrontRegardless() }
        let wasAdd = board.page == .add
        board.dropdown = nil; board.pageAction = nil
        board.page = p; board.pageTitle = title; board.pageRows = rows; board.pageFoot = foot; board.pageFootAccent = false
        board.pageNav = nav; board.pageDots = dots; board.pageMinRows = minRows
        if wasAdd, p != .add { releaseKeyboard() }
        render()
        board.placeSearchField()
    }

    /// 把前台还给原来的程序
    func returnFocus() {
        guard let app = borrowedFrom else { return }
        borrowedFrom = nil
        if NSApp.isActive { app.activate(options: []) }
    }

    /// 详情展开或翻到别的页面时接住键盘（↑↓ 换一只 / 换一行）；回到普通列表就把键盘还给原来的窗口
    func syncKeyboard() {
        guard let kp = panel as? KeyPanel else { return }
        let need = panel.isVisible && !mini && (selected != nil || board.page != .list)
        if need {
            if !kp.allowKey || !panel.isKeyWindow { kp.allowKey = true; panel.makeKey() }
            if board.page != .add, panel.firstResponder !== board { panel.makeFirstResponder(board) }
        } else if kp.allowKey {
            releaseKeyboard()
            returnFocus()
        }
    }

    /// 「添加」页借用了键盘焦点，离开时还给原来的窗口
    func releaseKeyboard() {
        evt("releaseKeyboard（窗口会藏一下再显示）key=\(panel.isKeyWindow)")
        (panel as? KeyPanel)?.allowKey = false
        panel.makeFirstResponder(nil)
        if panel.isKeyWindow, panel.isVisible { panel.orderOut(nil); panel.orderFrontRegardless() }
    }

    func closePage() {
        guard board.page != .list else { return }
        let wasAdd = board.page == .add
        board.page = .list; board.pageRows = []; board.pageNav = []; board.pageFoot = ""; board.pageDots = nil; board.pageMinRows = 0
        board.keyNav = false; board.dropdown = nil; board.pageAction = nil
        board.placeSearchField()
        searchTimer?.invalidate()
        if wasAdd { releaseKeyboard() }
        render(); refresh()
    }

    /// 菜单页和详情一样是「临时翻出来看一眼」的东西：鼠标离开 5 秒自己收回。添加和设置页要打字、要做选择，不自动收
    func schedulePageClose() {
        pageIdle?.invalidate(); pageIdle = nil
        guard board.page == .menu, !hovering, cfg.detailAutoCloseSeconds > 0 else { return }
        pageIdle = Timer.scheduledTimer(withTimeInterval: cfg.detailAutoCloseSeconds, repeats: false) { [weak self] _ in
            guard let self = self, !self.hovering, self.board.page == .menu else { return }
            self.closePage()
        }
    }

    func openMenu(row: Int?, keepOpen: Bool = false) {
        if board.page == .menu, row == nil { closePage(); return }
        if !keepOpen { menuOpen = nil; confirmReset = false }
        var rows: [PRow] = []
        let list = shown
        // 设置项：名称在左，当前值在右。点一下在这一行下面展开选项，再点某个选项才生效
        let reopen: () -> Void = { [weak self] in self?.board.page = .list; self?.openMenu(row: row, keepOpen: true) }
        func setting(_ id: String, _ title: String, current: String, options: [(String, String)], apply: @escaping (String) -> Void) {
            let idx = rows.count
            let cur = options.firstIndex { $0.0 == current } ?? 0
            rows.append(PRow(text: title, right: options[cur].1 + "  ▾", action: { [weak self] in
                guard let self = self else { return }
                self.board.dropSel = cur
                self.board.dropdown = BoardView.Dropdown(row: idx, options: options.map { $0.1 }, current: cur) { i in
                    if i != cur { apply(options[i].0) }
                    reopen()
                }
            }))
        }
        // 第一组：界面本身（大小、语言）——最常改、影响也最大的放最前面
        setting("ui", T("界面大小", "Interface size"), current: cfg.uiSize,
                options: [("s", T("小", "Small")), ("m", T("中", "Medium")), ("l", T("大", "Large")), ("xl", T("特大", "Extra large"))]) { [weak self] v in
            _ = self?.mutateConfigObject { $0["uiSize"] = v }
        }
        setting("lang", T("语言", "Language"), current: lang, options: [("zh", "中文"), ("en", "English")]) { [weak self] v in
            _ = self?.mutateConfigObject { $0["language"] = v }
        }
        rows.append(PRow(sep: true))
        // 第二组：拉拉队（大小、花球、作息）
        if cfg.miniStyle != "face" {
            setting("size", T("拉拉队大小", "Cheerleader size"), current: cfg.mascotSize,
                    options: [("s", T("小", "Small")), ("m", T("中", "Medium")), ("l", T("大", "Large"))]) { [weak self] v in
                _ = self?.mutateConfigObject { $0["mascotSize"] = v }
            }
            setting("pom", T("花球配色", "Pom-pom color"), current: cfg.pomColor == "white" ? "auto" : cfg.pomColor,
                    options: [("auto", T("跟随市场", "Match market")), ("red", T("红", "Red")), ("green", T("绿", "Green")),
                              ("yellow", T("黄", "Yellow")), ("blue", T("蓝", "Blue"))]) { [weak self] v in
                _ = self?.mutateConfigObject { $0["pomColor"] = v }
            }
            // 作息跟着哪个市场走：那个市场开盘就跳，休市就睡
            setting("rest", T("拉拉队作息", "Cheerleader hours"), current: cfg.restSchedule,
                    options: [("auto", T("跟随当前市场", "Match market")), ("a", T("跟随 A 股", "China")), ("hk", T("跟随港股", "Hong Kong")),
                              ("us", T("跟随美股", "US")), ("never", T("永不休息", "Never rests"))]) { [weak self] v in
                _ = self?.mutateConfigObject { $0["restSchedule"] = v }
                self?.refreshMode()
            }
            rows.append(PRow(sep: true))
        }
        // 第三组：程序（登录时打开、恢复默认、退出）
        setting("login", T("登录时打开", "Open at login"), current: loginItemOn ? "on" : "off",
                options: [("on", T("开", "On")), ("off", T("关", "Off"))]) { [weak self] _ in self?.toggleLoginItem() }
        // 恢复默认设置：和别的操作一样是列表里的一行。要点两次才生效，免得误触
        let confirming = confirmReset
        let resetAction: () -> Void = { [weak self] in
            guard let self = self else { return }
            if confirming {
                self.confirmReset = false
                // 拉拉队和外观的设置回到默认；自选股、别名、语言不动
                let keep = ["stocks", "aliases", "language"]
                _ = self.mutateConfigObject { obj in obj = obj.filter { keep.contains($0.key) } }
                self.marketCheckedAt = 0
                self.flash(T("已恢复默认", "Defaults restored"))
            } else {
                self.confirmReset = true
            }
            reopen()
        }
        rows.append(PRow(text: confirming ? T("再点一次确认恢复", "Click again to restore") : T("恢复默认设置", "Restore default settings"), check: confirming ? true : nil, action: resetAction))
        rows.append(PRow(text: T("退出 CheerUp", "Quit CheerUp"), action: { NSApp.terminate(nil) }))
        setPage(.menu, title: T("设置", "Settings"), rows: rows)

        schedulePageClose()
    }

    /// 点顶部栏的图标：小窗藏着就叫出来，开着就藏起来
    @objc func statusClicked() { toggle() }

    /// 顶部栏图标：小窗里一条带箭头的走势线。模板图，系统会按深浅色自动上色
    static func barIcon() -> NSImage {
        // 和系统的电池图标同一种画法：一圈细的、半透明的圆角外框，里面的图形是实的。
        // 里面是一条往上走的走势线，线头不是箭头，而是一个花球
        let img = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { _ in
            let frame = NSBezierPath(roundedRect: NSRect(x: 0.75, y: 2.75, width: 20.5, height: 12.5), xRadius: 3.6, yRadius: 3.6)
            NSColor.black.withAlphaComponent(0.5).setStroke()
            frame.lineWidth = 1.0; frame.stroke()
            NSColor.black.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 4.3, y: 11.9)); line.line(to: NSPoint(x: 7.4, y: 9.2)); line.line(to: NSPoint(x: 9.6, y: 10.6)); line.line(to: NSPoint(x: 12.4, y: 8.0))
            line.lineWidth = 1.5; line.lineCapStyle = .round; line.lineJoinStyle = .round; line.stroke()
            let pom = NSBezierPath(), c = NSPoint(x: 15.0, y: 6.9), r: CGFloat = 2.5
            for k in 0..<3 {
                let a = CGFloat(k) * .pi / 3 + .pi / 6
                pom.move(to: NSPoint(x: c.x - cos(a) * r, y: c.y - sin(a) * r)); pom.line(to: NSPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
            }
            pom.lineWidth = 1.5; pom.lineCapStyle = .round; pom.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }

    // —— 添加 ——

    @objc func addStock() {
        if board.page == .add { closePage(); return }
        lastHits = []
        board.searchField.stringValue = ""
        board.keySel = 0
        setPage(.add, title: T("添加", "Add"), rows: [], minRows: 6)
        (panel as? KeyPanel)?.allowKey = true
        panel.makeKey()
        panel.makeFirstResponder(board.searchField)
    }

    func searchChanged(_ text: String) {
        searchTimer?.invalidate()
        searchSeq += 1
        guard board.page == .add else { return }
        guard let (q, market) = cleanQuery(text) else {
            lastHits = []
            let typed = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            showHits(foot: typed ? T("只能搜名称、拼音或代码", "Search by name or ticker only") : "")
            return
        }
        let mine = searchSeq
        if lastHits.isEmpty { showHits(foot: T("搜索中…", "Searching…")) }
        let t = Timer(timeInterval: 0.22, repeats: false) { [weak self] _ in      // 停手一小会儿再搜，别每个字母都发请求
            self?.runSearch(q, market: market, shown: text.trimmingCharacters(in: .whitespacesAndNewlines)) { hits, foot in
                guard let self = self, self.searchSeq == mine, self.board.page == .add else { return }    // 旧结果回来晚了就丢掉
                self.lastHits = Array(hits.prefix(6))
                self.board.keySel = 0
                // 搜到的都已经在列表里：别再提示「回车添加」
                let allListed = !self.lastHits.isEmpty && self.lastHits.allSatisfy { self.isListed($0) }
                self.showHits(foot: allListed ? T("已经在列表里了", "Already in your list") : foot)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        searchTimer = t
    }

    /// 一次完整的搜索，带三层兜底：
    /// 1. 搜索接口正常返回结果 → 直接用
    /// 2. 没结果或接口不通，而输入像一个代码 → 直接问行情接口有没有这只
    /// 3. 还是没有，而输入是名称 → 去掉最后一个字再搜（多半是打错了一个字），告诉用户这是相近的结果
    func runSearch(_ q: String, market: String?, shown: String, done: @escaping ([SearchHit], String) -> Void) {
        let pick = T("↑↓ 选择，回车添加", "↑↓ to select, Return to add")
        func byCode(else fallback: @escaping () -> Void) {
            let cands = codeCandidates(q).filter { c in market.map { c.hasPrefix($0) || (c.hasPrefix("r_hk") && $0 == "hk") } ?? true }
            guard !cands.isEmpty else { fallback(); return }
            fetchQuotes(cands) { quotes in
                guard let quotes = quotes else { fallback(); return }
                let hits = cands.compactMap { key -> SearchHit? in
                    guard let quote = quotes[key], quote.prevClose > 0 || quote.price > 0 else { return nil }
                    let mk = Market.of(key)
                    let short = mk == .us ? String(key.dropFirst(2)) : quote.code
                    let code = mk == .hk ? "hk" + quote.code : (mk == .us ? key : (apiSymbol(quote.code) == key ? quote.code : key))
                    let tag = mk == .hk ? T("港股", "HK") : (mk == .us ? T("美股", "US") : (key.hasPrefix("sh") ? T("沪", "SH") : (key.hasPrefix("sz") ? T("深", "SZ") : T("北", "BJ"))))
                    return SearchHit(code: code, name: self.displayName(quote, key: key), shortCode: short, market: tag, tag: quote.str(61).contains("ZS") ? T("指数", "Index") : tag)
                }
                if hits.isEmpty { fallback() } else { done(hits, pick) }
            }
        }
        func shorter(_ word: String, tries: Int) {
            let cjk = word.unicodeScalars.contains { $0.value >= 0x2E80 }
            guard tries > 0, word.count > (cjk ? 1 : 3) else { done([], T("没找到「\(shown)」", "No results for “\(shown)”")); return }
            let w = String(word.dropLast())
            searchStocks(w, query: w, market: market) { hits, _ in
                if hits.isEmpty { shorter(w, tries: tries - 1) }
                else { done(hits, T("没找到「\(shown)」，相近的有", "No “\(shown)”. Similar:")) }
            }
        }
        let idx = indexHits(shown, market: market)        // 用原始输入匹配（清洗会去掉 & 这样的符号）
        searchStocks(q, query: q, market: market) { hits, ok in
            var seen = Set<String>()
            let merged = (idx + hits).filter { seen.insert(apiSymbol($0.code)).inserted }
            if !merged.isEmpty { done(merged, pick); return }
            byCode {
                if ok { shorter(q, tries: 2) } else { done([], T("没连上网络", "No connection")) }
            }
        }
    }

    /// 直接问行情接口。返回 nil 表示没连上
    func fetchQuotes(_ keys: [String], done: @escaping ([String: Quote]?) -> Void) {
        guard let url = URL(string: host("https://qt.gtimg.cn/") + "q=" + keys.joined(separator: ",")) else { done(nil); return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        req.setValue("https://gu.qq.com", forHTTPHeaderField: "Referer")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let parsed = data.flatMap { String(data: $0, encoding: gbk) }.map(parseQuotes)
            DispatchQueue.main.async { done(parsed) }
        }.resume()
    }

    func isListed(_ h: SearchHit) -> Bool { cfg.stocks.contains { isValidCode($0) && apiSymbol($0) == apiSymbol(h.code) } }

    /// 把搜索结果画成和股票列表一样的行：名称在左，代码和市场在右
    func showHits(foot: String, accent: Bool = false) {
        board.pageRows = lastHits.map { h in
            let listed = isListed(h)
            return PRow(text: h.name, right: listed ? T("已添加", "Added") : "\(h.shortCode)  \(h.tag.isEmpty ? h.market : h.tag)", dim: listed,
                        action: listed || adding ? nil : { [weak self] in self?.addHit(h) })
        }
        board.pageFoot = foot; board.pageFootAccent = accent
        render()
    }

    /// 加进列表之前先确认这只真的有行情：搜索结果里偶尔有已退市、长期停牌、行情接口不收录的
    func addHit(_ h: SearchHit) {
        if isListed(h) { showHits(foot: T("「\(h.name)」已经在列表里", "\(h.name) is already listed"), accent: true); return }
        if cfg.stocks.count >= maxStocks { showHits(foot: T("最多 \(maxStocks) 只，先移除几只", "Limit is \(maxStocks). Remove some first"), accent: true); return }
        guard !adding else { return }
        adding = true
        showHits(foot: T("正在确认「\(h.name)」…", "Checking \(h.name)…"))
        let key = apiSymbol(h.code)
        fetchQuotes([key]) { [weak self] quotes in
            guard let self = self else { return }
            self.adding = false
            guard self.board.page == .add else { return }
            guard let quotes = quotes else { self.showHits(foot: T("没连上网络，没添加", "No connection. Not added"), accent: true); return }
            guard let q = quotes[key], q.prevClose > 0 || q.price > 0 else {
                self.showHits(foot: T("「\(h.name)」查不到行情，没添加", "No quote for \(h.name). Not added"), accent: true); return
            }
            if q.str(40) == "D" || (q.stamp.map { Date().timeIntervalSince($0) > 45 * 86400 } ?? false) {      // 接口把退市、长期停牌的标成 D
                self.showHits(foot: T("「\(h.name)」已停止交易，没添加", "\(h.name) no longer trades. Not added"), accent: true); return
            }
            guard self.mutateConfig({ $0.append(h.code) }) else { self.showHits(foot: T("配置文件有误，没保存", "Config file error. Not saved"), accent: true); return }
            self.quotes[key] = q                   // 回到列表时这一行马上有数
            self.tab = AppDelegate.tabOf(h.code)   // 回到列表，停在它所在的那一页，标题条上提示一句
            self.closePage()
            self.flash(T("已添加「\(h.name)」", "Added \(h.name)"))
        }
    }

    // —— 引导 ——

    static var popular: [(String, [SearchHit])] {
        func h(_ code: String, _ zh: String, _ en: String, _ short: String, _ mk: String) -> SearchHit { SearchHit(code: code, name: T(zh, en), shortCode: short, market: mk) }
        let sh = T("沪", "SH"), sz = T("深", "SZ"), hk = T("港股", "HK"), us = T("美股", "US")
        return [
            ("a", [h("sh000001", "上证指数", "SSE Composite", "000001", sh), h("600519", "贵州茅台", "Kweichow Moutai", "600519", sh),
                   h("300750", "宁德时代", "CATL", "300750", sz), h("002594", "比亚迪", "BYD", "002594", sz)]),
            ("hk", [h("hkHSI", "恒生指数", "Hang Seng", "HSI", hk), h("hk00700", "腾讯控股", "Tencent", "00700", hk), h("hk09988", "阿里巴巴", "Alibaba", "09988", hk)]),
            ("us", [h("us.IXIC", "纳斯达克", "Nasdaq", ".IXIC", us), h("usAAPL", "苹果", "Apple", "AAPL", us), h("usNVDA", "英伟达", "NVIDIA", "NVDA", us)]),
        ]
    }

    @objc func showOnboarding() { guideMarkets = ["a"]; guidePicked = []; openGuide(0) }

    func openGuide(_ step: Int) {
        guideStep = step
        var rows: [PRow] = []
        var title = ""
        switch step {
        case 0:         // 语言：选了立刻生效，后面两步就用这个语言
            title = "语言 / Language"
            for (id, name) in [("zh", "中文"), ("en", "English")] {
                rows.append(PRow(text: name, check: lang == id, action: { [weak self] in
                    guard let self = self else { return }
                    lang = id
                    if !self.mutateConfigObject({ $0["language"] = id }) { self.cfg.language = id }
                    self.openGuide(0)
                }))
            }
        case 1:
            title = T("选择市场", "Markets")
            for (id, name) in [("a", T("A 股", "China A-shares")), ("hk", T("港股", "Hong Kong")), ("us", T("美股", "US"))] {
                rows.append(PRow(text: name, check: guideMarkets.contains(id), action: { [weak self] in
                    guard let self = self else { return }
                    if self.guideMarkets.contains(id) { if self.guideMarkets.count > 1 { self.guideMarkets.remove(id) } } else { self.guideMarkets.insert(id) }
                    self.openGuide(1)
                }))
            }
        default:
            title = T("挑几只", "Pick a few")
            for h in AppDelegate.popular.filter({ guideMarkets.contains($0.0) }).flatMap({ $0.1 }) {
                let on = guidePicked.contains { $0.code == h.code }
                rows.append(PRow(text: h.name, right: "\(h.shortCode)  \(h.market)", check: on, action: { [weak self] in
                    guard let self = self else { return }
                    if on { self.guidePicked.removeAll { $0.code == h.code } } else { self.guidePicked.append(h) }
                    self.openGuide(2)
                }))
            }
        }
        var nav: [(String, () -> Void)] = []
        if step == 0 { nav.append((T("跳过", "Skip"), { [weak self] in store.set(true, forKey: "onboarded"); self?.closePage() })) }
        else { nav.append((T("上一步", "Back"), { [weak self] in self?.openGuide(step - 1) })) }
        if step < 2 { nav.append((T("下一步", "Next"), { [weak self] in self?.openGuide(step + 1) })) }
        else { nav.append((T("完成", "Done"), { [weak self] in self?.finishGuide() })) }
        setPage(.guide, title: title, rows: rows, foot: step == 2 ? T("之后点 + 可以再加", "Add more later with +") : "", nav: nav, dots: (step, 3))
    }

    func finishGuide() {
        store.set(true, forKey: "onboarded")
        let codes = guidePicked.map { $0.code }
        if !codes.isEmpty {        // 一只都没选就不动原来的列表
            let replace = guideReplaces
            let ok = mutateConfigObject { obj in
                let old = replace ? [] : ((obj["stocks"] as? [String]) ?? [])
                obj["stocks"] = old + codes.filter { c in !old.contains { isValidCode($0) && apiSymbol($0) == apiSymbol(c) } }
            }
            if !ok { flash(T("配置文件有误，没保存", "Config file error. Not saved")) }
            tab = AppDelegate.tabOf(codes[0])
        }
        guideReplaces = false
        closePage()
    }

    /// 在标题条上显示几秒钟的一句话（代替系统提示框）
    func flash(_ text: String) {
        flashText = text
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.flashText = nil; self?.render() }
        render()
    }

    @objc func show() {
        if !panel.isVisible { panel.orderFrontRegardless() }
        render(); refresh()
        updateCheer()
    }

    @objc func toggle() {
        closePage()
        if panel.isVisible { panel.orderOut(nil); updateCheer() } else { show() }
    }

    /// 程序已经在跑时又被双击 / 从聚焦搜索打开：把小窗叫出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    // MARK: 开机自动启动（写一个 LaunchAgent，由用户自己在菜单里开关）

    var loginAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/local.cheerup.plist")
    }
    var loginItemOn: Bool { FileManager.default.fileExists(atPath: loginAgentURL.path) }

    @objc func toggleLoginItem() {
        if loginItemOn {
            try? FileManager.default.removeItem(at: loginAgentURL)
            return
        }
        let plist: [String: Any] = ["Label": "local.cheerup", "RunAtLoad": true,
                                    "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath]]
        try? FileManager.default.createDirectory(at: loginAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: loginAgentURL)
        }
    }

    // MARK: 增删自选股（直接改配置文件里的 stocks）

    /// 读出配置 → 改 → 写回。配置格式有误时不动文件，返回 false
    func mutateConfig(_ change: (inout [String]) -> Void) -> Bool {
        mutateConfigObject { obj in
            var list = (obj["stocks"] as? [String]) ?? self.cfg.stocks
            change(&list)
            obj["stocks"] = list
        }
    }

    func mutateConfigObject(_ change: (inout [String: Any]) -> Void) -> Bool {
        guard let data = try? Data(contentsOf: configURL),
              var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              decodeConfig(data) != nil else { return false }
        change(&obj)
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              (try? out.write(to: configURL, options: .atomic)) != nil else { return false }
        refresh()
        return true
    }

    func edit(_ change: (inout [String]) -> Void) {
        if !mutateConfig(change) { flash(T("配置文件有误，没保存", "Config file error. Not saved")) }
    }

    struct SearchHit { var code: String; var name: String; var shortCode: String; var market: String; var tag = "" }

    /// 用腾讯的搜索接口按名称 / 拼音 / 代码找股票。回调第二个参数表示接口是否连通
    func searchStocks(_ q: String, query: String = "", market: String? = nil, done: @escaping ([SearchHit], Bool) -> Void) {
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let url = URL(string: host("https://smartbox.gtimg.cn/") + "s3/?v=2&t=all&q=" + enc) else { done([], false); return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 6)) { data, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }
            let hits = text.map { parseSearch($0, query: query, market: market) } ?? []
            let ok = text.map { $0.contains("v_hint") } ?? false          // 返回的不是搜索结果（被拦截、报错页）也算没连上
            DispatchQueue.main.async { done(hits, ok) }
        }.resume()
    }

    /// 收起并且看得见的时候才播动作；展开、隐藏时停掉节拍，不白耗电
    func updateCheer() {
        defer { syncBubbleKey() }
        let run = panel.isVisible && mascotVisible && ProcessInfo.processInfo.environment["PEEK_CHEER_T"] == nil
        if !run {
            if bubbleOpen { bubbleOpen = false; bubble.isHidden = true }       // 小窗藏起来时气泡也跟着收，不然再叫出来时它还开着
            cheerTimer?.invalidate(); cheerTimer = nil; return
        }
        guard cheerTimer == nil else { return }
        cheerStart = CACurrentMediaTime() + 0.25           // 等小窗缩完再开始
        cheerBlendFrom = nil
        cheerResting = false; marketCheckedAt = 0
        mascot.pose = cheerRoutine[0].pose
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.cheerTick() }
        RunLoop.main.add(t, forMode: .common)
        cheerTimer = t
    }

    var wobble = Wobble()
    var lastOrigin = NSPoint.zero, lastOriginAt = 0.0, lastMovedAt = 0.0
    var dragVX: CGFloat = 0, dragVY: CGFloat = 0
    var tickN = 0
    var quietDiv = 1                 // 安静的时候每几拍才真算一次（1 = 每拍都算）
    func cheerTick() {
        // 它睡着了、或者不在（只剩花球）的时候，画面几乎不动，没必要每秒算 30 次、画 20 次：它可能一歇就是一整晚。
        // 这时大部分拍子直接跳过；鼠标一靠近就恢复全速，所以反应不会变慢
        tickN += 1
        if quietDiv > 1, tickN % quietDiv != 0, wobble.isCalm, !panel.frame.insetBy(dx: -48, dy: -48).contains(NSEvent.mouseLocation) { return }
        let now = CACurrentMediaTime()
        if now - marketCheckedAt > 5 {          // 每 5 秒看一眼当前这一页的市场是不是在交易
            marketCheckedAt = now
            refreshMode()
        }
        // 鼠标在它周围一圈（不必正好压在身上）就算在看它
        // 展开时，鼠标在面板上也算在看它：它会停下来，眼睛跟着鼠标在面板上走
        let mr = mascotScreenRect
        // 进来的线（30）比出去的线（48）靠里：鼠标停在边界上时不会一会儿算在、一会儿算不在，它也就不会在两种样子之间来回闪
        var near = (mascotVisible && mr.insetBy(dx: nearLatch ? -48 : -30, dy: nearLatch ? -48 : -30).contains(NSEvent.mouseLocation)) || (!mini && mouseInside())
        nearLatch = near
        if ProcessInfo.processInfo.environment["PEEK_NEAR"] != nil { near = true }      // 调试用：当作鼠标一直在面板上
        if nearMuted {                         // 刚切过模式：鼠标离开那一片超过半秒之前，都不算在看它
            if muteZone.contains(NSEvent.mouseLocation) || near { muteOutAt = 0 }
            else if muteOutAt == 0 { muteOutAt = now }
            else if now - muteOutAt > 0.5 { nearMuted = false }
            near = false
        }
        if near { lastNearAt = now }
        // 鼠标在拉拉队身上停一小会儿，它旁边就冒出气泡；鼠标离开它和气泡一会儿，气泡自己收起来
        let onMascotArea = mascotVisible && mascotScreenRect.contains(NSEvent.mouseLocation)
        let onMascot = onMascotArea && awayState == 0          // 它不在的时候，这块地方不算「在它身上」（不冒气泡、不摆「嗯？」）
        // 脚下那块板：收起着、鼠标指着它时亮一点
        let mp = mascot.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let hot = mini && onMascotArea && mascot.pillRect.insetBy(dx: -3, dy: -3).contains(mp)
        if hot != mascot.pillHot { mascot.pillHot = hot; mascot.needsDisplay = true }
        if !onMascot { bubbleHoverAt = 0; bubbleMuted = false }
        else if bubbleHoverAt == 0 { bubbleHoverAt = now }
        // 按着鼠标（点它、拖它）的时候不出气泡；已经出来的马上藏掉，窗口等松手再缩
        let pressing = NSEvent.pressedMouseButtons & 1 != 0
        let onBubble = bubbleOpen && (bubble.window?.convertToScreen(bubble.convert(bubble.bounds, to: nil)).contains(NSEvent.mouseLocation) ?? false)
        if pressing, !onBubble, onMascot || bubbleOpen {
            bubbleMuted = true
            if bubbleOpen { bubbleOpen = false; bubble.isHidden = true; bubbleShrinkPending = true }
        }
        if !pressing, bubbleShrinkPending { bubbleShrinkPending = false; render() }
        // 鼠标要进到它身上里面一点才开气泡（而不是刚擦到边），同样是为了不在边界上一开一关地闪
        let wellInside = onMascot && mascotScreenRect.insetBy(dx: 4, dy: 4).contains(NSEvent.mouseLocation)
        if wellInside, !pressing, !bubbleOpen, !bubbleMuted, !bubbleShrinkPending, !folding, animTimer == nil { openBubble() }
        if bubbleOpen {
            // 只看它本人和气泡这两块（各放宽几个点）。不能把看板也算进去，那样鼠标移到看板上气泡还一直开着
            let stillOn = mascotScreenRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
                || (bubble.window?.convertToScreen(bubble.convert(bubble.bounds, to: nil)).insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) ?? false)
            if stillOn { bubbleLeftAt = 0 }
            else if bubbleLeftAt == 0 { bubbleLeftAt = now }
            else if now - bubbleLeftAt > 0.15, ProcessInfo.processInfo.environment["PEEK_BUBBLE"] == nil { closeBubble() }      // 调试时不自动收
        }
        if bubbleOpen {                                        // 气泡开着时它醒着、停下来；鼠标指着哪一项，哪一项亮
            near = true; lastNearAt = now
            if ProcessInfo.processInfo.environment["PEEK_BUBBLE"] == nil { bubble.hover = bubble.row(at: bubble.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)) }
        }
        // 鼠标走开后不是马上睡：先醒着 1.5 秒，然后 5 秒里眼皮越来越沉，最后才睡着
        let away = now - lastNearAt
        let drowsy = CGFloat(min(max((away - 1.5) / 5.0, 0), 1))
        let off = resting0
        let asleep = off && !near && drowsy >= 1
        let resting = near || off          // 鼠标在旁边，或者市场没在交易（午休、收盘、周末）：歇着
        if resting != cheerResting {
            cheerResting = resting
            cheerBlendFrom = mascot.pose; cheerBlendStart = now
            if !resting { cheerStart = now + 0.3 }      // 重新开始时从头跳
        }
        // 休息时一秒只算 12 个画面：动作本来就慢，没必要按 30 帧重画（它可能一歇就是一整晚）
        let rt = (now * 20).rounded() / 20          // 休息时一秒 20 个画面：够顺，又不用按 30 帧重画
        var target = resting ? Pose.resting(at: rt, asleep: asleep) : cheerPose(at: max(0, now - cheerStart))
        var sleepyBlink = false
        var zFade: CGFloat = 1
        if resting, !near, off, drowsy > 0 {
            // 犯困：眨眼越来越慢、闭着的时间越来越长，头一点一点往下掉。
            // 睡着之后这些不是一下子停：头保持歪着，点头的幅度用 2 秒慢慢收掉，z 用 1.5 秒淡入
            let since = max(0, away - 6.5)                              // 睡着了多久
            let ph = CGFloat((rt / 1.6).truncatingRemainder(dividingBy: 1))
            let amp = asleep ? max(0, 1 - CGFloat(since) / 2) : drowsy
            target.hop += 1.1 * amp * max(0, sin(ph * 2 * .pi))
            target.lean += 0.5 * drowsy
            if asleep { zFade = CGFloat(min(1, since / 1.5)) }
            else { sleepyBlink = ph < 0.15 + 0.8 * drowsy }             // 快睡着时几乎一直闭着，接上睡着后的闭眼
        }
        if zFade != mascot.zFade { mascot.zFade = zFade; mascot.needsDisplay = true }
        // 鼠标停在它身上时：醒着，眼睛跟着鼠标走
        var gaze = NSPoint.zero
        if near {
            let m = mascot.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
            let half = max(mascot.bounds.width, 1) / 2
            // 看的是方向：鼠标离得远（比如在面板最下面）时眼睛也不会顶死在角上不动，左右移动仍然跟得上
            let dx = m.x - half, dy = m.y - mascot.bounds.height * 0.27, dist = hypot(dx, dy)
            let amount = min(1, dist / (dist + half * 0.5) * 1.2)
            if dist > 0.5 { gaze = NSPoint(x: ((dx / dist * amount) * 40).rounded() / 40, y: ((dy / dist * amount) * 40).rounded() / 40) }
            gazeHeld = gaze
        } else if away < 2.0 {
            // 鼠标走开后不马上看回正前方：先朝它离开的方向多看 0.7 秒，再用 1.3 秒慢慢收回来
            let x = CGFloat(min(max((away - 0.7) / 1.3, 0), 1))
            let k = 1 - x * x * (3 - 2 * x)
            gaze = NSPoint(x: ((gazeHeld.x * k) * 50).rounded() / 50, y: ((gazeHeld.y * k) * 50).rounded() / 50)
        }
        if bubbleOpen { gaze = NSPoint(x: -0.95, y: -0.35) }        // 抬头看着左边的气泡
        if pressing, onMascot || mouseInside() { gaze = .zero }     // 被按住、被拖着走的时候目视前方
        // 眼睛不是一下子转过去的：每帧朝要看的方向挪一截，换目标（看气泡、看鼠标、回正）时都是滑过去的
        let cur = mascot.gaze
        var eased = NSPoint(x: cur.x + (gaze.x - cur.x) * 0.22, y: cur.y + (gaze.y - cur.y) * 0.22)
        if abs(eased.x - gaze.x) < 0.02, abs(eased.y - gaze.y) < 0.02 { eased = gaze }
        if eased != mascot.gaze || near != mascot.facing { mascot.gaze = eased; mascot.facing = near; mascot.needsDisplay = true }
        if let from = cheerBlendFrom {                      // 进入或离开休息：用 0.3 秒过渡过去，不硬切
            let x = CGFloat(min(1, (now - cheerBlendStart) / 0.3))
            if x >= 1 { cheerBlendFrom = nil } else { target = from.mix(target, x * x * (3 - 2 * x)) }
        }
        var behind: CGFloat = 0, dig: CGFloat = 0
        if swapStart > 0 {
            let x = (now - swapStart) / swapSeconds          // 睡着时也照样换：闭着眼把手背过去摸一副新的
            let st = swapState(min(x, 1))
            if st.found || x >= 1, mascot.greenUp != board.greenUp { mascot.greenUp = board.greenUp; mascot.needsDisplay = true }   // 手还在身后时已经换好
            if st.found || x >= 1, mascot.cfg.pomColor != cfg.pomColor { mascot.cfg.pomColor = cfg.pomColor; mascot.needsDisplay = true }
            var stand = Pose(); stand.face = 1; stand.z = target.z
            if swapFrom == nil { swapFrom = mascot.pose }
            // 手开始往外拿的那一刻，后面的动作就已经开始了：这套动作从「跳起、双手举高」那一拍接上。
            // 这样「拿出来」和「举起来」是连着的一个动作；如果等手完全拿出来、停住，再开始下一个动作，中间就会顿一下
            if x >= swapOut, !swapRestarted {
                swapRestarted = true
                cheerStart = now - (cheerRoutine[0].move + cheerRoutine[0].hold + cheerRoutine[1].move + cheerRoutine[1].hold + cheerRoutine[2].move * 0.55)
                cheerBlendFrom = nil
                if !resting { target = cheerPose(at: max(0, now - cheerStart)) }
            }
            if x >= 1 {
                lastActEnd = now
                swapStart = 0; swapFrom = nil; swapRestarted = false          // 到这儿手已经完全拿出来了，姿势就是后面动作本身，不用再过渡
            } else {
                behind = st.behind; dig = st.dig
                // 换的时候整个人站定：不抛、不蹦、身子不晃、腿不动，淡定地换；表情不变
                let keepFace = target.face
                let live = target
                if x < swapIn { target = (swapFrom ?? stand).mix(stand, behind) }       // 收手：从原来的姿势过渡到站定
                else if x < swapOut { target = stand }                                 // 在身后换：一直站定
                else { target = stand.mix(live, 1 - behind) }                          // 往外拿：一边拿一边过渡到后面的动作
                if x < swapOut { target.face = !asleep && drowsy == 0 ? 1 : keepFace }
                if !near, !asleep {
                    let g = NSPoint(x: 0, y: ((behind * (st.found ? 0 : 0.35)) * 20).rounded() / 20)
                    if g != mascot.gaze { mascot.gaze = g; mascot.needsDisplay = true }
                }
            }
        }
        syncBubbleKey()
        if dig != mascot.dig { mascot.dig = dig; mascot.needsDisplay = true }
        // 鼠标停在它身上（气泡开着）时：歪头、一只手抬到下巴、头边冒个问号；按住拖动、换花球时不摆
        let wantCurious: CGFloat = (bubbleOpen || (onMascot && !pressing && !bubbleMuted)) && swapStart == 0 ? 1 : 0
        var cq = mascot.curious + (wantCurious - mascot.curious) * 0.2
        if abs(cq - wantCurious) < 0.01 { cq = wantCurious }
        if cq != mascot.curious { mascot.curious = cq; mascot.needsDisplay = true }
        if cq > 0 {
            target.lean += 0.9 * cq
            if cq > 0.5, !asleep { target.face = 2 }                // 嘴微微张成小 o
        }
        if behind != mascot.behind { mascot.behind = behind; mascot.needsDisplay = true }
        // 被拖着走：量一下窗口这一刻的速度（只认右上角的移动，变大变小不算），喂给「站不稳」的弹簧
        do {
            let corner = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
            let dtv = CGFloat(min(max(now - lastOriginAt, 1.0 / 120), 0.1))
            let moved = lastOriginAt > 0 && pressing && !resizing && animTimer == nil
            let vx = moved ? (corner.x - lastOrigin.x) / dtv : 0, vy = moved ? (corner.y - lastOrigin.y) / dtv : 0
            dragVX += (vx - dragVX) * 0.35; dragVY += (vy - dragVY) * 0.35
            if abs(vx) + abs(vy) > 12 { lastMovedAt = now }
            lastOrigin = corner; lastOriginAt = now
            wobble.step(vx: dragVX, vy: dragVY, dragging: pressing && now - lastMovedAt < 0.35, dt: dtv)
        }
        // 喝茶休息：只在它真的在跳的时候（没被看着、没在换花球、没走开）
        let cheering = !resting && swapStart == 0 && awayState == 0
        if teaStart == 0, cheering {
            let loops = Int(max(0, now - cheerStart) / cheerRoutineLength)
            if loops < teaLoopBase { teaLoopBase = loops }                    // 这套动作被重新开始过：重新数
            if (loops - teaLoopBase >= teaEveryLoops && now - lastActEnd > actGap) || debugTea { teaStart = now; teaFrom = mascot.pose; teaInRest = false; teaRestarted = false }
        }
        // 休息模式下的咖啡：刚进入休息时先喝一杯再睡；睡着之后每隔一阵（一分钟上下，不固定）醒来喝一杯，喝完接着睡
        if modeKnown, modeCheer != lastModeCheer, !modeCheer {       // 刚从加油变成休息
            if coffeeDecided { coffeeDecided = false } else { restCoffeeAt = now + 0.25 }      // 点「休息」的已经掷过了；收盘自己歇下来的，先喝一杯
        }
        coffeeDecided = false
        lastModeCheer = modeCheer; modeKnown = true
        if teaStart == 0, resting0, swapStart == 0, awayState == 0 {
            if restCoffeeAt == 0 { restCoffeeAt = now + Double.random(in: 50...85) }
            if now >= restCoffeeAt {
                // 到点了。但如果刚做完别的（换花球、走回来、上一杯），不紧接着喝：往后推一阵
                if now - lastActEnd < actGap { restCoffeeAt = now + Double.random(in: 12...25) }
                else { teaStart = now; teaFrom = mascot.pose; teaInRest = true; teaRestarted = false; restCoffeeAt = 0 }
            }
        } else if restCoffeeAt > 0, now >= restCoffeeAt, swapStart > 0 || awayState != 0 {
            restCoffeeAt = now + Double.random(in: 12...25)        // 到点时正在忙别的：不排队等着，往后推
        }
        if teaStart > 0 {
            let tf = teaFrame(now - teaStart, from: teaFrom)
            if !teaInRest, resting0 { teaInRest = true; restCoffeeAt = 0 }       // 跳着喝的时候改成了休息：把这杯喝完，然后直接去睡
            if swapPending {
                // 喝到一半要换花球：不把杯子变没。等这一口放下（或比赞收回），直接跳到「把杯子收到身后」那一段；
                // 手到了身后，就地开始换花球——换的动作从「手已经在身后」接上，拿出来的就是新花球
                let tt = now - teaStart, putAway = teaSeconds - 1.5
                if tt < putAway, tf.sip < 0.05, tf.thumb < 0.05 { teaStart = now - putAway }
                else if tt >= teaSeconds - 1.0 {
                    swapPending = false
                    teaStart = 0; teaLoopBase = 0; teaRestarted = false
                    mascot.cup = false; mascot.sip = 0; mascot.thumb = 0; mascot.heldLeft = true
                    swapStart = now - swapIn * swapSeconds; swapFrom = Pose(); swapRestarted = false
                    lastActEnd = now
                    mascot.needsDisplay = true
                }
            }
            // 什么时候不喝了、马上收起来：喝完了；被叫去换花球；被隐藏；休息着喝的时候改成了加油
            if tf.done || swapStart > 0 || awayState != 0 || (teaInRest && !resting0) {
                let finished = tf.done, handed = teaRestarted
                if finished { lastActEnd = now }
                teaStart = 0; teaLoopBase = 0; teaRestarted = false
                mascot.cup = false; mascot.sip = 0; mascot.heldLeft = true; mascot.thumb = 0
                if !handed, finished || !resting0 { cheerBlendFrom = mascot.pose; cheerBlendStart = now }       // 中途被打断的：从现在的样子过渡到后面的动作（正常喝完的已经接上了）
                if resting0 {
                    if finished { lastNearAt = now - 4.5 }             // 喝完了就犯困：两秒左右睡着，不用再等平时那六七秒
                } else if !handed {
                    cheerStart = now                                   // 加油模式，中途被打断：从头接着跳
                }
                mascot.needsDisplay = true
            } else {
                // 最后往外拿花球的那一段：后面的动作同时接上（加油模式从「跳起、双手举高」那一拍接，和换完花球时一样）
                if tf.live > 0, !teaRestarted {
                    teaRestarted = true; cheerBlendFrom = nil
                    if !resting {
                        cheerStart = now - (cheerRoutine[0].move + cheerRoutine[0].hold + cheerRoutine[1].move + cheerRoutine[1].hold + cheerRoutine[2].move * 0.55)
                        target = cheerPose(at: max(0, now - cheerStart))
                    }
                }
                target = tf.live > 0 ? tf.pose.mix(target, tf.live) : tf.pose
                behind = tf.behind
                let heldL = !tf.cup
                if tf.cup { mascot.steam = CGFloat(((now - teaStart) / 2.4).truncatingRemainder(dividingBy: 1)); mascot.needsDisplay = true }
                if tf.cup != mascot.cup || tf.sip != mascot.sip || heldL != mascot.heldLeft || tf.thumb != mascot.thumb { mascot.cup = tf.cup; mascot.sip = tf.sip; mascot.heldLeft = heldL; mascot.thumb = tf.thumb; mascot.needsDisplay = true }
                if behind != mascot.behind { mascot.behind = behind; mascot.needsDisplay = true }
            }
        }
        // 站不稳的反应叠在当前姿势上（换花球、喝茶时照样会晃；它走开的过场不受影响，见下面）
        let fr = swapStart > 0 ? 0 : wobble.apply(to: &target)
        if abs(fr - mascot.frown) > 0.004 { mascot.frown = fr; mascot.needsDisplay = true }
        // 「隐藏」的过场和它不在时的样子：整个接管姿势
        var av = AwayFrame(); var avOn = false
        if awayState == 1 {
            let t = now - awayStart
            av = leaveFrame(t, from: awayFrom, hand: awayHand); avOn = true
            if t >= leaveSeconds { awayState = 2 }
        }
        if awayState == 2 {
            av = AwayFrame(); av.fade = 0; av.held = false; av.loose = loosePomSpot; avOn = true
            // 鼠标指着花球时它轻轻晃，表示可以点
            if onMascotArea, mascot.loosePomRect.contains(mp) { av.rot = 0.22 * CGFloat(sin(now * 9)) }
        } else if awayState == 3 {
            let t = now - awayStart
            av = returnFrame(t); avOn = true
            if av.held, !returnRestarted {      // 捡起花球的那一刻：后面那套动作从「跳起、双手举高」接上（和换完花球时一样）
                returnRestarted = true; cheerBlendFrom = nil
                if !resting {
                    cheerStart = now - (cheerRoutine[0].move + cheerRoutine[0].hold + cheerRoutine[1].move + cheerRoutine[1].hold + cheerRoutine[2].move * 0.55)
                    target = cheerPose(at: max(0, now - cheerStart))
                }
            }
            if t >= returnSeconds {            // 回来了：这时的姿势已经是后面的动作本身，不用再过渡
                awayState = 0; avOn = false; returnRestarted = false; lastActEnd = now
                mascot.offsetX = 0; mascot.fade = 1; mascot.heldLeft = true; mascot.loosePom = nil; mascot.isAway = false
                mascot.needsDisplay = true
            }
        }
        if avOn {
            if awayState != 2 { target = av.live > 0 ? av.pose.mix(target, av.live) : av.pose }
            if av.x != mascot.offsetX || av.fade != mascot.fade || av.held != mascot.heldLeft || av.loose != mascot.loosePom || av.rot != mascot.loosePomRot {
                mascot.offsetX = av.x; mascot.fade = av.fade; mascot.heldLeft = av.held; mascot.loosePom = av.loose; mascot.loosePomRot = av.rot
                mascot.needsDisplay = true
            }
            mascot.isAway = awayState == 2
            if awayState != 2 { let g = NSPoint(x: av.gazeX, y: av.gazeY); if g != mascot.gaze { mascot.gaze = g; mascot.needsDisplay = true } }
        }
        target.blink = sleepyBlink || ((!resting || near) && now.truncatingRemainder(dividingBy: 2.9) < 0.13)       // 每隔不到三秒眨一下眼
        if traceUntil > now {        // 调试用：换花球前后逐帧打印手臂和身体的状态
            print(String(format: "t=%.2f swap=%@ behind=%.2f aL=%.0f aR=%.0f tuck=%.2f hop=%.1f blend=%@ resting=%@ green=%@ pomY=%.1f handY=%.1f", now - traceStart, swapStart > 0 ? "Y" : "n", Double(behind), Double(target.aL), Double(target.aR), Double(target.tuck), Double(target.hop), cheerBlendFrom != nil ? "Y" : "n", resting ? "Y" : "n", mascot.greenUp ? "Y" : "n", Double(mascot.debugPomY), Double(mascot.debugPomTargetY)))
            fflush(stdout)
        }
        // 睡着：每秒 10 拍（呼吸、点头、飘 z 都很慢，再少 z 就一格一格地跳）；不在：每秒 3 拍，只是为了留意状态变化
        quietDiv = awayState == 2 ? 10 : (asleep && zFade >= 1 && swapStart == 0 && teaStart == 0 && !bubbleOpen && awayState == 0 ? 3 : 1)
        if awayState == 2 {
            // 它不在：人不画，姿势不用更新
        } else if target != mascot.pose {                    // 定住不动的那些拍子不重画
            mascot.pose = target
            mascot.needsDisplay = true
        } else if mascot.stepIdle() {                         // 姿势没变，但花球或头还在晃：接着算、接着画
            mascot.needsDisplay = true
        }
    }

    @objc func toggleMini() {
        if bubbleOpen { bubbleOpen = false; bubble.isHidden = true }
        bubbleMuted = true                  // 点它收起、展开之后，鼠标离开前不再冒气泡
        mini.toggle()
        store.set(mini, forKey: "mini")
        folding = mini && cheerStyle && panel.isVisible && !board.isHidden       // 收起时播一小段：面板缩成脚下的横线
        board.fold = nil
        if mini { closePage(); selected = nil; board.detail = nil; closing = false }
        if !panel.isVisible { panel.orderFrontRegardless() }
        render()
        updateCheer()
        if !mini { refresh() }
    }

    @objc func editConfig() {
        _ = loadConfig()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-e", configURL.path]
        try? p.run()
    }

    @objc func quit() { NSApp.terminate(nil) }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let id = hk.id
            DispatchQueue.main.async {
                if id == 1 { AppDelegate.shared?.toggle() } else if id == 9 { AppDelegate.shared?.hotkeyToggleBoard() } else { AppDelegate.shared?.bubbleKeyPressed(id) }
            }
            return noErr
        }, 1, &spec, nil, nil)
        hotKeyHandlerInstalled = true
        let st = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey),
                                     EventHotKeyID(signature: OSType(0x5045454B), id: 1),
                                     GetApplicationEventTarget(), 0, &hotKeyRef)
        hotKeyOK = st == noErr
        if !hotKeyOK { applyConfig() }
        // ⌃⌥D：展开 / 收起看板（小窗藏着的时候先叫出来）
        RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x5045454B), id: 9), GetApplicationEventTarget(), 0, &boardKeyRef)
    }

    /// 气泡开着时，把当前那一项的字母（休息 R / 加油 C）登记成快捷键；气泡一收就撤掉。
    /// 用系统的快捷键登记，不抢键盘焦点：别的键照常打进用户正在用的程序里，只有这一个字母被接走
    func hotkeyToggleBoard() {
        if !panel.isVisible { show(); if !mini { return } }       // 藏着的：先叫出来；叫出来已经是展开的就够了
        toggleMini()
    }
    func syncBubbleKey() {
        guard hotKeyHandlerInstalled else { return }
        let want: [UInt32] = bubbleOpen && panel.isVisible ? [UInt32(kVK_ANSI_C), UInt32(kVK_ANSI_R), UInt32(kVK_ANSI_H)] : []        // 编号 2、3、4 对应气泡的前三项
        guard want != bubbleKeyCodes else { return }
        for r in bubbleKeyRefs { if let r = r { UnregisterEventHotKey(r) } }
        bubbleKeyRefs = []; bubbleKeyCodes = []
        for (k, code) in want.enumerated() {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(code, 0, EventHotKeyID(signature: OSType(0x5045454B), id: UInt32(2 + k)), GetApplicationEventTarget(), 0, &ref)
            bubbleKeyRefs.append(ref)
        }
        bubbleKeyCodes = want
    }
    func bubbleKeyPressed(_ id: UInt32) {
        guard bubbleOpen else { return }
        let item = Int(id) - 2
        guard item >= 0, item <= 2 else { return }
        bubble.pressed = item                                // 和点下去一样亮一下再执行
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in self?.bubble.pressed = nil; self?.bubble.onPick?(item) }
    }

    /// auto = 定时器触发的那种。鼠标移上来、换标签、改了列表这些主动的操作不受下面的限速
    func refresh(auto: Bool = false) {
        evt("refresh")
        let mtime = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date
        if mtime == nil || mtime != configMTime {       // 配置文件没改过就不重新读、不重新应用
            if let c = loadConfig() { cfg = c; configBad = false } else { configBad = true }
            configMTime = (try? FileManager.default.attributesOfItem(atPath: configURL.path))?[.modificationDate] as? Date
            applyConfig()
        }
        syncHover()
        // 隐藏或收成笑脸时不联网：没人看，也少留痕迹
        guard panel.isVisible, !mini else { render(); return }
        // 这一页的市场没在交易时，价格不会变：定时的那种刷新放慢到一分钟一次，少发一大半请求
        if auto, ProcessInfo.processInfo.environment["PEEK_FORCE_LIVE"] == nil {
            let mk: Market = tab == "us" ? .us : (tab == "hk" ? .hk : .aStock)
            // 这一页里有金价这类几乎全天交易的品种时，A 股收盘后它们还在动，照常刷新
            let hasCmdty = shown.contains { isValidCode($0) && Market.of(apiSymbol($0)) == .cmdty } && Market.cmdty.status(stamp: nil).live
            if !mk.status(stamp: nil).live, !hasCmdty, Date().timeIntervalSince(lastFetchAt) < 60 { return }
        }
        var seen = Set<String>()
        let symbols = shown.filter(isValidCode).map(apiSymbol).filter { seen.insert($0).inserted }
        // 这一页里有黄金、白银、原油相关的产品时，顺带把对应的国际价格一起问回来（同一个请求，不多发）
        var ask = symbols
        for k in symbols where Market.of(k) != .cmdty {
            if let q = quotes[k], let r = referencePrice(forName: q.name), !ask.contains(r.code) { ask.append(r.code) }
        }
        guard !symbols.isEmpty,
              let url = URL(string: host("https://qt.gtimg.cn/") + "q=" + ask.joined(separator: ",")) else { render(); return }
        lastFetchAt = Date()
        requestCount += 1
        if let t = testHome { try? "\(requestCount)".write(toFile: t + "/requests", atomically: true, encoding: .utf8) }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        req.setValue("https://gu.qq.com", forHTTPHeaderField: "Referer")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let text = data.flatMap { String(data: $0, encoding: gbk) }
            let parsed = text.map(parseQuotes) ?? [:]
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !parsed.isEmpty, let t = text, Date().timeIntervalSince(self.cacheSavedAt) > 20 {      // 存一份，下次启动先显示它
                    self.cacheSavedAt = Date()
                    try? t.write(to: configDir.appendingPathComponent("cache_\(self.tab).txt"), atomically: true, encoding: .utf8)
                }
                self.failed = parsed.isEmpty
                let first = !self.everLoaded && !parsed.isEmpty
                if !parsed.isEmpty { self.everLoaded = true; self.lastOK = Date() }
                for (k, v) in parsed { self.quotes[k] = v }
                _ = first       // 不在启动时批量预拉分时：请求太密会被行情服务器的防火墙拦截（实测遇到过）
                self.render()
            }
        }.resume()
        if let s = selected { fetchMinutes(for: s, force: false) }
    }

    /// 详情开着、鼠标又不在小窗上时开始倒计时，到点自动收起；鼠标移回来就取消
    func scheduleAutoClose() {
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
        guard selected != nil, !hovering, cfg.detailAutoCloseSeconds > 0 else { return }
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: cfg.detailAutoCloseSeconds, repeats: false) { [weak self] _ in
            guard let self = self, !self.hovering else { return }
            self.selected = nil
            self.render()
        }
    }

    /// 拉某只的分时走势，同一只最多 30 秒拉一次。主源是腾讯（三个市场三个接口），被拦截或失败时换东方财富
    func fetchMinutes(for raw: String, force: Bool) {
        guard isValidCode(raw) else { return }
        let key = apiSymbol(raw)
        if !force, let t = minuteFetchedAt[key], Date().timeIntervalSince(t) < 30 { return }
        guard let q = quotes[key] else { return }
        let mk = Market.of(key, type: q.str(61))
        minuteFetchedAt[key] = Date()

        func finish(_ m: MinuteData?) {
            // 失败时保留旧数据；从没拿到过就记成空，界面显示「暂无分时数据」
            if let m = m, !m.prices.isEmpty {
                minutes[key] = m.prices; minuteVols[key] = m.vols; minuteTimes[key] = m.times; minuteAvg[key] = m.avg
            } else if minutes[key] == nil {
                minutes[key] = []
                minuteFetchedAt[key] = Date().addingTimeInterval(-18)     // 没拿到：12 秒后就可以再试，不用等满 30 秒
            }
            if selected.map(apiSymbol) == key { render() }
        }
        if mk == .cmdty { minutes[key] = []; if selected.map(apiSymbol) == key { render() }; return }      // 商品没有接分时走势，详情里只有数字
        func get(_ urlText: String, _ parse: @escaping (Data) -> MinuteData, then: @escaping (MinuteData?) -> Void) {
            guard let url = URL(string: urlText) else { then(nil); return }
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
            req.setValue("https://gu.qq.com", forHTTPHeaderField: "Referer")
            URLSession.shared.dataTask(with: req) { data, _, _ in
                let m = data.map(parse)
                DispatchQueue.main.async { then(m) }
            }.resume()
        }
        func backup() {
            guard let secid = eastmoneySecid(key: key, market: mk, code: q.code) else { finish(nil); return }
            get(host("https://push2his.eastmoney.com/") + "api/qt/stock/trends2/get?secid=\(secid)&fields1=f1,f2,f3&fields2=f51,f53,f56,f57,f58&ndays=1&iscr=0",
                { parseEastmoneyMinutes($0) }, then: finish)
        }

        var path = "appstock/app/minute/query", code = key
        if mk == .hk { path = "appstock/app/hkMinute/query"; code = String(key.dropFirst(2)) }        // r_hk00700 → hk00700
        if mk == .us { path = "appstock/app/UsMinute/query"; code = "us" + q.code }                   // 美股要带交易所后缀（AAPL.OQ）
        let enc = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        // 同一份数据有三个地址。挨个试，哪个被拦了就十分钟内跳过它（按「地址 + 接口」分别记，互不连累）
        let bases = ["https://web.ifzq.gtimg.cn/", "https://ifzq.gtimg.cn/", "https://proxy.finance.qq.com/ifzqgtimg/"]
        func attempt(_ i: Int) {
            guard i < bases.count else { backup(); return }
            let tag = bases[i] + path
            if let until = blockedUntil[tag], Date() < until { attempt(i + 1); return }
            get(host(bases[i]) + path + "?code=" + enc, { parseMinutes($0, code: code, market: mk) }) { [weak self] m in
                if let m = m, !m.prices.isEmpty { finish(m); return }
                self?.blockedUntil[tag] = Date().addingTimeInterval(600)
                attempt(i + 1)
            }
        }
        attempt(0)
    }

    func buildDetail(raw: String, q: Quote) -> Detail {
        let key = apiSymbol(raw)
        let mk = Market.of(key, type: q.str(61))
        func yi(_ v: Double?) -> String? {      // 单位：亿
            guard let v = v, v > 0 else { return nil }
            if lang == "en" {       // 英文按 M / B / T 写
                let b = v / 10
                return b >= 1000 ? String(format: "%.2fT", b / 1000) : (b >= 1 ? String(format: b >= 100 ? "%.0fB" : "%.2fB", b) : String(format: "%.0fM", b * 1000))
            }
            return v >= 10000 ? String(format: "%.2f万亿", v / 10000) : String(format: v >= 100 ? "%.0f亿" : "%.2f亿", v)
        }
        func plain(_ i: Int, _ suffix: String = "") -> String? {
            guard let v = q.num(i), v != 0 else { return nil }
            return String(format: "%.2f", v) + suffix
        }
        func price(_ v: Double?) -> String? { (v ?? 0) > 0 ? fmt(v!) : nil }
        var core: [Stat] = []
        func add(_ id: String, _ label: String, _ value: String?) {
            if let v = value { core.append(Stat(id: id, label: label, value: v)) }     // 这个市场没有的指标就不占位置
        }
        let isA = mk == .aStock || mk == .aIndex
        let amount = q.num(37).map { isA ? $0 / 10000 : $0 / 1e8 }   // A 股给的是万元，港美股是元
        // 只留四个最常用的数。估值、市值、涨跌停、盘口这些专业指标不放进来，这不是给交易员用的工具
        add("open", T("今开", "Open"), price(q.open)); add("prev", T("昨收", "Prev"), price(q.prevClose))
        add("amount", T("成交额", "Value"), yi(amount)); if mk != .hk, mk != .aIndex { add("turnover", T("换手", "Turnover"), plain(38, "%")) }
        // 黄金 / 白银 / 原油相关的产品：多一行它跟的那个国际价格和今天的涨跌
        if mk != .cmdty, let r = referencePrice(forName: q.name), let rq = quotes[r.code], rq.live {
            core.append(Stat(id: "ref", label: T(r.zh, r.en), value: fmt(rq.price), tint: rq.dir))
            core.append(Stat(id: "refpct", label: T("今日", "Today"), value: String(format: "%+.2f%%", rq.pct), tint: rq.dir))
        }
        var buy = 0.0, sell = 0.0
        if mk == .aStock { buy = q.num(7) ?? 0; sell = q.num(8) ?? 0 }          // 外盘 / 内盘，单位手

        let st = mk.status(stamp: q.stamp)
        var status = st.text
        if mk == .us {       // 美股时间是美东时间，白天看到的是上一个交易日的数据，要说清楚
            let f = DateFormatter(); f.timeZone = mk.zone; f.dateFormat = "M-d HH:mm"
            status += q.stamp.map { T(" 美东 ", " ET ") + f.string(from: $0) } ?? ""
        } else {
            status += " " + q.time
        }
        let spark = minutes[key]
        let total = mk.sessions.reduce(0) { $0 + $1.1 - $1.0 + 1 }
        let notOpen = !st.live && q.stamp.map { Date().timeIntervalSince($0) > 3600 * 6 } ?? true      // 今天还没有行情
        return Detail(name: displayName(q, key: key), code: q.code + (mk.currency.isEmpty ? "" : " · " + mk.currency), statusText: status, live: st.live,
                      direction: q.dir, price: q.price, prevClose: q.prevClose, open: q.open, high: q.high, low: q.low,
                      buy: buy, sell: sell, core: core, more: [],
                      spark: spark ?? [], avg: [], vols: minuteVols[key] ?? [], times: minuteTimes[key] ?? [],
                      chartNote: spark == nil ? T("加载中…", "Loading…") : (notOpen ? T("还没开盘", "Not open yet") : (mk == .cmdty ? T("这类品种没有走势图", "No chart for this type") : T("走势没取到", "Chart unavailable"))),
                      sessions: mk.sessions, sparkTotal: total)
    }

    /// 窗口变大变小后，鼠标可能已经不在（或已经在）小窗上却没收到进出事件，这里按实际位置校正
    func syncHover() {
        guard panel.isVisible else { return }
        let inside = mouseInside()
        guard inside != hovering else { return }
        hovering = inside
        applyConfig()
        render()
        scheduleAutoClose()
    }

    /// 把小窗平滑地过渡到目标大小，同时淡入 / 淡出详情区
    /// 收起的那一小段播完：面板藏起来，脚下换回拉拉队自己的横线
    func endFold() {
        guard folding else { return }
        folding = false
        board.fold = nil
        board.isHidden = cheerStyle && mini
        if mascot.onBoard == mini { mascot.onBoard = !mini }
        mascot.needsDisplay = true
    }

    func animate(to target: NSRect, detailAlpha: CGFloat, dip: Bool, done: @escaping () -> Void) {
        if target == animTarget, detailAlpha == animAlphaTarget, !dip { return }   // 已经在去往这个状态的路上，或已经到了
        evt("animate 到 \(Int(target.width))x\(Int(target.height)) 从 \(Int(panel.frame.width))x\(Int(panel.frame.height)) dip=\(dip)")
        animTarget = target
        animAlphaTarget = detailAlpha
        animTimer?.invalidate()
        animTimer = nil
        let from = panel.frame
        // 没显示出来、或者只是挪位置不变大小（比如刚拖完），就不做动画
        let snap = snapNext; snapNext = false
        guard panel.isVisible, !snap, from.size != target.size || dip || board.detailAlpha != detailAlpha else {
            resizing = true; panel.setFrame(target, display: true); resizing = false
            board.detailAlpha = detailAlpha
            endFold()
            done()
            return
        }
        animDone = done
        let fromAlpha: CGFloat = dip ? 0.25 : board.detailAlpha    // 切换股票时让详情轻轻淡入
        let start = CACurrentMediaTime()
        let duration = folding ? 0.2 : (board.isHidden || from.height <= mascotSide + 1 ? 0.2 : 0.16)      // 收起、展开慢一点，看得清它怎么变的
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            let p = min(1, (CACurrentMediaTime() - start) / duration)
            let e = CGFloat(1 - pow(1 - p, 3))                     // 先快后慢
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
            var f = target
            if p < 1 {      // 右上角钉住不动，只让左边和下边伸缩
                let maxX = mix(from.maxX, target.maxX).rounded(), maxY = mix(from.maxY, target.maxY).rounded()
                let w = mix(from.width, target.width).rounded(), h = mix(from.height, target.height).rounded()
                f = NSRect(x: maxX - w, y: maxY - h, width: w, height: h)
            }
            self.board.detailAlpha = mix(fromAlpha, detailAlpha)
            if self.folding { self.board.fold = e }
            if self.folding, let stop = self.debugFold, p >= stop { timer.invalidate(); self.animTimer = nil; print("fold stopped at \(p) frame=\(self.panel.frame.size)"); fflush(stdout); return }
            self.resizing = true
            self.panel.setFrame(f, display: true)
            self.resizing = false
            self.board.needsDisplay = true
            if p >= 1 {
                timer.invalidate()
                self.animTimer = nil
                self.endFold()
                let d = self.animDone; self.animDone = nil; d?()
                self.syncHover()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }

    /// 根据右上角锚点算出小窗该放哪。放不下时临时挪进屏幕（靠边时往里收，靠下时往上顶），锚点本身不变
    func place(_ size: NSSize) -> NSRect {
        let probe = NSPoint(x: anchorRight - 1, y: anchorTop - 1)
        let screen = NSScreen.screens.first { $0.frame.contains(probe) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else {
            return NSRect(x: anchorRight - size.width, y: anchorTop - size.height, width: size.width, height: size.height)
        }
        let x = max(vf.minX + 4, min(anchorRight - size.width, vf.maxX - size.width - 4))
        var top = min(anchorTop, vf.maxY - 2)
        if top - size.height < vf.minY + 4 { top = min(vf.maxY - 2, vf.minY + 4 + size.height) }
        return NSRect(x: x, y: top - size.height, width: size.width, height: size.height)
    }

    static let clockFormatter: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    func statusText() -> String {
        if let f = flashText { return f }
        var parts: [String] = []
        if configBad { parts.append(T("配置文件有误", "Config file error")) }
        let f = AppDelegate.clockFormatter
        if failed { parts.append(T("断线", "Offline")) }
        if let t = lastOK { parts.append(f.string(from: t)) }
        if cfg.stocks.count > maxStocks { parts.append(T("还有 \(cfg.stocks.count - maxStocks) 只没显示", "\(cfg.stocks.count - maxStocks) more not shown")) }
        return parts.joined(separator: " · ")
    }

    func render() {
        evt("render 页=\(board.page) 下拉=\(board.dropdown != nil)")
        let list = shown
        if let s = selected, !list.contains(s) { selected = nil }
        var want = false
        if !mini, let s = selected, let i = list.firstIndex(of: s), let q = quotes[apiSymbol(s)] {
            board.detail = buildDetail(raw: s, q: q)
            board.selectedRow = i
            want = true
            closing = false
        } else {
            board.selectedRow = nil
            if board.detail != nil { closing = true }   // 内容先留着，等收起动画播完再清
        }
        var rows: [Row] = []
        let blanks = expanded ? 8 : 0       // 更多列展开时，缺数据的行也补齐列数，免得错位
        func pad(_ cells: [Cell]) -> [Cell] {
            guard expanded else { return cells }
            return cells + [Cell(text: "", right: true), Cell(text: "开", dim: true), Cell(text: "—", right: true),
                            Cell(text: "高", dim: true), Cell(text: "—", right: true),
                            Cell(text: "低", dim: true), Cell(text: "—", right: true), Cell(text: "", right: true, dim: true)].prefix(blanks)
        }
        for raw in list {
            let alias = cfg.aliases[raw]
            guard isValidCode(raw) else {
                rows.append(Row(cells: pad([Cell(text: alias ?? raw), Cell(text: "", right: true), Cell(text: T("代码有误", "Bad ticker"), right: true, dim: true)]), direction: 0))
                continue
            }
            guard let q = quotes[apiSymbol(raw)] else {
                rows.append(Row(cells: pad([Cell(text: alias ?? raw), Cell(text: "", right: true),
                                            Cell(text: everLoaded ? T("无数据", "No data") : "—", right: true, dim: true)]), direction: 0))
                continue
            }
            let label = alias ?? (cfg.label == "code" ? raw : displayName(q, key: apiSymbol(raw)))
            guard q.live else {      // 开盘前 / 停牌：现价是 0，只显示昨收，不算涨跌
                rows.append(Row(cells: pad([Cell(text: label), Cell(text: fmtP(q.prevClose), right: true, dim: true),
                                            Cell(text: "—", right: true, dim: true)]), direction: 0))
                continue
            }
            var cells = [Cell(text: label),
                         Cell(text: fmt(q.price), right: true, tint: true),
                         Cell(text: String(format: "%+.2f%%", q.pct), right: true, tint: true)]
            if expanded {
                cells += [Cell(text: String(format: "%+.2f", q.change), right: true, tint: true),
                          Cell(text: "开", dim: true), Cell(text: fmtP(q.open), right: true),
                          Cell(text: "高", dim: true), Cell(text: fmtP(q.high), right: true),
                          Cell(text: "低", dim: true), Cell(text: fmtP(q.low), right: true),
                          Cell(text: q.time, right: true, dim: true)]
            }
            rows.append(Row(cells: cells, direction: q.dir))
        }
        if rows.isEmpty { rows = [Row(cells: [Cell(text: T("点 + 添加", "Click + to add"), dim: true, whole: true)], direction: 0)] }

        let ids = tabIDs
        if !ids.contains(tab), let f = ids.first { tab = f }
        board.tabs = ids.count > 1 ? ids.map { AppDelegate.tabNames[$0] ?? $0 } : []
        board.tabIndex = ids.firstIndex(of: tab) ?? 0
        board.greenUp = tab == "us" ? cfg.usGreenUp : cfg.upColor == "green"
        board.expanded = expanded
        board.showMore = detailMore
        board.mini = mini
        board.isHidden = cheerStyle && mini && !folding
        board.foldSide = mascotSide
        if folding, board.fold == nil { board.fold = 0 }
        mascot.isHidden = !mascotVisible
        if mascot.greenUp != board.greenUp {
            // 花球跟着市场变色时，不是直接换颜色：背过手去换一副（cheerTick 里做）
            if cfg.pomColor == "auto", cfg.color, cheerTimer != nil, !mascot.isHidden { if teaStart > 0 { swapPending = true } else if swapStart == 0 { swapStart = CACurrentMediaTime() } }
            else { mascot.greenUp = board.greenUp; mascot.needsDisplay = true }
        }
        let standing = !mini || folding
        if mascot.onBoard != standing { mascot.onBoard = standing; mascot.needsDisplay = true }
        mascot.passBelow = mini ? nil : stageTop
        stage.side = mascotSide; stage.top = stageTop; stage.scale = uiScale; board.foldScale = uiScale; board.foldTop = stageTop
        board.status = statusText()
        board.rows = rows
        // 展开着改设置（拉拉队大小、展开时显不显示它）会让面板上方那一块变高、变矮或消失。
        // 窗口是按右上角钉住的，不处理的话面板会整体上下跳一截，刚点的那一行就不在鼠标底下了。
        // 所以这时挪的是钉子：面板留在原地，让拉拉队那一侧去伸缩
        if lastStageTop >= 0, stageTop != lastStageTop, !mini, panel.isVisible, !folding {
            anchorTop += stageTop - lastStageTop
            store.set(Double(anchorTop), forKey: "top")
        }
        lastStageTop = stageTop
        // 改了界面大小或拉拉队大小：里面的内容是立刻按新尺寸摆的，窗口如果还慢慢变过去，两者对不上，看板会先跳一下再滑回来。
        // 所以这种时候窗口也一步到位
        let metrics = "\(uiScale)|\(mascotSide)|\(stageTop)"
        if !lastMetrics.isEmpty, metrics != lastMetrics { snapNext = true }
        lastMetrics = metrics
        var size = board.size(withDetail: want)
        if !mini { size = NSSize(width: ceil(size.width * uiScale), height: ceil(size.height * uiScale)) }      // 面板整体大小
        if cheerStyle && !mini { size.height += stageTop }        // 上面给拉拉队留一块
        if cheerStyle, bubbleOpen {               // 收起时窗口往左伸出一块放气泡；气泡比拉拉队高的话，往下也多留一点
            size.width = max(size.width, mascotSide + bubbleWidth)
            size.height = max(size.height, bubble.fittingSize().height + 2)
        }
        let target = place(size)
        let switched = want && lastDetailKey != nil && lastDetailKey != selected
        lastDetailKey = want ? selected : nil
        animate(to: target, detailAlpha: want ? 1 : 0, dip: switched) { [weak self] in
            guard let self = self, self.closing else { return }
            self.closing = false
            self.board.detail = nil
            self.board.needsDisplay = true
        }
        // 详情展开时保持清晰，不然 35% 透明度下看不清数字
        let alpha = CGFloat(hovering || want || board.page != .list ? cfg.hoverOpacity : (mini ? max(cfg.opacity, 0.8) : cfg.opacity))
        if abs(panel.alphaValue - alpha) > 0.001 {
            evt("透明度 \(panel.alphaValue) → \(alpha)")
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = alpha
            }
        }
        board.needsDisplay = true
        syncKeyboard()
    }
}

// MARK: - 自检（./CheerUp --selftest）

func selfTest() -> Int32 {
    var fails = 0, n = 0
    func check(_ name: String, _ ok: Bool) { n += 1; if !ok { fails += 1; print("FAIL  \(name)") } }
    // 代码识别
    for (a, b) in [("600519", "sh600519"), ("000858", "sz000858"), ("000333", "sz000333"), ("688981", "sh688981"),
                   ("510300", "sh510300"), ("159915", "sz159915"), ("830799", "bj830799"), ("920001", "bj920001"),
                   ("00700", "r_hk00700"), ("700", "r_hk00700"), ("hk00700", "r_hk00700"), ("hkHSI", "r_hkHSI"),
                   ("AAPL", "usAAPL"), ("aapl", "usAAPL"), ("BRK.B", "usBRK.B"), ("SHOP", "usSHOP"),
                   ("sh000001", "sh000001"), ("usNVDA", "usNVDA"), (".IXIC", "us.IXIC")] {
        check("apiSymbol \(a)", apiSymbol(a) == b)
    }
    check("合法代码", isValidCode("600519") && isValidCode("BRK.B") && isValidCode("sh000001"))
    check("非法代码", !isValidCode("茅台") && !isValidCode("AA PL") && !isValidCode("") && !isValidCode("a&b=1") && !isValidCode(String(repeating: "A", count: 40)))
    // 行情解析
    func line(_ key: String, price: String, prev: String) -> String {
        var f = Array(repeating: "0", count: 50)
        f[1] = "测试"; f[2] = "000001"; f[3] = price; f[4] = prev; f[5] = "10.00"; f[30] = "20261125104627"; f[33] = "11.00"; f[34] = "9.00"
        return "v_\(key)=\"" + f.joined(separator: "~") + "\";"
    }
    let q1 = parseQuotes(line("sz000001", price: "10.50", prev: "10.00"))["sz000001"]
    check("正常行情", q1 != nil && abs(q1!.pct - 5) < 1e-9 && q1!.dir == 1 && q1!.time == "10:46")
    let q0 = parseQuotes(line("sz000001", price: "0.00", prev: "10.00"))["sz000001"]
    check("现价为 0 不算跌 100%", q0 != nil && !q0!.live && q0!.pct == 0 && q0!.dir == 0 && q0!.change == 0)
    check("垃圾响应不崩", parseQuotes("v_pv_none_match=\"1\";").isEmpty && parseQuotes("").isEmpty && parseQuotes("<html>502</html>").isEmpty)
    check("字段不够不崩", parseQuotes("v_sh1=\"1~a~b~1.0\";").isEmpty)
    // 配置
    func cfg(_ json: String) -> Config? { decodeConfig(json.data(using: .utf8)!) }
    check("空对象用默认值", cfg("{}")?.refreshSeconds == 3)
    check("坏 JSON 返回 nil", cfg("{ \"stocks\": [\"600519\", }") == nil)
    check("弯引号返回 nil", cfg("{ “stocks”: [] }") == nil)
    check("类型写错返回 nil", cfg("{ \"fontSize\": \"大\" }") == nil)
    let c = cfg("{ \"opacity\": 0, \"hoverOpacity\": 0, \"fontSize\": 200, \"refreshSeconds\": 0.01, \"theme\": \"pink\", \"stocks\": [\" 600519 \", \"\"] }")
    check("越界数值被拉回", c != nil && c!.opacity >= 0.08 && c!.hoverOpacity >= 0.3 && c!.fontSize == 22 && c!.refreshSeconds == 2 && c!.theme == "dark" && c!.stocks == ["600519"])
    let hits = parseSearch("v_hint=\"sh~600519~\\u8d35\\u5dde\\u8305\\u53f0~gzmt~GP-A^jj~007005~x~y~KJ^hk~00700~\\u817e\\u8baf\\u63a7\\u80a1~txkg~GP^us~aapl.oq~\\u82f9\\u679c~pg~GP^sh~000001~\\u4e0a\\u8bc1\\u6307\\u6570~szzs~ZS\"")
    check("搜索解析", hits.map { $0.code } == ["600519", "hk00700", "usAAPL", "sh000001"] && hits.first?.name == "贵州茅台" && hits.last?.tag == "指数")
    check("搜索无结果", parseSearch("v_hint=\"N\";").isEmpty && parseSearch("").isEmpty && parseSearch("<html>501</html>").isEmpty)
    let h2 = parseSearch("v_hint=\"us~brk.b.n~x~y~GP^us~ixic~n~y~ZS^hk~80700~tencent r~y~GP^hk~13005~w~y~QZ^us~tcehy.ps~t adr~y~GP\"")
    check("美股分类股与指数代码", h2.map { $0.code } == ["usBRK.B", "us.IXIC", "usTCEHY"])
    let h3 = parseSearch("v_hint=\"jj~000001~f~y~KJ^sz~000700~a~y~GP-A^hk~00700~b~y~GP^sh~600700~c~y~GP-A\"", query: "700")
    check("代码完全一致的排最前", h3.first?.code == "hk00700" && h3.count == 3)
    check("只看指定市场", parseSearch("v_hint=\"sh~000001~i~y~ZS^sz~000001~b~y~GP-A\"", query: "000001", market: "sz").map { $0.code } == ["000001"])
    check("常用指数的口头叫法", indexHits("恒生", market: nil).map { $0.code } == ["hkHSI", "hkHSTECH"] && indexHits("纳指", market: nil).first?.code == "us.IXIC"
          && indexHits("s&p", market: nil).first?.code == "us.INX" && indexHits("茅台", market: nil).isEmpty && indexHits("恒", market: nil).isEmpty)
    check("输入清洗", cleanQuery("  茅 台 ")?.q == "茅台" && cleanQuery("ＡＡＰＬ")?.q == "AAPL" && cleanQuery("apple   inc")?.q == "apple inc"
          && cleanQuery("<script>'\"%")?.q == "script" && cleanQuery("'\"%<>") == nil && cleanQuery("   ") == nil)
    check("带市场前缀的输入", cleanQuery("sh600519")?.market == "sh" && cleanQuery("sh600519")?.q == "600519" && cleanQuery("hk00700")?.q == "00700"
          && cleanQuery("usAAPL")?.q == "AAPL" && cleanQuery("us.IXIC")?.q == "IXIC" && cleanQuery("usb")?.market == nil && cleanQuery("shop")?.market == nil && cleanQuery("hkHSI")?.q == "HSI")
    check("代码兜底的候选", codeCandidates("600519") == ["sh600519", "sz600519", "bj600519"] && codeCandidates("700") == ["r_hk00700"] && codeCandidates("aapl") == ["usAAPL"]
          && codeCandidates("brk.b") == ["usBRK.B"] && codeCandidates("茅台").isEmpty && codeCandidates("1234567").isEmpty)
    check("行数上限", cfg("{ \"maxVisibleRows\": 999 }")?.maxVisibleRows == 20 && cfg("{ \"maxVisibleRows\": 0 }")?.maxVisibleRows == 3)
    check("重复代码去重", cfg("{ \"stocks\": [\"600519\", \"sh600519\", \"600519\", \"AAPL\", \"aapl\"] }")?.stocks == ["600519", "AAPL"])
    // 市场状态（用固定时刻验证：2026-11-25 是周三）
    func at(_ s: String, _ zone: String) -> Date {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: zone); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }
    let sh = "Asia/Shanghai", ny = "America/New_York"
    check("A股 交易中", Market.aStock.status(now: at("2026-11-25 10:00", sh), stamp: at("2026-11-25 09:59", sh)).text == "交易中")
    check("A股 午休", Market.aStock.status(now: at("2026-11-25 12:00", sh), stamp: nil).text == "午休")
    check("英文状态", { lang = "en"; defer { lang = "zh" }; return Market.us.status(now: at("2026-11-25 08:00", ny), stamp: nil).text == "Pre-market" && Market.aStock.status(now: at("2026-11-25 12:00", sh), stamp: nil).text == "Lunch break" }())
    check("A股 集合竞价", Market.aStock.status(now: at("2026-11-25 09:20", sh), stamp: nil).text == "集合竞价")
    check("A股 已收盘", Market.aStock.status(now: at("2026-11-25 15:30", sh), stamp: nil).text == "已收盘")
    check("A股 周末", Market.aStock.status(now: at("2026-11-28 10:00", sh), stamp: nil).text == "休市")
    check("A股 节假日（工作日但没有新行情）", Market.aStock.status(now: at("2026-11-25 10:00", sh), stamp: at("2026-11-24 15:00", sh)).text == "休市")
    check("港股 下午 15:30 还在交易", Market.hk.status(now: at("2026-11-25 15:30", sh), stamp: at("2026-11-25 15:29", sh)).live)
    check("美股 北京白天是已收盘", Market.us.status(now: at("2026-11-25 11:00", sh), stamp: at("2026-11-24 16:00", ny)).text == "已收盘")
    check("美股 北京晚上 23 点交易中", Market.us.status(now: at("2026-11-25 23:00", sh), stamp: at("2026-11-25 09:59", ny)).text == "交易中")
    check("美股 盘前", Market.us.status(now: at("2026-11-25 08:00", ny), stamp: nil).text == "盘前")
    let hf = parseQuotes("v_hf_XAU=\"3576.36,-0.34,3576.36,3576.71,3607.02,3551.13,11:20:00,3588.55,3589.32,0,0,0,2026-11-26,伦敦金（现货黄金）\";")["hf_XAU"]
    check("商品行情解析", hf != nil && hf!.name == "伦敦金" && hf!.price == 3576.36 && hf!.prevClose == 3588.55 && hf!.high == 3607.02 && hf!.low == 3551.13 && hf!.time == "11:20" && abs(hf!.pct + 0.34) < 0.01)
    check("商品代码和归属", apiSymbol("hf_xau") == "hf_XAU" && Market.of("hf_XAU") == .cmdty && AppDelegate.tabOf("hf_GC") == "a" && isValidCode("hf_XAU"))
    check("黄金产品认得出", referencePrice(forName: "黄金ETF博时")?.code == "hf_XAU" && referencePrice(forName: "黄金主题LOF")?.code == "hf_XAU" && referencePrice(forName: "白银LOF")?.code == "hf_XAG" && referencePrice(forName: "原油LOF易方达")?.code == "hf_CL" && referencePrice(forName: "贵州茅台") == nil)
    check("商品搜得到", indexHits("黄金", market: nil).contains { $0.code == "hf_XAU" } && indexHits("gold", market: nil).contains { $0.code == "hf_GC" } && !indexHits("黄金", market: "sh").contains { $0.code == "hf_XAU" })
    check("市场识别", Market.of("sh600519") == .aStock && Market.of("sh000001", type: "ZS") == .aIndex && Market.of("r_hk00700") == .hk && Market.of("usAAPL") == .us)
    let us = parseQuotes(line("usAAPL", price: "354.07", prev: "349.08").replacingOccurrences(of: "20261125104627", with: "2026-11-24 16:00:02"))["usAAPL"]
    check("美股时间按美东解析", us?.stamp == at("2026-11-24 16:00", ny).addingTimeInterval(2) && us?.time == "16:00")
    let md = parseMinutes(Data("{\"data\":{\"sz1\":{\"data\":{\"data\":[\"0930 10.00 100 100000.00\",\"0931 10.20 300 303000.00\",\"0932 0 300 303000\"]}}}}".utf8), code: "sz1", market: .aStock)
    check("分时解析与均价", md.prices == [10.0, 10.2] && md.vols == [100, 200] && md.avg.count == 2 && abs(md.avg[1] - 10.1) < 1e-9)
    let mu = parseMinutes(Data("{\"data\":{\"usA.OQ\":{\"data\":{\"data\":[\"0930 346.09 1112947\",\"0931 346.10 1873392\"]}}}}".utf8), code: "usA.OQ", market: .us)
    check("美股分时没有均价", mu.prices.count == 2 && mu.avg.isEmpty)
    check("分时垃圾响应", parseMinutes(Data("<!DOCTYPE html>".utf8), code: "x", market: .us).prices.isEmpty)
    let em = parseEastmoneyMinutes(Data("{\"data\":{\"trends\":[\"2026-11-25 09:30,44.88,3990,17906536.00,44.880\",\"2026-11-25 09:31,45.00,15159,68226339.00,44.982\"]}}".utf8))
    check("备用分时源解析", em.prices == [44.88, 45.0] && em.vols == [3990, 15159] && em.times == ["0930", "0931"] && em.avg.count == 2)
    check("备用源编号", eastmoneySecid(key: "sh600519", market: .aStock, code: "600519") == "1.600519" && eastmoneySecid(key: "sz000858", market: .aStock, code: "000858") == "0.000858"
          && eastmoneySecid(key: "r_hk00700", market: .hk, code: "00700") == "116.00700" && eastmoneySecid(key: "usAAPL", market: .us, code: "AAPL.OQ") == "105.AAPL"
          && eastmoneySecid(key: "r_hkHSI", market: .hk, code: "HSI") == nil)
    check("分页归属", AppDelegate.tabOf("600519") == "a" && AppDelegate.tabOf("sh000001") == "a" && AppDelegate.tabOf("00700") == "hk" && AppDelegate.tabOf("hkHSI") == "hk"
          && AppDelegate.tabOf("AAPL") == "us" && AppDelegate.tabOf("us.IXIC") == "us" && AppDelegate.tabOf("茅台") == "a")
    check("动作首尾相接", cheerPose(at: 0).aL == -50 && cheerPose(at: 0.41) == Pose() && cheerPose(at: cheerRoutineLength - 0.001).aL < -49 && cheerRoutineLength > 5)
    check("标签顺序", cfg("{}")?.tabOrder == ["a", "hk", "us"] && cfg("{ \"tabOrder\": [\"us\", \"y\", \"us\"] }")?.tabOrder == ["us", "a", "hk"])
    check("界面大小", cfg("{}")?.uiSize == "m" && cfg("{ \"uiSize\": \"xl\" }")?.uiSize == "xl" && cfg("{ \"uiSize\": \"huge\" }")?.uiSize == "m")
    check("小人大小", cfg("{}")?.mascotSize == "m" && cfg("{ \"mascotSize\": \"huge\" }")?.mascotSize == "m" && cfg("{ \"mascotSize\": \"l\" }")?.mascotSize == "l")
    check("花球颜色", cfg("{}")?.pomColor == "auto" && cfg("{ \"pomColor\": \"pink\" }")?.pomColor == "auto" && cfg("{ \"pomColor\": \"green\" }")?.pomColor == "green")
    check("作息设置", cfg("{}")?.restSchedule == "auto" && cfg("{ \"restSchedule\": \"never\" }")?.restSchedule == "never" && cfg("{ \"restSchedule\": \"x\" }")?.restSchedule == "auto")
    check("价格格式", fmt(0.5) == "0.500" && fmt(12.345) == "12.35" && fmtP(0) == "—")
    print(fails == 0 ? "PASS  \(n) 项自检全部通过" : "\(fails)/\(n) 项失败")
    return fails == 0 ? 0 : 1
}

if CommandLine.arguments.contains("--selftest") { exit(selfTest()) }
if let i = CommandLine.arguments.firstIndex(of: "--film"), i + 3 < CommandLine.arguments.count {
    // 调试用：不开任何窗口，把拉拉队在一段时间里的每一帧画成一张连环画。./CheerUp --film 起始秒 结束秒 步长 输出.png
    let a = CommandLine.arguments
    let t0 = Double(a[i + 1])!, t1 = Double(a[i + 2])!, dt = Double(a[i + 3])!, path = a[i + 4]
    let side: CGFloat = ProcessInfo.processInfo.environment["PEEK_FILMSIDE"].flatMap { Double($0) }.map { CGFloat($0) } ?? 132      // 想看清线条衔接时调大
    let n = Int(((t1 - t0) / dt).rounded()) + 1, cols = min(n, 12), rowsN = (n + cols - 1) / cols
    let view = BoardView(frame: NSRect(x: 0, y: 0, width: side, height: side))
    view.mini = true
    var filmWobble = Wobble()
    let sheet = NSImage(size: NSSize(width: CGFloat(cols) * side, height: CGFloat(rowsN) * side))
    sheet.lockFocus()
    for k in 0..<n {
        let r = NSRect(x: CGFloat(k % cols) * side, y: CGFloat(rowsN - 1 - k / cols) * side, width: side, height: side)
        (k / cols % 2 == 0 ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill(); r.fill()      // 一行深底、一行浅底
        view.fixedStep = 1.0 / 60
        if k > 0, ProcessInfo.processInfo.environment["PEEK_BEHIND"] == nil {
            var tt = t0 + dt * Double(k - 1)
            while tt < t0 + dt * Double(k) - 1e-6 { tt += 1.0 / 60; view.pose = cheerPose(at: min(tt, t0 + dt * Double(k))) }
        } else { view.pose = cheerPose(at: t0 + dt * Double(k)) }
        if ProcessInfo.processInfo.environment["PEEK_DRAG"] != nil {      // 调试用：这一条连环画改成演示被拖着走（往右拖 0.6 秒、往左拖 0.6 秒、松手）
            let t = Double(k) * dt
            var base = Pose.resting(at: 0.8, asleep: false)
            var w = filmWobble; var tt = max(0, t - dt)
            while tt < t - 1e-6 {
                tt += 1.0 / 60
                let dragging = tt < 1.2, vx: CGFloat = tt < 0.6 ? 520 : (tt < 1.2 ? -520 : 0)
                w.step(vx: vx, vy: 0, dragging: dragging, dt: 1.0 / 60)
            }
            filmWobble = w
            view.frown = w.apply(to: &base)
            for _ in 0..<6 { view.pose = base }
        }
        if ProcessInfo.processInfo.environment["PEEK_TEA"] != nil {      // 调试用：这一条连环画改成演示喝茶休息
            let tf = teaFrame(Double(k) * dt, from: Pose())
            view.behind = tf.behind; view.cup = tf.cup; view.sip = tf.sip; view.heldLeft = !tf.cup; view.thumb = tf.thumb
            view.steam = CGFloat((Double(k) * dt / 2.4).truncatingRemainder(dividingBy: 1))
            let shownTea = tf.live > 0 ? tf.pose.mix(cheerPose(at: 1.15 + max(0, Double(k) * dt - (teaSeconds - 0.55))), tf.live) : tf.pose
            for _ in 0..<6 { view.pose = shownTea }
        }
        if let mode = ProcessInfo.processInfo.environment["PEEK_AWAY"] {      // 调试用：这一条连环画改成演示「隐藏」（leave）或「回来」（return）的过场
            let t = Double(k) * dt, from = Pose.resting(at: 0.8, asleep: false)
            if k == 0 { view.pose = from }
            let f = mode == "return" ? returnFrame(t) : leaveFrame(t, from: from, hand: NSPoint(x: 9.2, y: 12.5))
            view.offsetX = f.x; view.fade = f.fade; view.heldLeft = f.held; view.loosePom = f.loose; view.loosePomRot = f.rot
            view.gaze = NSPoint(x: f.gazeX, y: f.gazeY)
            let shown = f.live > 0 ? f.pose.mix(cheerPose(at: 1.15 + max(0, t - 0.98)), f.live) : f.pose
            for _ in 0..<6 { view.pose = shown }
        }
        if ProcessInfo.processInfo.environment["PEEK_CURIOUS"] != nil {      // 调试用：这一条连环画改成演示鼠标停上去时的「嗯？」
            let c = CGFloat(min(1, Double(k) * dt / 0.5)); var ps = Pose.resting(at: 0.8, asleep: false)
            ps.lean += 0.9 * c; if c > 0.5 { ps.face = 2 }
            view.curious = c; view.facing = true; view.gaze = NSPoint(x: -0.95 * c, y: -0.35 * c)
            for _ in 0..<12 { view.pose = ps }
        }
        if ProcessInfo.processInfo.environment["PEEK_BEHIND"] != nil {       // 调试用：这一条连环画改成演示背手换花球
            let st = swapState(min(Double(k) * dt / swapSeconds, 1))
            let ps = Pose.resting(at: 0.8, asleep: false)
            view.behind = st.behind; view.dig = st.dig; view.greenUp = st.found; view.pose = ps
            view.gaze = NSPoint(x: 0, y: st.behind * (st.found ? 0 : 0.35))
        }
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        rep.draw(in: r)
    }
    sheet.unlockFocus()
    if let t = sheet.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)) }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--search") {       // 调试用：./CheerUp --search 关键词…  逐个跑完整搜索并打印
    let d = AppDelegate()
    var rest = Array(CommandLine.arguments[(i + 1)...])
    func next() {
        guard !rest.isEmpty else { exit(0) }
        let raw = rest.removeFirst()
        guard let (q, m) = cleanQuery(raw) else { print("「\(raw)」 → （无可搜内容）"); next(); return }
        d.runSearch(q, market: m, shown: raw) { hits, foot in
            print("「\(raw)」 → " + hits.prefix(6).map { "\($0.name)(\($0.code) \($0.tag))" }.joined(separator: " | ") + "  ［\(foot)］")
            next()
        }
    }
    next()
    RunLoop.main.run()
}
if let i = CommandLine.arguments.firstIndex(of: "--baricon"), i + 1 < CommandLine.arguments.count {     // 调试用：把顶部栏图标存成图片
    let big = NSImage(size: NSSize(width: 144, height: 144), flipped: false) { r in NSColor.white.setFill(); r.fill(); let ic = AppDelegate.barIcon(); let h = r.width * ic.size.height / ic.size.width; ic.draw(in: NSRect(x: 0, y: (r.height - h) / 2, width: r.width, height: h)); return true }
    if let t = big.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) }
    exit(0)
}

// 已经有一个在跑就不再开第二个（否则两个小窗叠在一起，快捷键也会打架）
if testHome == nil, let bid = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bid).contains(where: { $0 != NSRunningApplication.current }) {
    DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.cheerup.show"), object: nil, userInfo: nil, deliverImmediately: true)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
