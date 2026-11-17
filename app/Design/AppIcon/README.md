# App-Icon

- **In Verwendung:** Vorschlag 4 „T-Monogramm“ (gewählt am 2026-11-17): `tagwerk-light.svg`, `tagwerk-dark.svg`, `tagwerk-tinted.svg`.
- **Reserve:** Vorschlag 2 „Zeitleiste“: `backup-zeitleiste.svg`.
- Alle Vorschläge: `docs/superpowers/mockups/2026-11-17-app-icon-proposals.html`.

PNGs neu erzeugen (1024 × 1024, ohne Transparenz):

```zsh
cd app/Design/AppIcon
for v in light dark tinted; do
  rsvg-convert -w 1024 -h 1024 -b black tagwerk-$v.svg -o ../../Tagwerk/Assets.xcassets/AppIcon.appiconset/AppIcon-${(C)v}.png
done
```
