import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showsSignOutConfirmation = false

    var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section {
                Toggle("Nové známky", isOn: $settings.notifyOnNewGrade)
                Toggle("Poznámky a pochvaly", isOn: $settings.notifyOnNewNotification)
                Toggle("Změny v rozvrhu", isOn: $settings.notifyOnTimetableChange)
                Toggle("Školní aktuality", isOn: $settings.notifyOnNews)
            } header: {
                Text("Upozornění")
            } footer: {
                Text("Upozornění vznikají přímo na telefonu — aplikace si na pozadí stáhne stránku se známkami a porovná ji s tím, co už jsi viděl. Heslo tak nikam neodchází, ale systém si sám rozhoduje, kdy aplikaci na pozadí spustí. Zpoždění desítek minut je normální.")
            }

            Section {
                Toggle("Obnovovat na pozadí", isOn: $settings.backgroundRefreshEnabled)
                Toggle("Neupozorňovat v noci", isOn: $settings.quietHoursEnabled)
            } footer: {
                Text("V nočních hodinách se upozornění odloží na ráno.")
            }

            Section("Známky") {
                Picker("Řazení předmětů", selection: $settings.subjectSorting) {
                    ForEach(AppSettings.SubjectSorting.allCases) { sorting in
                        Text(sorting.title).tag(sorting)
                    }
                }
                Toggle("Počítat „N“ do průměru", isOn: $settings.showNSymbolInAverages)
            }

            Section {
                Picker("Simulovaná chyba", selection: $settings.simulatedFailure) {
                    ForEach(MockJecnaService.FailureMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .onChange(of: settings.simulatedFailure) { _, newValue in
                    Task {
                        if let mock = model.service as? MockJecnaService {
                            await mock.setFailureMode(newValue)
                        }
                    }
                }

                Button("Označit známky jako nepřečtené") {
                    if let page = model.grades.value {
                        model.newGrades.simulateNewGrades(from: page)
                        Haptics.impact()
                    }
                }

                Button("Znovu načíst všechno") {
                    Task { await model.refreshDashboard() }
                }
            } header: {
                Text("Maketa")
            } footer: {
                Text("Nástroje pro zkoušení stavů obrazovek. V ostré verzi tato sekce nebude.")
            }

            Section {
                Button("Odhlásit se", role: .destructive) {
                    showsSignOutConfirmation = true
                }
            }
        }
        .navigationTitle("Nastavení")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Opravdu se chceš odhlásit?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Odhlásit se", role: .destructive) {
                Task { await model.signOut() }
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Stažená data se z telefonu smažou.")
        }
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                    Text("iJečná")
                        .font(.title2.weight(.bold))
                    Text("Verze 0.1 — maketa")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                Text("Neoficiální aplikace pro studenty SPŠE Ječná. Není provozována, schválena ani nijak spojena se školou.")
                    .font(.footnote)
            } header: {
                Text("Upozornění")
            }

            Section {
                Text("Aplikace čte veřejné i přihlášené stránky webu spsejecna.cz a zobrazuje je v nativním rozhraní. Žádná data neodesílá na servery třetích stran.")
                    .font(.footnote)
                Text("Přihlašovací údaje jsou uloženy v systémové Klíčence, pouze na tomto zařízení, bez zálohy na iCloud.")
                    .font(.footnote)
            } header: {
                Text("Data a soukromí")
            }

            Section {
                Link("JecnaAPI (jzitnik-dev / tomhula)", destination: URL(string: "https://github.com/jzitnik-dev/JecnaAPI")!)
                Link("Web školy", destination: URL(string: "https://www.spsejecna.cz")!)
            } header: {
                Text("Zdroje")
            } footer: {
                Text("Struktura dat vychází z otevřené knihovny JecnaAPI, která popisuje, jak školní web funguje.")
            }
        }
        .navigationTitle("O aplikaci")
        .navigationBarTitleDisplayMode(.inline)
    }
}
