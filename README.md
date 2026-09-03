# Padel tournament aggregator

A static website that lists upcoming official padel tournaments in Estonia, Latvia and Finland, plus every FIP Bronze tournament worldwide. Filter by country and month, or search by name, city, venue or class.

Open `index.html` in a browser to use it. No build step and no server needed. If you prefer a local URL, run the bundled server and open http://localhost:8765/:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\serve.ps1
```

## Sources

| Chip | Source | What is included |
|---|---|---|
| Estonia | [Eesti Padeli Liit on Rankedin](https://www.rankedin.com/en/organisation/calendar/1763/eesti-padeli-liit) | A-liiga and B-liiga stages (men and women). Run the refresh with `-AllEstonianLeagues` to include C and D. |
| Latvia | [Latvijas Padel Federācija](https://padelfederacija.lv/lv-LV/tournaments) | Every upcoming tournament on the federation site (Gold / Silver / Bronze series, championships). |
| Finland | [Suomen Padelliitto on Padelution](https://www.padelution.com/events?pid=62) | Events sanctioned by the federation: Finnish Padel Tour Gold and Silver plus national ranking tournaments ("Kansalliset"). |
| FIP Bronze | [Cupra FIP Tour calendar](https://www.padelfip.com/calendar-cupra-fip-tour/) | FIP Bronze tournaments only, for the current and next year. |

By default Estonia, Latvia and Finland are selected. FIP Bronze is one click away.

## Refreshing the data

The site reads `data/tournaments.js` (and the identical `data/tournaments.json`). Regenerate them with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\refresh.ps1
```

The script needs only Windows PowerShell 5.1 or PowerShell 7. It fetches the four sources, keeps tournaments whose end date is today or later, and prints a per-source count. If one source fails, the others are still written and the failure is shown in the site footer.

## Hosting

Any static host works (GitHub Pages, Netlify, Cloudflare Pages). The included GitHub Actions workflow in `.github/workflows/refresh.yml` re-runs the refresh script every morning and commits the new data, so a GitHub Pages site stays current on its own. Enable Pages for the repository from the `main` branch root.

## Files

```
index.html              the page
assets/style.css        styles (light and dark)
assets/app.js           filtering and rendering
data/tournaments.js     generated data loaded by the page
data/tournaments.json   same data as plain JSON
scripts/refresh.ps1     scraper that regenerates the data
scripts/serve.ps1       optional local preview server
.github/workflows/      daily refresh on GitHub Actions
```

## Known limits

- The Latvian federation page embeds its first 15 tournaments (upcoming first). If more than 15 upcoming tournaments are ever listed, the rest would be missed.
- Finnish dates are given without a year on Padelution. The script takes the year from the month headings on the page.
- Registration deadlines are shown where the source provides them (Estonia, Latvia). Finland and FIP only show a status.
