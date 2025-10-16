#!/usr/bin/env python3
import json
import sys

# Läs in Localizable.xcstrings
with open('Localizable.xcstrings', 'r', encoding='utf-8') as f:
    data = json.load(f)

# Översättningar att lägga till
translations = {
    "Loading your books...": "Laddar dina böcker...",
    "Failed to load books": "Kunde inte ladda böcker",
    "No books currently reading": "Inga böcker läses just nu",
    "Start reading a book on Hardcover to see it here": "Börja läsa en bok på Hardcover för att se den här",
    "Marked as finished": "Markerad som färdigläst",
    "Currently Reading": "Läser just nu",
    "Mark as finished": "Markera som färdigläst",
    "Change edition": "Ändra utgåva",
    "No progress information": "Ingen läsframgång",
    "Remove from Currently Reading": "Ta bort från Läser just nu",
    "Please try again.": "Försök igen.",
    "Loading profile...": "Laddar profil...",
    "Failed to load profile": "Kunde inte ladda profil",
    "Reading Stats": "Lässtatistik",
    "Reading History": "Läshistorik",
    "Lists": "Listor",
    "Friends": "Vänner",
    "No profile data available": "Ingen profildata tillgänglig",
    "Profile": "Profil",
    "Following": "Följer",
    "Follow": "Följ",
    "Loading friends...": "Laddar vänner...",
    "Failed to load friends": "Kunde inte ladda vänner",
    "Search": "Sök",
    "Explore": "Utforska",
    "Trending": "Trending",
    "Upcoming": "Kommande",
    "Community Lists": "Community-listor",
    "Loading statistics...": "Laddar statistik...",
    "Failed to load statistics": "Kunde inte ladda statistik",
    "Reading Goals": "Läsmål",
    "No statistics available": "Ingen statistik tillgänglig",
    "Start reading and setting goals to see your statistics here": "Börja läsa och sätt mål för att se din statistik här",
    "Description": "Beskrivning",
    "Reviews": "Recensioner",
    "No reviews found": "Inga recensioner hittades",
    "Load more": "Ladda fler",
    "Book Details": "Bokdetaljer",
    "Want to Read": "Vill läsa",
    "Start Reading": "Börja läsa",
    "Dates Read": "Läsdatum",
    "Add New Read": "Lägg till ny läsning",
    "Delete": "Ta bort",
    "Started:": "Påbörjad:",
    "Finished:": "Avslutad:",
    "In progress": "Pågående",
    "Select when you finished reading, then tap Confirm": "Välj när du slutade läsa, tryck sedan på Bekräfta",
    "Tap a date to mark when you started reading": "Tryck på ett datum för att markera när du började läsa",
    "Confirm End Date": "Bekräfta slutdatum",
    "Edit Read": "Redigera läsning",
    "Delete This Read": "Ta bort denna läsning",
    "Are you sure you want to delete this reading record?": "Är du säker på att du vill ta bort denna läspost?",
    "Cancel": "Avbryt",
    "Save": "Spara",
    "Done": "Klar",
    "Clear": "Rensa",
    "Recent Searches": "Senaste sökningar",
    "Loading trending books...": "Laddar trending-böcker...",
    "Failed to load trending books": "Kunde inte ladda trending-böcker",
    "No trending books found": "Inga trending-böcker hittades",
    "Trending this month": "Trending denna månad",
    "Search Hardcover for books": "Sök efter böcker på Hardcover",
    "Rate & Review": "Betygsätt & recensera",
    "Creating entry...": "Skapar post...",
    "Review": "Recension",
    "Like review": "Gilla recension",
    "Unlike review": "Ta bort gillning",
    "Rating": "Betyg",
    "Loading lists...": "Laddar listor...",
    "Failed to load lists": "Kunde inte ladda listor",
    "No lists yet": "Inga listor än",
    "Loading list...": "Laddar lista...",
    "Failed to load list": "Kunde inte ladda lista",
    "No books in this list": "Inga böcker i denna lista",
    "Created by": "Skapad av",
    "Average Rating": "Genomsnittsbetyg",
    "This user hasn't shared any statistics yet": "Denna användare har inte delat någon statistik än",
    "Change Edition": "Ändra utgåva",
    "Mark as Reading": "Markera som läser",
    "Has finished reading": "Har slutat läsa",
    "Start Date": "Startdatum",
    "End Date": "Slutdatum",
    "Loading Want to Read…": "Laddar Vill läsa...",
    "No books in Want to Read": "Inga böcker i Vill läsa",
    "Add books to your Want to Read list on Hardcover to see them here.": "Lägg till böcker i din Vill läsa-lista på Hardcover för att se dem här.",
    "Remove from Want to Read": "Ta bort från Vill läsa",
    "Reading Now": "Läser nu",
    "No Books": "Inga böcker",
    "Add books to read in Hardcover": "Lägg till böcker att läsa i Hardcover",
    "No Reading Goal": "Inget läsmål",
    "Loading description...": "Laddar beskrivning...",
    "Select Edition": "Välj utgåva",
    "Loading editions...": "Laddar utgåvor...",
    "No books found": "Inga böcker hittades",
    "Try Again": "Försök igen",
    "Reload trending": "Ladda om trending",
    "List": "Lista",
    "No books found in this list": "Inga böcker hittades i denna lista",
    "Select Start Date": "Välj startdatum",
    "Select End Date": "Välj slutdatum",
    "Reading": "Läser",
    "Saving...": "Sparar...",
}

# Lägg till översättningar
added_count = 0
for english, swedish in translations.items():
    if english not in data["strings"]:
        data["strings"][english] = {
            "localizations": {
                "sv": {
                    "stringUnit": {
                        "state": "translated",
                        "value": swedish
                    }
                }
            }
        }
        added_count += 1
        print(f"✅ Added: '{english}' → '{swedish}'")
    elif "localizations" not in data["strings"][english]:
        data["strings"][english]["localizations"] = {
            "sv": {
                "stringUnit": {
                    "state": "translated",
                    "value": swedish
                }
            }
        }
        added_count += 1
        print(f"✅ Updated: '{english}' → '{swedish}'")
    elif "sv" not in data["strings"][english]["localizations"]:
        data["strings"][english]["localizations"]["sv"] = {
            "stringUnit": {
                "state": "translated",
                "value": swedish
            }
        }
        added_count += 1
        print(f"✅ Added Swedish: '{english}' → '{swedish}'")
    else:
        print(f"⏭️  Skipped (already exists): '{english}'")

# Skriv tillbaka till filen
with open('Localizable.xcstrings', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"\n🎉 Done! Added/updated {added_count} translations")
print(f"📝 Total translations in file: {len(data['strings'])}")
