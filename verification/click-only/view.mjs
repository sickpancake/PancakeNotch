export const title = 'Click-only opening';
export const state = v => ({
  Opening: v.clickOnly ? 'Click to open' : 'Hover or click to open',
  Notch: v.expanded ? (v.pending === 'close' ? 'Waiting to close' : 'Open')
    : v.pending === 'open' ? 'Waiting to open' : 'Resting'
});
export const step = action => ({Enter:'you move onto the notch', Leave:'you move away',
  ChangeSetting:'you change click-only', DelayEnds:'the delay ends', Click:'you click the notch',
  Close:'you close the notch', Idle:null})[action];
