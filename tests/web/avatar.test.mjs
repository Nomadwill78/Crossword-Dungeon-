import test from 'node:test';
import assert from 'node:assert/strict';
import { avatarState, avatarSvg, describeAvatar, HeroAvatar } from '../../src/avatar.js';
import { HEROES, HERO_LIST, DEFAULT_HERO } from '../../src/heroes.js';

test('the portrait follows health: confident, wary, battered, defeated', () => {
  assert.equal(avatarState(40, 40), 'confident');
  assert.equal(avatarState(28, 40), 'confident', '70% is still confident');
  assert.equal(avatarState(27, 40), 'wary');
  assert.equal(avatarState(16, 40), 'wary', '40% is still wary');
  assert.equal(avatarState(15, 40), 'battered');
  assert.equal(avatarState(1, 40), 'battered');
  assert.equal(avatarState(0, 40), 'defeated');
  assert.equal(avatarState(-5, 40), 'defeated', 'overkill is still defeated');
  assert.equal(avatarState(5, 0), 'confident', 'a zero max HP does not divide by zero');
});

test('each state has its own face', () => {
  const marks = { defeated: 'av-x', battered: 'av-bandage', wary: 'av-sweat', confident: 'av-glint' };
  for (const [state, mark] of Object.entries(marks)) {
    const svg = avatarSvg(state);
    assert.ok(svg.startsWith('<svg'), `${state} is an SVG`);
    assert.ok(svg.includes(mark), `${state} draws ${mark}`);
  }
  assert.ok(!avatarSvg('confident').includes('av-x'), 'a confident hero has no X eyes');
  assert.ok(!avatarSvg('wary').includes('av-bandage'), 'a wary hero is not bandaged yet');
  assert.ok(!avatarSvg('confident').includes('av-bandage'));
  assert.notEqual(avatarSvg('confident'), avatarSvg('battered'));
});

test('the description says how the hero is doing, for screen readers', () => {
  assert.match(describeAvatar('battered', 5, 40), /battered.*5 of 40 HP/);
  assert.match(describeAvatar('defeated', 0, 40), /defeated/);
});

test('every hero has a portrait in every state, and they look different', () => {
  const states = ['confident', 'wary', 'battered', 'defeated'];
  const marks = { defeated: 'av-x', battered: 'av-bandage', wary: 'av-sweat', confident: 'av-glint' };
  for (const hero of HERO_LIST) {
    for (const state of states) {
      const svg = avatarSvg(state, hero.id);
      assert.ok(svg.startsWith('<svg'), `${hero.id} ${state} is an SVG`);
      assert.ok(svg.includes(marks[state]), `${hero.id} ${state} draws ${marks[state]}`);
    }
  }
  const drawings = new Set(HERO_LIST.map((h) => avatarSvg('confident', h.id)));
  assert.equal(drawings.size, HERO_LIST.length, 'no two heroes share a drawing');
  assert.equal(avatarSvg('confident'), avatarSvg('confident', DEFAULT_HERO.id), 'the default hero is the default drawing');
  assert.equal(avatarSvg('confident', 'nobody'), avatarSvg('confident', DEFAULT_HERO.id), 'an unknown hero falls back');
});

test('the screen-reader text names the hero', () => {
  assert.match(describeAvatar('wary', 20, 40, HEROES.warden), /^The Warden looks wary \(20 of 40 HP\)/);
  assert.match(describeAvatar('wary', 20, 40), /^The Scribe looks/);
});

/** Just enough of an element for HeroAvatar. */
function fakeElement() {
  const classes = new Set();
  return {
    dataset: {},
    attrs: {},
    innerHTML: '',
    offsetWidth: 1,
    setAttribute(k, v) { this.attrs[k] = v; },
    classList: { add: (c) => classes.add(c), remove: (c) => classes.delete(c), has: (c) => classes.has(c) },
  };
}

test('HeroAvatar redraws only when the expression changes and flinches on damage', () => {
  const el = fakeElement();
  const avatar = new HeroAvatar(el);
  avatar.update(40, 40);
  assert.equal(el.dataset.state, 'confident');
  assert.equal(el.attrs.role, 'img');
  assert.ok(!el.classList.has('hit'), 'no flinch on the first draw');

  const drawn = el.innerHTML;
  el.innerHTML = 'SENTINEL';
  avatar.update(36, 40); // still confident
  assert.equal(el.innerHTML, 'SENTINEL', 'same expression, no redraw');
  assert.ok(el.classList.has('hit'), 'but taking damage still flinches');

  el.classList.remove('hit');
  avatar.update(40, 40); // healed
  assert.ok(!el.classList.has('hit'), 'healing does not flinch');

  avatar.update(10, 40);
  assert.equal(el.dataset.state, 'battered');
  assert.notEqual(el.innerHTML, 'SENTINEL');
  avatar.update(0, 40);
  assert.equal(el.dataset.state, 'defeated');
  assert.match(el.attrs['aria-label'], /defeated/);
  assert.ok(drawn.includes('<svg'));
});

test('switching hero redraws in their gear and forgets the old HP (no flinch)', () => {
  const el = fakeElement();
  const avatar = new HeroAvatar(el, HEROES.scribe);
  assert.equal(el.dataset.hero, 'scribe');
  avatar.update(40, 40);
  const scribe = el.innerHTML;

  avatar.update(30, 40);
  assert.ok(el.classList.has('hit'), 'the old run left a flinch behind');
  avatar.setHero(HEROES.warden);
  assert.ok(!el.classList.has('hit'), 'a swap clears it');
  assert.equal(el.dataset.hero, 'warden');
  avatar.update(10, 50); // far lower than the old run's HP: a new run, not damage
  assert.ok(!el.classList.has('hit'), 'a new run is not a flinch');
  assert.notEqual(el.innerHTML, scribe);
  assert.match(el.attrs['aria-label'], /^The Warden looks battered/);

  avatar.setHero(HEROES.duelist);
  avatar.update(40, 40);
  assert.match(el.attrs['aria-label'], /^The Duelist/);
  assert.equal(el.dataset.state, 'confident', 'state is recomputed after a swap');
});
