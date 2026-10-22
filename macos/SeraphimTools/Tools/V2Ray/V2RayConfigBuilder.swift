import Foundation

/// 把节点拼成 Xray / v2ray 能读的 config.json
enum XrayConfigBuilder {
    struct Options: Sendable {
        var socksPort: Int = 10808
        var httpPort: Int = 10809
        var bypassLAN: Bool = true
        var bypassChina: Bool = true
        /// geosite.dat 在不在。不在就别写 geosite:cn —— 内核会因为读不到文件直接拒绝启动
        var geoAvailable: Bool = true
        var sniffing: Bool = true
        var allowUDP: Bool = true
        var logLevel: String = "warning"

        /// 实际能不能走大陆分流
        var chinaBypassEffective: Bool { bypassChina && geoAvailable }
    }

    static func build(node: V2RayNode, options: Options) -> String {
        let config = JSONValue.object([
            ("log", .object([
                ("loglevel", .string(options.logLevel)),
                ("access", .string(""))
            ])),
            ("inbounds", .array(inbounds(options))),
            ("outbounds", .array(outbounds(node: node))),
            ("routing", routing(options))
        ])
        return config.render() + "\n"
    }

    // MARK: 入站

    private static func inbounds(_ options: Options) -> [JSONValue] {
        let sniffing: JSONValue = options.sniffing
            ? .object([
                ("enabled", .bool(true)),
                ("destOverride", .array([.string("http"), .string("tls"), .string("quic")])),
                ("routeOnly", .bool(false))
            ])
            : .object([("enabled", .bool(false))])

        let socks = JSONValue.object([
            ("tag", .string("socks-in")),
            ("listen", .string("127.0.0.1")),
            ("port", .int(options.socksPort)),
            ("protocol", .string("socks")),
            ("settings", .object([
                ("auth", .string("noauth")),
                ("udp", .bool(options.allowUDP)),
                ("userLevel", .int(0))
            ])),
            ("sniffing", sniffing)
        ])

        let http = JSONValue.object([
            ("tag", .string("http-in")),
            ("listen", .string("127.0.0.1")),
            ("port", .int(options.httpPort)),
            ("protocol", .string("http")),
            ("settings", .object([
                ("userLevel", .int(0)),
                ("allowTransparent", .bool(false))
            ])),
            ("sniffing", sniffing)
        ])

        return [socks, http]
    }

    // MARK: 出站

    private static func outbounds(node: V2RayNode) -> [JSONValue] {
        var list: [JSONValue] = [proxyOutbound(node)]

        list.append(.object([
            ("tag", .string("direct")),
            ("protocol", .string("freedom")),
            ("settings", .object([
                ("domainStrategy", .string("UseIP"))
            ]))
        ]))

        list.append(.object([
            ("tag", .string("block")),
            ("protocol", .string("blackhole")),
            ("settings", .object([]))
        ]))

        return list
    }

    private static func proxyOutbound(_ node: V2RayNode) -> JSONValue {
        var pairs: [(String, JSONValue)] = [
            ("tag", .string("proxy")),
            ("protocol", .string(node.proto.outboundName)),
            ("settings", settings(for: node))
        ]

        if node.proto.supportsStream {
            pairs.append(("streamSettings", streamSettings(for: node)))
        } else if node.proto == .http || node.proto == .socks {
            // 本地型出站也可能挂 TLS
            if node.security == .tls {
                pairs.append(("streamSettings", streamSettings(for: node)))
            }
        }
        return .object(pairs)
    }

    private static func settings(for node: V2RayNode) -> JSONValue {
        switch node.proto {
        case .vmess:
            return .object([
                ("vnext", .array([
                    .object([
                        ("address", .string(node.address)),
                        ("port", .int(node.port)),
                        ("users", .array([
                            .object([
                                ("id", .string(node.uuid)),
                                ("alterId", .int(node.alterId)),
                                ("security", .string(node.cipher.isEmpty ? "auto" : node.cipher)),
                                ("level", .int(0))
                            ])
                        ]))
                    ])
                ]))
            ])

        case .vless:
            var user: [(String, JSONValue)] = [
                ("id", .string(node.uuid)),
                ("encryption", .string("none")),
                ("level", .int(0))
            ]
            if !node.flow.isEmpty { user.insert(("flow", .string(node.flow)), at: 1) }
            return .object([
                ("vnext", .array([
                    .object([
                        ("address", .string(node.address)),
                        ("port", .int(node.port)),
                        ("users", .array([.object(user)]))
                    ])
                ]))
            ])

        case .trojan:
            return .object([
                ("servers", .array([
                    .object([
                        ("address", .string(node.address)),
                        ("port", .int(node.port)),
                        ("password", .string(node.password)),
                        ("level", .int(0))
                    ])
                ]))
            ])

        case .shadowsocks:
            return .object([
                ("servers", .array([
                    .object([
                        ("address", .string(node.address)),
                        ("port", .int(node.port)),
                        ("method", .string(node.method)),
                        ("password", .string(node.password)),
                        ("uot", .bool(false)),
                        ("level", .int(0))
                    ])
                ]))
            ])

        case .socks:
            var server: [(String, JSONValue)] = [
                ("address", .string(node.address)),
                ("port", .int(node.port))
            ]
            if !node.password.isEmpty || !node.uuid.isEmpty {
                server.append(("users", .array([
                    .object([
                        ("user", .string(node.uuid)),
                        ("pass", .string(node.password)),
                        ("level", .int(0))
                    ])
                ])))
            }
            return .object([("servers", .array([.object(server)]))])

        case .http:
            var server: [(String, JSONValue)] = [
                ("address", .string(node.address)),
                ("port", .int(node.port))
            ]
            if !node.password.isEmpty || !node.uuid.isEmpty {
                server.append(("users", .array([
                    .object([
                        ("user", .string(node.uuid)),
                        ("pass", .string(node.password)),
                        ("level", .int(0))
                    ])
                ])))
            }
            return .object([("servers", .array([.object(server)]))])
        }
    }

    // MARK: 传输层

    private static func streamSettings(for node: V2RayNode) -> JSONValue {
        var pairs: [(String, JSONValue)] = [
            ("network", .string(node.network.rawValue)),
            ("security", .string(node.security.rawValue))
        ]

        switch node.security {
        case .none:
            break
        case .tls:
            var tls: [(String, JSONValue)] = []
            if !node.sni.isEmpty { tls.append(("serverName", .string(node.sni))) }
            if !node.fingerprint.isEmpty { tls.append(("fingerprint", .string(node.fingerprint))) }
            if node.allowInsecure { tls.append(("allowInsecure", .bool(true))) }
            if !node.alpn.isEmpty {
                tls.append(("alpn", .array(node.alpn.split(separator: ",").map { .string(String($0).trimmingCharacters(in: .whitespaces)) })))
            }
            pairs.append(("tlsSettings", .object(tls)))
        case .reality:
            var reality: [(String, JSONValue)] = []
            if !node.sni.isEmpty { reality.append(("serverName", .string(node.sni))) }
            if !node.publicKey.isEmpty { reality.append(("publicKey", .string(node.publicKey))) }
            if !node.shortId.isEmpty { reality.append(("shortId", .string(node.shortId))) }
            if !node.fingerprint.isEmpty { reality.append(("fingerprint", .string(node.fingerprint))) }
            reality.append(("spiderX", .string(node.spiderX.isEmpty ? "/" : node.spiderX)))
            reality.append(("show", .bool(false)))
            pairs.append(("realitySettings", .object(reality)))
        }

        switch node.network {
        case .tcp:
            if node.headerType == "http" {
                var request: [(String, JSONValue)] = [
                    ("path", .array([.string(node.path.isEmpty ? "/" : node.path)]))
                ]
                if !node.host.isEmpty {
                    request.append(("headers", .object([("Host", .array([.string(node.host)]))])))
                }
                pairs.append(("tcpSettings", .object([
                    ("header", .object([
                        ("type", .string("http")),
                        ("request", .object(request))
                    ]))
                ])))
            }
        case .ws:
            var ws: [(String, JSONValue)] = [
                ("path", .string(node.path.isEmpty ? "/" : node.path))
            ]
            if !node.host.isEmpty {
                ws.append(("headers", .object([("Host", .string(node.host))])))
            }
            pairs.append(("wsSettings", .object(ws)))
        case .grpc:
            pairs.append(("grpcSettings", .object([
                ("serviceName", .string(node.serviceName)),
                ("multiMode", .bool(false))
            ])))
        case .http, .h2:
            var http: [(String, JSONValue)] = [
                ("path", .string(node.path.isEmpty ? "/" : node.path))
            ]
            if !node.host.isEmpty {
                http.append(("host", .array([.string(node.host)])))
            }
            pairs.append(("httpSettings", .object(http)))
        case .quic:
            pairs.append(("quicSettings", .object([
                ("security", .string("none")),
                ("key", .string("")),
                ("header", .object([("type", .string(node.headerType.isEmpty ? "none" : node.headerType))]))
            ])))
        case .kcp:
            pairs.append(("kcpSettings", .object([
                ("mtu", .int(1350)),
                ("tti", .int(50)),
                ("uplinkCapacity", .int(12)),
                ("downlinkCapacity", .int(100)),
                ("congestion", .bool(false)),
                ("readBufferSize", .int(2)),
                ("writeBufferSize", .int(2)),
                ("header", .object([("type", .string(node.headerType.isEmpty ? "none" : node.headerType))]))
            ])))
        case .httpupgrade:
            var upgrade: [(String, JSONValue)] = [
                ("path", .string(node.path.isEmpty ? "/" : node.path))
            ]
            if !node.host.isEmpty { upgrade.append(("host", .string(node.host))) }
            pairs.append(("httpupgradeSettings", .object(upgrade)))
        case .xhttp:
            var xhttp: [(String, JSONValue)] = [
                ("path", .string(node.path.isEmpty ? "/" : node.path)),
                ("mode", .string("auto"))
            ]
            if !node.host.isEmpty { xhttp.append(("host", .string(node.host))) }
            pairs.append(("xhttpSettings", .object(xhttp)))
        }

        return .object(pairs)
    }

    // MARK: 路由

    private static func routing(_ options: Options) -> JSONValue {
        var rules: [JSONValue] = []

        if options.chinaBypassEffective {
            // 顺序很讲究：先把"墙外域名"扣出来走代理，再让剩下的国内域名直连。
            //
            // 两个坑叠在一起：
            // 1. 不能用 geoip:cn 判国内外——国内 DNS 对国外域名经常返回污染地址，而污染
            //    地址往往落在中国 IP 段里（实测 www.gstatic.com 被解析到 58.254.137.162，
            //    广东电信），流量会被判成"国内网站"直接放行，表现出来就是代理开了没效果。
            // 2. geosite:cn 里其实混着一批 Google 的国内 CDN 域名（www.gstatic.com、
            //    fonts.gstatic.com 都在里面），只按 cn 列表放行的话，Google 页面会被判直连，
            //    结果就是"网页打开了但一片空白"。
            //
            // 所以先匹配 geolocation-!cn（中国大陆访问不了的域名），它包含 google、gstatic、
            // youtube、twitter 这些，命中即走代理；剩下的才按 cn 列表直连。
            rules.append(.object([
                ("type", .string("field")),
                ("outboundTag", .string("proxy")),
                ("domain", .array([.string("geosite:geolocation-!cn")]))
            ]))
            rules.append(.object([
                ("type", .string("field")),
                ("outboundTag", .string("direct")),
                ("domain", .array([
                    .string("geosite:cn"),
                    .string("geosite:private")
                ]))
            ]))
        }

        if options.bypassLAN {
            let privateNets = [
                "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
                "169.254.0.0/16", "100.64.0.0/10", "224.0.0.0/4",
                "::1/128", "fc00::/7", "fe80::/10"
            ]
            rules.append(.object([
                ("type", .string("field")),
                ("outboundTag", .string("direct")),
                ("ip", .array(privateNets.map { .string($0) }))
            ]))
            rules.append(.object([
                ("type", .string("field")),
                ("outboundTag", .string("direct")),
                ("domain", .array([.string("localhost")]))
            ]))
        }

        rules.append(.object([
            ("type", .string("field")),
            ("outboundTag", .string("block")),
            ("protocol", .array([.string("bittorrent")]))
        ]))

        return .object([
            // AsIs：不替客户端反查域名对应的 IP。省一次 DNS，也免得被污染结果带偏路由。
            ("domainStrategy", .string("AsIs")),
            ("rules", .array(rules))
        ])
    }
}
