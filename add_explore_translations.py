#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Add missing English→Swedish translations for Trending and time filters.
"""

import json

# Read the existing file
with open('Localizable.xcstrings', 'r', encoding='utf-8') as f:
    data = json.load(f)

# New translations - words that should be localized but aren't yet
new_translations = {
    # Trending section
    "Trending": "Trendande",
    "Trending this month": "Trendande denna månad",
    "Reload trending": "Ladda om trendande",
    
    # Time filters
    "Last Month": "Förra månaden",
    "3 Months": "3 månader",
    "1 Year": "1 år",
    "All Time": "Alltid",
    "Time Range": "Tidsperiod",
    
    # Upcoming section
    "Upcoming": "Kommande",
    
    # Lists section  
    "Lists": "Listor",
    
    # Info texts
    "A list of what books are read the most on Hardcover.": "En lista över de mest lästa böckerna på Hardcover.",
    "A list of what books are most anticipated on Hardcover.": "En lista över de mest efterlängtade böckerna på Hardcover.",
    "Lists are organized collections of books created by anyone. Create a list and maybe it'll get featured!": 
        "Listor är organiserade boksamlingar skapade av vem som helst. Skapa en lista så kanske den presenteras!",
    
    # Picker labels
    "Section": "Sektion",
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
