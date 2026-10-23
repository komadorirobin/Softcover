# Softcover Supporter Pack experiment

This release tests whether Softcover's current audience will pay for a small,
optional upgrade without removing any existing free feature.

## Offer

- Standard product: Softcover Supporter Pack
- Standard product ID: `komadori.softcover.supporter.lifetime`
- Standard price: SEK 99 (use Apple's nearest comparable price elsewhere)
- Generous product: Generous Supporter Pack
- Generous product ID: `komadori.softcover.supporter.generous`
- Generous price: SEK 149 (use Apple's nearest comparable price elsewhere)
- Type: both are non-consumable, one-time purchases
- Both unlock the same cosmetic Supporter Collection:
  - four alternate app icons: Aurora, Sunset, Ink, and Vellum
  - eight Reading Quote widget themes: Aurora, Sunset, Ink, Lavender, Ember,
    Moss, Moonlight, and Parchment
  - four extra app accent palettes: Aurora, Sunset, Moss, and Lavender
- Future cosmetics added to the collection are included
- The generous option provides no additional functionality; it is extra support
- Existing app features and the five existing quote themes remain free

The existing consumable tips remain available below the supporter choices, but
the non-consumable purchases are the primary offer.

## App Store Connect checklist

1. Create both non-consumable in-app purchases with the exact product IDs above.
2. Add English and Swedish names/descriptions matching `Softcover/TipProducts.storekit`.
3. Select SEK 99 for the standard product and SEK 149 for the generous product.
4. Upload a review screenshot showing Settings or Profile → Support Softcover.
5. Include the in-app purchase with the next app version submitted for review.
6. In review notes, say that both purchases unlock the same cosmetic collection,
   the higher price is optional extra support, all functional features remain
   free, and Restore Purchase is on the same screen.

## Measurement window

Run the test for eight weeks after the release reaches 100% availability. Record
these App Store Connect values weekly:

- first-time downloads (Units)
- active devices and sessions
- standard and generous Supporter Pack units and proceeds, separately
- tip units and proceeds, separately
- crashes and widget-related support messages

At this audience size, the test is directional rather than statistically strong.
Treat three or more Supporter Pack purchases as evidence that users will pay;
zero purchases after eight weeks is a reason to stop investing in paid Softcover
features. Do not interpret one purchase either way.

The current baseline is roughly 160 first-time downloads in 26 weeks (about six
per week). Growth remains the main constraint even if the paid conversion is good.
