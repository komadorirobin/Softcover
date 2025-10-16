#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Add missing English→Swedish translations for hardcoded strings found in code.
"""

import json

# Read the existing file
with open('Localizable.xcstrings', 'r', encoding='utf-8') as f:
    data = json.load(f)

# New translations from hardcoded Swedish strings we just fixed
new_translations = {
    # ApiKeySettingsView
    "API Key": "API-nyckel",
    "Paste your API key": "Klistra in din API-nyckel",
    "Clear": "Rensa",
    "Save Settings": "Spara inställningar",
    "Where do I find the key?": "Var hittar jag nyckeln?",
    "You can find your personal API key on Hardcover under Account → API. Log in and go to:": 
        "Du hittar din personliga API-nyckel på Hardcover under Konto → API. Logga in och gå till:",
    "Appearance": "Utseende",
    "Theme": "Tema",
    "Follow System": "Följer system",
    "Light": "Ljust",
    "Dark": "Mörkt",
    "Add Book": "Lägg till bok",
    "Skip \"Choose Edition\" when adding": "Hoppa över \"Välj utgåva\" vid tillägg",
    "When enabled, the default edition is automatically used when you add a book to \"Want to Read\" or \"Currently Reading\".":
        "När detta är aktiverat används standardutgåvan automatiskt när du lägger till en bok i \"Vill läsa\" eller \"Läser just nu\".",
    "Account": "Konto",
    "Username": "Användarnamn",
    "API Settings": "API-inställningar",
    "Close": "Stäng",
    "Saved": "Sparat",
    "Your settings were saved. Widgets will update shortly.": "Dina inställningar sparades. Widgetar uppdateras strax.",
    "Could not paste": "Kunde inte klistra in",
    "Check that clipboard contains text, and allow \"Paste\" if iOS asks.": 
        "Kontrollera att clipboard innehåller text, och tillåt \"Klistra in\" om iOS frågar.",
    "App is forced to light mode.": "Appen tvingas till ljust läge.",
    "App is forced to dark mode.": "Appen tvingas till mörkt läge.",
    "App follows system light/dark mode.": "Appen följer systemets ljus/mörkt.",
    
    # UpcomingReleasesView
    "Show More": "Visa fler",
    "Upcoming Releases": "Kommande släpp",
}

# Process each translation
updated_count = 0
skipped_count = 0

for english, swedish in new_translations.items():
    if english not in data["strings"]:
        # Add completely new entry
        data["strings"][english] = {
            "extractionState": "manual",
            "localizations": {
                "sv": {
                    "stringUnit": {
                        "state": "translated",
                        "value": swedish
                    }
                }
            }
        }
        print(f"✅ Added: {english}")
        updated_count += 1
    elif "sv" not in data["strings"][english].get("localizations", {}):
        # Entry exists but no Swedish translation
        if "localizations" not in data["strings"][english]:
            data["strings"][english]["localizations"] = {}
        data["strings"][english]["localizations"]["sv"] = {
            "stringUnit": {
                "state": "translated",
                "value": swedish
            }
        }
        print(f"✅ Updated: {english}")
        updated_count += 1
    else:
        print(f"⏭️  Skipped: {english} (already has Swedish)")
        skipped_count += 1

# Write back
with open('Localizable.xcstrings', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"\n🎉 Done! Added/updated {updated_count} translations, skipped {skipped_count}")
print(f"Total translations in file: {len(data['strings'])}")
