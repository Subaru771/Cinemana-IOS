// CINEMANA_ACCOUNT_HANDOFF_V08
// Independent SideStore (AGPL-3.0) opt-in, one-use, end-to-end encrypted USB handoff.
// Source is intentionally integrated into SideStore's existing Settings target.
// Never saves an Apple password, emits authentication logs, or uses our servers.
#if !os(tvOS)
import Foundation
import CryptoKit
import CoreData
import SwiftUI
import SideSign

@MainActor
final class CinemanaHandoffState: ObservableObject {
    static let shared = CinemanaHandoffState()
    @Published var waiting = false
    @Published var working = false
    @Published var status = "Not started"
    @Published var success = false
    private var key: Curve25519.KeyAgreement.PrivateKey?
    private var request: Request?
    private var generation = UUID()

    private let maxLifetime: TimeInterval = 300
    private let info = Data("cinemana.sidestore.handoff.v1".utf8)
    private var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CinemanaHandoff", isDirectory: true)
    }
    struct Request: Codable {
        let version: Int
        let id: String
        let publicKey: String
        let salt: String
        let expires: Double
    }
    struct Response: Codable {
        let version: Int
        let id: String
        let ephemeralPublicKey: String
        let iv: String
        let ciphertext: String
        let tag: String
    }
    struct Credentials: Codable {
        let email: String
        let adsid: String
        let xcodeToken: String
        let createdAt: Double
    }
    private enum TransferError: LocalizedError {
        case invalidRequest, expired, wrongChallenge, malformed, invalidSession, multipleTeams
        var errorDescription: String? {
            switch self {
            case .invalidRequest: return "The transfer request is invalid. Restart account transfer."
            case .expired: return "The transfer timed out. Tap Try again."
            case .wrongChallenge: return "Account data was sent for another request."
            case .malformed: return "Encrypted account data is invalid."
            case .invalidSession: return "Apple rejected this imported session. Sign in normally in SideStore."
            case .multipleTeams: return "This Apple Account has multiple developer teams. Sign in normally to choose the correct one."
            }
        }
    }

    func begin() {
        cancel()
        do {
            let priv = Curve25519.KeyAgreement.PrivateKey()
            let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            let req = Request(version: 1, id: UUID().uuidString,
                publicKey: priv.publicKey.rawRepresentation.base64EncodedString(),
                salt: salt.base64EncodedString(),
                expires: Date().addingTimeInterval(maxLifetime).timeIntervalSince1970)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // The request contains no secrets; the private key is never written to disk.
            try JSONEncoder().encode(req).write(to: folder.appendingPathComponent("request.json"), options: .atomic)
            key = priv
            request = req
            waiting = true
            status = "Ready. In Cinemana iLoader, choose Transfer account to SideStore."
            let stamp = generation
            Task { [weak self] in await self?.receiveUntilDeadline(stamp) }
        } catch {
            status = "Could not prepare transfer: \(error.localizedDescription)"
        }
    }

    func cancel() {
        generation = UUID()
        waiting = false
        working = false
        key = nil
        request = nil
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("request.json"))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("response.json"))
    }

    private func receiveUntilDeadline(_ stamp: UUID) async {
        while stamp == generation, let req = request,
              Date().timeIntervalSince1970 < req.expires {
            let responseURL = folder.appendingPathComponent("response.json")
            if FileManager.default.fileExists(atPath: responseURL.path) {
                working = true
                waiting = false
                do {
                    let data = try Data(contentsOf: responseURL)
                    let value = try decode(data)
                    try await activate(value)
                    success = true
                    status = "Account connected. Open My Apps and refresh SideStore."
                } catch {
                    status = "Transfer failed: \(error.localizedDescription) Use normal sign-in if needed."
                }
                // Delete sensitive ciphertext and the public request after a single attempt.
                cancel()
                return
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
        if stamp == generation {
            cancel()
            status = "Request expired. Tap Try again."
        }
    }

    private func decode(_ data: Data) throws -> Credentials {
        guard let req = request, let privateKey = key,
              Date().timeIntervalSince1970 < req.expires else { throw TransferError.expired }
        guard data.count < 32_768 else { throw TransferError.malformed }
        let packet = try JSONDecoder().decode(Response.self, from: data)
        guard packet.version == 1, packet.id == req.id else { throw TransferError.wrongChallenge }
        guard let peerBytes = Data(base64Encoded: packet.ephemeralPublicKey), peerBytes.count == 32,
              let iv = Data(base64Encoded: packet.iv), iv.count == 12,
              let encrypted = Data(base64Encoded: packet.ciphertext), encrypted.count < 16384,
              let tag = Data(base64Encoded: packet.tag), tag.count == 16,
              let salt = Data(base64Encoded: req.salt), salt.count == 32 else {
            throw TransferError.malformed
        }
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerBytes)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let symmetricKey = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
            sharedInfo: info, outputByteCount: 32)
        let sealed = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv),
            ciphertext: encrypted, tag: tag)
        let plain = try AES.GCM.open(sealed, using: symmetricKey)
        let credentials = try JSONDecoder().decode(Credentials.self, from: plain)
        guard Date().timeIntervalSince1970 - credentials.createdAt < maxLifetime,
              credentials.createdAt < Date().timeIntervalSince1970 + 30,
              credentials.email.contains("@"), credentials.email.count < 256,
              !credentials.adsid.isEmpty, credentials.adsid.count < 128,
              !credentials.xcodeToken.isEmpty, credentials.xcodeToken.count < 8192 else {
            throw TransferError.invalidRequest
        }
        return credentials
    }

    private func activate(_ creds: Credentials) async throws {
        // Validate against Apple first; do not alter existing Keychain or DB state on failure.
        let anisette = try await AnisetteProvider.fetch()
        let xcodeVersion = await AnisetteConfigManager.shared.resolvedXcodeVersion()
        let session = ALTAppleAPISession(dsid: creds.adsid, authToken: creds.xcodeToken,
            anisetteData: anisette, xcodeVersion: xcodeVersion)
        let account = try await ALTAppleAPI.shared.fetchAccount(session: session)
        let teams = try await ALTAppleAPI.shared.fetchTeams(for: account, session: session)
        guard teams.count == 1 else {
            if teams.isEmpty { throw TransferError.invalidSession }
            throw TransferError.multipleTeams
        }
        let altTeam = teams[0]
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        try await context.perform {
            let accountID = altTeam.account?.identifier ?? altTeam.identifier
            let storedAccount: Account
            if let existing = Account.first(satisfying: NSPredicate(format: "%K == %@",
                #keyPath(Account.identifier), accountID), in: context) {
                storedAccount = existing
            } else if let linked = altTeam.account {
                storedAccount = Account(linked, context: context)
            } else {
                storedAccount = Account(ALTAccount(appleID: creds.email, identifier: accountID), context: context)
            }
            if let linked = altTeam.account { storedAccount.update(account: linked) }
            storedAccount.appleID = creds.email
            let storedTeam: Team
            if let existing = Team.first(satisfying: NSPredicate(format: "%K == %@",
                #keyPath(Team.identifier), altTeam.identifier), in: context) {
                storedTeam = existing
            } else {
                storedTeam = Team(altTeam, account: storedAccount, context: context)
            }
            storedTeam.update(team: altTeam)
            storedAccount.isActiveAccount = true
            storedTeam.isActiveTeam = true
            let otherAccounts = Account.fetchRequest() as NSFetchRequest<Account>
            otherAccounts.predicate = NSPredicate(format: "%K != %@", #keyPath(Account.identifier), storedAccount.identifier)
            for item in try context.fetch(otherAccounts) { item.isActiveAccount = false }
            let otherTeams = Team.fetchRequest() as NSFetchRequest<Team>
            otherTeams.predicate = NSPredicate(format: "%K != %@", #keyPath(Team.identifier), storedTeam.identifier)
            for item in try context.fetch(otherTeams) { item.isActiveTeam = false }
            try context.save()
        }
        AuthManager.shared.currentAppleID = creds.email
        AuthManager.shared.adsid = creds.adsid
        AuthManager.shared.xcodeToken = creds.xcodeToken
        // Password intentionally stays unset. Apple may expire the imported token.
    }
}

private struct CinemanaHandoffView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model = CinemanaHandoffState.shared
    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Image(systemName: "lock.iphone")
                    .font(.system(size: 49)).foregroundColor(.accentColor)
                Text("Connect your iLoader account")
                    .font(.title3.weight(.bold))
                Text("1. Connect your iPhone to your Windows PC by USB.\n2. Sign in to Cinemana iLoader.\n3. Tap Start transfer here, then Transfer account in iLoader.\n4. Keep this screen open until confirmed.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.status).font(.footnote).foregroundColor(.secondary)
                if model.working { ProgressView() }
                if model.success {
                    Label("Verified by Apple", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)
                } else if model.waiting {
                    ProgressView()
                    SwiftUI.Button("Cancel transfer") { model.cancel() }
                } else {
                    SwiftUI.Button("Start secure USB transfer") { model.begin() }
                        .buttonStyle(.borderedProminent)
                }
                Text("No password is transferred. Encrypted handoff expires after 5 minutes. Only use with a trusted computer. If Apple rejects the session, sign in normally.")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(20)
            .navigationTitle("iLoader account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    SwiftUI.Button("Done") { model.cancel(); dismiss() }
                }
            }
        }
    }
}
#endif
