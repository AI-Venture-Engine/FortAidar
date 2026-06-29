import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: PrototypeVaultStore
    @FocusState private var passphraseFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(store: store, passphraseFocused: $passphraseFocused)
                .frame(minHeight: store.authMode == .register && !store.state.isMounted ? 204 : 164)

            Divider()

            HSplitView {
                MainVaultView(store: store)
                    .frame(minWidth: 560)

                ActivityPanel(store: store)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .onChange(of: store.passphraseFieldToken) {
            passphraseFocused = true
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.addItemsWithPicker()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(!store.state.isMounted)

                Button {
                    Task { await store.lock() }
                } label: {
                    Label("Lock", systemImage: "lock.open.fill")
                }
                .disabled(!store.state.isMounted)

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }
}

private struct HeaderBar: View {
    @ObservedObject var store: PrototypeVaultStore
    let passphraseFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Fort Aidar")
                            .font(.title2.weight(.semibold))
                        Text("Private folder. Unlock, add, lock.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(appBuildLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 260, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Picker("Auth mode", selection: $store.authMode) {
                        ForEach(AuthMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(store.state.isMounted || store.state.isWorking)

                    Text("Email")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        TextField("name@example.com", text: $store.ownerContact)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .disabled(store.state.isMounted || store.state.isWorking)

                        Button {
                            store.clearAuthEmailForNewLocalUser()
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.state.isMounted || store.state.isWorking)
                        .help("Use another email / new local vault")
                    }

                    Text(store.ownerSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(store.authContextText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
                .frame(width: 250, alignment: .leading)

                StatusPill(store: store)
                    .frame(width: 200, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    passphraseInput(text: $store.passphrase, prompt: passphrasePrompt, isFocused: true)

                    if shouldShowPasswordConfirmation {
                        passphraseInput(text: $store.passphraseConfirmation, prompt: "Repeat password", isFocused: false)
                    }
                }
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)

                VStack(spacing: 8) {
                    if store.canShowBiometricButton {
                        Button {
                            Task { await store.performBiometricButtonAction() }
                        } label: {
                            Label(store.biometricButtonTitle, systemImage: "touchid")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.canTapBiometricAction)
                    }

                    if store.canRunBiometricAction {
                        Button {
                            Task { await store.performPrimaryVaultAction() }
                        } label: {
                            Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.state.isWorking)
                    } else {
                        Button {
                            Task { await store.performPrimaryVaultAction() }
                        } label: {
                            Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.state.isWorking)
                    }
                }
                .frame(width: 160)

                Button {
                    store.addItemsWithPicker()
                } label: {
                    Label("Add", systemImage: "plus")
                        .frame(width: 86)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.state.isMounted)
            }

            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(store.biometricStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "timer")
                    .foregroundStyle(.secondary)
                Text(store.autoLockStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Text("Vault file:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(store.selectedIdentity.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("FortAidar.sparsebundle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    store.revealVaultFile()
                } label: {
                    Label("Show", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var passphrasePrompt: String {
        switch store.authMode {
        case .register:
            return "New password"
        case .signIn:
            return "Password"
        }
    }

    private var shouldShowPasswordConfirmation: Bool {
        store.authMode == .register && !store.state.isMounted
    }

    private func passphraseInput(text: Binding<String>, prompt: String, isFocused: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if store.isPassphraseVisible {
                    TextField(prompt, text: text)
                } else {
                    SecureField(prompt, text: text)
                }
            }
            .textFieldStyle(.plain)
            .focused(passphraseFocused, equals: isFocused)
            .onSubmit {
                Task { await store.performPrimaryVaultAction() }
            }

            Button {
                store.isPassphraseVisible.toggle()
            } label: {
                Image(systemName: store.isPassphraseVisible ? "eye.slash" : "eye")
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(store.isPassphraseVisible ? "Hide password" : "Show password")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.24))
        }
    }

    private var primaryButtonTitle: String {
        if store.authMode == .register && !store.state.isMounted {
            return store.state.isWorking ? "Working" : "Register"
        }

        switch store.state {
        case .missing:
            return "Sign in"
        case .locked:
            return "Sign in"
        case .error:
            return "Sign in"
        case .unlocked:
            return "Lock"
        case .working:
            return "Working"
        }
    }

    private var primaryButtonIcon: String {
        if store.authMode == .register && !store.state.isMounted {
            return store.state.isWorking ? "hourglass" : "person.badge.plus"
        }

        switch store.state {
        case .missing:
            return "lock.fill"
        case .locked:
            return "lock.fill"
        case .error:
            return "lock.fill"
        case .unlocked:
            return "lock.open.fill"
        case .working:
            return "hourglass"
        }
    }

    private var appBuildLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "preview"
        let build = info["CFBundleVersion"] as? String ?? "dev"
        return "Build \(version) / \(build)"
    }
}

private struct StatusPill: View {
    @ObservedObject var store: PrototypeVaultStore

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: store.stateSymbolName)
                .font(.title3)
                .foregroundStyle(store.stateTint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.state.title)
                    .font(.headline)
                    .lineLimit(1)
                stateDetail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var stateDetail: some View {
        switch store.state {
        case .missing:
            if store.authMode == .register {
                Text(store.hasAuthEmail ? "Ready to create this vault." : "Enter email to register.")
            } else {
                Text(store.hasAuthEmail ? "No local vault. Register first." : "Enter email to sign in.")
            }
        case .locked:
            Text("Ready to sign in.")
        case .unlocked:
            Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s") inside. \(store.autoLockStatusText).")
        case .working(let label):
            Text(label)
        case .error(let message):
            Text(message)
        }
    }
}

private struct MainVaultView: View {
    @ObservedObject var store: PrototypeVaultStore

    var body: some View {
        VStack(spacing: 18) {
            DropZone(store: store)
                .frame(minHeight: 250)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Vault contents")
                        .font(.headline)

                    Spacer()

                    Button {
                        store.revealMountedVault()
                    } label: {
                        Label("Open mounted vault", systemImage: "arrow.up.forward.app")
                    }
                    .disabled(!store.state.isMounted)
                }

                if store.items.isEmpty {
                    ContentUnavailableView(
                        "No files yet",
                        systemImage: "tray",
                        description: Text(store.state.isMounted ? "Click Add or drop documents above." : "Unlock the vault first.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(store.items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.kind == "Folder" ? "folder.fill" : "doc.fill")
                                .foregroundStyle(item.kind == "Folder" ? .blue : .secondary)
                                .frame(width: 22)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .lineLimit(1)
                                Text("\(item.kind) · \(item.sizeDescription)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .padding(22)
    }
}

private struct DropZone: View {
    @ObservedObject var store: PrototypeVaultStore

    var body: some View {
        ZStack {
            VaultDogWebView(bridge: store.vaultDogBridge)
                .opacity(store.state.isMounted ? 1 : 0.72)
                .allowsHitTesting(false)

            VStack {
                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                    Text(store.state.isMounted ? "Add private files" : "Unlock to add private files")
                        .font(.headline.weight(.semibold))

                    Text(store.state.isMounted ? "Click Add or drop files here. VaultDog will guard them." : "Register with a password first. Touch ID works after the password is saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            store.addItemsWithPicker()
                        } label: {
                            Label("Add files or folders", systemImage: "plus")
                                .frame(minWidth: 180)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(!store.state.isMounted)

                        Text("guardian preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(0.72)
                    }
                    .frame(width: 310, alignment: .leading)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 44)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.92))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    store.isDropTargeted ? Color.blue : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
        }
        .onDrop(
            of: [NSPasteboard.PasteboardType.fileURL.rawValue],
            isTargeted: $store.isDropTargeted,
            perform: store.importProviders
        )
    }
}

private struct ActivityPanel: View {
    @ObservedObject var store: PrototypeVaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.headline)

            if store.events.isEmpty {
                ContentUnavailableView(
                    "No activity",
                    systemImage: "clock",
                    description: Text("Vault events will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text(event.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                        Text(event.date, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .padding(18)
        .background(.regularMaterial)
    }
}
