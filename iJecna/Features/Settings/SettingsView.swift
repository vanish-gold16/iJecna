import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(StudyTaskStore.self) private var tasks
    @State private var showsSignOutConfirmation = false
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingReminders = 0

    var body: some View {
        @Bindable var settings = model.settings

        Form {
            taskNotificationsSection

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
                    .onChange(of: settings.quietHoursEnabled) { _, newValue in
                        // Změna se musí propsat do už naplánovaných upozornění.
                        tasks.setQuietHours(newValue)
                        Task { pendingReminders = await tasks.pendingNotificationCount() }
                    }
            } footer: {
                Text("Upozornění, které by přišlo mezi 21:00 a 7:00, se odloží na ráno.")
            }

            substitutionSection

            Section("Známky") {
                Picker("Řazení předmětů", selection: $settings.subjectSorting) {
                    ForEach(AppSettings.SubjectSorting.allCases) { sorting in
                        Text(sorting.title).tag(sorting)
                    }
                }
                Toggle("Počítat „N“ do průměru", isOn: $settings.showNSymbolInAverages)
            }

            if model.isUsingMockData {
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
                Text("Nástroje pro zkoušení stavů obrazovek. Ukazují se jen když aplikace běží na maketě.")
            }
            }

            Section {
                Button("Odhlásit se", role: .destructive) {
                    showsSignOutConfirmation = true
                }
            }
        }
        .navigationTitle("Nastavení")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            authorizationStatus = await tasks.notificationAuthorizationStatus()
            pendingReminders = await tasks.pendingNotificationCount()
        }
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

extension SettingsView {

    /// Mimořádný rozvrh nechodí ze školního webu, proto vlastní oddíl
    /// s vysvětlením, odkud se data berou, a s možností poskytovatele změnit.
    @ViewBuilder
    fileprivate var substitutionSection: some View {
        @Bindable var settings = model.settings

        Section {
            Toggle("Zobrazovat mimořádný rozvrh", isOn: $settings.substitutionsEnabled)
                .onChange(of: settings.substitutionsEnabled) { _, _ in
                    Task { await model.loadSubstitutions(force: true) }
                }

            if settings.substitutionsEnabled {
                if let schedule = model.substitutions.value {
                    LabeledContent("Aktualizováno", value: schedule.status.lastUpdated)
                } else if let error = model.substitutions.error {
                    Text(error.errorDescription ?? "Nedostupné")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                TextField("Vlastní adresa služby", text: $settings.substitutionProvider)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit {
                        Task { await model.loadSubstitutions(force: true) }
                    }
            }
        } header: {
            Text("Mimořádný rozvrh")
        } footer: {
            Text("""
            Suplování škola nevede na svém webu, ale v tabulce na SharePointu \
            za přihlášením Microsoftem, kam se aplikace nedostane. Data proto \
            pocházejí z veřejné služby, která tu tabulku převádí na data — \
            není to server školy. Adresu jde přepsat na vlastní. O tobě se \
            neodesílá nic: stáhne se celá tabulka a tvoje třída se vybírá \
            až v telefonu.
            """)
        }
    }

    /// Stav systémového oprávnění a přehled naplánovaných upozornění na úkoly.
    /// Úkoly jsou lokální, takže se tady dá spolehlivě ukázat i počet.
    @ViewBuilder
    fileprivate var taskNotificationsSection: some View {
        Section {
            switch authorizationStatus {
            case .notDetermined:
                Button("Povolit upozornění na úkoly") {
                    Task {
                        await tasks.requestNotificationAuthorization()
                        authorizationStatus = await tasks.notificationAuthorizationStatus()
                        pendingReminders = await tasks.pendingNotificationCount()
                    }
                }
            case .denied:
                LabeledContent("Upozornění") {
                    Text("Zakázáno").foregroundStyle(.red)
                }
                Button("Otevřít nastavení systému") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            default:
                LabeledContent("Upozornění") {
                    Text("Povoleno").foregroundStyle(.green)
                }
                LabeledContent("Naplánováno", value: "\(pendingReminders)")
            }

            if let error = tasks.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Úkoly a testy")
        } footer: {
            Text("Termíny úkolů a testů si vedeš sám, škola je nikde nezveřejňuje. Data zůstávají na tomhle zařízení.")
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
