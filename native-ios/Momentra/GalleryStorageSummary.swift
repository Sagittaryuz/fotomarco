import SwiftUI
import GoogleSignIn

struct GalleryCapacitySummary: View {
    let section: Int
    let accounts: [CloudArchiveAccounts.Account]
    var compact = false
    @State private var local: StorageTotals?
    @State private var quotas: [CloudDeliveryPlan.Destination: CloudQuota] = [:]
    @State private var loading = Set<CloudDeliveryPlan.Destination>()
    @Environment(\.scenePhase) private var scenePhase

    private struct CloudQuota: Sendable {
        let total: Int64
        let used: Int64
    }

    var body: some View {
        VStack(spacing: compact ? 3 : 8) {
            if section != 2 {
                let name = section == 0 && !compact ? "Capturas no iPhone" : "Armazenamento do iPhone"
                let value = local.map { CloudQuota(total: $0.total, used: section == 0 && !compact ? $0.primary : $0.used) }
                row(name: name, quota: value, unavailable: "Capacidade do iPhone indisponível", tint: .mint) {
                    Image(systemName: "photo.on.rectangle.fill")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                        .frame(width: compact ? 17 : 25, height: compact ? 17 : 25)
                        .background(AngularGradient(colors: [.purple, .blue, .mint, .orange, .pink, .purple],
                                                    center: .center, startAngle: .zero, endAngle: .degrees(360)), in: Circle())
                }
            }
            if section != 1 {
                ForEach(accounts) { account in
                    let google = account.id.provider == .googleDrive
                    let name = (google ? "Google Drive" : "OneDrive") + " · " + account.label
                    row(name: name, quota: quotas[account.id],
                        unavailable: loading.contains(account.id) ? "Consultando capacidade…" : "Limite não informado pelo serviço",
                        tint: google ? .green : .blue) {
                        Image(google ? "GoogleDriveMark" : "OneDriveMark")
                            .renderingMode(.original).resizable().scaledToFit().frame(width: compact ? 17 : 24, height: compact ? 17 : 24)
                    }
                }
                if section == 2 && accounts.isEmpty {
                    Text("Conecte uma conta para consultar a capacidade da nuvem.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.bottom, compact ? 4 : 10)
        .task { await refreshLocal() }
        .task(id: accounts.map(\.id)) {
            let destinations = accounts.map(\.id)
            loading = Set(destinations)
            quotas = quotas.filter { destinations.contains($0.key) }
            await withTaskGroup(of: (CloudDeliveryPlan.Destination, CloudQuota?).self) { group in
                for destination in destinations {
                    group.addTask { (destination, await Self.fetchQuota(for: destination)) }
                }
                for await (destination, quota) in group {
                    guard !Task.isCancelled else { return }
                    quotas[destination] = quota
                    loading.remove(destination)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshLocal() } }
        }
    }

    private func row<Icon: View>(name: String, quota: CloudQuota?, unavailable: String, tint: Color,
                                 @ViewBuilder icon: () -> Icon) -> some View {
        HStack(spacing: 9) {
            icon().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font((compact ? Font.caption2 : Font.caption).weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let quota {
                        let fraction = Double(quota.used) / Double(quota.total)
                        Text(fraction, format: .percent.precision(.fractionLength(0...1)))
                            .font(.caption.monospacedDigit()).foregroundStyle(tint)
                    }
                }
                if let quota {
                    ProgressView(value: min(1, Double(quota.used) / Double(quota.total))).tint(tint)
                    if !compact {
                        Text("\(format(quota.used)) de \(format(quota.total))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(unavailable).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func refreshLocal() async {
        local = await Task.detached(priority: .utility) { StorageTotals.local() }.value
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func fetchQuota(for destination: CloudDeliveryPlan.Destination) async -> CloudQuota? {
        struct GoogleResponse: Decodable {
            struct Storage: Decodable { let limit: String?; let usage: String? }
            let storageQuota: Storage
        }
        struct MicrosoftResponse: Decodable {
            struct Storage: Decodable { let total: Int64?; let used: Int64? }
            let quota: Storage?
        }
        do {
            let google = destination.provider == .googleDrive
            let endpoint = google ? "https://www.googleapis.com/drive/v3/about?fields=storageQuota%28limit%2Cusage%29" :
                "https://graph.microsoft.com/v1.0/me/drive?$select=quota"
            let token = try await CloudArchiveAccounts.shared.accessToken(for: destination)
            var request = URLRequest(url: URL(string: endpoint)!, timeoutInterval: 10)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let session = URLSession(configuration: .ephemeral, delegate: NoQuotaRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, response.expectedContentLength <= 32768 else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 32768 else { return nil }
                data.append(byte)
            }
            let total: Int64?
            let used: Int64?
            if google {
                let quota = try JSONDecoder().decode(GoogleResponse.self, from: data).storageQuota
                total = Int64(quota.limit ?? "")
                used = Int64(quota.usage ?? "")
            } else {
                let quota = try JSONDecoder().decode(MicrosoftResponse.self, from: data).quota
                total = quota?.total
                used = quota?.used
            }
            guard let total, let used, total > 0, used >= 0 else { return nil }
            return CloudQuota(total: total, used: used)
        } catch { return nil }
    }
}

struct GalleryStorageSummary: View {
    let cloud: Bool
    @State private var local: StorageTotals?
    @StateObject private var google = GoogleStorageQuota()
    @State private var confirmAccess = false
    @State private var showDetails = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cloud ? "Armazenamento Google" : "Armazenamento do iPhone").font(.subheadline.weight(.semibold))
                Spacer()
                if let totals = cloud ? google.totals : local {
                    Text("\(cloud ? "" : "≈ ")\(format(totals.used)) de \(format(totals.total)) usados")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let totals = cloud ? google.totals : local {
                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        Rectangle().fill(cloud ? Color.blue : Color.green)
                            .frame(width: geometry.size.width * totals.primaryFraction)
                        Rectangle().fill(cloud ? Color.teal : Color.mint)
                            .frame(width: geometry.size.width * totals.otherFraction)
                        Spacer(minLength: 0)
                    }.background(.secondary.opacity(0.22), in: Capsule()).clipShape(Capsule())
                }.frame(height: 8)
                HStack(spacing: 12) {
                    legend(cloud ? "Google Drive" : "Momentra (aprox.)", color: cloud ? .blue : .green, bytes: totals.primary)
                    legend(cloud ? "Outros serviços" : "Outros dados", color: cloud ? .teal : .mint, bytes: totals.other)
                }
                HStack {
                    Text("\(format(max(0, totals.total - totals.used))) disponíveis")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Gerenciar") { showDetails = true }.font(.caption)
                }
            } else if cloud {
                if google.loading { ProgressView().controlSize(.small) }
                else if google.hasScope {
                    Text(google.message ?? "Espaço da conta indisponível no momento.").font(.caption).foregroundStyle(.secondary)
                    Button("Atualizar armazenamento") { google.refresh() }.font(.caption)
                } else {
                    Text(google.message ?? "Consulte o espaço compartilhado da sua conta Google.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Mostrar armazenamento Google") { confirmAccess = true }.font(.caption)
                }
            } else {
                Text("Espaço indisponível no momento.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .task(id: cloud) {
            if cloud { google.refresh() } else { await refreshLocal() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if cloud { google.refresh() } else { Task { await refreshLocal() } }
            }
        }
        .sheet(isPresented: $showDetails) {
            if let totals = cloud ? google.totals : local { StorageDetailView(totals: totals, cloud: cloud) }
        }
        .confirmationDialog("Para mostrar o espaço disponível, o Momentra consultará o armazenamento compartilhado da conta Google usando acesso limitado aos dados do aplicativo no Google Drive.", isPresented: $confirmAccess, titleVisibility: .visible) {
            Button("Continuar") { google.requestAccess() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func refreshLocal() async {
        local = await Task.detached(priority: .utility) { StorageTotals.local() }.value
    }

    private func format(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
    private func legend(_ title: String, color: Color, bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) \(format(bytes))").lineLimit(1)
        }.font(.caption2).foregroundStyle(.secondary)
    }
}

struct StorageTotals {
    let total: Int64
    let used: Int64
    let primary: Int64
    var other: Int64 { max(0, used - primary) }
    var primaryFraction: CGFloat { CGFloat(Double(primary) / Double(total)) }
    var otherFraction: CGFloat { CGFloat(Double(other) / Double(total)) }

    init?(total: Int64, used: Int64, primary: Int64) {
        guard total > 0, used >= 0, used <= total, primary >= 0, primary <= used else { return nil }
        self.total = total; self.used = used; self.primary = primary
    }

    static func local() -> StorageTotals? {
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        guard let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage,
              total > 0, free >= 0, free <= Int64(total) else { return nil }
        let used = Int64(total) - free
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey]
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [])
        var appBytes: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            guard let info = try? url.resourceValues(forKeys: keys) else { continue }
            if info.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
            if info.isRegularFile == true { appBytes += Int64(info.fileAllocatedSize ?? 0) }
        }
        return StorageTotals(total: Int64(total), used: used, primary: min(used, max(0, appBytes)))
    }
}

private final class NoQuotaRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
private final class GoogleStorageQuota: ObservableObject {
    private static let scope = "https://www.googleapis.com/auth/drive.appdata"
    @Published var totals: StorageTotals?
    @Published var loading = false
    @Published var message: String?
    var hasScope: Bool { GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(Self.scope) == true }

    func requestAccess() {
        guard !loading, let user = GIDSignIn.sharedInstance.currentUser, let owner = user.userID,
              let controller = Self.presentingController() else {
            message = "Conecte a conta Google para consultar o armazenamento."
            return
        }
        loading = true
        Task {
            do {
                let result = try await user.addScopes([Self.scope], presenting: controller)
                guard result.user.userID == owner,
                      GIDSignIn.sharedInstance.currentUser?.userID == owner,
                      result.user.grantedScopes?.contains(Self.scope) == true else { throw URLError(.userAuthenticationRequired) }
                loading = false
                refresh()
            } catch {
                loading = false; totals = nil
                message = "Não foi possível autorizar a consulta."
            }
        }
    }

    func refresh() {
        guard !loading, hasScope, let user = GIDSignIn.sharedInstance.currentUser,
              let owner = user.userID else { totals = nil; return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let refreshed = try await user.refreshTokensIfNeeded()
                guard refreshed.userID == owner, GIDSignIn.sharedInstance.currentUser?.userID == owner,
                      let url = URL(string: "https://www.googleapis.com/drive/v3/about?fields=storageQuota(limit,usage,usageInDrive)") else {
                    throw URLError(.userAuthenticationRequired)
                }
                var request = URLRequest(url: url)
                request.setValue("Bearer " + refreshed.accessToken.tokenString, forHTTPHeaderField: "Authorization")
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 15
                let session = URLSession(configuration: config, delegate: NoQuotaRedirect(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      response.expectedContentLength <= 32768 else { throw URLError(.badServerResponse) }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 32768 else { throw URLError(.dataLengthExceedsMaximum) }
                    data.append(byte)
                }
                guard GIDSignIn.sharedInstance.currentUser?.userID == owner else { throw URLError(.userAuthenticationRequired) }
                let result = try JSONDecoder().decode(Response.self, from: data).storageQuota
                guard let total = Int64(result.limit ?? ""), let used = Int64(result.usage ?? ""),
                      let drive = Int64(result.usageInDrive ?? ""),
                      let value = StorageTotals(total: total, used: used, primary: drive) else {
                    throw URLError(.cannotParseResponse)
                }
                totals = value; message = nil
            } catch {
                totals = nil
                message = "Não foi possível consultar o espaço. Verifique a conexão e a autorização."
            }
        }
    }

    private struct Response: Decodable {
        struct Quota: Decodable { let limit: String?; let usage: String?; let usageInDrive: String? }
        let storageQuota: Quota
    }

    private static func presentingController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

private struct StorageDetailView: View {
    let totals: StorageTotals
    let cloud: Bool
    @Environment(\.dismiss) private var dismiss

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: cloud ? "cloud.fill" : "iphone")
                        .font(.system(size: 72)).foregroundStyle(cloud ? .blue : .green)
                        .padding(.top, 24)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Armazenamento")
                            Spacer()
                            Text("\(cloud ? "" : "≈ ")\(format(totals.used)) usados de \(format(totals.total))")
                                .foregroundStyle(.secondary)
                        }.font(.subheadline)
                        GeometryReader { proxy in
                            HStack(spacing: 1) {
                                Rectangle().fill(cloud ? Color.blue : Color.green).frame(width: proxy.size.width * totals.primaryFraction)
                                Rectangle().fill(cloud ? Color.teal : Color.mint).frame(width: proxy.size.width * totals.otherFraction)
                                Spacer(minLength: 0)
                            }.background(.secondary.opacity(0.22), in: Capsule()).clipShape(Capsule())
                        }.frame(height: 10)
                        Text("\(format(max(0, totals.total - totals.used))) disponíveis")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 0) {
                        row(cloud ? "Google Drive" : "Momentra (aproximado)", value: format(totals.primary),
                            symbol: cloud ? "folder.fill" : "camera.fill", color: cloud ? .blue : .green)
                        Divider().padding(.leading, 52)
                        row(cloud ? "Outros serviços" : "Outros dados", value: format(totals.other),
                            symbol: cloud ? "cloud.fill" : "square.stack.fill", color: cloud ? .teal : .mint)
                    }.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    Text(cloud ? "Outros serviços incluem o Google Fotos e o Gmail; a API não informa cada parcela separadamente." :
                         "Os números do iPhone são aproximados e podem incluir espaço que o sistema consegue recuperar.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding()
            }
            .navigationTitle("Gerenciar armazenamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluído") { dismiss() } } }
        }
    }
    private func row(_ title: String, value: String, symbol: String, color: Color) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 32)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }.padding()
    }
}
