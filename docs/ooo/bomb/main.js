/* Constants */
const bombs = [
  'Idle',
  'Metroid',
  'Player',
  'Poop',
  'Pudding',
  'Record',
  'Skull',
  'Balloon',
  'Egg',
  'Emoji',
  'Hako',
];

const BOMB_SPRITES_URL = '/game/assets/ooo/sprites/sBomb/';

/* App */
const App = document.querySelector('#app');
for (const bomb of bombs) {
  const filename = `sBomb${bomb}`;

  App.insertAdjacentHTML(
    'beforeend',
    `<div class="bomb">
      <div class="big">
        <span>${bomb}</span>
        <div class="anim">
          <img src="${BOMB_SPRITES_URL}/${filename}_0.png" style="--i: 0">
          <img src="${BOMB_SPRITES_URL}/${filename}_1.png" style="--i: 1">
          <img src="${BOMB_SPRITES_URL}/${filename}_2.png" style="--i: 2">
          <img src="${BOMB_SPRITES_URL}/${filename}_3.png" style="--i: 3">
        </div>
        <img src="${BOMB_SPRITES_URL}/${filename}Next_0.png">
      </div>

      <div class="small">
        <img src="${BOMB_SPRITES_URL}/${filename}_0.png">
        <img src="${BOMB_SPRITES_URL}/${filename}_1.png">
        <img src="${BOMB_SPRITES_URL}/${filename}_2.png">
        <img src="${BOMB_SPRITES_URL}/${filename}_3.png">
        <img src="${BOMB_SPRITES_URL}/${filename}Next_0.png">
      </div>
    </div>`,
  );
}
