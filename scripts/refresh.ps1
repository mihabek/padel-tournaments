#requires -Version 5.1
<#
.SYNOPSIS
  Refreshes data/tournaments.json and data/tournaments.js from four sources:
    - Estonia : Eesti Padeli Liit on Rankedin (A, B, C and D leagues; -AllEstonianLeagues adds youth, seniors and other events)
    - Finland : Suomen Padelliitto sanctioned events on Padelution
    - Latvia  : Latvijas Padel Federacija on padelfederacija.lv (Tournated platform)
    - FIP     : Cupra FIP Tour calendar on padelfip.com, FIP Bronze tournaments only
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\refresh.ps1
#>
[CmdletBinding()]
param(
  [string]$OutDir = '',
  [switch]$AllEstonianLeagues
)

$ErrorActionPreference = 'Stop'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutDir) { $OutDir = Join-Path $ScriptDir '..\data' }
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'
$Today = (Get-Date).Date
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$TextInfo = (Get-Culture).TextInfo

# ---------- helpers ----------
function Get-Text([string]$Url) {
  $r = Invoke-WebRequest -UseBasicParsing -Uri $Url -UserAgent $UA -TimeoutSec 90
  if ($r.RawContentStream) {
    $ms = New-Object System.IO.MemoryStream
    $r.RawContentStream.Position = 0
    $r.RawContentStream.CopyTo($ms)
    return $Utf8.GetString($ms.ToArray())
  }
  return $r.Content
}
function Get-JsonUrl([string]$Url) { return (Get-Text $Url | ConvertFrom-Json) }
function Clean-Text([string]$s) {
  if ($null -eq $s) { return '' }
  $t = $s -replace '<!--.*?-->', ' ' -replace '<[^>]+>', ' '
  $t = [System.Net.WebUtility]::HtmlDecode($t)
  return ($t -replace '\s+', ' ').Trim()
}
function Iso([datetime]$d) { return $d.ToString('yyyy-MM-dd') }
function MakeDate([int]$y, [int]$m, [int]$d) { return New-Object DateTime($y, $m, $d) }
function Smart-TitleCase([string]$s) {
  # Title-case an ALL CAPS name but keep roman numerals and vowel-less short acronyms (QNB, MH) upper case,
  # and keep small connecting words (del, de, la, ...) lower case unless they start the name.
  $small = @('de','del','della','di','da','du','la','le','les','el','los','las','van','von','of','and','the','y','e','en','sur','au','aux')
  $i = 0
  $out = foreach ($tok in ($s -split ' ')) {
    $lower = $tok.ToLower(); $i++
    if ($tok -match '^[IVX]+$') { $tok }
    elseif ($tok.Length -le 3 -and $tok -cmatch '^[A-Z0-9]+$' -and $tok -notmatch '[AEIOU]') { $tok }
    elseif ($i -gt 1 -and $small -contains $lower) { $lower }
    else { $TextInfo.ToTitleCase($lower) }
  }
  return ($out -join ' ')
}
function New-Tournament {
  param($Country, $CountryName, $Source, $SourceName, $Id, $Name, $Tier, $Classes, $Gender,
        $City, $Venue, $HostCountry, [datetime]$Start, [datetime]$End, $Url, $Status, $Deadline, $Organizer)
  [ordered]@{
    id          = "$Source-$Id"
    country     = $Country            # EE | FI | LV | FIP
    countryName = $CountryName
    source      = $Source             # EPL | SPL | LPF | FIP
    sourceName  = $SourceName
    name        = $Name
    tier        = $Tier
    classes     = @($Classes | Where-Object { $_ })
    gender      = $Gender             # men | women | open
    city        = $City
    venue       = $Venue
    hostCountry = $HostCountry
    startDate   = (Iso $Start)
    endDate     = (Iso $End)
    url         = $Url
    status      = $Status             # open | closed | live | upcoming | unknown
    deadline    = $(if ($Deadline) { Iso $Deadline } else { $null })
    organizer   = $Organizer
  }
}
$Months  = @{ January=1; February=2; March=3; April=4; May=5; June=6; July=7; August=8; September=9; October=10; November=11; December=12 }
$MonAbbr = @{ Jan=1; Feb=2; Mar=3; Apr=4; May=5; Jun=6; Jul=7; Aug=8; Sep=9; Oct=10; Nov=11; Dec=12 }

$all = New-Object System.Collections.ArrayList
$sources = New-Object System.Collections.ArrayList
function Add-Source($Id, $Name, $Url, $Count, $Ok, $Err) {
  [void]$sources.Add([ordered]@{ id=$Id; name=$Name; url=$Url; count=$Count; ok=$Ok; error=$Err; fetchedAt=(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') })
}

# ---------- Estonia: Eesti Padeli Liit on Rankedin ----------
$eeUrl = 'https://www.rankedin.com/en/organisation/calendar/1763/eesti-padeli-liit'
$eeName = 'Eesti Padeli Liit (Rankedin)'
try {
  $api = 'https://api.rankedin.com/v1/Organization/GetOrganisationEventsAsync?organisationId=1763&IsFinished=false&Language=en&skip=0&take=200'
  $ee = Get-JsonUrl $api
  $n = 0
  foreach ($e in @($ee.payload)) {
    # Example name: "EPL Meeste B-liiga | 5. etapp | FV Padel EACE | ****#"
    $parts = @(($e.eventName -split '\s*\|\s*') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '#' })
    if ($parts.Count -eq 0) { continue }
    $league = $parts[0]
    $tierLetter = if ($league -match '\b([A-D])-liiga') { $Matches[1] } else { $null }
    if (-not $AllEstonianLeagues -and $tierLetter -notin @('A','B','C','D')) { continue }
    $gender = if ($league -match 'Naiste') { 'women' } elseif ($league -match 'Meeste') { 'men' } else { 'open' }
    $stage  = if ($parts.Count -gt 1) { $parts[1] } else { '' }
    # A stage can be split into groups: "EPL Meeste D-liiga | 7. etapp | Grupp A | Padel Arenas"
    $rest   = @($parts | Select-Object -Skip 2)
    $group  = [string](@($rest | Where-Object { $_ -match '^Grupp\b' }) | Select-Object -First 1)
    $venue  = [string](@($rest | Where-Object { $_ -notmatch '^Grupp\b' }) | Select-Object -First 1)
    $tier   = if ($tierLetter) { "$tierLetter-liiga" } else { 'Other' }
    $shortLeague = ($league -replace '^EPL\s+', '' -replace 'Elizabeth Arden\s+', '')
    $name = if ($stage) { "$shortLeague, $stage" } else { $shortLeague }
    if ($group) { $name = "$name, $group" }
    $start = [datetime]$e.startDate; $end = [datetime]$e.endDate
    if ($end.Date -lt $Today) { continue }
    $deadline = $null; $status = 'unknown'
    try {
      $info = Get-JsonUrl ("https://api.rankedin.com/v1/tournament/GetInfoAsync?id=$($e.eventId)&language=en")
      $sb = $info.TournamentSidebarModel
      if ($sb.ClosingDate) { $deadline = [datetime]$sb.ClosingDate }
      if (-not $venue -and $sb.LocationName) { $venue = ([string]$sb.LocationName -split ',')[0].Trim() }
    } catch { Write-Warning "EE info $($e.eventId): $($_.Exception.Message)" }
    if ($deadline) { $status = if ($deadline -ge (Get-Date)) { 'open' } else { 'closed' } }
    if ($start.Date -le $Today -and $end.Date -ge $Today) { $status = 'live' }
    [void]$all.Add((New-Tournament -Country 'EE' -CountryName 'Estonia' -Source 'EPL' -SourceName 'Eesti Padeli Liit' `
      -Id $e.eventId -Name $name -Tier $tier -Classes @() -Gender $gender -City ([string]$e.city) -Venue $venue -HostCountry 'Estonia' `
      -Start $start -End $end -Url ('https://www.rankedin.com' + $e.eventUrl) -Status $status -Deadline $deadline -Organizer 'Eesti Padeli Liit'))
    $n++
  }
  Add-Source 'EPL' $eeName $eeUrl $n $true $null
} catch { Write-Warning "Estonia failed: $($_.Exception.Message)"; Add-Source 'EPL' $eeName $eeUrl 0 $false $_.Exception.Message }

# ---------- Finland: Suomen Padelliitto (Padelution page id 62) ----------
$fiUrl = 'https://www.padelution.com/events?pid=62'
$fiName = 'Suomen Padelliitto (Padelution)'
try {
  $seen = @{}; $n = 0; $page = 1; $curMonth = 0; $curYear = 0
  $rowRx = [regex]'<td class="p-2" colspan="3">\s*([A-Za-z]+)\s+(\d{4})\s*</td>|<tr class="hidden lg:table-row[^"]*" wire:key="desk-event-(\d+)">(.*?)</tr>'
  do {
    $html = (Get-Text "$fiUrl&page=$page") -replace '[\r\n]+', ' '
    $rows = 0
    foreach ($m in $rowRx.Matches($html)) {
      if ($m.Groups[1].Success) {
        if ($Months.ContainsKey($m.Groups[1].Value)) { $curMonth = $Months[$m.Groups[1].Value]; $curYear = [int]$m.Groups[2].Value }
        continue
      }
      $rows++
      $id = $m.Groups[3].Value; $row = $m.Groups[4].Value
      if ($seen.ContainsKey($id) -or $curMonth -eq 0) { continue }
      $seen[$id] = $true
      try {
        $dateTxt = Clean-Text ([regex]::Match($row, '<span>([^<]*)</span>').Groups[1].Value)
        $dm = [regex]::Match($dateTxt, '^(\d{1,2})\.(?:\s*([A-Za-z]{3})\.)?(?:\s*-\s*(\d{1,2})\.(?:\s*([A-Za-z]{3})\.)?)?')
        if (-not $dm.Success) { Write-Warning "FI $id unparsed date '$dateTxt'"; continue }
        $sd = [int]$dm.Groups[1].Value
        $sm = if ($dm.Groups[2].Success -and $MonAbbr.ContainsKey($dm.Groups[2].Value)) { $MonAbbr[$dm.Groups[2].Value] } else { $curMonth }
        $start = MakeDate $curYear $sm $sd
        $end = $start
        if ($dm.Groups[3].Success) {
          $ed = [int]$dm.Groups[3].Value
          $em = if ($dm.Groups[4].Success -and $MonAbbr.ContainsKey($dm.Groups[4].Value)) { $MonAbbr[$dm.Groups[4].Value] } elseif ($ed -lt $sd) { $sm + 1 } else { $sm }
          $ey = $curYear; if ($em -gt 12) { $em = 1; $ey++ }
          $end = MakeDate $ey $em $ed
        }
        $organizer = Clean-Text ([regex]::Match($row, 'class="text-gray-500">(.*?)</span>').Groups[1].Value)
        $lm = [regex]::Match($row, '<a href="(https://www\.padelution\.com/events/[^"?]+)"\s+class="transition">\s*<div[^>]*>(.*?)</div>')
        $url = $lm.Groups[1].Value; $name = Clean-Text $lm.Groups[2].Value
        if (-not $url) { continue }
        $classes = @([regex]::Matches($row, 'wire:key="eventclass-\d+-\d+">\s*<div[^>]*>(.*?)</div>') | ForEach-Object { Clean-Text $_.Groups[1].Value } | Where-Object { $_ })
        # The date cell has class "whitespace-nowrap font-medium ..."; the city cell has "whitespace-nowrap text-gray-100 align-top".
        $cityMatch = [regex]::Match($row, 'whitespace-nowrap text-gray-100 align-top">\s*(?:<!--.*?-->\s*)*<span>([^<]*)</span>')
        $city = if ($cityMatch.Success) { Clean-Text $cityMatch.Groups[1].Value } else { '' }
        if ($city -cmatch '^[A-Z\s-]+$') { $city = $TextInfo.ToTitleCase($city.ToLower()) }
        $tier = if ($name -match 'FPT\s*Gold' -or ($classes -contains 'MFPTG') -or ($classes -contains 'NFPTG')) { 'FPT Gold' }
                elseif ($name -match 'FPT\s*Silver' -or ($classes -contains 'MFPTS') -or ($classes -contains 'NFPTS')) { 'FPT Silver' }
                elseif ($name -match '\bSM\b|Suomen\s*mestaruus') { 'Finnish Championship' }
                else { 'Nationals' }
        $hasM = @($classes | Where-Object { $_ -cmatch '^M' }).Count -gt 0
        $hasN = @($classes | Where-Object { $_ -cmatch '^N' }).Count -gt 0
        $gender = if ($hasM -and $hasN) { 'open' } elseif ($hasM) { 'men' } elseif ($hasN) { 'women' } else { 'open' }
        if ($end.Date -lt $Today) { continue }
        $status = if ($start.Date -le $Today -and $end.Date -ge $Today) { 'live' } else { 'upcoming' }
        [void]$all.Add((New-Tournament -Country 'FI' -CountryName 'Finland' -Source 'SPL' -SourceName 'Suomen Padelliitto' `
          -Id $id -Name $name -Tier $tier -Classes $classes -Gender $gender -City $city -Venue '' -HostCountry 'Finland' `
          -Start $start -End $end -Url $url -Status $status -Deadline $null -Organizer $organizer))
        $n++
      } catch { Write-Warning "FI row $id skipped: $($_.Exception.Message)" }
    }
    $page++
  } while ($rows -gt 0 -and $page -le 15)
  Add-Source 'SPL' $fiName $fiUrl $n $true $null
} catch { Write-Warning "Finland failed: $($_.Exception.Message)"; Add-Source 'SPL' $fiName $fiUrl 0 $false $_.Exception.Message }

# ---------- Latvia: padelfederacija.lv (Tournated, list embedded in the Next.js payload) ----------
$lvUrl = 'https://padelfederacija.lv/lv-LV/tournaments'
$lvName = 'Latvijas Padel Federacija (padelfederacija.lv)'
try {
  $tz = $null
  foreach ($tzid in @('FLE Standard Time', 'Europe/Riga')) { try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById($tzid); break } catch {} }
  function ToRiga([string]$iso) {
    $utc = ([datetime]$iso).ToUniversalTime()
    if ($tz) { return [TimeZoneInfo]::ConvertTimeFromUtc($utc, $tz) } else { return $utc.AddHours(2) }
  }
  $html = Get-Text $lvUrl
  $i = $html.IndexOf('tournamentListBootstrap'); if ($i -lt 0) { throw 'bootstrap marker not found' }
  $startTok = '\"result\":{\"items\":['
  $s = $html.IndexOf($startTok, $i); if ($s -lt 0) { throw 'result start not found' }
  $endTok = '\"__typename\":\"PublicTournamentListResult\"}'
  $e2 = $html.IndexOf($endTok, $s); if ($e2 -lt 0) { throw 'result end not found' }
  $raw = $html.Substring($s, $e2 + $endTok.Length - $s)
  # The payload is a JS string literal: undo one level of escaping (\\ -> \, \" -> ") and keep JSON escapes intact.
  $nul = [string][char]0
  $json = '{' + $raw.Replace('\\', $nul).Replace('\"', '"').Replace($nul, '\') + '}'
  $res = ($json | ConvertFrom-Json).result
  $n = 0
  foreach ($t in @($res.items)) {
    if ($t.isHideFromCalendar) { continue }
    $start = ToRiga $t.startDate; $end = ToRiga $t.endDate
    if ($end.Date -lt $Today) { continue }
    $deadline = $null; if ($t.entryDeadline) { $deadline = ToRiga $t.entryDeadline }
    $title = [string]$t.title
    $tier = 'Other'
    if ($title -match '^(GOLD|SILVER|BRONZE)\s*-\s*(.+)$') { $tier = $TextInfo.ToTitleCase($Matches[1].ToLower()); $title = $Matches[2].Trim() }
    elseif ($title -match 'empion') { $tier = 'Championship' }
    $title = ($title -replace '\s*\[[^\]]*\]\s*', ' ').Trim()
    $venue = ''; $city = ''
    $venues = @($t.venues)
    if ($venues.Count -gt 0) { $venue = [string]$venues[0].title; $city = [string]$venues[0].city }
    if (-not $city -and $t.city) { $city = [string]$t.city }
    if ($venue -eq $title -or $venue -eq [string]$t.title) { $venue = '' }
    $cats = @(@($t.tournamentCategory) | ForEach-Object { [string]$_.category.name } | Where-Object { $_ })
    $hasM = @($cats | Where-Object { $_ -match 'V.rie' }).Count -gt 0
    $hasW = @($cats | Where-Object { $_ -match 'Siev' }).Count -gt 0
    $gender = if ($hasM -and $hasW) { 'open' } elseif ($hasM) { 'men' } elseif ($hasW) { 'women' } else { 'open' }
    $status = 'unknown'
    if ($deadline) { $status = if ($deadline -ge (Get-Date)) { 'open' } else { 'closed' } }
    if ($t.closeRegistration) { $status = 'closed' }
    if ($start.Date -le $Today -and $end.Date -ge $Today) { $status = 'live' }
    $organizer = ''; if ($t.organizer) { $organizer = [string]$t.organizer.organizationName }
    [void]$all.Add((New-Tournament -Country 'LV' -CountryName 'Latvia' -Source 'LPF' -SourceName 'Latvijas Padel Federacija' `
      -Id $t.id -Name $title -Tier $tier -Classes @() -Gender $gender -City $city -Venue $venue -HostCountry 'Latvia' `
      -Start $start -End $end -Url "https://padelfederacija.lv/lv-LV/tournament/$($t.id)" -Status $status -Deadline $deadline -Organizer $organizer))
    $n++
  }
  Add-Source 'LPF' $lvName $lvUrl $n $true $null
} catch { Write-Warning "Latvia failed: $($_.Exception.Message)"; Add-Source 'LPF' $lvName $lvUrl 0 $false $_.Exception.Message }

# ---------- FIP Bronze: padelfip.com Cupra FIP Tour calendar ----------
$fipUrl = 'https://www.padelfip.com/calendar-cupra-fip-tour/'
$fipName = 'Cupra FIP Tour calendar (padelfip.com)'
try {
  $n = 0; $seen = @{}
  $blockRx = [regex]'<div class="event-container">(.*?)<div class="event-right">'
  foreach ($year in @($Today.Year, ($Today.Year + 1))) {
    $html = $null
    try { $html = (Get-Text "$fipUrl`?events-year=$year") -replace '[\r\n]+', ' ' }
    catch {
      # The FIP site drops the connection for a year with no events yet; only the current year is required.
      if ($year -eq $Today.Year) { throw }
      Write-Warning "FIP $year not available: $($_.Exception.Message)"; continue
    }
    foreach ($b in $blockRx.Matches($html)) {
      $blk = $b.Groups[1].Value
      $tm = [regex]::Match($blk, '<div class="event-title"><span><a href="([^"]*)"[^>]*>(.*?)</a>')
      $title = Clean-Text $tm.Groups[2].Value; $url = $tm.Groups[1].Value
      if ($title -notmatch '\bBRONZE\b') { continue }
      if ($seen.ContainsKey($url)) { continue }; $seen[$url] = $true
      $dm = [regex]::Match($blk, 'From\s+(\d{2})/(\d{2})/(\d{4})\s+to\s+(\d{2})/(\d{2})/(\d{4})')
      if (-not $dm.Success) { Write-Warning "FIP unparsed date for $title"; continue }
      $start = MakeDate ([int]$dm.Groups[3].Value) ([int]$dm.Groups[2].Value) ([int]$dm.Groups[1].Value)
      $end   = MakeDate ([int]$dm.Groups[6].Value) ([int]$dm.Groups[5].Value) ([int]$dm.Groups[4].Value)
      if ($end.Date -lt $Today) { continue }
      $loc = Clean-Text ([regex]::Match($blk, '<div class="event-location">(.*?)</div>').Groups[1].Value)
      $city = $loc; $hostCountry = ''
      if ($loc -match '^(.*?)\s+-\s+(.*)$') { $city = $Matches[1].Trim(); $hostCountry = $Matches[2].Trim() }
      $st = [regex]::Match($blk, 'class="([a-z-]+) event-status"').Groups[1].Value
      $status = switch ($st) { 'registration-open' { 'open' } 'registration-closed' { 'closed' } 'live' { 'live' } 'finished' { 'finished' } default { 'upcoming' } }
      if ($start.Date -le $Today -and $end.Date -ge $Today -and $status -ne 'finished') { $status = 'live' }
      $name = Smart-TitleCase (($title -replace '^FIP\s+BRONZE\s+', '' -replace '^BRONZE\s+', '').Trim())
      [void]$all.Add((New-Tournament -Country 'FIP' -CountryName 'FIP Bronze' -Source 'FIP' -SourceName 'International Padel Federation' `
        -Id ($url.TrimEnd('/').Split('/')[-1]) -Name $name -Tier 'FIP Bronze' -Classes @() -Gender 'open' -City $city -Venue '' -HostCountry $hostCountry `
        -Start $start -End $end -Url $url -Status $status -Deadline $null -Organizer 'FIP'))
      $n++
    }
  }
  Add-Source 'FIP' $fipName ($fipUrl + '?events-year=' + $Today.Year) $n $true $null
} catch { Write-Warning "FIP failed: $($_.Exception.Message)"; Add-Source 'FIP' $fipName $fipUrl 0 $false $_.Exception.Message }

# ---------- write output ----------
$sorted = @($all.ToArray() | Sort-Object -Property @{Expression={$_.startDate}}, @{Expression={$_.endDate}}, @{Expression={$_.country}}, @{Expression={$_.name}})
$doc = [ordered]@{
  generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  sources     = @($sources.ToArray())
  tournaments = $sorted
}
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$OutDir = (Resolve-Path $OutDir).Path
$json = $doc | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $OutDir 'tournaments.json'), $json, $Utf8)
[IO.File]::WriteAllText((Join-Path $OutDir 'tournaments.js'), "window.PADEL_DATA = $json;`n", $Utf8)

Write-Host ("Wrote {0} tournaments to {1}" -f $sorted.Count, $OutDir)
foreach ($s in $sources) { Write-Host ("  {0,-4} {1,4}  {2}" -f $s.id, $s.count, $(if ($s.ok) { 'ok' } else { 'FAILED: ' + $s.error })) }
if (@($sources | Where-Object { -not $_.ok }).Count -gt 0) { exit 1 }
