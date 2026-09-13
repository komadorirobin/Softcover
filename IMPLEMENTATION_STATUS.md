# Genomförande av appgranskningen

Datum: 2026-09-13. Kodändringarna i APP_REVIEW_2026-09-13.md är genomförda. Befintliga katalogändringar har bevarats. TestFlight-kandidat: 1.1.8 (202609130922). Offentlig App Store-publicering ingår inte i denna leverans.

## Genomförda förändringar

- [x] Gemensam nätverksdel med typade fel, kontoisolering, cache, samordning av identiska läsningar och rate-limit-hantering. Avbrutna väntare lämnar inte onödiga API-anrop. Skrivningar återspelas inte automatiskt.
- [x] Sidvis bibliotekshämtning, stabil serverordning, betyg i grundfrågan och datumtolkning vid modellinläsning. Läser är inte längre begränsat till tio böcker i appen.
- [x] Sökning med debounce, avbrytning, skydd mot sena svar, separata laddnings-/fel-/tomlägen och fler resultatsidor. Tillägg till Vill läsa lämnar användaren i sökningen.
- [x] Utforska med riktiga utgivningsintervall, kompakt tidsmeny och bevarade resultat/filter. Överflödig förklaringstext och upprepade trendetiketter borttagna.
- [x] Gemensam bokrad, bokdetaljvy och progressredigerare. Omedelbar navigation; separat bokmetadata, utgåva och egen läsning. Tekniska ID:n samlade i en kopierbar informationssektion.
- [x] Sid-/tids-/procentinmatning använder samma enhet och gränser. Extern progressändring upptäcks före sparning. Ingen helskärmskonfetti vid varje progressändring.
- [x] Utgåveval visar format, språk, förlag och giltigt utgivningsår. Långa titlar får utrymme och vald utgåva har tillgänglighetssemantik. Ljudböcker finns med bland valbara utgåvor.
- [x] Historik återanvänder redan hämtade sidor och skiljer avbrott från komplett resultat. Sociala bibliotek laddar vald statusgrupp först. Profilen är kompaktare med läsmål nära toppen.
- [x] Listor, prompts, citat och läsdatum har förbättrad felhantering. HTML-fel skiljs från legitimt tomma svar och gamla svar skyddas vid kontobyte.
- [x] Ny API-nyckel valideras innan kontot byts. Katalogens färska behörighetskontroll före skrivning är kvar.
- [x] Widgetar delar kontobundna snapshots, behåller senaste lyckade innehåll vid fel och uppdateras selektivt/samlat. Länkar innehåller exakt mål/bok/utgåva. Bara de synliga läsböckernas omslag hämtas.
- [x] Bildcache gallras samlat med storleksbokföring och separat färskhet/åtkomst. Gemensamma omslag, större tryckytor, Minska rörelse och svenska texter har införts/förbättrats.
- [x] Sex verifierat inaktiva rotkopior och oanvända sökkomponenter borttagna. Stora vyer och tjänster uppdelade efter ansvar. Relevanta Swift- och concurrency-varningar åtgärdade.
- [x] Automatiserade regressionstester, schemavalidering, Debug-/Release-byggen och isolerad visuell kontroll genomförda.

## Verifierat

- Samlat kommando: sh scripts/test-app-review.sh, exit 0.
- Kärna: 49 testgrupper, inklusive 125-bokspaginering, omkastade svar, kontobyten, felkoder, avbrott och cacheinvalidering efter skrivning.
- Katalog-, social-/prompt-/HTML- och widget-/bildcachetester passerar.
- 31 GraphQL-dokument validerade: 15 app-/biblioteksfrågor, 14 katalogoperationer och 2 widgetfrågor.
- Hela appen och widgettillägget bygger i Debug och Release med CODE_SIGNING_ALLOWED=NO. Inga Swift-varningar i senaste Release-loggen.
- SoftcoverTests är åter kopplat till Xcode-schemat; build-for-testing passerar. Dessa Xcode-tester har byggts, inte körts i simulatorn.
- Riktiga bokvyer med mockade beroenden har kompilerats och bildgranskats på iPhone, iPad i mörkt läge, stor text och ljudboksprogress. Fixturen kontrollerar även progressenheter och konkurrerande detaljladdningar.

Loggar: build/app-review-tests.log, build/app-review-release-build.log och build/app-review-test-build.log.
Bilder: build/book-ui-*.png. Körinstruktioner och testavgränsningar: Tests/AppReview.md.

## Före release

- [ ] Prova den inloggade appens huvudsakliga arbetsflöden på fysisk iPhone, särskilt utgåvebyte, läsdatum, avslut med recension och kontoanslutning.
- [ ] Kontrollera VoiceOver, touch/tangentbord, liggande läge och systemets verkliga widgetscheduling. Dessa är inte verifierade av bildfixturen.
- [ ] Mät scrollning, huvudtråd, minne och upplevda väntetider i Instruments med samma data före/efter. Ingen faktisk iPhone-FPS- eller batteriförbättring påstås.
- [ ] Kör en livekontroll av Hardcover med avsedda testdata. De automatiserade testerna gör inga produktionsskrivningar.

Den installerade CoreSimulator-versionen är äldre än vad Xcode väntar sig. Därför kunde den vanliga Xcode-simulatorintegrationens testkörning inte användas; isolerade bildfixturer kördes med den installerade simulatorns verktyg. Enhetsbyggena och de fristående regressionstesterna påverkas inte av detta.

Widgetar kan visa upp till ett dygn gammal lyckad data vid nätverksfel. Citatwidgeten hämtar fortfarande hela journalen vid en lyckad förnyelse för att kunna välja även äldre citat, men delar och begränsar den cachade mängden mellan widgetinstanser.
