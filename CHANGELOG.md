# SilkRoad 0.7.6

## New

- **Leveling Guide follows the game's recipe colours**: each time you open a profession
  window, SilkRoad notes the colour the game shows every recipe in (orange, yellow, green,
  grey) and recipes giving more than one point per skill-up, and corrects its plans to match.
- **Separate data wipes**: Settings > Data can now wipe auction prices and merchant prices
  separately, besides wiping both.

## Changed

- **Buy lists take every reagent**: adding a recipe to a buy list adds all its reagents.
  Reagents that vendors also sell are listed in a notice with their vendor price, so you can
  buy those from a vendor instead.

## Fixed

- **Leveling Guide**: a craft that sells for more than it costs no longer counts as free, so
  the plan picks recipes needing fewer crafts (for example orange Hillman's Leather Gloves
  instead of dozens of low-chance Hillman's Shoulders).
- **Sold by vendors**: only items actually seen at a merchant count as sold by vendors, and
  limited-stock offers are ignored, so items like Heavy Leather are no longer flagged wrongly.
