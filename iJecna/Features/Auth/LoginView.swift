import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    @State private var username = MockJecnaService.demoUsername
    @State private var password = MockJecnaService.demoPassword
    @State private var isPasswordVisible = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    private var isSigningIn: Bool { model.session == .signingIn }
    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSigningIn
    }

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    form
                    disclaimer
                }
                .padding(.horizontal, 22)
                .padding(.top, 60)
                .padding(.bottom, 40)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 92, height: 92)
                .glassEffect(.regular.tint(Theme.accent.opacity(0.22)), in: .rect(cornerRadius: 26, style: .continuous))

            VStack(spacing: 6) {
                Text("iJečná")
                    .font(.largeTitle.weight(.bold))
                Text("Neoficiální aplikace pro studenty SPŠE Ječná")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var form: some View {
        GlassCard {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Uživatelské jméno", systemImage: "person")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("novak", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }
                        .padding(12)
                        .background(.background.secondary, in: Theme.compactShape)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Heslo", systemImage: "lock")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    HStack {
                        Group {
                            if isPasswordVisible {
                                TextField("Heslo", text: $password)
                            } else {
                                SecureField("Heslo", text: $password)
                            }
                        }
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focusedField, equals: .password)
                        .onSubmit { submit() }

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isPasswordVisible ? "Skrýt heslo" : "Zobrazit heslo")
                    }
                    .padding(12)
                    .background(.background.secondary, in: Theme.compactShape)
                }

                if let error = model.signInError {
                    Label(error.errorDescription ?? "Přihlášení selhalo", systemImage: error.symbolName)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Button(action: submit) {
                    HStack(spacing: 8) {
                        if isSigningIn {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text(isSigningIn ? "Přihlašuji…" : "Přihlásit se")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .disabled(!canSubmit)
            }
        }
        .animation(.smooth, value: model.signInError)
    }

    private var disclaimer: some View {
        VStack(spacing: 10) {
            Label {
                Text("Heslo se ukládá jen do Klíčenky na tomhle zařízení a nikam se neodesílá.")
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)

            Text("Aplikace není provozována ani schválena SPŠE Ječná.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("Maketa — přihlaš se jako \(MockJecnaService.demoUsername) / \(MockJecnaService.demoPassword)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task { await model.signIn(username: username, password: password) }
    }
}

#Preview {
    LoginView()
        .environment(AppModel(service: MockJecnaService()))
}
