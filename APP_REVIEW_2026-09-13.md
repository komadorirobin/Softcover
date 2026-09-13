# Softcover: prestanda- och UI-granskning

Datum: 2026-09-13. Granskning av den lokala arbetskopian på `main`, inklusive de senaste, ännu ej committade katalogredigeringsändringarna.

## Slutsats

Det finns tydliga förbättringsmöjligheter, men appen behöver inte skrivas om från grunden. De viktigaste problemen är överflödiga nätverksanrop, dyrt arbete när listor beräknas, bristande samordning mellan asynkrona laddningar och inkonsekventa bokdetaljer. Det förklarar mer än modellernas ålder. En app kan använda moderna SwiftUI-komponenter och ändå kännas omständlig.

Min rekommendation är tre avgränsade omgångar: stabilisera laddning och listor, förenkla läsning och bokdetaljer, och därefter förbättra resten av gränssnittet och widgetarnas uppdateringar. Behåll appens identitet, bokomslag, accentfärg och systemets navigation.

## Omfattning och verifiering

- Granskat huvudflikarnas vyer och dataflöden: Läser, Vill läsa, Sök, Utforska och Profil. Även bokdetaljer, utgåveval, katalogredigering, historik, statistik, sociala vyer, listor, frågor/prompts, inställningar, bildhantering och widgetarnas laddning har ingått.
- Kontrollerat byggmedlemskap mot Xcode-projektet och senaste arkivets SwiftFileList. Äldre kopior av exempelvis sök- och metadatavyer i reporoten används inte som underlag för produktionsfynd. `UpcomingReleasesView` kompileras, men jag hittade ingen ingång till den från huvudnavigationen; Utforska använder `CommunityUpcomingView`.
- UI-bedömningen bygger på aktuell kod och skärmbilderna i tråden. Ingen ny fullständig visuell körning av den inloggade appen, VoiceOver-körning eller Instruments-profilering på iPhone har gjorts. Det här är inte ett påstående om uppmätta bildfrekvenser eller batterivinster.
- Kört `sh scripts/test-catalog-editing.sh`: samtliga befintliga katalogkontroller godkända, inklusive format, behörighet, glesa uppdateringar, konflikter, kontobyte och HTTP 429. De testerna täcker inte hela appen.
- Kört ett separat optimerat Foundation-test av datumfiltrering/sortering; resultat och metod nedan.
- Inga produktionsfiler ändrade och ingen ny build publicerad. Endast den här rapporten och ett isolerat mätprogram under `build/` har lagts till i granskningen. Befintliga lokala ändringar har lämnats kvar.

## Prioriterade fynd

P1 = bör åtgärdas först på grund av tydlig påverkan på tillförlitlighet eller respons. P2 = nästa omgång. P3 = underhåll och finputsning. Prioriteringen är min bedömning, inte en mätning av hur ofta varje fel inträffar hos användare.

### 1. P1: Vill läsa kan skapa upp till 100 extra API-anrop

`reload()` hämtar 100 böcker. Därefter skapas en uppgift per bok för att hämta dess medelbetyg, utan samtidighetsbegränsning. Grundfrågan hämtar inte betyget, så detta kan inträffa för hela listan vid en kall laddning. Varje lyckat betygssvar uppdaterar dessutom vyns state separat.

Belägg: [grundfrågan](/Users/robinbolinsson/Softcover/ReadingProgressWidget/HardcoverService.swift:624), [laddning och anropsloopen](/Users/robinbolinsson/Softcover/WantToReadView.swift:466).

Detta är en konkret risk för HTTP 429 även när en enskild annan vy använder få anrop. Hardcover dokumenterar en burst på 10/15 och 60 förfrågningar per minut. Antalet HTTP-anrop är inte hela kostnaden: varje GraphQL-fält på toppnivå räknas och högst fem tillåts per vanlig fråga. [Hardcovers egna API-regler](https://raw.githubusercontent.com/hardcoverapp/hardcover-docs/main/src/content/docs/api/Getting-Started.mdx).

Åtgärd: hämta `book.rating` i samma listfråga, alternativt en enda bokfråga med flera ID:n. Samla resultat innan state uppdateras. Inför gemensam, kontobunden anropssamordning som följer rate-limit-headerfält och `Retry-After`. Att bara lägga till fler parallella uppgifter är inte en optimering här.

Acceptans: en laddning av 100 böcker ska inte ge 100 betygsanrop; samtidig sökning och öppning av redigeraren ska inte skapa en okontrollerad anropsvåg.

### 2. P1: Dyr datumtolkning körs när listans innehåll beräknas

`filteredItems` tolkar datum för filtreringen och sedan båda datumen igen för varje sorteringsjämförelse. Varje tolkning skapar och konfigurerar en ny `DateFormatter`. Detta sker i en beräknad egenskap som används av SwiftUI-vyn, inte bara när serverdata först tas emot. Separata betygsuppdateringar kan utlösa samma arbete igen.

Belägg: [datumtolkning](/Users/robinbolinsson/Softcover/WantToReadView.swift:62), [filtrering och sortering](/Users/robinbolinsson/Softcover/WantToReadView.swift:88), [state-uppdatering per betyg](/Users/robinbolinsson/Softcover/WantToReadView.swift:504).

| Antal böcker | Nuvarande algoritm | Tolka varje datum en gång, inklusive förberedelsen |
| --- | ---: | ---: |
| 100 | 518,17 ms | 5,59 ms |
| 1 000 | 8 122,89 ms | 55,18 ms |

Mätning på Apple M1 Max, `swiftc -O`, median av fem upprepningar efter uppvärmning. Syntetiska, blandade framtida utgivningsdatum; alla poster passerar filtret. Samma bokordning kontrollerades i båda varianterna. Testet isolerar algoritmen från SwiftUI, nätverk och bilder. 100 motsvarar nuvarande listtak; 1 000 visar skalning inför riktig paginering. Resultaten är inte iPhone-tider eller en utlovad total hastighetsökning.

Åtgärd: tolka datum vid modellinläsning, behåll typade datum och räkna om filtrerad ordning när data eller filtret faktiskt ändras. Använd lokaliserad formatering enbart för presentation. Verifiera sedan i Instruments enligt [Apples vägledning för SwiftUI-prestanda](https://developer.apple.com/videos/play/wwdc2025/306/).

Mätprogram: [review-date-benchmark.swift](/Users/robinbolinsson/Softcover/build/review-date-benchmark.swift). Kör `xcrun swiftc -O build/review-date-benchmark.swift -o build/review-date-benchmark` och därefter `build/review-date-benchmark`.

### 3. P1: Gamla söksvar kan skriva över nya

Textändringar startar nya uppgifter efter en väntetid, men redan pågående sökningar avbryts inte. Efter nätverkssvaret tilldelar `runSearch()` resultat utan kontroll av vilken söktext eller söktyp svaret gäller. Om svaren kommer i omvänd ordning kan fel resultat visas; rensade resultat kan också komma tillbaka. Historiktryck och submit kan dessutom överlappa den automatiska sökningen.

Belägg: [sökstart](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/SearchBooksView.swift:293>), [ovillkorlig resultattilldelning](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/SearchBooksView.swift:385>).

`isSearching` skrivs men används inte för att visa laddning. Användaren kan därför få en tomvy eller se gamla träffar utan tydlig återkoppling.

Åtgärd: en gemensam sökväg med debounce, avbrytning och ett versions-ID för söktext plus söktyp. Visa separata tillstånd för väntan, laddning, träffar, tomt resultat och fel. Samma skydd behövs vid snabba filterbyten i Utforska och flödet.

Acceptans: fördröj svar A och låt B bli klart först; B ska stanna kvar. Testa även rensa, byt mellan böcker/personer och lämna vyn medan en sökning pågår.

### 4. P2: Listtak döljer böcker i stället för att paginera

Läser hämtar högst 20 poster utan serverordning, sorterar lokalt och behåller sedan bara tio. Begränsningen gäller även appen, inte bara widgeten. Vill läsa hämtar högst 100 och söker endast i den arrayen. Kommentaren om att resten kan nås genom sökning stämmer därför inte. Global boksökning anropar bara första sidan med 25 träffar trots att tjänsten har en sidparameter.

Belägg: [Läser-frågan](/Users/robinbolinsson/Softcover/ReadingProgressWidget/HardcoverService.swift:897), [tioboksgränsen](/Users/robinbolinsson/Softcover/ReadingProgressWidget/HardcoverService.swift:948), [Vill läsa-gränsen](/Users/robinbolinsson/Softcover/WantToReadView.swift:471), [sökningens sidparameter](/Users/robinbolinsson/Softcover/ReadingProgressWidget/HardcoverService.swift:1534).

Åtgärd: skilj widgetens urval från appens bibliotek. Lägg till stabil serverordning och paginering. Sökning måste omfatta hela det avsedda biblioteket; välj en API-stödd söklösning och verifiera schemat, inte förbjudna textoperatorer. Höj inte bara alla gränser och ladda allt samtidigt.

Acceptans: bok 11 i Läser, bok 101 i Vill läsa och träff 26 i global sökning ska gå att nå.

### 5. P2: Kommandes tidsfilter används inte

Utforska visar Senaste, 1 månad, 3 månader och 1 år och skickar olika `filter`-värden. `fetchCommunityUpcomingReleases(filter:)` använder däremot inte parametern. Båda frågevarianterna filtrerar bara på utgivningsdatum från och med idag och returnerar samma populära urval, utan vald övre datumgräns.

Belägg: [valet i vyn](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/CommunityUpcomingView.swift:87>), [ignorerad parameter och datumfråga](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/HardcoverService+Lists.swift:571>).

Åtgärd: definiera vad Senaste betyder och översätt varje val till ett verkligt intervall i både bok- och utgåvefrågan. Låt valt intervall ingå i cachenyckeln. Detta är ett kodfynd i den aktuella arbetskopian, inte ett påstående baserat på de äldre skärmbilderna.

### 6. P2: Nätverksfel blir tomma bibliotek

Flera läsfunktioner returnerar `[]` eller `nil` vid fel. I Läser ersätts den befintliga listan med detta resultat och uppdateringstidpunkten flyttas fram även om anropet misslyckades. Därmed blir det omöjligt att skilja ett faktiskt tomt bibliotek från utgången token, 429 eller serverfel. Statistikens `catch` kan inte fånga fel eftersom de underliggande funktionerna inte kastar dem; senaste byggloggen varnar också för detta.

Belägg: [feltolkning i tjänsten](/Users/robinbolinsson/Softcover/ReadingProgressWidget/HardcoverService.swift:902), [ersättning av listan](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:372>), [statistikens felhantering](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/StatsView.swift:142>).

Åtgärd: typade fel för nätverk, HTTP, GraphQL och behörighet. Behåll senaste lyckade innehåll under uppdatering och visa en diskret felrad med återförsök. Visa en tomvy först när ett lyckat svar faktiskt är tomt. Katalogredigerarens nyare felhantering är ett bra lokalt mönster att bygga vidare på.

### 7. P2: Boköppning väntar på nätverk och detaljer laddas om i flera varianter

I sökning och historik inväntas `fetchBookDetailsById` innan detaljvyn öppnas. Funktionen väntar i sin tur på omslagsnedladdning/bearbetning. Därefter startar detaljvyn ytterligare laddningar av bland annat genrer, stämningar, recensioner och lässtatus. För böcker utan stämningsdata kan huvuddetaljvyn prova upp till sex olika frågor innan den accepterar att data saknas.

Belägg: [öppning från sök](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/SearchBooksView.swift:463>), [väntan på omslag](/Users/robinbolinsson/Softcover/ReadingProgressWidget/HardcoverService.swift:3309), [separata detaljladdningar](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/SearchResultDetailSheet.swift:175>), [fallbackkedjan](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/BookDetailView.swift:947>).

Fyra detaljimplementationer nås från huvudflödena: `BookDetailView`, `SearchResultDetailSheet`, `TrendingBookDetailSheet` och `WantToReadView.InlineBookDetailView`. De har egna tillstånd, åtgärder och delvis kopierade API-hjälpare. Det finns dessutom en äldre kompilerad detaljvariant i `UpcomingReleasesView`.

Åtgärd: öppna direkt med titel, omslags-URL och annan redan känd information. Samla bokmetadata i en delad, kontomedveten datakälla, och lägg till en gemensam bokdetaljvy med tydlig skillnad mellan bok, vald utgåva och användarens läsning. Ladda recensioner och annat underordnat innehåll separat. Cacha även lyckade tomma metadataresultat så att saknade taggar inte ständigt startar nya fallbackkedjor.

### 8. P2: Onödigt breda omladdningar efter små ändringar

Exempelvis `onProgressSaved` anropar `loadBooks()` och därefter `reloadAllTimelines()`. `loadBooks()` anropar redan `reloadAllTimelines()`. Samma dubblering finns i flera callbacks. En uppdaterad sidposition ska normalt inte behöva trigga en omladdning av citat och kommande utgivningar.

Belägg: [callback efter siduppdatering](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:268>), [omladdning inne i loadBooks](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:381>), [läswidgetens nätverkshämtning](/Users/robinbolinsson/Softcover/ReadingProgressWidget/ReadingProgressWidget.swift:38).

Åtgärd: uppdatera berörd bok i gemensamt state, samordna en eventuell bakgrundskontroll och uppdatera bara berörda widgettyper. Dela senaste lyckade snapshot via App Group med kontonyckel och ålder. Apple rekommenderar att begränsa onödiga widgetomladdningar och erbjuder riktad uppdatering per widgettyp. Systemet kan slå ihop uppdateringar, så två anrop innebär inte säkert två faktiska nätverkskörningar. [WidgetKit-dokumentationen](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

### 9. P2: Bildcachen skannar hela mappen efter varje skrivning

Den egna bildhanteringen har bra byggstenar: minnescache, diskcache, samordning av identiska nedladdningar och nedskalning. Men varje sparad originalfil och bearbetad bild anropar `trimIfNeeded`, som läser metadata för alla cachefiler innan den vet om storleksgränsen är passerad. Arbetet växer med cachemappens storlek och ligger i samma actor som övriga diskoperationer.

Belägg: [sparande och gallring](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/AsyncCachedImage.swift:682>), [fullständig mappgenomgång](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/AsyncCachedImage.swift:781>).

Åtgärd: behåll bildhanteringen men gallra samlat, med storleksbokföring eller tidsstyrd kontroll, inte fullskanning per bild. Separera senaste åtkomst från lagringstid om TTL ska betyda färskhet. Återanvänd samma omslagskomponent i Utforska där vanlig `AsyncImage` fortfarande används. Den faktiska scrollpåverkan behöver mätas; jag har inte mätt den här diskvägen.

### 10. P2: Historiksökning kan stanna vid en ofullständig cache

Sökning i historiken börjar ladda alla sidor från början. Avbrytning kontrolleras först efter en sidhämtning. När söktexten töms kan funktionen markera `allLoaded = true` eftersom `!isSearching`, trots att den inte nått sista sidan. Nästa sökning kan då använda en ofullständig cache. Även ett saknat totalantal kan göra fullständighetskontrollen missvisande.

Belägg: [all-sidor-laddningen och slutvillkoret](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/HistoryView.swift:272>).

Åtgärd: låt en explicit slut-på-sidor-signal avgöra fullständighet. Återanvänd redan laddade sidor, behåll nästa sidposition och skilj avbruten hämtning från färdig hämtning. På sikt behövs en sökväg som inte först kräver hela historiken.

### 11. P2: Läsningens formulär blandar sid- och tidsenheter

`editedPage` innehåller minuter för ljudböcker men begränsas i `onChange` mot `book.totalPages`. Om en ljudboksutgåva även har ett sidantal kan tidsvärdet kapas mot fel enhet. Samtidigt synkas förändringar av `currentPage`, men inte motsvarande `currentMinute`, i samma kod.

Belägg: [initialisering i olika enheter](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:437>), [sidbaserad begränsning och synkning](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:882>).

Åtgärd: en typad progressmodell och en gemensam progressredigerare. Ha samma enhet för inmatning, gränser, visning och API-konvertering. Testa särskilt ljudboksutgåvor med både `pages` och `audio_seconds`, ändrad längd och extern progressuppdatering under redigering.

## UI-förslag vy för vy

Detta är designrekommendationer, inte alla verifierade funktionsfel. Prioritera tydlighet och färre konkurrerande kontroller framför en ny dekorativ stil.

| Område | Nuvarande friktion | Föreslagen riktning |
| --- | --- | --- |
| Läser | Varje bokrad innehåller omslag, progress, flera åtgärder och ett formulär som byter mellan stepper, tangentbord och procentläge. | Kompakt bokrad med titel, författare, format och progress. En tydlig åtgärd för att uppdatera läsningen. Låt exakt sid-/tids-/procentinmatning ske i samma lilla redigeringsvy för alla böcker. Behåll snabbuppdatering om den används ofta. |
| Bokdetaljer | Olika detaljvyer erbjuder olika funktioner. Ändra utgåva finns ibland både i toolbar och innehåll. Tekniska ID:n visas i huvudflödet. | En gemensam detaljvy: bokhuvud, aktuell utgåva, egen lässtatus/progress, beskrivning, eget omdöme/citat, övriga recensioner. Lägg tekniska ID:n i en kopierbar informationssektion. Behåll librarian-redigering tydligt separat från den egna läsningen. |
| Navigation | Bokdetaljer visas ibland som sheet och ibland via NavigationLink. `BookDetailView` äger själv en NavigationStack även när den läggs i en annan stack. Sökning byter till Läser efter ett tillägg medan Utforska stannar kvar. | Gemensamt navigationsmönster: bokvisning som destination och redigering/utgåveval som sheet. Behåll huvudflikarna. Stanna i sökresultatet efter Lägg till i Vill läsa; byt till Läser endast efter en uttrycklig Börja läsa-åtgärd. |
| Sök | Otydlig väntan, ingen fortsatt paginering och nätverksberoende boköppning. | Omedelbar navigation, tydliga laddnings-/feltillstånd, fortsatt laddning av träffar och bibehållen söktext/scrollposition när man återvänder. Behåll skannern som ikonåtgärd. |
| Utforska | Stor rubrik, två segmentkontroller, förklarande text och upprepade Trendande-etiketter tar mycket plats före böckerna. Långa svenska segmentetiketter kapas i skärmbilderna. | Behåll ämnesvalet men gör tidsfiltret till en kompakt meny när etiketterna inte ryms. Ta bort återkommande förklaringstext och trendetikett på varje rad. Visa böcker tidigare och bevara varje ämnes resultat och position. |
| Vill läsa | Fullständighet och datumfilter är inte tillförlitliga. Bokrad och actions skiljer sig från övriga listor. | Riktig paginering, samma bokrad som i sök/Utforska och tydligt filter för kommande utgivningar. Visa datum/format där det hjälper att välja bok. |
| Utgåveval | Titeln konkurrerar med NUVARANDE-badgen. Visuell valdmarkering är dold för tillgänglighet utan motsvarande vald-egenskap på knappen. | Behåll den nyligen tillagda formatinformationen. Prioritera format, språk, förlag och utgivningsår. Gör vald/nuvarande utgåva tydlig även för VoiceOver och låt längre titlar få plats utan att statusbadgen tar över. |
| Katalogredigering | Grundflödet är nu betydligt bättre testat än äldre delar; storleken på formuläret gör ändå bok/utgåva lätt att blanda ihop. | Behåll den uttryckliga ingången Redigera aktuell utgåva och tydliga avsnitt för bok respektive utgåva. Återanvänd de nya skydden för behörighet, konflikter, osparade ändringar och 429. Eventuell cache av UI-behörighet får aldrig ersätta kontroll före skrivning. |
| Profil/statistik | Profilen är huvudsakligen en stor profilheader och meny. Andra användares bibliotek laddar alla tre statusgrupper innan någon visas. | Mer koncentrerad profilheader, läsmål nära toppen och tydliga grupper för bibliotek/socialt/inställningar. Ladda först den valda biblioteksgruppen och återanvänd användar-ID i stället för separata ID-anrop. |
| Historik/socialt/listor | Vissa delar har paginering, andra är engångshämtningar. Flera funktioner tolkar Hardcovers webbsidor. | Återanvänd list- och feltillstånd. Behåll fungerande paginering. Kapsla HTML-tolkning och lägg till fixtures så att en ändrad webbstruktur inte tyst blir en tom lista. Byt till dokumenterat API där motsvarande funktion är verifierad. |
| Inställningar | API-nyckeln sparas före verifiering och dialogen kan visa sparat även när användarhämtningen misslyckats. | Separera anslutning/kontostatus från allmänna inställningar. Validera en ny token före byte, visa saknad behörighet begripligt och töm kontobunden cache vid byte. |
| Widgets | Nya nätverkshämtningar och breda omladdningar; vissa länkar leder bara till en huvudflik. | Läs senaste lyckade data snabbt, förnya selektivt och öppna exakt läsmål/utgivning som användaren tryckte på. Behåll fungerande storleks- och utseendealternativ. |

Ytterligare belägg för UI-förslagen: [progresskontroller](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:629>), [sökningens flikbyte](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:78>), [Utforskas överdel](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ExplorerView.swift:21>), [utgåverad](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/EditionRow.swift:25>), [andra användares samtidiga gruppladdning](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/UserBooksView.swift:308>), [token sparas före kontroll](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ApiKeySettingsView.swift:263>).

### Tillgänglighet och språk

- Testa stora textstorlekar, svenska långa titlar, liggande läge, iPad, mörkt läge och VoiceOver. Många texter använder redan systemets typografistilar; behåll detta men låt layouten anpassa sig i stället för att bara kapa fler rader.
- Ge de små ikonerna för Markera som läst och Ändra utgåva en tydligt definierad tryckyta. De använder nu `.plain` och bildstorlek utan egen minsta tryckyta i [bokradens actiongrupp](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:553>). Sikta på 44 x 44 punkter som normal kontrollstorlek och kontrollera faktisk layout i Accessibility Inspector. [Apples tillgänglighetsriktlinjer](https://developer.apple.com/design/human-interface-guidelines/accessibility).
- Lägg till semantisk valdstatus på utgåveraderna. Undvik att vara beroende av enbart färg eller en dekorativ bock.
- Respektera Minska rörelse i egna animationer. Varje ökning av läsprogress kan nu utlösa helskärmskonfetti; en diskret sparbekräftelse räcker normalt, och firandet kan reserveras för avslutad bok. [Utlösningen](</Users/robinbolinsson/Softcover/Hardcover Reading Widget/ContentView.swift:949>).
- `ExplorerView.sectionInfoText` är en vanlig sträng som skickas direkt till `Text`, vilket förklarar den engelska texten i en svensk vy. Inventera även dynamiska felsträngar och den svenska literaltexten NUVARANDE. Att en text finns i String Catalog betyder inte att alla dynamiska strängvägar faktiskt lokaliserar den.

## Underhåll och testluckor

P3: rensa äldre kopior först efter kontrollerat byggmedlemskap, och dela därefter upp filer efter ansvar. `HardcoverService.swift` är 4 461 rader, `WantToReadView.swift` 2 121 och `ContentView.swift` 1 506. Storlek i sig gör inte appen långsam, men blandningen av formulär, nätverk, navigation och feedback gör det lätt att laga bara en av flera kopior.

P2 inför större ändringar: senaste [arkivloggen](/Users/robinbolinsson/Softcover/build/testflight-202609122045-archive.log) innehåller bland annat concurrency-varningar i bildhantering och prompts samt `catch`-block som aldrig kan köras. Hantera dessa efter risk, inte som en mekanisk jakt på alla varningar. Aktivera inte ett nytt Swift-språkläge över hela appen utan avgränsade tester.

De ursprungliga [enhetstesterna](</Users/robinbolinsson/Softcover/Hardcover Reading WidgetTests/Hardcover_Reading_WidgetTests.swift:13>) är en tom exempeltest, och [UI-testerna](</Users/robinbolinsson/Softcover/Hardcover Reading WidgetUITests/Hardcover_Reading_WidgetUITests.swift:28>) testar främst start, inte arbetsflöden. De nyare katalogtesterna är ett användbart undantag. Det finns alltså inte en heltäckande regressionstestsvit som gör en stor ombyggnad riskfri.

## Föreslagen ordning

### Omgång 1: Snabbare och tillförlitligare

1. Ta bort betygsanrop per bok och flytta datumtolkning ur listberäkningen.
2. Samordna sökningar och filterbyten; skriv tester med omvänd svarsordning.
3. Skilj fel från tomma resultat och behåll senast lyckade data.
4. Inför riktig paginering och fungerande datumintervall i Kommande.
5. Testa ljudboksprogressens enheter och historikens avbrutna sökning.

### Omgång 2: Mindre klumpig vardagsanvändning

1. Inför gemensam bokrad och gemensam bokdetaljvy med omedelbar öppning.
2. Samla progressinmatningen och minska konkurrerande knappar i läslistan.
3. Gör bok, vald utgåva och egen läsning tydliga i detaljvyn.
4. Förenkla Utforskas filteryta och behåll sök-/scrollpositioner.
5. Verifiera svenska, Dynamic Type, VoiceOver, tryckytor och Minska rörelse innan den nya layouten sprids till alla listor.

### Omgång 3: Återstående förbättringar

1. Selektiv widgetsynk och kontobunden snapshot-cache.
2. Samlad gallring av bildcache och enhetlig omslagshantering.
3. Profil, historik och sociala vyer med gemensamma laddningstillstånd och fixtures för HTML-tolkning.
4. Rensa inaktiva filer, minska kodkopiering och åtgärda relevanta byggvarningar.

## Mätning före nästa release

Använd en releasekonfiguration på fysisk iPhone med samma testdata före och efter. Apples SwiftUI-instrument, Time Profiler och Hangs/Hitches är lämpliga för att skilja dyra vyuppdateringar från andra flaskhalsar. [Apples prestandadokumentation](https://developer.apple.com/documentation/swiftui/performance-analysis).

Följ antal API-operationer per arbetsflöde, tid till första bokrad, tid från tryck till öppnad detaljvy, långa huvudtrådsarbeten, minnestopp vid omslagsscrollning och widgetuppdateringar per sparad läsändring. Registrera p50/p95 där det finns tillräckligt många körningar; välj förbättringsmål utifrån baslinjen, inte en gissad procentuell hastighetsvinst.

Regressionstesta: 10/100/1 000 biblioteksböcker, offline, 401/403/429/500, långsamma och omkastade svar, kontobyte, saknat omslag/utgivningsdatum, fysisk bok/e-bok/ljudbok, utgåvebyte, läsdatum, avsluta bok med misslyckad recension samt librarian/icke-librarian. Ingen ny TestFlight-build bör beskrivas som verifierat snabbare förrän de relevanta flödena har jämförts.
