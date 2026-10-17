// 开屏动画：每次进入/刷新页面都展示品牌柔光开场，随后淡出揭示应用。
// 参照 StudyBuddy internal/web/templates/partials.html 的开屏风格：
//   - 每次刷新都重放（不缓存播放状态）；
//   - 系统开启「减弱动态效果」(prefers-reduced-motion) 时跳过动画直接隐藏；
//   - CSS 另有 splash-failsafe 兜底，即使本脚本失效也不会卡屏。
(function () {
  'use strict';

  var splash = document.getElementById('splash');
  if (!splash) return;

  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

  function remove() {
    if (splash && splash.parentNode) splash.parentNode.removeChild(splash);
  }
  function hide() {
    if (!splash) return;
    splash.classList.add('is-leaving'); // 触发淡出过渡（CSS 中 animation:none + opacity:0）
    setTimeout(remove, 600);
  }

  // 减弱动态效果：直接隐藏，不播放开屏
  if (reduce) {
    remove();
    return;
  }

  // 入场动画结束后收场；CSS 兜底 4s 内也会隐藏（每次刷新都会走到这里）
  setTimeout(hide, 1600);
})();
