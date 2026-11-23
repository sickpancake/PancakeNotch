export const title = 'Reduce motion';

const motion = v =>
  v.own && v.macSeen ? 'Reduced: both switches'
  : v.own ? 'Reduced: PancakeNotch switch'
  : v.macSeen ? 'Reduced: Mac switch'
  : 'Full motion';

const home = v =>
  !v.between ? 'Home on a page'
  : v.fingers && v.active ? 'Fingers scrolling Home'
  : v.settling ? 'Home settling'
  : 'Home stuck halfway';

export const state = v => ({ Motion: motion(v), Home: home(v) });

export const group = v => (v.own || v.macSeen ? 'reduced' : 'full');
export const colors = { reduced: 'teal', full: 'tan' };

export const step = (action, from, to) => ({
  YouClickSwitch: 'you click Reduce motion in Settings',
  MacFlips: null, // the Mac's switch alone changes nothing until the Mac tells the app
  MacTellsApp: "you change the Mac's Reduce motion",
  FingersDown: 'you start scrolling Home',
  FingersTurnPageReduced: 'your scroll turns a page',
  FingersLift: 'you lift your fingers',
  PageKey: 'you press an arrow key or a page dot',
  SettleEnds: 'the page finishes settling',
  ViewsRedraw: null,       // the bars' pose: not drawn in this chart
  MusicStartsOrStops: null,
})[action];
