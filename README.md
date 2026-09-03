# iJečná

Neoficiální iOS aplikace pro studenty [SPŠE Ječná](https://www.spsejecna.cz).
Známky, rozvrh, školní adresář — a vlastní úkoly a termíny testů, které škola nikde nevede.

> **Upozornění:** aplikace není provozována, schválena ani nijak spojena se SPŠE Ječná.

## Stav

Aplikace čte **skutečná data** ze `spsejecna.cz`: známky, rozvrh, aktuality,
učitelský sbor a sdělení rodičům. Profil učitele, seznam učeben a skříňka
zatím načíst neumí — k těm stránkám nemáme uloženou předlohu, podle které
by šel parser ověřit, a hádat obsah je horší než ho neukázat.

Úkoly a termíny testů jsou lokální data na zařízení, se školním webem nesouvisí.

Maketa zůstává k dispozici pro práci na vzhledu bez připojení:

```sh
SIMCTL_CHILD_USE_MOCK=1 xcrun simctl launch booted mytrofanov.iJecna
```

- Cíl: **iOS 26+** (Liquid Glass API bez záložních cest)
- Jazyk rozhraní: čeština (angličtina přibude přes katalog řetězců)
- Přihlášení do makety: `novotny` / `jecna`

## Obrazovky

| Záložka | Obsah |
|---|---|
| **Dnes** | probíhající nebo nejbližší hodina s postupem bloku, nové známky, úkoly a testy, dnešní rozvrh, prospěch |
| **Známky** | vážený průměr, rozložení známek, předměty, detail s částmi (Teorie / Cvičení) a predikcí „co když dostanu…“ |
| **Rozvrh** | denní seznam i týdenní mřížka, dělené skupiny, vícehodinové bloky, detail hodiny |
| **Úkoly** | vlastní úkoly, testy a projekty s lokálními upozorněními |
| **Více** | aktuality, učitelé, učebny, profil, skříňka, poznámky a pochvaly, nastavení |

## Architektura

```
iJecna/
├─ Core/
│  ├─ Models/         doménové typy (kopírují strukturu JecnaAPI)
│  ├─ Services/       JecnaService (protokol) + maketa; StudyTaskStore; NotificationScheduler
│  ├─ State/          AppModel, LoadState, NewGradesTracker
│  └─ DesignSystem/   Theme, sklo, odznaky známek
└─ Features/          Dashboard, Grades, Timetable, Tasks, Directory, Profile, Settings, Auth
```

Veškerý přístup ke školním datům vede přes protokol `JecnaService`. Existují
dvě implementace — `WebJecnaService` nad skutečným webem a `MockJecnaService`
pro maketu — a obrazovky mezi nimi nepoznají rozdíl.

### Úkoly a testy

Škola termíny úkolů ani písemek nezveřejňuje, takže si je student vede sám:

- ukládají se do JSON souboru v Application Support, jen na daném zařízení
- upozornění plánuje `UNUserNotificationCenter` (funguje offline, čas je znám dopředu)
- přednastavené časy: večer předem, ráno v den, hodinu před vyučováním, tři dny předem, vlastní
- volitelné tiché hodiny posunou noční upozornění na ráno
- úkol lze založit z hodiny v rozvrhu — datum i předmět se předvyplní

## Poznámky ke školnímu webu

Podklady vycházejí z knihovny [JecnaAPI](https://github.com/tomhula/JecnaAPI) (GPLv3),
která popisuje, jak `spsejecna.cz` funguje. **Není to REST API — je to HTML.**

Přihlášení:

1. cookie `WTDGUID=10` (role student), `GET /`
2. CSRF token z `#loginForm input[name=token3]`
3. `POST /user/login` — `user`, `pass`, `token3` (form-urlencoded)
4. úspěch = **302 s `Location: /`**; špatné heslo = **200** se stránkou login-problem
5. relace drží cookie `JSESSIONID`; její vypršení se pozná podle 302 na `/user/need-login`

Klient nesmí následovat přesměrování, jinak úspěch od selhání nerozliší.

Stránky (všechny vracejí HTML):

| Cesta | Obsah |
|---|---|
| `/score/student?schoolYearId=N&schoolYearHalfId=21\|22` | známky |
| `/timetable/class?schoolYearId=N&timetableId=M` | rozvrh |
| `/absence/passing-student?schoolYearId=N&schoolYearPartMonthId=1..12` | příchody a odchody |
| `/absence/student?schoolYearId=N` | absence a omluvný list |
| `/akce` | aktuality |
| `/ucitel`, `/ucitel/{tag}` | učitelé |
| `/ucebna`, `/ucebna/{code}` | učebny |
| `/student/{username}`, `/locker/student` | profil, skříňka |
| `/user-student/record-list`, `/user-student/record?userStudentRecordId=N` | poznámky a pochvaly |
| `/certification/student` | výuční listy (jen 4. ročník) |

`schoolYearId = prvníKalendářníRok − 2008`. Pololetí: `21` první, `22` druhé.
Jídelna je samostatný systém (`strav.nasejidelna.cz`, kód `0341`) s vlastním přihlášením.

### Chování serveru, na které se naráží

**User-Agent nesmí obsahovat „jecna“.** Server odpovídá `403` na každého
klienta, který má jméno školy v označení — ověřeno proti webu:

| User-Agent | Odpověď |
|---|---|
| `curl/8.x` | 200 |
| `JAPI` | 200 |
| prohlížeč | 200 |
| `iJecna/0.1` | **403** |
| `MyApp/0.1` | 200 |

Není to plošná obrana proti automatizaci, jen úzké pravidlo na ten řetězec.
Klient se proto hlásí jako `iJ/0.1 (unofficial student client; …)` — pravdivě,
jen bez jména školy. Hlídá to zkouška `testUserAgentAvoidsBlockedWord`.

**Role musí do cookies dřív než první požadavek.** Bez `WTDGUID=10` server
vrátí stránku pro zájemce, na které přihlašovací formulář vůbec není, a přihlášení
skončí na „chybí token3“. Vlastní `HTTPCookieStorage()` se pro to nedá použít —
relace ho nepoužije a cookie neodejde.

**`robots.txt`** uvádí `Crawl-delay: 5` a zakazuje `/dokumenty`, `/download`,
`/icon`, `/lib`. Stránky, které čteme, zakázané nejsou. Rozestup mezi požadavky
je půl sekundy, když u telefonu čeká uživatel, a celých pět sekund pro
automatickou kontrolu na pozadí, kdy se aplikace chová jako robot. Přílohy
z `/download` se nikdy nestahují dopředu — jen když na ně někdo klepne.

### Na co si dát pozor

- **Licence.** JecnaAPI je GPLv3; její přilinkování by nakazilo celou aplikaci.
  Plán je vlastní parser ve Swiftu nad SwiftSoup (MIT) podle protokolu výše.
- **Upozornění na nové známky.** iOS neumí spolehlivě dotazovat web na pozadí.
  `BGAppRefreshTask` běží podle uvážení systému; zpoždění desítek minut je normální.
  Okamžité doručení by vyžadovalo server, který drží školní hesla studentů.
- **Křehkost parseru.** Změna šablony školního webu rozbije parsování.
  Nutné jsou snímkové testy nad uloženým HTML a měkký pád na částečná data.
- **Soukromí.** Heslo patří výhradně do Klíčenky (`ThisDeviceOnly`, bez zálohy na iCloud).
- **Časová zóna.** Škola žije v `Europe/Prague` bez ohledu na nastavení telefonu.

## Vývoj

```sh
open iJecna.xcodeproj      # ⌘R, iPhone 17 Pro
```

V **Nastavení → Maketa** jde zapnout simulovanou chybu (výpadek sítě, vypršelá
relace, rozbitý parser, pomalá odezva) a projít si tak všechny stavy obrazovek.

### Testy a snímky

`iJecnaUITests/ScreenshotTests` slouží zároveň jako kouřová zkouška navigace
a jako zdroj snímků obrazovek:

```sh
xcodebuild test -project iJecna.xcodeproj -scheme iJecna \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:iJecnaUITests/ScreenshotTests \
  -resultBundlePath /tmp/shots.xcresult

xcrun xcresulttool export attachments \
  --path /tmp/shots.xcresult --output-path /tmp/shots
```

### Zkoušky proti živému webu

Standardně se přeskakují. Nepotřebují heslo — ověřují jen to, co jde zjistit
bez účtu: že server našeho klienta pustí, že najdeme CSRF token a že chráněná
stránka nepřihlášeného odmítne přesně tak, jak klient čeká.

```sh
TEST_RUNNER_RUN_LIVE_TESTS=1 xcodebuild test -project iJecna.xcodeproj -scheme iJecna \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:iJecnaTests/LiveTransportTests
```

Aplikaci lze spustit rovnou na konkrétní záložce:

```sh
SIMCTL_CHILD_INITIAL_TAB=grades xcrun simctl launch booted mytrofanov.iJecna
```

## Další kroky

- [x] vlastní parser `spsejecna.cz` ve Swiftu (SwiftSoup), Keychain, automatické přihlášení
- [x] snímkové testy parserů nad uloženým HTML
- [ ] profil učitele, učebny a skříňka — chybí uložené předlohy stránek
- [ ] `BGAppRefreshTask` a upozornění na nové známky
- [ ] jídelna, příchody a odchody, absence
- [ ] katalog řetězců s angličtinou
- [ ] widget a Live Activity s aktuální hodinou
