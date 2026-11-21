export const title = 'A closed video stays cleared';
export const state = v => {
  const broken = [];
  if (v.title !== 'Nothing' && v.titleSession !== v.sessionGeneration) broken.push('Old video cached after closure');
  if (Object.values(v.fieldSession).some(x => x !== -1 && x !== v.sessionGeneration)) broken.push('Old player details accepted after closure');
  if (v.appliedOldReply) broken.push('Older reply replaces newer details');
  if (broken.length) return broken.join(' / ');
  if (v.closed) return v.title === 'Nothing' ? 'Closed video cleared' : 'Next video loaded';
  if (v.title === 'Nothing') return 'Waiting for video details';
  return 'Loaded video';
};
export const step = (action, from, to) => {
  if (action === 'InfoReply') {
    if (to.closed && to.title !== 'Nothing' && to.titleSession === to.sessionGeneration) return "a new video's details arrive";
    return to.title === 'Nothing' && from.title !== 'Nothing' ? 'the system confirms nothing is loaded' : 'media details arrive';
  }
  return ({ RequestNowPlayingInfo: 'the system starts reading media details',
    FieldReply: 'player details arrive', CloseSession: 'the media session closes', Idle: null })[action];
};
