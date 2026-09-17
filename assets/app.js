(function () {
  'use strict';

  var DATA = window.PADEL_DATA || { tournaments: [], sources: [], generatedAt: null };
  var COUNTRIES = [
    { code: 'EE', label: 'Estonia', flag: '🇪🇪' },
    { code: 'LV', label: 'Latvia', flag: '🇱🇻' },
    { code: 'FI', label: 'Finland', flag: '🇫🇮' },
    { code: 'FIP', label: 'FIP Bronze', flag: '🌍' }
  ];
  var DEFAULT_COUNTRIES = ['EE', 'LV', 'FI'];
  var MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  var MONTH_LONG = { format: function (d) { return MONTHS[d.getMonth()] + ' ' + d.getFullYear(); } };
  var MON = { format: function (d) { return MONTHS[d.getMonth()].slice(0, 3); } };
  var MONTH_SHORT = { format: function (d) { return MON.format(d) + ' ' + d.getFullYear(); } };
  var DAY_MON = { format: function (d) { return d.getDate() + ' ' + MON.format(d); } };
  var FULL = { format: function (d) { return DAY_MON.format(d) + ' ' + d.getFullYear(); } };

  var $countries = document.getElementById('countryChips');
  var $months = document.getElementById('monthChips');
  var $search = document.getElementById('search');
  var $summary = document.getElementById('summary');
  var $list = document.getElementById('list');
  var $sources = document.getElementById('sources');

  function parseDate(s) { var p = s.split('-'); return new Date(+p[0], +p[1] - 1, +p[2]); }
  function ym(d) { return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0'); }
  function ymToDate(k) { var p = k.split('-'); return new Date(+p[0], +p[1] - 1, 1); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }

  var today = new Date(); today.setHours(0, 0, 0, 0);

  // Only upcoming or ongoing tournaments, whatever the data file says.
  var items = DATA.tournaments.map(function (t) {
    return Object.assign({}, t, { start: parseDate(t.startDate), end: parseDate(t.endDate) });
  }).filter(function (t) { return t.end >= today; });

  var monthKeys = [];
  items.forEach(function (t) {
    var d = new Date(t.start.getFullYear(), t.start.getMonth(), 1);
    while (d <= t.end) { var k = ym(d); if (monthKeys.indexOf(k) < 0) monthKeys.push(k); d.setMonth(d.getMonth() + 1); }
  });
  monthKeys.sort();

  // ----- state (mirrored in the URL hash so views can be shared) -----
  var state = { countries: DEFAULT_COUNTRIES.slice(), month: 'all', q: '' };
  function readHash() {
    state = { countries: DEFAULT_COUNTRIES.slice(), month: 'all', q: '' };
    var h = location.hash.replace(/^#/, '');
    if (!h) return;
    var p = new URLSearchParams(h);
    if (p.has('c')) {
      var cs = p.get('c').split(',').filter(function (c) { return COUNTRIES.some(function (k) { return k.code === c; }); });
      if (cs.length) state.countries = cs;
    }
    if (p.has('m') && (p.get('m') === 'all' || monthKeys.indexOf(p.get('m')) >= 0)) state.month = p.get('m');
    if (p.has('q')) state.q = p.get('q');
  }
  function writeHash() {
    var p = new URLSearchParams();
    var isDefault = state.countries.slice().sort().join() === DEFAULT_COUNTRIES.slice().sort().join();
    if (!isDefault) p.set('c', state.countries.join(','));
    if (state.month !== 'all') p.set('m', state.month);
    if (state.q) p.set('q', state.q);
    var s = p.toString();
    history.replaceState(null, '', s ? '#' + s : location.pathname + location.search);
  }

  // ----- filters -----
  function matches(t) {
    if (state.countries.indexOf(t.country) < 0) return false;
    if (state.month !== 'all') {
      var m = ymToDate(state.month), mEnd = new Date(m.getFullYear(), m.getMonth() + 1, 0);
      if (t.start > mEnd || t.end < m) return false;
    }
    if (state.q) {
      var q = state.q.toLowerCase();
      var hay = [t.name, t.city, t.venue, t.hostCountry, t.countryName, t.tier, t.organizer, (t.classes || []).join(' ')].join(' ').toLowerCase();
      if (hay.indexOf(q) < 0) return false;
    }
    return true;
  }

  function chip(label, pressed, onClick, count) {
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'chip';
    b.setAttribute('aria-pressed', pressed ? 'true' : 'false');
    b.innerHTML = esc(label) + (count != null ? '<span class="n">' + count + '</span>' : '');
    b.addEventListener('click', onClick);
    return b;
  }

  function renderCountryChips() {
    $countries.innerHTML = '';
    COUNTRIES.forEach(function (c) {
      var n = items.filter(function (t) { return t.country === c.code; }).length;
      var on = state.countries.indexOf(c.code) >= 0;
      $countries.appendChild(chip(c.flag + ' ' + c.label, on, function () {
        var i = state.countries.indexOf(c.code);
        if (i >= 0) { if (state.countries.length > 1) state.countries.splice(i, 1); }
        else state.countries.push(c.code);
        update();
      }, n));
    });
  }

  function renderMonthChips() {
    $months.innerHTML = '';
    $months.appendChild(chip('All', state.month === 'all', function () { state.month = 'all'; update(); }));
    monthKeys.forEach(function (k) {
      var d = ymToDate(k);
      var label = d.getFullYear() === today.getFullYear() ? MON.format(d) : MONTH_SHORT.format(d);
      $months.appendChild(chip(label, state.month === k, function () { state.month = (state.month === k ? 'all' : k); update(); }));
    });
  }

  // ----- list -----
  function dateCell(t) {
    var s = t.start, e = t.end, d, m;
    if (s.getTime() === e.getTime()) { d = String(s.getDate()); m = MON.format(s); }
    else if (s.getMonth() === e.getMonth() && s.getFullYear() === e.getFullYear()) { d = s.getDate() + '–' + e.getDate(); m = MON.format(s); }
    else { d = DAY_MON.format(s) + ' – ' + DAY_MON.format(e); m = ''; }
    return '<div class="date"><span class="d">' + esc(d) + '</span>' + (m ? '<span class="m">' + esc(m) + '</span>' : '') + '</div>';
  }
  function statusCell(t) {
    var label = { open: 'Registration open', closed: 'Registration closed', live: 'Ongoing', finished: 'Finished', upcoming: '', unknown: '' }[t.status] || '';
    var until = '';
    if (t.deadline) {
      var dl = parseDate(t.deadline);
      until = (t.status === 'open' ? 'until ' : 'closed ') + DAY_MON.format(dl);
    }
    if (!label && !until) return '<div class="side"></div>';
    return '<div class="side"><span class="status ' + esc(t.status) + '">' + esc(label) + '</span>' + (until ? '<span class="until">' + esc(until) + '</span>' : '') + '</div>';
  }
  function row(t) {
    var c = COUNTRIES.filter(function (k) { return k.code === t.country; })[0] || { flag: '', label: t.countryName };
    var place = [];
    if (t.country === 'FIP') { place.push(t.city); if (t.hostCountry && t.hostCountry !== t.city) place.push(t.hostCountry); }
    else { if (t.city) place.push(t.city); if (t.venue) place.push(t.venue); }
    var meta = '<span class="flag">' + c.flag + '</span>' + esc(t.country === 'FIP' ? 'FIP' : c.label);
    place.filter(Boolean).forEach(function (p) { meta += '<span class="sep">·</span>' + esc(p); });
    if (t.country === 'FI' && t.organizer && t.organizer !== 'Suomen Padelliitto') meta += '<span class="sep">·</span>' + esc(t.organizer);

    var tags = '<span class="tag tier" style="--c:var(--' + t.country.toLowerCase() + ');--c-soft:var(--' + t.country.toLowerCase() + '-soft)">' + esc(t.tier) + '</span>';
    if (t.gender === 'men') tags += '<span class="tag">Men</span>';
    if (t.gender === 'women') tags += '<span class="tag">Women</span>';
    if (t.classes && t.classes.length) tags += '<span class="tag cls">' + esc(t.classes.join(' ')) + '</span>';

    return '<li class="row">' + dateCell(t) +
      '<div class="main"><a class="name" href="' + esc(t.url) + '" target="_blank" rel="noopener">' + esc(t.name) + '</a>' +
      '<div class="meta">' + meta + '</div><div class="tags">' + tags + '</div></div>' +
      statusCell(t) + '</li>';
  }

  function renderList() {
    var shown = items.filter(matches);
    var byMonth = {}, order = [];
    shown.forEach(function (t) {
      var k = ym(t.start);
      // When a month is selected, file long-running events under that month.
      if (state.month !== 'all') k = state.month;
      if (!byMonth[k]) { byMonth[k] = []; order.push(k); }
      byMonth[k].push(t);
    });
    order.sort();
    var html = '';
    order.forEach(function (k) {
      html += '<h2 class="month">' + esc(MONTH_LONG.format(ymToDate(k))) + '</h2><ul class="rows">' + byMonth[k].map(row).join('') + '</ul>';
    });
    if (!shown.length) html = '<div class="empty">No tournaments match these filters.<br><button type="button" class="chip" id="reset">Reset filters</button></div>';
    $list.innerHTML = html;
    var r = document.getElementById('reset');
    if (r) r.addEventListener('click', function () { state = { countries: DEFAULT_COUNTRIES.slice(), month: 'all', q: '' }; $search.value = ''; update(); });
    $summary.textContent = shown.length + (shown.length === 1 ? ' tournament' : ' tournaments') + (state.month !== 'all' ? ' in ' + MONTH_LONG.format(ymToDate(state.month)) : ' upcoming');
  }

  function renderSources() {
    var gen = DATA.generatedAt ? FULL.format(new Date(DATA.generatedAt)) : 'unknown';
    var html = '<ul>';
    (DATA.sources || []).forEach(function (s) {
      html += '<li>' + (s.ok ? '' : '<span class="warn">⚠ </span>') + '<a href="' + esc(s.url) + '" target="_blank" rel="noopener">' + esc(s.name) + '</a>' +
        (s.ok ? ' · ' + s.count + ' upcoming' : ' · failed to load last time') + '</li>';
    });
    html += '</ul><p>Data updated ' + esc(gen) + '. Estonia shows the A, B, C and D leagues.</p>';
    $sources.innerHTML = html;
  }

  function update() { writeHash(); renderCountryChips(); renderMonthChips(); renderList(); }

  var debounce;
  $search.addEventListener('input', function () {
    clearTimeout(debounce);
    debounce = setTimeout(function () { state.q = $search.value.trim(); update(); }, 120);
  });
  window.addEventListener('hashchange', function () { readHash(); $search.value = state.q; update(); });

  // ----- legend -----
  var $legendToggle = document.getElementById('legendToggle');
  var $legend = document.getElementById('legend');
  $legendToggle.addEventListener('click', function () {
    var open = $legend.hidden;
    $legend.hidden = !open;
    $legendToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    $legendToggle.textContent = open ? 'Hide levels' : 'Levels explained';
  });

  // ----- theme (dark by default, light on request, remembered per browser) -----
  var $theme = document.getElementById('themeToggle');
  function applyTheme(t) {
    if (t === 'light') document.documentElement.setAttribute('data-theme', 'light');
    else document.documentElement.removeAttribute('data-theme');
    $theme.textContent = t === 'light' ? '☾' : '☀';
    $theme.setAttribute('aria-label', t === 'light' ? 'Switch to dark theme' : 'Switch to light theme');
  }
  var savedTheme = null;
  try { savedTheme = localStorage.getItem('padel-theme'); } catch (e) {}
  applyTheme(savedTheme === 'light' ? 'light' : 'dark');
  $theme.addEventListener('click', function () {
    var next = document.documentElement.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    applyTheme(next);
    try { localStorage.setItem('padel-theme', next); } catch (e) {}
  });

  readHash();
  $search.value = state.q;
  renderSources();
  update();
})();
