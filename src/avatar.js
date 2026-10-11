// The hero portrait beside the HP bar. It is a vector drawing whose face and
// posture follow the player's health, so a glance at the header tells you how
// the run is going:
//
//   confident  70%+ HP     bright-eyed smirk
//   wary       40-69% HP   brow furrowed, tight mouth
//   battered   1-39% HP    half-closed eyes, panting, sweat, a bandage
//   defeated   0 HP        X eyes, greyed out
//
// Each hero has their own gear (see GEAR). Colours come from CSS (.av-*
// classes in main.css, keyed on data-hero) so the drawing themes like the rest
// of the page.

import { DEFAULT_HERO, heroById } from './heroes.js';

/** Which expression to show for [hp] of [maxHp]. */
export function avatarState(hp, maxHp) {
  if (hp <= 0) return 'defeated';
  const fraction = hp / Math.max(1, maxHp);
  if (fraction >= 0.7) return 'confident';
  if (fraction >= 0.4) return 'wary';
  return 'battered';
}

const FACES = {
  confident: `
    <path class="av-brow" d="M22 24 Q26 21 30 23"/>
    <path class="av-brow" d="M34 22 Q38 19 43 22"/>
    <ellipse class="av-eye" cx="26" cy="29" rx="2.3" ry="2.8"/>
    <ellipse class="av-eye" cx="38" cy="29" rx="2.3" ry="2.8"/>
    <circle class="av-glint" cx="26.8" cy="28" r="0.8"/>
    <circle class="av-glint" cx="38.8" cy="28" r="0.8"/>
    <path class="av-mouth" d="M26 38 Q33 44 40 37"/>`,
  wary: `
    <path class="av-brow" d="M22 22 Q26 24 30 25"/>
    <path class="av-brow" d="M34 25 Q38 24 42 22"/>
    <ellipse class="av-eye" cx="26" cy="30" rx="2.1" ry="2.4"/>
    <ellipse class="av-eye" cx="38" cy="30" rx="2.1" ry="2.4"/>
    <path class="av-mouth" d="M27 40 Q32 38 37 40"/>
    <path class="av-sweat" d="M48 22 Q50 26 48 28 Q46 26 48 22Z"/>`,
  battered: `
    <path class="av-brow" d="M22 24 Q26 27 30 26"/>
    <path class="av-brow" d="M34 26 Q38 27 42 24"/>
    <path class="av-lid" d="M23 30 L29 30"/>
    <path class="av-lid" d="M35 30 L41 30"/>
    <ellipse class="av-mouth-open" cx="32" cy="40" rx="4" ry="3.4"/>
    <path class="av-tongue" d="M29.5 41.5 Q32 44 34.5 41.5"/>
    <path class="av-sweat" d="M16 28 Q18 33 16 35 Q14 33 16 28Z"/>
    <path class="av-sweat" d="M49 24 Q51 29 49 31 Q47 29 49 24Z"/>
    <g class="av-bandage"><rect x="19" y="17" width="26" height="5" rx="1.5" transform="rotate(-7 32 19)"/><path d="M30 17 L34 22 M34 17 L30 22" transform="rotate(-7 32 19)"/></g>`,
  defeated: `
    <path class="av-x" d="M22 26 L29 33 M29 26 L22 33"/>
    <path class="av-x" d="M35 26 L42 33 M42 26 L35 33"/>
    <path class="av-mouth" d="M27 41 Q30 38 32 41 Q34 44 37 41"/>
    <circle class="av-star" cx="20" cy="12" r="1.6"/>
    <circle class="av-star" cx="32" cy="8" r="1.6"/>
    <circle class="av-star" cx="44" cy="12" r="1.6"/>`,
};

// What distinguishes each hero: gear drawn behind the face (`head`) and in
// front of it (`extra`). Colours are CSS, keyed on the avatar's data-hero.
const GEAR = {
  scribe: {
    head: `<path class="av-robe" d="M6 64 Q8 47 32 45 Q56 47 58 64Z"/>
      <path class="av-hood" d="M11 36 Q9 8 32 7 Q55 8 53 36 Q52 48 32 50 Q12 48 11 36Z"/>`,
    extra: `<path class="av-quill" d="M53 58 Q57 46 51 38 Q56 47 49 58Z"/>`,
  },
  warden: {
    head: `<path class="av-robe" d="M6 64 Q8 47 32 45 Q56 47 58 64Z"/>
      <path class="av-plate" d="M3 64 Q4 50 20 46 L24 60Z"/>
      <path class="av-plate" d="M61 64 Q60 50 44 46 L40 60Z"/>
      <path class="av-helm" d="M11 38 Q8 5 32 4 Q56 5 53 38 L53 44 Q32 52 11 44Z"/>
      <path class="av-crest" d="M32 4 Q30 -1 36 -1 Q35 2 36 5Z"/>`,
    extra: `<path class="av-guard" d="M32 14 L32 33"/>`,
  },
  duelist: {
    head: `<path class="av-robe" d="M6 64 Q8 47 32 45 Q56 47 58 64Z"/>
      <path class="av-sash" d="M8 64 L30 47 L37 48 L17 64Z"/>
      <path class="av-hair" d="M12 40 Q8 12 32 10 Q56 12 52 40 Q50 27 32 25 Q14 27 12 40Z"/>`,
    extra: `<path class="av-cap" d="M9 23 Q32 1 55 21 Q44 14 32 15 Q20 14 9 23Z"/>
      <path class="av-feather" d="M49 16 Q60 11 61 3 Q56 9 47 14Z"/>`,
  },
};

/** The portrait as an SVG string. [hero] is a hero id (default: the Scribe). */
export function avatarSvg(state, hero = DEFAULT_HERO.id) {
  const gear = GEAR[hero] ?? GEAR[DEFAULT_HERO.id];
  return `<svg viewBox="0 0 64 64" width="100%" height="100%" aria-hidden="true" focusable="false">
    ${gear.head}
    <ellipse class="av-skin" cx="32" cy="32" rx="14" ry="15.5"/>
    ${FACES[state] ?? FACES.confident}
    ${gear.extra}
  </svg>`;
}

/** Screen-reader text for the portrait. */
export function describeAvatar(state, hp, maxHp, hero = DEFAULT_HERO) {
  const mood = {
    confident: 'confident',
    wary: 'wary',
    battered: 'battered and panting',
    defeated: 'defeated',
  }[state];
  return `${hero.name} looks ${mood} (${hp} of ${maxHp} HP)`;
}

/** Owns one portrait element: call update(hp, maxHp) whenever HP changes. */
export class HeroAvatar {
  constructor(element, hero = DEFAULT_HERO) {
    this.el = element;
    this.hero = heroById(hero.id);
    this.state = null;
    this.lastHp = null;
    this.el.setAttribute('role', 'img');
    this.el.dataset.hero = this.hero.id;
  }

  /** Switch to another hero (a new run): redraw from scratch, no flinch. */
  setHero(hero) {
    this.hero = heroById(hero.id);
    this.el.dataset.hero = this.hero.id;
    this.state = null;
    this.lastHp = null;
    this.el.classList.remove('hit');
  }

  update(hp, maxHp) {
    const state = avatarState(hp, maxHp);
    if (state !== this.state) {
      this.state = state;
      this.el.dataset.state = state;
      this.el.innerHTML = avatarSvg(state, this.hero.id);
    }
    this.el.setAttribute('aria-label', describeAvatar(state, hp, maxHp, this.hero));

    // A short flinch whenever HP drops.
    if (this.lastHp !== null && hp < this.lastHp) {
      this.el.classList.remove('hit');
      void this.el.offsetWidth; // restart the animation
      this.el.classList.add('hit');
    }
    this.lastHp = hp;
  }
}
