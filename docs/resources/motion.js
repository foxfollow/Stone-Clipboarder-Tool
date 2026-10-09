/*
 * Landing page motion, shared by index.html and index-ua.html.
 * Loaded with `defer`, so it runs after the page's inline script has defined
 * openModal, closeModal, toggleTheme and showCopied, and before its
 * DOMContentLoaded handler starts the scroll reveal.
 * With "reduce motion" on, only the static Quick Picker demo is built.
 */
(() => {
    const root = document.documentElement;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    const finePointer = matchMedia('(hover: hover) and (pointer: fine)').matches;
    const $ = (sel, el = document) => el.querySelector(sel);
    const $$ = (sel, el = document) => [...el.querySelectorAll(sel)];
    const EASE_OUT = 'cubic-bezier(0.16, 1, 0.3, 1)';

    const hero = $('main > section');

    // ---------- Quick Picker demo (hero) ----------
    // Mirrors the app's Quick Picker: search, type filters with counts, two-line
    // rows, the Return / OCR hints on the selected row and the footer shortcuts.
    // It shows the app's own English UI on both pages.
    const DEMO_ITEMS = [
        { type: 'text', title: 'brew install stone-clipboarder-tool' },
        { type: 'image', title: '[Image - 1470×923]', thumb: 'resources/index/sct-dark-basicwindow.png' },
        { type: 'text', title: 'git remote add origin https://github.com/foxfollow/Stone-Clipboarder-Tool.git' },
        { type: 'file', title: '[File - invite.ics (5 KB)]' },
        { type: 'text', title: '2fe05c3029ae3f5a2d8e9ac3831c6e7dd84e44de' },
        { type: 'image', title: '[Image - 815×813]', thumb: 'resources/index/StoneClipboarderIcon2-iOS-Default-1024x1024@1x.png' },
        { type: 'text', title: 'Never lose what you copy.' },
        { type: 'text', title: 'https://foxfollow.github.io/Stone-Clipboarder-Tool/' },
    ];
    const TYPE_LABEL = { text: 'Text', image: 'Image', file: 'File' };
    const VISIBLE_ROWS = 4;
    const INITIAL_AGES = [8, 425, 571, 631]; // seconds, top row first

    function initClipDemo() {
        const host = $('.clip-demo');
        if (!host) return;
        const counts = { all: 2818, favs: 5, text: 2162, image: 602, file: 54 };
        const fmt = n => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
        const chip = (key, label, active) =>
            `<span class="qp-chip${active ? ' on' : ''}" data-k="${key}">${label} <b>${fmt(counts[key])}</b></span>`;
        host.innerHTML =
            '<div class="qp"><div class="qp-grip"></div>' +
            '<div class="qp-search"><i class="fa-solid fa-magnifying-glass"></i><span class="qp-caret"></span><span class="qp-ph">Search clipboard...</span></div>' +
            '<div class="qp-chips">' + chip('all', 'All', true) + chip('favs', '<i class="fa-solid fa-heart"></i> Favs') +
            chip('text', 'Text') + chip('image', 'Images') + chip('file', 'Files') +
            '<span class="qp-switch"><kbd>⇥</kbd> switch</span></div>' +
            '<div class="qp-list"></div>' +
            '<div class="qp-foot"><span class="qp-disk"><b></b> + 5 <i class="fa-solid fa-heart"></i> on Disk</span>' +
            '<span class="qp-hints"><span><kbd>⇧↑↓</kbd> Multi-select</span><span><kbd>ESC</kbd> Close</span>' +
            '<span class="qp-x"><kbd>⌥␣</kbd> ♡</span><span class="qp-x"><kbd>⌥P</kbd> <i class="fa-solid fa-thumbtack"></i></span>' +
            '<span class="qp-x"><kbd>␣</kbd> Preview</span></span></div></div>';
        const list = $('.qp-list', host);
        const disk = $('.qp-disk b', host);
        const rowHeight = () => parseFloat(getComputedStyle(host).getPropertyValue('--row')) || 64;

        const age = s => s < 60 ? `${s} sec` : `${Math.floor(s / 60)} min, ${s % 60} sec`;
        function makeRow(item, seconds) {
            const row = document.createElement('div');
            row.className = 'qp-row';
            row._item = item;
            row._born = Date.now() - seconds * 1000;
            const tile = item.type === 'image'
                ? `<span class="qp-tile thumb"><img src="${item.thumb}" alt=""></span>`
                : `<span class="qp-tile ${item.type}"><i class="fa-regular ${item.type === 'file' ? 'fa-file' : 'fa-file-lines'}"></i></span>`;
            const hint = item.type === 'image'
                ? '<span class="qp-hint">OCR: <kbd>⌥↩</kbd> <kbd>↩</kbd></span>'
                : '<span class="qp-hint"><kbd>↩</kbd></span>';
            row.innerHTML = tile + '<span class="qp-txt"><span class="qp-title"></span><span class="qp-meta"></span></span>' + hint;
            $('.qp-title', row).textContent = item.title;
            return row;
        }

        const rows = [];
        function refreshMeta() {
            const now = Date.now();
            rows.forEach(row => {
                $('.qp-meta', row).textContent =
                    `${age(Math.max(0, Math.round((now - row._born) / 1000)))} · ${TYPE_LABEL[row._item.type]}`;
            });
            disk.textContent = fmt(counts.all - counts.favs);
            $$('.qp-chip', host).forEach(c => { c.querySelector('b').textContent = fmt(counts[c.dataset.k]); });
        }
        function layout() {
            const h = rowHeight();
            rows.forEach((row, i) => {
                row.style.transform = `translateY(${i * h}px)`;
                row.classList.toggle('sel', i === 0);
            });
        }

        let next = 0;
        for (; next < VISIBLE_ROWS; next++) {
            const row = makeRow(DEMO_ITEMS[next], INITIAL_AGES[next]);
            list.append(row);
            rows.push(row);
        }
        layout();
        refreshMeta();
        if (reduce) return;

        function step() {
            const item = DEMO_ITEMS[next++ % DEMO_ITEMS.length];
            const row = makeRow(item, 0);
            row.classList.add('enter');
            row.style.transform = `translateY(${-rowHeight() * 0.6}px) scale(0.97)`;
            list.prepend(row);
            rows.unshift(row);
            row.getBoundingClientRect(); // commit the start position before moving
            layout();
            row.classList.remove('enter');
            if (rows.length > VISIBLE_ROWS) {
                const old = rows[rows.length - 1];
                old.classList.add('leave');
                setTimeout(() => { old.remove(); rows.splice(rows.indexOf(old), 1); }, 700);
            }
            counts.all++;
            counts[item.type]++;
            refreshMeta();
            ['all', item.type].forEach(k => {
                const c = $(`.qp-chip[data-k="${k}"]`, host);
                c.classList.remove('bump');
                void c.offsetWidth;
                c.classList.add('bump');
            });
        }

        // Cycle only while the demo is on screen, the tab is visible and the pointer isn't resting on it.
        let timer = 0, clock = 0, onScreen = false, hovered = false;
        const sync = () => {
            const run = onScreen && !hovered && !document.hidden;
            if (run && !timer) { timer = setInterval(step, 2800); clock = setInterval(refreshMeta, 1000); }
            if (!run && timer) { clearInterval(timer); clearInterval(clock); timer = clock = 0; }
        };
        new IntersectionObserver(([e]) => { onScreen = e.isIntersecting; sync(); }).observe(host);
        document.addEventListener('visibilitychange', sync);
        host.addEventListener('pointerenter', () => { hovered = true; sync(); });
        host.addEventListener('pointerleave', () => { hovered = false; sync(); });
        addEventListener('resize', layout);
    }

    // ---------- Hero headline ----------
    function splitHeadline() {
        const h1 = $('.hero-title');
        if (!h1 || h1.children.length) return;
        const words = h1.textContent.trim().split(/\s+/);
        h1.setAttribute('aria-label', words.join(' '));
        h1.textContent = '';
        words.forEach((word, i) => {
            const span = document.createElement('span');
            span.className = 'hw';
            span.setAttribute('aria-hidden', 'true');
            span.style.setProperty('--w', i);
            span.textContent = word;
            if (i) h1.append(' ');
            h1.append(span);
        });
        h1.classList.remove('anim-fade');
        h1.classList.add('split');
    }

    // ---------- Hero ambience: glow drift and dot-grid flashlight ----------
    function initHeroAmbience() {
        if (!hero) return;
        const glow = $('.hero-glow', hero);
        const grid = document.createElement('div');
        grid.className = 'hero-grid';
        grid.setAttribute('aria-hidden', 'true');
        hero.prepend(grid);
        if (!finePointer) return;
        let raf = 0;
        hero.addEventListener('pointermove', e => {
            cancelAnimationFrame(raf);
            raf = requestAnimationFrame(() => {
                const hr = hero.getBoundingClientRect();
                const gr = grid.getBoundingClientRect();
                const px = (e.clientX - hr.left) / hr.width - 0.5;
                const py = (e.clientY - hr.top) / hr.height - 0.5;
                if (glow) glow.style.translate = `${px * 80}px ${py * 50}px`;
                grid.style.setProperty('--gx', `${e.clientX - gr.left}px`);
                grid.style.setProperty('--gy', `${e.clientY - gr.top}px`);
                grid.classList.add('lit');
            });
        });
        hero.addEventListener('pointerleave', () => {
            cancelAnimationFrame(raf);
            if (glow) glow.style.translate = '';
            grid.classList.remove('lit');
        });
    }

    // ---------- Hero buttons ----------
    function initButtons() {
        if (!hero) return;
        const primary = $('a.bg-primary', hero);
        if (primary) primary.classList.add('btn-shine');
        if (!finePointer) return;
        [primary, $('.btn-secondary', hero)].filter(Boolean).forEach(btn => {
            btn.classList.add('magnetic');
            btn.addEventListener('pointermove', e => {
                const r = btn.getBoundingClientRect();
                const dx = e.clientX - (r.left + r.width / 2);
                const dy = e.clientY - (r.top + r.height / 2);
                btn.style.translate = `${dx * 0.18}px ${dy * 0.3}px`;
            });
            btn.addEventListener('pointerleave', () => { btn.style.translate = ''; });
        });
    }

    // ---------- Page scroll progress ----------
    function initProgress() {
        const bar = document.createElement('div');
        bar.className = 'page-progress';
        bar.setAttribute('aria-hidden', 'true');
        document.body.append(bar);
        let raf = 0;
        const update = () => {
            raf = 0;
            const max = root.scrollHeight - innerHeight;
            bar.style.transform = `scaleX(${max > 0 ? Math.min(1, scrollY / max) : 0})`;
        };
        addEventListener('scroll', () => { if (!raf) raf = requestAnimationFrame(update); }, { passive: true });
        addEventListener('resize', update);
        update();
    }

    // ---------- Screenshot tilt ----------
    function initTilt() {
        if (!finePointer) return;
        $$('.screenshot-card').forEach(card => {
            // Measure the untransformed wrapper so the tilt doesn't feed back into itself.
            const box = card.parentElement;
            let raf = 0;
            card.addEventListener('pointerenter', () => card.classList.add('tilting'));
            card.addEventListener('pointermove', e => {
                cancelAnimationFrame(raf);
                raf = requestAnimationFrame(() => {
                    const r = box.getBoundingClientRect();
                    const px = Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
                    const py = Math.min(1, Math.max(0, (e.clientY - r.top) / r.height));
                    card.style.transform =
                        `perspective(900px) translateY(-6px) rotateX(${(0.5 - py) * 9}deg) rotateY(${(px - 0.5) * 11}deg)`;
                    card.style.setProperty('--sx', `${px * 100}%`);
                    card.style.setProperty('--sy', `${py * 100}%`);
                });
            });
            card.addEventListener('pointerleave', () => {
                cancelAnimationFrame(raf);
                card.classList.remove('tilting');
                card.style.transform = '';
            });
        });
    }

    // ---------- Features carousel ----------
    function initCarousel() {
        const strip = $('#featureCarousel');
        if (!strip) return;
        const cards = $$('.feat-card', strip);
        $$('.carousel-slide', strip).forEach((slide, i) => slide.style.setProperty('--i', Math.min(i, 6)));

        // Edge fades show there is more to scroll in that direction.
        const edges = () => {
            const max = strip.scrollWidth - strip.clientWidth;
            strip.classList.toggle('fade-l', strip.scrollLeft > 4);
            strip.classList.toggle('fade-r', strip.scrollLeft < max - 4);
        };
        strip.addEventListener('scroll', edges, { passive: true });
        addEventListener('resize', edges);
        edges();

        if (!finePointer) return;

        // Spotlight follows the cursor across every card at once.
        let raf = 0;
        strip.addEventListener('pointermove', e => {
            cancelAnimationFrame(raf);
            raf = requestAnimationFrame(() => {
                cards.forEach(card => {
                    const r = card.getBoundingClientRect();
                    card.style.setProperty('--mx', `${e.clientX - r.left}px`);
                    card.style.setProperty('--my', `${e.clientY - r.top}px`);
                });
                strip.classList.add('spot-on');
            });
        });
        strip.addEventListener('pointerleave', () => { cancelAnimationFrame(raf); strip.classList.remove('spot-on'); });

        // Mouse drag with momentum (touch and trackpads already scroll natively).
        let down = false, moved = false, startX = 0, startLeft = 0, lastX = 0, lastT = 0, velocity = 0, glide = 0;
        strip.addEventListener('pointerdown', e => {
            if (e.pointerType !== 'mouse' || e.button !== 0) return;
            e.preventDefault();
            down = true; moved = false; velocity = 0;
            startX = lastX = e.clientX; startLeft = strip.scrollLeft; lastT = performance.now();
            cancelAnimationFrame(glide);
        });
        addEventListener('pointermove', e => {
            if (!down) return;
            const dx = e.clientX - startX;
            if (!moved && Math.abs(dx) > 4) { moved = true; strip.classList.add('dragging'); }
            if (!moved) return;
            strip.scrollLeft = startLeft - dx;
            const now = performance.now();
            velocity = 0.75 * velocity + 0.25 * ((lastX - e.clientX) / Math.max(1, now - lastT));
            lastX = e.clientX; lastT = now;
        });
        addEventListener('pointerup', () => {
            if (!down) return;
            down = false;
            strip.classList.remove('dragging');
            if (!moved || performance.now() - lastT > 80) return;
            let v = velocity * 16;
            const tick = () => {
                v *= 0.94;
                if (Math.abs(v) < 0.4) return;
                strip.scrollLeft += v;
                glide = requestAnimationFrame(tick);
            };
            glide = requestAnimationFrame(tick);
        });
        strip.addEventListener('click', e => { if (moved) { e.preventDefault(); e.stopPropagation(); } }, true);
    }

    // ---------- Features carousel: vertical wheel scrolls it sideways ----------
    // Only while the strip can still move that way; at either end the wheel
    // scrolls the page again, so the section never traps the visitor.
    function initCarouselWheel() {
        const strip = $('#featureCarousel');
        if (!strip) return;
        let target = strip.scrollLeft, raf = 0;
        const animate = () => {
            const diff = target - strip.scrollLeft;
            if (Math.abs(diff) < 0.5) { strip.scrollLeft = target; raf = 0; return; }
            strip.scrollLeft += diff * 0.2;
            raf = requestAnimationFrame(animate);
        };
        const stop = () => { cancelAnimationFrame(raf); raf = 0; };
        strip.addEventListener('wheel', e => {
            if (e.ctrlKey || Math.abs(e.deltaX) >= Math.abs(e.deltaY)) return; // pinch zoom or a sideways swipe
            const max = strip.scrollWidth - strip.clientWidth;
            if (!raf) target = strip.scrollLeft;
            const delta = e.deltaY * (e.deltaMode === 1 ? 40 : e.deltaMode === 2 ? strip.clientWidth : 1);
            if ((delta < 0 && target <= 0) || (delta > 0 && target >= max - 1)) return;
            e.preventDefault();
            target = Math.max(0, Math.min(max, target + delta));
            if (reduce) { strip.scrollLeft = target; return; }
            if (!raf) raf = requestAnimationFrame(animate);
        }, { passive: false });
        strip.addEventListener('pointerdown', stop);
    }

    // ---------- Comparison table ----------
    function initTable() {
        $$('table tbody tr').forEach((tr, i) => tr.style.setProperty('--r', i));
    }

    // ---------- Homebrew commands type themselves ----------
    function initTyping() {
        const box = $('.code-box');
        if (!box) return;
        // Untyped text stays in the layout (hidden), so the box never changes size.
        const lines = $$('code', box).map(code => {
            const text = code.textContent;
            const typed = document.createElement('span');
            const ghost = document.createElement('span');
            ghost.className = 'ty-ghost';
            ghost.textContent = text;
            code.textContent = '';
            code.append(typed, ghost);
            return { text, typed, ghost };
        });
        if (!lines.length) return;
        const caret = document.createElement('span');
        caret.className = 'ty-caret';
        caret.setAttribute('aria-hidden', 'true');
        lines[0].typed.after(caret);

        const io = new IntersectionObserver(([e]) => {
            if (!e.isIntersecting) return;
            io.disconnect();
            let line = 0, ch = 0;
            const tick = () => {
                const l = lines[line];
                ch++;
                l.typed.textContent = l.text.slice(0, ch);
                l.ghost.textContent = l.text.slice(ch);
                l.typed.after(caret);
                if (ch < l.text.length) return setTimeout(tick, 16 + Math.random() * 34);
                if (++line < lines.length) { ch = 0; setTimeout(tick, 320); }
            };
            setTimeout(tick, 450);
        }, { threshold: 0.6 });
        io.observe(box);
    }

    function initCopyPop() {
        const original = window.showCopied;
        if (typeof original !== 'function') return;
        window.showCopied = icon => {
            original(icon);
            icon.closest('button')?.animate(
                [{ transform: 'scale(1)' }, { transform: 'scale(0.8)' }, { transform: 'scale(1.2)' }, { transform: 'scale(1)' }],
                { duration: 520, easing: 'ease-out' });
        };
    }

    // ---------- Screenshot modal: fly from the card and back ----------
    function initModalFlip() {
        const modal = $('#imageModal');
        const big = $('#modalImage');
        if (!modal || !big || !big.animate) return;
        let source = null, closing = false;
        const flyFrom = (from, to) => {
            const s = from.width / to.width;
            const dx = from.left + from.width / 2 - (to.left + to.width / 2);
            const dy = from.top + from.height / 2 - (to.top + to.height / 2);
            return `translate(${dx}px, ${dy}px) scale(${s})`;
        };

        window.openModal = (img, caption) => {
            if (closing) return;
            source = img;
            big.src = img.src;
            big.alt = img.alt;
            $('#modalCaption').textContent = caption;
            big.style.opacity = '0';
            modal.classList.add('flip');
            modal.style.display = 'flex';
            document.body.style.overflow = 'hidden';
            big.decode().catch(() => {}).then(() => {
                const to = big.getBoundingClientRect();
                const from = img.getBoundingClientRect();
                big.style.opacity = '';
                modal.classList.add('show');
                if (!to.width) return;
                img.style.visibility = 'hidden';
                big.animate([{ transform: flyFrom(from, to) }, { transform: 'none' }], { duration: 560, easing: EASE_OUT })
                    .finished.finally(() => { img.style.visibility = ''; });
            });
        };

        window.closeModal = () => {
            if (!modal.classList.contains('show') || closing) return;
            closing = true;
            const to = big.getBoundingClientRect();
            const from = source ? source.getBoundingClientRect() : null;
            modal.classList.remove('show');
            const done = () => {
                modal.style.display = 'none';
                modal.classList.remove('flip');
                document.body.style.overflow = 'auto';
                if (source) source.style.visibility = '';
                closing = false;
            };
            if (!from || !from.width || !to.width) { setTimeout(done, 300); return; }
            if (source) source.style.visibility = 'hidden';
            const anim = big.animate([{ transform: 'none' }, { transform: flyFrom(from, to) }],
                { duration: 440, easing: 'cubic-bezier(0.4, 0, 0.2, 1)', fill: 'forwards' });
            anim.finished.finally(() => { done(); anim.cancel(); });
        };
    }

    // ---------- Theme switch: circular reveal from the toggle ----------
    function initThemeReveal() {
        const original = window.toggleTheme;
        if (typeof original !== 'function') return;
        const images = $$('.theme-image');
        // Preload the other theme's screenshots so the reveal never shows an empty frame.
        const preload = () => images.forEach(img => {
            [img.dataset.lightSrc, img.dataset.darkSrc].forEach(src => { if (src) new Image().src = src; });
        });
        (window.requestIdleCallback || (fn => setTimeout(fn, 1500)))(preload);

        if (!document.startViewTransition) return;
        window.toggleTheme = () => {
            const btn = $('#theme-toggle');
            const r = btn.getBoundingClientRect();
            const x = r.left + r.width / 2, y = r.top + r.height / 2;
            const radius = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y));
            const transition = document.startViewTransition(async () => {
                original();
                const decoded = Promise.all(images.map(img => img.decode().catch(() => {})));
                await Promise.race([decoded, new Promise(res => setTimeout(res, 250))]);
            });
            transition.ready.then(() => {
                root.animate(
                    { clipPath: [`circle(0px at ${x}px ${y}px)`, `circle(${radius}px at ${x}px ${y}px)`] },
                    { duration: 650, easing: 'cubic-bezier(0.65, 0, 0.35, 1)', pseudoElement: '::view-transition-new(root)' });
            }).catch(() => {});
        };
    }

    initClipDemo();
    initCarouselWheel();
    if (reduce) return;
    root.classList.add('motion');
    splitHeadline();
    initHeroAmbience();
    initButtons();
    initProgress();
    initTilt();
    initCarousel();
    initTable();
    initTyping();
    initCopyPop();
    initModalFlip();
    initThemeReveal();
})();
