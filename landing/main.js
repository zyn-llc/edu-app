/* =========================================================================
   main.js — Topag'on landing
   =========================================================================
   TUZILISH
     0. Shartlar va yordamchi funksiyalar
     1. Matnni content.js dan joylashtirish (tarjima uchun)
     2. Hero — niqob bilan ochilish + javob doiralari (canvas)
     3. Sinf zinasi — BITTA pinlangan ScrollTrigger timeline
     4. Fanlar tokchasi — gorizontal surish + tezlikka bog'liq qiyshayish
     5. Bitta savoldan butun bankgacha — canvas maydon
     6. Reyting — FLIP, bir marta
   ========================================================================= */
(function () {
  'use strict';

  /* ======================================================== 0. Shartlar */

  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var hasGsap = typeof window.gsap !== 'undefined' &&
                typeof window.ScrollTrigger !== 'undefined';

  /* Pinlangan scrub faqat kengroq ekranda. Telefonda o'rtacha Android
     qurilmada scrub sakraydi — u yerda oddiy kirish animatsiyasi ishlaydi. */
  var wide = window.matchMedia('(min-width: 900px)').matches;

  /* Harakat umuman yoqiladimi. `.js-motion` klassi CSS dagi boshlang'ich
     ("from") holatlarini yoqadi — u yo'q bo'lsa sahifa to'liq ko'rinadi. */
  var motion = !reduce && hasGsap;

  var C = window.CONTENT || null;

  function $(sel, root) { return (root || document).querySelector(sel); }
  function $$(sel, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(sel));
  }

  /* 13447 -> "13 447". Ingichka bo'shliq (U+2009): vergul o'zbek tilida
     o'nlik ajratgich, shuning uchun mingliklar uchun ishlatilmaydi. */
  function grouped(n) {
    var s = String(Math.round(n));
    var out = '';
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 === 0) out += ' ';
      out += s[i];
    }
    return out;
  }

  function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

  /* ============================================ 1. Matnni joylashtirish */
  /*
     content.js — matnning yagona manbasi. HTML da ham matn bor (JS'siz
     o'qish uchun), lekin JS yuklanganda quyidagi funksiya uni content.js
     dan qayta yozadi. Ruscha versiya uchun faqat content.js almashadi.
  */
  function hydrate() {
    if (!C) return;

    var t;
    if ((t = $('#hero-sub')))   t.textContent = C.hero.sub;
    if ((t = $('#hero-cta')))   t.textContent = C.hero.cta;
    if ((t = $('#hero-proof'))) t.textContent = C.hero.proof;
    if ((t = $('#zina-lead')))  t.textContent = C.ladder.lead;

    /* Zina bosqichlari */
    $$('#rungs .rung').forEach(function (el, i) {
      var r = C.ladder.rungs[i];
      if (!r) return;
      $('.rung__grade', el).textContent = r.grade + '-sinf';
      var num = $('.num', el);
      num.setAttribute('data-count', String(r.count));
      num.textContent = grouped(r.count);
      $('.rung__label', el).textContent = C.ladder.counterLabel;
      $('.rung__line', el).textContent = r.line;
      var chips = $('.chips', el);
      chips.innerHTML = '';
      r.subjects.forEach(function (s) {
        var li = document.createElement('li');
        li.textContent = s;
        chips.appendChild(li);
      });
    });

    /* Fan kartalari */
    $$('#shelf-track .scard').forEach(function (el, i) {
      var s = C.shelf.subjects[i];
      if (!s) return;
      $('.scard__name', el).textContent = s.name;
      $('.scard__grades', el).textContent = s.gradeRange;
      $('.scard__num .num', el).textContent = grouped(s.count);
      $('.scard__unit', el).textContent = C.shelf.countLabel;
    });

    /* Asosiy tugma. Play listing chiqmaguncha u brauzerdagi ilovaga
       olib boradi — mavjud bo'lmagan sahifaga yuborish yolg'on bo'lardi. */
    var cta = $('#hero-cta');
    if (cta && C.hero.ctaHref) cta.setAttribute('href', C.hero.ctaHref);

    /* Play Store badge'i. Manzil hali yo'q bo'lsa (`#`) — bosilmaydigan
       "Tez orada" holatiga o'tadi: `aria-disabled` + `tabindex="-1"`,
       ya'ni klaviatura bilan ham unga tushib qolinmaydi. */
    var dl = $('#dl-link');
    if (dl) {
      var href = C.footer.downloadHref;
      if (href && href !== '#') {
        dl.setAttribute('href', href);
      } else {
        dl.classList.add('is-soon');
        dl.setAttribute('aria-disabled', 'true');
        dl.setAttribute('tabindex', '-1');
        dl.removeAttribute('href');
        var small = $('.badge__small', dl);
        if (small) small.textContent = C.footer.downloadSoon || 'Tez orada';
      }
    }

    var web = $('a.flink[href*="topagon"]');
    if (web && C.footer.webHref) web.setAttribute('href', C.footer.webHref);
  }

  hydrate();

  /* Harakat yo'q bo'lsa — shu yerda to'xtaymiz. Sahifa allaqachon to'liq
     ko'rinib turibdi, chunki CSS standarti yakuniy holat. */
  if (!motion) return;

  document.documentElement.classList.add('js-motion');

  gsap.registerPlugin(ScrollTrigger);

  /* Silliq scroll. Lenis bo'lmasa ham hammasi ishlaydi — u faqat his. */
  if (typeof window.Lenis !== 'undefined' && wide) {
    var lenis = new window.Lenis({ duration: 1.05, smoothWheel: true });
    lenis.on('scroll', ScrollTrigger.update);
    gsap.ticker.add(function (time) { lenis.raf(time * 1000); });
    gsap.ticker.lagSmoothing(0);
  }

  /* ================================================================ 2. HERO */

  /* Yuklanishdagi ochilish — scroll bilan bog'liq emas.
     Stagger 80 ms, egri chiziq CSS dagi --e-out bilan bir xil. */
  (function heroIntro() {
    var ease = 'cubic-bezier(.16,.84,.34,1)';
    var tl = gsap.timeline({ defaults: { ease: ease } });

    tl.to('.hero__brand', { opacity: 1, duration: .5 }, 0)
      .to('.hero__title .line__in', {
        y: '0%', duration: .95, stagger: 0.08
      }, 0.1)
      .to('.hero__sub',     { opacity: 1, duration: .6 }, 0.55)
      .to('.hero__actions', { opacity: 1, duration: .6 }, 0.68)
      .to('.hero__hint',    { opacity: 1, duration: .6 }, 0.85);
  })();

  /*
     Javob doiralari (A/B/C/D) — hero orqasidagi ambient qatlam.
     Har qatorda bitta doira sekin to'ladi: bu imtihon varag'ining o'zi.
     Canvas, chunki yuzlab DOM tugun scroll'ni o'ldiradi.
     Ekrandan chiqsa — to'xtaydi (batareya).
  */
  (function bubbles() {
    var cv = $('#bubbles');
    if (!cv) return;
    var ctx = cv.getContext('2d');
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var rows = [], raf = null, running = false, W = 0, H = 0;
    var LETTERS = ['A', 'B', 'C', 'D'];

    function build() {
      W = cv.clientWidth; H = cv.clientHeight;
      cv.width = Math.round(W * dpr);
      cv.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      rows = [];
      var step = 44;
      var count = Math.ceil(H / step) + 1;
      for (var i = 0; i < count; i++) {
        rows.push({
          y: i * step + 22,
          x: 24 + Math.random() * Math.max(0, W - 200),
          speed: 0.06 + Math.random() * 0.10,
          correct: Math.floor(Math.random() * 4),
          fill: 0,
          delay: Math.random() * 900
        });
      }
    }

    function frame(t) {
      ctx.clearRect(0, 0, W, H);
      ctx.font = '10px "JetBrains Mono", monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';

      for (var i = 0; i < rows.length; i++) {
        var r = rows[i];
        r.x += r.speed;
        if (r.x > W + 120) r.x = -120;

        if (r.delay > 0) r.delay -= 16;
        else if (r.fill < 1) r.fill += 0.004;

        for (var j = 0; j < 4; j++) {
          var cx = r.x + j * 30, cy = r.y;
          if (cx < -20 || cx > W + 20) continue;

          ctx.beginPath();
          ctx.arc(cx, cy, 9, 0, Math.PI * 2);
          ctx.strokeStyle = 'rgba(154,166,178,0.30)';
          ctx.lineWidth = 1;
          ctx.stroke();

          if (j === r.correct && r.fill > 0) {
            ctx.beginPath();
            ctx.arc(cx, cy, 9 * Math.min(r.fill, 1), 0, Math.PI * 2);
            ctx.fillStyle = 'rgba(22,53,127,0.55)';
            ctx.fill();
          }

          ctx.fillStyle = 'rgba(154,166,178,0.35)';
          ctx.fillText(LETTERS[j], cx, cy + 0.5);
        }
      }
      raf = requestAnimationFrame(frame);
    }

    function start() { if (!running) { running = true; raf = requestAnimationFrame(frame); } }
    function stop() { running = false; if (raf) cancelAnimationFrame(raf); raf = null; }

    build();
    start();

    window.addEventListener('resize', function () { build(); }, { passive: true });

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        entries[0].isIntersecting ? start() : stop();
      }, { threshold: 0 }).observe(cv);
    }
  })();

  /* ======================================================= 3. SINF ZINASI */
  /*
     SIGNATURE BO'LIM.

     ScrollTrigger #1 — `.ladder__stage` ni ~300vh ga pinlaydi va BITTA
     timeline'ni scrub qiladi. Timeline uchta narsani BIR VAQTDA boshqaradi:
       a) markerning zina bo'ylab yuqoriga siljishi (SVG `transform`);
       b) faol bosqich kartasining crossfade + 8px y siljishi;
       c) raqamning 0 dan haqiqiy qiymatgacha sanalishi.

     Nega yettita alohida trigger EMAS: yettita trigger yettita mustaqil
     progress beradi va ular chegaralarda bir-biriga urishadi — marker
     sakraydi. Bitta scrub esa bitta uzluksiz progress.

     Telefonda (wide === false) pin YO'Q: bosqichlar oddiy vertikal ro'yxat
     bo'lib qoladi va har biri odatdagi kirish triggeri bilan chiqadi.
  */
  (function ladder() {
    var stage = $('#ladder-stage');
    var rungs = $$('#rungs .rung');
    var marker = $('#rail-marker');
    if (!stage || !rungs.length) return;

    if (!wide) {
      /* ScrollTrigger #1a — mobil: har bosqich ko'ringanda bir marta chiqadi. */
      rungs.forEach(function (el) {
        gsap.to(el, {
          opacity: 1, y: 0, duration: .5, ease: 'power2.out',
          scrollTrigger: { trigger: el, start: 'top 85%', once: true }
        });
      });
      gsap.set(rungs, { y: 8 });
      return;
    }

    stage.classList.add('js-ladder');
    document.documentElement.classList.add('js-ladder');

    /* SVG dagi rung koordinatalari (pastdan yuqoriga: 5-sinf → 11-sinf). */
    var RUNG_Y = [640, 536, 432, 328, 224, 120, 36];
    var startY = RUNG_Y[0];

    gsap.set(rungs, { opacity: 0, y: 8 });
    gsap.set(rungs[0], { opacity: 1, y: 0 });

    var tl = gsap.timeline({
      scrollTrigger: {
        trigger: stage,
        start: 'top top',
        end: '+=300%',        /* ~300vh scroll */
        pin: true,
        pinSpacing: true,
        scrub: 1,
        anticipatePin: 1,
        invalidateOnRefresh: true
      }
    });

    /* Birinchi bosqichning raqami — timeline boshida sanaladi. */
    addCounter(tl, rungs[0], 0);

    for (var i = 1; i < rungs.length; i++) {
      var at = (i - 1) / (rungs.length - 1);

      /* (a) marker yuqoriga */
      tl.to(marker, {
        y: RUNG_Y[i] - startY,
        duration: 1, ease: 'none'
      }, at * (rungs.length - 1));

      /* (b) eski bosqich chiqadi, yangisi kiradi — crossfade + 8px */
      tl.to(rungs[i - 1], { opacity: 0, y: -8, duration: .4 }, at * (rungs.length - 1) + .1);
      tl.fromTo(rungs[i],
        { opacity: 0, y: 8 },
        { opacity: 1, y: 0, duration: .4 },
        at * (rungs.length - 1) + .3);

      /* (c) raqam sanaladi */
      addCounter(tl, rungs[i], at * (rungs.length - 1) + .3);
    }

    function addCounter(timeline, rung, pos) {
      var el = $('.num', rung);
      if (!el) return;
      var target = parseInt(el.getAttribute('data-count'), 10) || 0;
      var proxy = { v: 0 };
      timeline.to(proxy, {
        v: target,
        duration: .6,
        ease: 'none',
        onUpdate: function () { el.textContent = grouped(proxy.v); }
      }, pos);
    }
  })();

  /* ==================================================== 4. FANLAR TOKCHASI */
  /*
     ScrollTrigger #2 — `.shelf` ni pinlaydi va tokchani gorizontal suradi.
     Surish masofasi = trek kengligi − ko'rinadigan kenglik, ya'ni oxirgi
     karta aynan o'ng chetda to'xtaydi.

     Qiyshayish (skew) `ScrollTrigger.getVelocity()` dan olinadi va QATTIQ
     cheklanadi: ±6°. Cheklanmasa, tez g'ildirakda qiymat minglarga chiqadi
     va kartalar buzilib ko'rinadi. Scroll to'xtaganda 0 ga qaytadi.

     Telefonda pin YO'Q — u yerda tokcha barmoq bilan suriladi (CSS
     `overflow-x: auto` + scroll-snap), ya'ni tabiiyroq.
  */
  (function shelf() {
    var section = $('.shelf');
    var viewport = $('#shelf-viewport');
    var track = $('#shelf-track');
    var cards = $$('.scard', track);
    if (!section || !track || !cards.length) return;

    if (!wide) {
      /* ScrollTrigger #2a — mobil: kartalar ketma-ket chiqadi. */
      gsap.set(cards, { y: 12 });
      gsap.to(cards, {
        opacity: 1, y: 0, duration: .5, stagger: .06, ease: 'power2.out',
        scrollTrigger: { trigger: section, start: 'top 75%', once: true }
      });
      return;
    }

    document.documentElement.classList.add('js-pinned-shelf');
    gsap.set(cards, { opacity: 1 });

    function distance() {
      return Math.max(0, track.scrollWidth - viewport.clientWidth);
    }

    var st = gsap.to(track, {
      x: function () { return -distance(); },
      ease: 'none',
      scrollTrigger: {
        trigger: section,
        start: 'top top',
        end: function () { return '+=' + (distance() + window.innerHeight * 0.6); },
        pin: true,
        scrub: 1,
        invalidateOnRefresh: true,
        onUpdate: onScroll,
        onLeave: settle,
        onLeaveBack: settle
      }
    });

    var setSkew = gsap.quickTo(cards, 'skewX', { duration: .35, ease: 'power3.out' });

    function onScroll(self) {
      /* getVelocity() px/soniya qaytaradi. 900 ga bo'lish — 1° ga ~900px/s.
         Keyin ±6° ga qisamiz: undan kattasi "buzilgan" ko'rinadi. */
      var deg = clamp(ScrollTrigger.getVelocity() / -900, -6, 6);
      setSkew(deg);
    }
    function settle() { setSkew(0); }

    /* Scroll to'xtasa qiyshayish 0 ga qaytsin — `onUpdate` chaqirilmay
       qolgan holat uchun zaxira. */
    var idle;
    window.addEventListener('scroll', function () {
      clearTimeout(idle);
      idle = setTimeout(settle, 140);
    }, { passive: true });

    void st;
  })();

  /* ================================ 5. BITTA SAVOLDAN BUTUN BANKGACHA */
  /*
     ScrollTrigger #3 — `.zoom__stage` ni pinlaydi. Progress bo'yicha:
       * savol kartasi 1 → 0.13 ga kichrayadi (`scale`, layout emas);
       * orqada canvas maydonida savol to'rtburchaklari markazdan
         tashqariga ko'payib boradi;
       * oxirida sarlavha ochiladi.

     Nega canvas: 22 000 ta DOM tugun brauzerni o'ldiradi. Bu yerda bitta
     canvas va bitta `requestAnimationFrame` — progress o'zgarganda qayta
     chiziladi, boshqa paytda tinch turadi.

     Telefonda pin YO'Q: karta va sarlavha oddiy kirish bilan chiqadi.
  */
  (function zoomOut() {
    var stage = $('#zoom-stage');
    var card = $('#zoom-card');
    var caption = $('#zoom-caption');
    var cv = $('#field');
    if (!stage || !card || !cv) return;

    if (!wide) {
      /* ScrollTrigger #3a — mobil: sarlavha ko'ringanda chiqadi. */
      gsap.to(caption, {
        opacity: 1, y: 0, duration: .6, ease: 'power2.out',
        scrollTrigger: { trigger: caption, start: 'top 85%', once: true }
      });
      gsap.set(caption, { y: 12 });
      cv.style.display = 'none';   /* mobil GPU'ni bekorga qizdirmaymiz */
      return;
    }

    var ctx = cv.getContext('2d');
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var W = 0, H = 0;

    function size() {
      W = cv.clientWidth; H = cv.clientHeight;
      cv.width = Math.round(W * dpr);
      cv.height = Math.round(H * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    size();
    window.addEventListener('resize', size, { passive: true });

    /* Maydon: markazdan halqa-halqa kengayadigan to'rtburchaklar to'ri.
       `p` — 0..1 progress. */
    function draw(p) {
      ctx.clearRect(0, 0, W, H);
      if (p <= 0.04) return;

      var cell = 26, gap = 6;
      var cols = Math.ceil(W / (cell + gap)) + 2;
      var rows = Math.ceil(H / (cell + gap)) + 2;
      var cx = cols / 2, cy = rows / 2;
      var maxR = Math.sqrt(cx * cx + cy * cy);
      var reach = maxR * p;

      var ox = (W - cols * (cell + gap)) / 2;
      var oy = (H - rows * (cell + gap)) / 2;

      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          var dx = c - cx, dy = r - cy;
          var d = Math.sqrt(dx * dx + dy * dy);
          if (d > reach) continue;

          /* Markazdagi katak — savol kartasining o'zi, uni chizmaymiz. */
          if (d < 1.6) continue;

          var edge = clamp((reach - d) / 2, 0, 1);
          var x = ox + c * (cell + gap);
          var y = oy + r * (cell + gap);

          ctx.fillStyle = 'rgba(251,250,246,' + (0.10 + 0.12 * edge) + ')';
          ctx.fillRect(x, y, cell, cell * 0.62);

          /* Har o'ninchi katakda qizil belgi — "tekshirilgan" ma'nosi. */
          if ((r * cols + c) % 11 === 0 && edge > .6) {
            ctx.fillStyle = 'rgba(193,54,47,0.55)';
            ctx.fillRect(x + cell - 7, y + 3, 4, 4);
          }
        }
      }
    }

    gsap.timeline({
      scrollTrigger: {
        trigger: stage,
        start: 'top top',
        end: '+=260%',
        pin: true,
        scrub: 1,
        invalidateOnRefresh: true,
        onUpdate: function (self) { draw(self.progress); }
      }
    })
      .fromTo(card, { scale: 1 }, { scale: 0.13, ease: 'power1.in', duration: 1 }, 0)
      .fromTo(caption, { opacity: 0, y: 12 }, { opacity: 1, y: 0, duration: .3 }, .72);
  })();

  /* ============================================================ 6. REYTING */
  /*
     ScrollTrigger #4 — jadval ko'ringanda BIR MARTA ishlaydi (`once: true`).
     Tsikl ATAYLAB yo'q: takrorlanadigan animatsiya soxta ko'rinadi va
     "bu shunchaki bezak" degan xabar beradi.

     Texnika — FLIP: avval qatorlarning eski o'rni o'lchanadi (First),
     keyin DOM da tartib almashtiriladi (Last), farq `transform` ga
     yoziladi (Invert) va nolga animatsiya qilinadi (Play). Layout
     xususiyatlari animatsiya qilinmaydi — faqat `transform`.
  */
  (function board() {
    var body = $('#board-body');
    if (!body) return;
    var rows = $$('tr', body);
    if (rows.length < 2) return;

    function play() {
      /* First — eski o'rinlar */
      var first = {};
      rows.forEach(function (r) {
        first[r.getAttribute('data-id')] = r.getBoundingClientRect().top;
      });

      /* XP ni yangilaymiz va yangi tartibni hisoblaymiz */
      var data = rows.map(function (r) {
        return {
          el: r,
          id: r.getAttribute('data-id'),
          to: parseInt($('.board__xp', r).getAttribute('data-to'), 10) || 0
        };
      });
      data.sort(function (a, b) { return b.to - a.to; });

      /* Last — DOM tartibini almashtiramiz */
      data.forEach(function (d, i) {
        body.appendChild(d.el);
        $('.board__rank', d.el).textContent = String(i + 1);
      });

      /* Invert + Play */
      data.forEach(function (d) {
        var now = d.el.getBoundingClientRect().top;
        var dy = first[d.id] - now;
        if (!dy) return;
        gsap.fromTo(d.el,
          { y: dy },
          { y: 0, duration: .75, ease: 'power3.inOut' });
      });

      /* XP raqamlari ham yangi qiymatga o'sadi */
      data.forEach(function (d) {
        var cell = $('.board__xp', d.el);
        var from = parseInt(cell.getAttribute('data-from'), 10) || 0;
        if (from === d.to) return;
        var proxy = { v: from };
        gsap.to(proxy, {
          v: d.to, duration: .75, ease: 'power2.out',
          onUpdate: function () { cell.textContent = grouped(proxy.v); }
        });
      });
    }

    ScrollTrigger.create({
      trigger: '#board-table',
      start: 'top 72%',
      once: true,
      onEnter: function () { setTimeout(play, 420); }
    });
  })();

  /* Shriftlar kech kelsa o'lchamlar siljiydi — pinlar qayta hisoblansin. */
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function () { ScrollTrigger.refresh(); });
  }

})();
