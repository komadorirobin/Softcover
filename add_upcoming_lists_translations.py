#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Add missing English→Swedish translations for Community Upcoming and Lists sections.
"""

import json

# Read the existing file
with open('Localizable.xcstrings', 'r', encoding='utf-8') as f:
    data = json.load(f)

# New translations for Upcoming and Lists sections
new_translations = {
    # Community Upcoming filters
    "Recent": "Senaste",
    "1 Month": "1 månad",
    
    # Lists filters
    "Featured": "Utvalda",
    "Popular": "Populära",
    "Filter": "Filter",
    
    # Loading/error messages
    "Loading upcoming releases...": "Laddar kommande släpp...",
    "No upcoming releases found": "Inga kommande släpp hittades",
    "Loading lists...": "Laddar listor...",
    "No lists found": "Inga listor hittades",
    "Community Lists": "Gemenskapslistor",
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
        # Check if Swedish translation needs updating
        current_swedish = data["strings"][english]["localizations"]["sv"]["stringUnit"]["value"]
        if current_swedish != swedish:
            data["strings"][english]["localizations"]["sv"]["stringUnit"]["value"] = swedish
            print(f"🔄 Updated translation: {english} -> {swedish}")
            updated_count += 1
        else:
            print(f"⏭️  Skipped: {english} (already correct)")
            skipped_count += 1

# Write back
with open('Localizable.xcstrings', 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)

print(f"\n🎉 Done! Added/updated {updated_count} translations, skipped {skipped_count}")
print(f"Total translations in file: {len(data['strings'])}")
