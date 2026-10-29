(() => {
  const canvas = document.getElementById("board");
  const ctx = canvas.getContext("2d");
  const CELL = 20;
  const CELLS = canvas.width / CELL;
  const scoreEl = document.getElementById("score");
  const overEl = document.getElementById("gameover");
  const finalEl = document.getElementById("final");
  const msgEl = document.getElementById("msg");
  const nameEl = document.getElementById("name");
  const listEl = document.getElementById("scores");

  const DIRS = {
    up: { x: 0, y: -1 }, down: { x: 0, y: 1 },
    left: { x: -1, y: 0 }, right: { x: 1, y: 0 },
  };
  const KEYS = {
    ArrowUp: "up", ArrowDown: "down", ArrowLeft: "left", ArrowRight: "right",
    w: "up", s: "down", a: "left", d: "right",
  };

  let snake, dir, nextDir, food, score, timer, speed;

  function placeFood() {
    do {
      food = { x: Math.floor(Math.random() * CELLS), y: Math.floor(Math.random() * CELLS) };
    } while (snake.some((p) => p.x === food.x && p.y === food.y));
  }

  function setSpeed(ms) {
    speed = ms;
    clearInterval(timer);
    timer = setInterval(tick, speed);
  }

  function start() {
    snake = [{ x: 10, y: 10 }, { x: 9, y: 10 }, { x: 8, y: 10 }];
    dir = DIRS.right;
    nextDir = dir;
    score = 0;
    scoreEl.textContent = "0";
    overEl.hidden = true;
    msgEl.textContent = "";
    placeFood();
    setSpeed(140);
    draw();
  }

  function gameOver() {
    clearInterval(timer);
    timer = null;
    finalEl.textContent = String(score);
    overEl.hidden = false;
  }

  function tick() {
    dir = nextDir;
    const head = { x: snake[0].x + dir.x, y: snake[0].y + dir.y };
    const hitWall = head.x < 0 || head.y < 0 || head.x >= CELLS || head.y >= CELLS;
    if (hitWall || snake.some((p) => p.x === head.x && p.y === head.y)) {
      gameOver();
      return;
    }
    snake.unshift(head);
    if (head.x === food.x && head.y === food.y) {
      score += 10;
      scoreEl.textContent = String(score);
      placeFood();
      const faster = Math.max(60, 140 - Math.floor(score / 50) * 10);
      if (faster !== speed) setSpeed(faster);
    } else {
      snake.pop();
    }
    draw();
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#ef4444";
    ctx.fillRect(food.x * CELL, food.y * CELL, CELL - 2, CELL - 2);
    ctx.fillStyle = "#22c55e";
    snake.forEach((p) => ctx.fillRect(p.x * CELL, p.y * CELL, CELL - 2, CELL - 2));
  }

  function turn(name) {
    const d = DIRS[name];
    if (d && (d.x !== -dir.x || d.y !== -dir.y)) nextDir = d;
  }

  async function loadScores() {
    try {
      const res = await fetch("/api/scores");
      const data = await res.json();
      listEl.textContent = "";
      data.forEach((e) => {
        const li = document.createElement("li");
        li.textContent = e.name + " - " + e.score;
        listEl.appendChild(li);
      });
    } catch (err) {
      listEl.textContent = "Could not load scores";
    }
  }

  async function submitScore() {
    const res = await fetch("/api/scores", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: nameEl.value.trim(), score }),
    });
    const body = await res.json();
    msgEl.textContent = res.ok ? "Saved!" : body.error;
    if (res.ok) {
      overEl.hidden = true;
      loadScores();
    }
  }

  document.addEventListener("keydown", (e) => {
    const name = KEYS[e.key];
    if (name && timer) {
      e.preventDefault();
      turn(name);
    }
  });
  document.querySelectorAll("[data-dir]").forEach((b) =>
    b.addEventListener("click", () => turn(b.dataset.dir)));
  document.getElementById("start").addEventListener("click", start);
  document.getElementById("submit").addEventListener("click", submitScore);

  snake = [{ x: 10, y: 10 }];
  food = { x: 15, y: 10 };
  dir = DIRS.right;
  draw();
  loadScores();
})();
