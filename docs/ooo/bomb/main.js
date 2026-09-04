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

const S_BOMB_DIR = '/game/assets/ooo/sprites/sBomb/';

/* App */
const App = document.querySelector('#app');
for (const bomb of bombs) {
  const filename = `sBomb${bomb}`;

  App.insertAdjacentHTML(
    'beforeend',
    `<div class="grid">
      <div class="grid-item" style="--area: title">
        <span>${bomb}</span>
      </div>

      <div class="grid-item" style="--area: anime">
        <img class="large" src="${S_BOMB_DIR}/${filename}_0.png" style="--i: 0">
        <img class="large" src="${S_BOMB_DIR}/${filename}_1.png" style="--i: 1">
        <img class="large" src="${S_BOMB_DIR}/${filename}_2.png" style="--i: 2">
        <img class="large" src="${S_BOMB_DIR}/${filename}_3.png" style="--i: 3">
      </div>

      <div class="grid-item" style="--area: still">
        <img class="large" src="${S_BOMB_DIR}/${filename}Next_0.png">
      </div>

      <div class="grid-item" style="--area: bomb0">
        <img class="small" src="${S_BOMB_DIR}/${filename}_0.png">
      </div>
      <div class="grid-item" style="--area: bomb1">
        <img class="small" src="${S_BOMB_DIR}/${filename}_1.png">
      </div>
      <div class="grid-item" style="--area: bomb2">
        <img class="small" src="${S_BOMB_DIR}/${filename}_2.png">
      </div>
      <div class="grid-item" style="--area: bomb3">
        <img class="small" src="${S_BOMB_DIR}/${filename}_3.png">
      </div>
      <div class="grid-item" style="--area: bombN">
        <img class="small" src="${S_BOMB_DIR}/${filename}Next_0.png">
      </div>
    </div>`,
  );
}
