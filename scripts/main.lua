-- ============================================================================
-- Pentris PC (五连块俄罗斯方块 - 电脑全屏版)
-- 支持单人(常规/无尽)和双人对战模式
-- ============================================================================

require "LuaScripts/Utilities/Sample"
local cjson = require "cjson"

-- ============================================================================
-- 游戏配置
-- ============================================================================
local CONFIG = {
    Title = "Pentris",
    COLS = 12,
    ROWS = 20,
    BASE_DROP_INTERVAL = 1.0,
    FAST_DROP_INTERVAL = 0.05,
    LEVEL_SPEED_FACTOR = 0.06,
    SCORE_PER_LINE = {120, 360, 700, 1100, 1600},
    SCORE_PER_BLOCKS = {5, 15, 30, 50, 80},
}

-- ============================================================================
-- 五连块定义 (18 种单面五连块)
-- ============================================================================
local PENTOMINOES = {
    { shape = {{1,0},{2,0},{0,1},{1,1},{1,2}}, color = {0, 200, 255, 255} },
    { shape = {{0,0},{1,0},{1,1},{2,1},{1,2}}, color = {0, 160, 220, 255} },
    { shape = {{0,0},{1,0},{2,0},{3,0},{4,0}}, color = {255, 100, 100, 255} },
    { shape = {{0,0},{0,1},{0,2},{0,3},{1,3}}, color = {255, 165, 0, 255} },
    { shape = {{1,0},{1,1},{1,2},{1,3},{0,3}}, color = {255, 200, 50, 255} },
    { shape = {{0,0},{0,1},{1,1},{1,2},{1,3}}, color = {50, 220, 50, 255} },
    { shape = {{1,0},{1,1},{0,1},{0,2},{0,3}}, color = {100, 255, 100, 255} },
    { shape = {{0,0},{1,0},{0,1},{1,1},{0,2}}, color = {200, 50, 255, 255} },
    { shape = {{0,0},{1,0},{0,1},{1,1},{1,2}}, color = {160, 80, 255, 255} },
    { shape = {{0,0},{1,0},{2,0},{1,1},{1,2}}, color = {255, 50, 150, 255} },
    { shape = {{0,0},{2,0},{0,1},{1,1},{2,1}}, color = {50, 200, 200, 255} },
    { shape = {{0,0},{0,1},{0,2},{1,2},{2,2}}, color = {200, 200, 50, 255} },
    { shape = {{0,0},{0,1},{1,1},{1,2},{2,2}}, color = {255, 120, 50, 255} },
    { shape = {{1,0},{0,1},{1,1},{2,1},{1,2}}, color = {120, 200, 255, 255} },
    { shape = {{0,0},{1,0},{2,0},{3,0},{1,1}}, color = {255, 80, 200, 255} },
    { shape = {{0,0},{1,0},{2,0},{3,0},{2,1}}, color = {220, 100, 220, 255} },
    { shape = {{0,0},{1,0},{1,1},{1,2},{2,2}}, color = {100, 255, 200, 255} },
    { shape = {{1,0},{2,0},{1,1},{1,2},{0,2}}, color = {80, 220, 180, 255} },
}

-- ============================================================================
-- 全局状态
-- ============================================================================
local nvgContext = nil
local gameState = "menu"  -- menu, playing, gameover

-- 游戏模式: "timed" = 常规限时, "endless" = 无尽模式, "versus" = 双人对战
local gameMode = "timed"

local TIME_LIMIT = 180

-- 排行榜
local leaderboard_timed = {}
local leaderboard_endless = {}

-- 屏幕
local screenW = 0
local screenH = 0

-- 菜单选择
local menuSelection = 1  -- 1=常规, 2=无尽, 3=双人
local gameoverSelection = 1

-- 粒子系统
local particles = {}

-- 空格键手动边缘检测
local spaceWasDown = false

-- 双人对战结果
local versusWinner = 0  -- 0=未结束, 1=P1赢, 2=P2赢

-- ============================================================================
-- 玩家状态对象
-- ============================================================================
local players = {}  -- 双人时 players[1], players[2]; 单人时 players[1]

local function createBoard()
    local b = {}
    for r = 1, CONFIG.ROWS do
        b[r] = {}
        for c = 1, CONFIG.COLS do
            b[r][c] = nil
        end
    end
    return b
end

local function nextFromBag(bag)
    if #bag == 0 then
        for i = 1, #PENTOMINOES do
            bag[i] = i
        end
        for i = #bag, 2, -1 do
            local j = math.random(1, i)
            bag[i], bag[j] = bag[j], bag[i]
        end
    end
    return table.remove(bag)
end

local function createPiece(tetro)
    local piece = {
        blocks = {},
        color = tetro.color,
        x = math.floor(CONFIG.COLS / 2) - 2,
        y = 1,
    }
    for _, b in ipairs(tetro.shape) do
        table.insert(piece.blocks, {b[1], b[2]})
    end
    return piece
end

local function randomPieceFromBag(bag)
    local idx = nextFromBag(bag)
    return createPiece(PENTOMINOES[idx])
end

local function canPlace(board, piece, px, py)
    for _, b in ipairs(piece.blocks) do
        local col = px + b[1]
        local row = py + b[2]
        if col < 1 or col > CONFIG.COLS or row > CONFIG.ROWS then
            return false
        end
        if row >= 1 and board[row][col] ~= nil then
            return false
        end
    end
    return true
end

local function lockPiece(board, piece)
    for _, b in ipairs(piece.blocks) do
        local col = piece.x + b[1]
        local row = piece.y + b[2]
        if row >= 1 and row <= CONFIG.ROWS and col >= 1 and col <= CONFIG.COLS then
            board[row][col] = piece.color
        end
    end
end

local function rotatePiece(piece)
    local rotated = {
        blocks = {},
        color = piece.color,
        x = piece.x,
        y = piece.y,
    }
    local cx, cy = 0, 0
    for _, b in ipairs(piece.blocks) do
        cx = cx + b[1]
        cy = cy + b[2]
    end
    cx = cx / #piece.blocks
    cy = cy / #piece.blocks

    local minX, minY = 999, 999
    local newBlocks = {}
    for _, b in ipairs(piece.blocks) do
        local rx = b[1] - cx
        local ry = b[2] - cy
        local nx = ry
        local ny = -rx
        table.insert(newBlocks, {nx, ny})
        if nx < minX then minX = nx end
        if ny < minY then minY = ny end
    end

    for _, nb in ipairs(newBlocks) do
        table.insert(rotated.blocks, {
            math.floor(nb[1] - minX + 0.5),
            math.floor(nb[2] - minY + 0.5)
        })
    end
    return rotated
end

local function rotatePieceCCW(piece)
    local r = rotatePiece(piece)
    r = rotatePiece(r)
    r = rotatePiece(r)
    r.x = piece.x
    r.y = piece.y
    return r
end

local function calcGhostY(board, piece)
    local gy = piece.y
    while canPlace(board, piece, piece.x, gy + 1) do
        gy = gy + 1
    end
    return gy
end

local function removeRandomBlock(piece)
    if #piece.blocks <= 1 then return end
    local idx = math.random(1, #piece.blocks)
    table.remove(piece.blocks, idx)
end

local function tryRotate(p, rotated)
    if canPlace(p.board, rotated, rotated.x, rotated.y) then
        removeRandomBlock(rotated)
        p.currentPiece = rotated
        p.ghostY = calcGhostY(p.board, p.currentPiece)
        return true
    end
    for _, dx in ipairs({-1, 1, -2, 2}) do
        if canPlace(p.board, rotated, rotated.x + dx, rotated.y) then
            rotated.x = rotated.x + dx
            removeRandomBlock(rotated)
            p.currentPiece = rotated
            p.ghostY = calcGhostY(p.board, p.currentPiece)
            return true
        end
    end
    if canPlace(p.board, rotated, rotated.x, rotated.y - 1) then
        rotated.y = rotated.y - 1
        removeRandomBlock(rotated)
        p.currentPiece = rotated
        p.ghostY = calcGhostY(p.board, p.currentPiece)
        return true
    end
    return false
end

local function spawnLineParticles(row, boardOX, boardOY, cs, board)
    for c = 1, CONFIG.COLS do
        local color = board[row][c] or {150, 200, 255, 255}
        local cx = boardOX + (c - 1) * cs + cs / 2
        local cy = boardOY + (row - 1) * cs + cs / 2
        local count = math.random(3, 5)
        for _ = 1, count do
            local angle = math.random() * math.pi * 2
            local speed = math.random(60, 180)
            local size = math.random(3, 7)
            table.insert(particles, {
                x = cx + math.random(-4, 4),
                y = cy + math.random(-4, 4),
                vx = math.cos(angle) * speed,
                vy = math.sin(angle) * speed - math.random(30, 80),
                size = size,
                life = 1.0,
                decay = math.random(150, 280) / 100,
                r = math.min(255, color[1] + math.random(-20, 40)),
                g = math.min(255, color[2] + math.random(-20, 40)),
                b = math.min(255, color[3] + math.random(-20, 40)),
            })
        end
    end
end

local function clearLines(p)
    local cleared = 0
    local r = CONFIG.ROWS
    while r >= 1 do
        local full = true
        for c = 1, CONFIG.COLS do
            if p.board[r][c] == nil then
                full = false
                break
            end
        end
        if full then
            spawnLineParticles(r, p.boardOX or 0, p.boardOY or 0, p.cellSize or 20, p.board)
            table.remove(p.board, r)
            local newRow = {}
            for c = 1, CONFIG.COLS do
                newRow[c] = nil
            end
            table.insert(p.board, 1, newRow)
            cleared = cleared + 1
        else
            r = r - 1
        end
    end
    return cleared
end

local function createPlayer(id)
    local p = {
        id = id,
        board = createBoard(),
        bag = {},
        currentPiece = nil,
        nextPiece = nil,
        ghostY = 0,
        score = 0,
        level = 1,
        linesCleared = 0,
        dropTimer = 0,
        fastDrop = false,
        moveTimer = 0,
        moveDir = 0,
        moveHeld = false,
        timeRemaining = TIME_LIMIT,
        timeElapsed = 0,
        alive = true,
        -- 布局（渲染时计算）
        boardOX = 0,
        boardOY = 0,
        cellSize = 0,
    }
    p.currentPiece = randomPieceFromBag(p.bag)
    p.nextPiece = randomPieceFromBag(p.bag)
    p.ghostY = calcGhostY(p.board, p.currentPiece)
    return p
end

-- ============================================================================
-- 排行榜
-- ============================================================================

local function loadLeaderboard()
    leaderboard_timed = {}
    leaderboard_endless = {}
    if fileSystem:FileExists("leaderboard.json") then
        local file = File("leaderboard.json", FILE_READ)
        if file:IsOpen() then
            local ok, data = pcall(cjson.decode, file:ReadString())
            file:Close()
            if ok and type(data) == "table" then
                leaderboard_timed = data.timed or {}
                leaderboard_endless = data.endless or {}
            end
        end
    end
end

local function saveLeaderboard()
    local file = File("leaderboard.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(cjson.encode({ timed = leaderboard_timed, endless = leaderboard_endless }))
        file:Close()
    end
end

local function getCurrentLeaderboard()
    loadLeaderboard()
    if gameMode == "endless" then
        return leaderboard_endless
    end
    return leaderboard_timed
end

local function addScoreToLeaderboard(newScore, p)
    local lb = getCurrentLeaderboard()
    table.insert(lb, { score = newScore, level = p.level, lines = p.linesCleared, time = os.date("%m/%d %H:%M") })
    table.sort(lb, function(a, b) return a.score > b.score end)
    while #lb > 10 do
        table.remove(lb)
    end
    saveLeaderboard()
end

-- ============================================================================
-- 玩家动作（操作指定玩家）
-- ============================================================================

local function actionMoveLeft(p)
    if not p.alive or not p.currentPiece then return end
    if canPlace(p.board, p.currentPiece, p.currentPiece.x - 1, p.currentPiece.y) then
        p.currentPiece.x = p.currentPiece.x - 1
        p.ghostY = calcGhostY(p.board, p.currentPiece)
    end
end

local function actionMoveRight(p)
    if not p.alive or not p.currentPiece then return end
    if canPlace(p.board, p.currentPiece, p.currentPiece.x + 1, p.currentPiece.y) then
        p.currentPiece.x = p.currentPiece.x + 1
        p.ghostY = calcGhostY(p.board, p.currentPiece)
    end
end

local function actionRotateCW(p)
    if not p.alive or not p.currentPiece then return end
    local rotated = rotatePiece(p.currentPiece)
    rotated.x = p.currentPiece.x
    rotated.y = p.currentPiece.y
    tryRotate(p, rotated)
end

local function actionRotateCCW(p)
    if not p.alive or not p.currentPiece then return end
    local rotated = rotatePieceCCW(p.currentPiece)
    tryRotate(p, rotated)
end

local function awardPieceScore(p)
    local blocks = #p.currentPiece.blocks
    local idx = math.min(math.max(blocks, 1), 5)
    p.score = p.score + CONFIG.SCORE_PER_BLOCKS[idx] * p.level
end

local function spawnNext(p)
    p.currentPiece = p.nextPiece
    p.nextPiece = randomPieceFromBag(p.bag)
    p.currentPiece.x = math.floor(CONFIG.COLS / 2) - 2
    p.currentPiece.y = 1
    if not canPlace(p.board, p.currentPiece, p.currentPiece.x, p.currentPiece.y) then
        p.alive = false
        return
    end
    p.ghostY = calcGhostY(p.board, p.currentPiece)
end

local function actionHardDrop(p)
    if not p.alive or not p.currentPiece then return end
    p.currentPiece.y = p.ghostY
    awardPieceScore(p)
    lockPiece(p.board, p.currentPiece)
    local cleared = clearLines(p)
    if cleared > 0 then
        p.linesCleared = p.linesCleared + cleared
        local idx = math.min(cleared, 5)
        p.score = p.score + CONFIG.SCORE_PER_LINE[idx] * p.level
        p.level = math.floor(p.linesCleared / 10) + 1
    end
    spawnNext(p)
    p.fastDrop = false
end

local function dropInterval(p)
    return math.max(0.1, CONFIG.BASE_DROP_INTERVAL - (p.level - 1) * CONFIG.LEVEL_SPEED_FACTOR)
end

-- ============================================================================
-- 游戏流程
-- ============================================================================

local function endGame()
    gameState = "gameover"
    gameoverSelection = 1
    if gameMode ~= "versus" then
        addScoreToLeaderboard(players[1].score, players[1])
    end
end

local function startGame(mode)
    gameMode = mode or "timed"
    particles = {}
    versusWinner = 0

    if gameMode == "versus" then
        players = { createPlayer(1), createPlayer(2) }
    else
        players = { createPlayer(1) }
    end

    gameState = "playing"
end

local function updatePlayer(p, dt)
    if not p.alive then return end

    -- 按键长按重复
    if p.moveDir ~= 0 and p.moveHeld then
        p.moveTimer = p.moveTimer + dt
        if p.moveTimer >= 0.18 then
            if p.moveDir == -1 then actionMoveLeft(p)
            elseif p.moveDir == 1 then actionMoveRight(p) end
            p.moveTimer = p.moveTimer - 0.05
        end
    end

    -- 下落
    local interval = p.fastDrop and CONFIG.FAST_DROP_INTERVAL or dropInterval(p)
    p.dropTimer = p.dropTimer + dt

    if p.dropTimer >= interval then
        p.dropTimer = 0
        if canPlace(p.board, p.currentPiece, p.currentPiece.x, p.currentPiece.y + 1) then
            p.currentPiece.y = p.currentPiece.y + 1
        else
            awardPieceScore(p)
            lockPiece(p.board, p.currentPiece)
            local cleared = clearLines(p)
            if cleared > 0 then
                p.linesCleared = p.linesCleared + cleared
                local idx = math.min(cleared, 5)
                p.score = p.score + CONFIG.SCORE_PER_LINE[idx] * p.level
                p.level = math.floor(p.linesCleared / 10) + 1
            end
            spawnNext(p)
            p.fastDrop = false
        end
    end
end

local function updateParticles(dt)
    local i = 1
    while i <= #particles do
        local p = particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 300 * dt
        p.life = p.life - p.decay * dt
        p.size = p.size * 0.97
        if p.life <= 0 or p.size < 0.5 then
            table.remove(particles, i)
        else
            i = i + 1
        end
    end
end

local function updateGame(dt)
    updateParticles(dt)
    if gameState ~= "playing" then return end

    if gameMode == "versus" then
        -- 双人模式：更新两个玩家
        for _, p in ipairs(players) do
            updatePlayer(p, dt)
        end
        -- 检查是否有人死亡
        if not players[1].alive and not players[2].alive then
            versusWinner = 0  -- 平局
            endGame()
        elseif not players[1].alive then
            versusWinner = 2
            endGame()
        elseif not players[2].alive then
            versusWinner = 1
            endGame()
        end
    else
        -- 单人模式
        local p = players[1]

        -- 时间处理
        if gameMode == "timed" then
            p.timeRemaining = p.timeRemaining - dt
            if p.timeRemaining <= 0 then
                p.timeRemaining = 0
                p.alive = false
                endGame()
                return
            end
        else
            p.timeElapsed = p.timeElapsed + dt
        end

        updatePlayer(p, dt)

        if not p.alive then
            endGame()
        end
    end
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================

local function drawCell(vg, x, y, size, color, alpha)
    alpha = alpha or 255
    local r, g, b = color[1], color[2], color[3]
    local margin = 1

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + margin, y + margin, size - margin * 2, size - margin * 2, 3)
    nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
    nvgFill(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, x + margin, y + size - margin)
    nvgLineTo(vg, x + margin, y + margin)
    nvgLineTo(vg, x + size - margin, y + margin)
    nvgStrokeColor(vg, nvgRGBA(math.min(255, r + 70), math.min(255, g + 70), math.min(255, b + 70), alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgBeginPath(vg)
    nvgMoveTo(vg, x + size - margin, y + margin)
    nvgLineTo(vg, x + size - margin, y + size - margin)
    nvgLineTo(vg, x + margin, y + size - margin)
    nvgStrokeColor(vg, nvgRGBA(math.max(0, r - 50), math.max(0, g - 50), math.max(0, b - 50), alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

local function drawBoardFor(vg, p)
    local cs = p.cellSize
    local ox = p.boardOX
    local oy = p.boardOY

    -- 棋盘背景
    nvgBeginPath(vg)
    nvgRect(vg, ox - 2, oy - 2, CONFIG.COLS * cs + 4, CONFIG.ROWS * cs + 4)
    nvgFillColor(vg, nvgRGBA(10, 10, 20, 250))
    nvgFill(vg)

    -- 边框
    nvgBeginPath(vg)
    nvgRect(vg, ox - 4, oy - 4, CONFIG.COLS * cs + 8, CONFIG.ROWS * cs + 8)
    nvgStrokeColor(vg, nvgRGBA(80, 100, 160, 200))
    nvgStrokeWidth(vg, 3)
    nvgStroke(vg)

    -- 网格
    for r = 1, CONFIG.ROWS do
        for c = 1, CONFIG.COLS do
            nvgBeginPath(vg)
            nvgRect(vg, ox + (c-1) * cs, oy + (r-1) * cs, cs, cs)
            nvgStrokeColor(vg, nvgRGBA(30, 30, 50, 100))
            nvgStrokeWidth(vg, 0.5)
            nvgStroke(vg)
        end
    end

    -- 已落下的方块
    for r = 1, CONFIG.ROWS do
        for c = 1, CONFIG.COLS do
            if p.board[r][c] then
                drawCell(vg, ox + (c-1) * cs, oy + (r-1) * cs, cs, p.board[r][c])
            end
        end
    end

    -- 影子
    if p.currentPiece and p.alive then
        for _, b in ipairs(p.currentPiece.blocks) do
            local col = p.currentPiece.x + b[1]
            local row = p.ghostY + b[2]
            if row >= 1 and row <= CONFIG.ROWS then
                drawCell(vg, ox + (col-1) * cs, oy + (row-1) * cs, cs, p.currentPiece.color, 40)
            end
        end

        -- 当前方块
        for _, b in ipairs(p.currentPiece.blocks) do
            local col = p.currentPiece.x + b[1]
            local row = p.currentPiece.y + b[2]
            if row >= 1 and row <= CONFIG.ROWS then
                drawCell(vg, ox + (col-1) * cs, oy + (row-1) * cs, cs, p.currentPiece.color)
            end
        end
    end
end

local function drawPlayerInfo(vg, p, infoX, align)
    local panelY = p.boardOY + 10

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, align + NVG_ALIGN_TOP)

    -- 玩家标签
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 220, 80, 230))
    if gameMode == "versus" then
        local label = p.id == 1 and "P1 (WASD)" or "P2 (方向键)"
        nvgText(vg, infoX, panelY, label)
        panelY = panelY + 25
    end

    -- TIME (仅常规模式)
    if gameMode == "timed" then
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
        nvgText(vg, infoX, panelY, "TIME")
        panelY = panelY + 20

        local mins = math.floor(p.timeRemaining / 60)
        local secs = math.floor(p.timeRemaining % 60)
        local timeStr = string.format("%d:%02d", mins, secs)
        nvgFontSize(vg, 28)
        if p.timeRemaining <= 30 then
            local blink = math.floor(p.timeRemaining * 3) % 2 == 0
            nvgFillColor(vg, blink and nvgRGBA(255, 60, 60, 255) or nvgRGBA(255, 120, 80, 255))
        elseif p.timeRemaining <= 60 then
            nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
        else
            nvgFillColor(vg, nvgRGBA(80, 255, 180, 255))
        end
        nvgText(vg, infoX, panelY, timeStr)
        panelY = panelY + 40
    end

    -- SCORE
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
    nvgText(vg, infoX, panelY, "SCORE")
    panelY = panelY + 20
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, infoX, panelY, tostring(p.score))

    -- LEVEL
    panelY = panelY + 40
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
    nvgText(vg, infoX, panelY, "LEVEL")
    panelY = panelY + 20
    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(100, 220, 255, 255))
    nvgText(vg, infoX, panelY, tostring(p.level))

    -- LINES
    panelY = panelY + 35
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
    nvgText(vg, infoX, panelY, "LINES")
    panelY = panelY + 20
    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(100, 255, 150, 255))
    nvgText(vg, infoX, panelY, tostring(p.linesCleared))

    -- NEXT 预览
    panelY = panelY + 40
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
    nvgText(vg, infoX, panelY, "NEXT")
    panelY = panelY + 22

    if p.nextPiece then
        local previewSize = p.cellSize * 0.7
        local previewX = infoX
        if align == NVG_ALIGN_RIGHT then
            previewX = infoX - previewSize * 5
        end
        for _, b in ipairs(p.nextPiece.blocks) do
            drawCell(vg, previewX + b[1] * previewSize, panelY + b[2] * previewSize, previewSize, p.nextPiece.color)
        end
    end
end

local function drawParticles(vg)
    for _, p in ipairs(particles) do
        local alpha = math.floor(p.life * 255)
        nvgBeginPath(vg)
        nvgCircle(vg, p.x, p.y, p.size)
        nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, alpha))
        nvgFill(vg)
        if p.size > 2 then
            nvgBeginPath(vg)
            nvgCircle(vg, p.x, p.y, p.size * 1.8)
            nvgFillColor(vg, nvgRGBA(p.r, p.g, p.b, math.floor(alpha * 0.2)))
            nvgFill(vg)
        end
    end
end

-- 单人模式渲染（保留原有风格）
local function drawSinglePlayer(vg)
    local p = players[1]

    -- 计算布局：棋盘居中
    local vertPadding = 20
    local availH = screenH - vertPadding * 2
    local availW = screenW * 0.5

    local csFromH = math.floor(availH / CONFIG.ROWS)
    local csFromW = math.floor(availW / CONFIG.COLS)
    p.cellSize = math.min(csFromH, csFromW)

    local boardW = CONFIG.COLS * p.cellSize
    local boardH = CONFIG.ROWS * p.cellSize
    p.boardOX = (screenW - boardW) / 2
    p.boardOY = (screenH - boardH) / 2

    drawBoardFor(vg, p)
    drawParticles(vg)

    -- 左侧信息
    drawPlayerInfo(vg, p, p.boardOX - 20, NVG_ALIGN_RIGHT)

    -- 右侧 NEXT + BLOCKS
    local panelX = p.boardOX + CONFIG.COLS * p.cellSize + 20
    local panelY = p.boardOY + 10
    local previewSize = p.cellSize * 0.8

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 220))
    nvgText(vg, panelX, panelY, "NEXT")
    panelY = panelY + 30

    if p.nextPiece then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, panelX - 6, panelY - 6, previewSize * 5 + 12, previewSize * 5 + 12, 6)
        nvgFillColor(vg, nvgRGBA(20, 20, 35, 200))
        nvgFill(vg)
        for _, b in ipairs(p.nextPiece.blocks) do
            drawCell(vg, panelX + b[1] * previewSize, panelY + b[2] * previewSize, previewSize, p.nextPiece.color)
        end
    end

    panelY = panelY + previewSize * 5 + 30
    if p.currentPiece then
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, 180))
        nvgText(vg, panelX, panelY, "BLOCKS")
        panelY = panelY + 22
        nvgFontSize(vg, 36)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, panelX, panelY, tostring(#p.currentPiece.blocks))
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(120, 120, 140, 160))
        nvgText(vg, panelX + 30, panelY + 12, "/ 5")
    end

    -- 操作说明
    panelY = p.boardOY + CONFIG.ROWS * p.cellSize - 120
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(100, 110, 140, 150))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgText(vg, panelX, panelY, "← → 移动")
    panelY = panelY + 18
    nvgText(vg, panelX, panelY, "↑ / X 顺时针")
    panelY = panelY + 18
    nvgText(vg, panelX, panelY, "Z 逆时针")
    panelY = panelY + 18
    nvgText(vg, panelX, panelY, "↓ 加速")
    panelY = panelY + 18
    nvgText(vg, panelX, panelY, "空格 硬降")
    panelY = panelY + 25
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 180, 60, 150))
    nvgText(vg, panelX, panelY, "旋转会随机丢失一块!")
end

-- 双人模式渲染
local function drawVersusMode(vg)
    local vertPadding = 20
    local availH = screenH - vertPadding * 2
    local halfW = screenW / 2
    local boardAreaW = halfW * 0.6

    local csFromH = math.floor(availH / CONFIG.ROWS)
    local csFromW = math.floor(boardAreaW / CONFIG.COLS)
    local cs = math.min(csFromH, csFromW)

    local boardW = CONFIG.COLS * cs
    local boardH = CONFIG.ROWS * cs

    -- P1 左半屏
    players[1].cellSize = cs
    players[1].boardOX = halfW * 0.2
    players[1].boardOY = (screenH - boardH) / 2

    -- P2 右半屏
    players[2].cellSize = cs
    players[2].boardOX = halfW + halfW * 0.2
    players[2].boardOY = (screenH - boardH) / 2

    -- 中间分割线
    nvgBeginPath(vg)
    nvgMoveTo(vg, halfW, 20)
    nvgLineTo(vg, halfW, screenH - 20)
    nvgStrokeColor(vg, nvgRGBA(60, 70, 100, 120))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 绘制两个棋盘
    for i, p in ipairs(players) do
        drawBoardFor(vg, p)

        -- 信息面板在棋盘右侧
        local infoX = p.boardOX + CONFIG.COLS * cs + 15
        drawPlayerInfo(vg, p, infoX, NVG_ALIGN_LEFT)

        -- 如果玩家已死，画一个半透明遮罩
        if not p.alive then
            nvgBeginPath(vg)
            nvgRect(vg, p.boardOX - 4, p.boardOY - 4, boardW + 8, boardH + 8)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 150))
            nvgFill(vg)

            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 28)
            nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, p.boardOX + boardW / 2, p.boardOY + boardH / 2, "OUT!")
        end
    end

    drawParticles(vg)

    -- 顶部标题
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 150))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgText(vg, halfW, 5, "VS")
end

local function drawMenu(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(8, 8, 18, 240))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 标题
    nvgFontSize(vg, 52)
    nvgFillColor(vg, nvgRGBA(0, 220, 255, 255))
    nvgText(vg, screenW / 2, screenH * 0.18, "PENTRIS")

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(180, 180, 220, 200))
    nvgText(vg, screenW / 2, screenH * 0.18 + 45, "五连块俄罗斯方块 · 18种方块")

    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 200, 80, 230))
    nvgText(vg, screenW / 2, screenH * 0.18 + 80, "特殊规则: 每次旋转随机丢失一块!")

    -- 3个模式按钮
    local cx = screenW / 2
    local btnW = 240
    local btnH = 50
    local gap = 16
    local startY = screenH * 0.42

    local buttons = {
        { text = "常规模式 (3分钟)", color = {0, 160, 220}, selColor = {80, 220, 255} },
        { text = "无尽模式 (无限时)", color = {180, 60, 200}, selColor = {220, 120, 255} },
        { text = "双人对战 (左右分屏)", color = {220, 140, 0}, selColor = {255, 200, 60} },
    }

    for i, btn in ipairs(buttons) do
        local btnY = startY + (i - 1) * (btnH + gap)
        local sel = (menuSelection == i)

        nvgBeginPath(vg)
        nvgRoundedRect(vg, cx - btnW / 2, btnY, btnW, btnH, 8)
        if sel then
            nvgFillColor(vg, nvgRGBA(btn.color[1], btn.color[2], btn.color[3], 240))
        else
            nvgFillColor(vg, nvgRGBA(40, 45, 65, 200))
        end
        nvgFill(vg)
        nvgStrokeColor(vg, sel and nvgRGBA(btn.selColor[1], btn.selColor[2], btn.selColor[3], 255) or nvgRGBA(70, 80, 110, 180))
        nvgStrokeWidth(vg, sel and 2.5 or 1.5)
        nvgStroke(vg)

        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, sel and 255 or 180))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, cx, btnY + btnH / 2, btn.text)

        if sel then
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgText(vg, cx - btnW / 2 - 10, btnY + btnH / 2, ">")
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        end
    end

    -- 提示
    local tipY = startY + 3 * (btnH + gap) + 10
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(160, 170, 200, 200))
    nvgText(vg, cx, tipY, "↑↓ 选择模式 | Enter/Space 确认")

    -- 操控说明
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(110, 120, 150, 150))
    nvgText(vg, cx, screenH * 0.88, "单人: ← → ↑ ↓ 空格  |  双人P1: WASD+Q/E+J  P2: 方向键+0")
end

local function drawGameOver(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(8, 8, 18, 230))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    if gameMode == "versus" then
        -- 双人结果
        nvgFontSize(vg, 38)
        nvgFillColor(vg, nvgRGBA(255, 220, 60, 255))
        nvgText(vg, screenW / 2, screenH * 0.2, "GAME OVER")

        nvgFontSize(vg, 28)
        if versusWinner == 1 then
            nvgFillColor(vg, nvgRGBA(80, 220, 255, 255))
            nvgText(vg, screenW / 2, screenH * 0.3, "P1 获胜!")
        elseif versusWinner == 2 then
            nvgFillColor(vg, nvgRGBA(255, 180, 60, 255))
            nvgText(vg, screenW / 2, screenH * 0.3, "P2 获胜!")
        else
            nvgFillColor(vg, nvgRGBA(200, 200, 200, 255))
            nvgText(vg, screenW / 2, screenH * 0.3, "平局!")
        end

        -- 双方分数对比
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(200, 200, 220, 220))
        nvgText(vg, screenW * 0.35, screenH * 0.4, "P1: " .. tostring(players[1].score) .. " 分")
        nvgText(vg, screenW * 0.65, screenH * 0.4, "P2: " .. tostring(players[2].score) .. " 分")

        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(150, 160, 200, 180))
        nvgText(vg, screenW * 0.35, screenH * 0.45, "Lv." .. players[1].level .. " | " .. players[1].linesCleared .. " lines")
        nvgText(vg, screenW * 0.65, screenH * 0.45, "Lv." .. players[2].level .. " | " .. players[2].linesCleared .. " lines")
    else
        -- 单人结果
        local leftX = screenW * 0.3
        nvgFontSize(vg, 38)
        nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
        nvgText(vg, leftX, screenH * 0.25, "GAME OVER")

        nvgFontSize(vg, 14)
        if gameMode == "timed" then
            nvgFillColor(vg, nvgRGBA(80, 200, 255, 200))
            nvgText(vg, leftX, screenH * 0.25 + 30, "常规模式")
        else
            nvgFillColor(vg, nvgRGBA(200, 140, 255, 200))
            nvgText(vg, leftX, screenH * 0.25 + 30, "无尽模式")
        end

        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, 180))
        local p = players[1]
        if gameMode == "timed" and p.timeRemaining <= 0 then
            nvgText(vg, leftX, screenH * 0.25 + 50, "时间到!")
        else
            nvgText(vg, leftX, screenH * 0.25 + 50, "方块溢出!")
        end

        nvgFontSize(vg, 24)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, leftX, screenH * 0.40, "得分: " .. tostring(p.score))

        nvgFontSize(vg, 16)
        nvgFillColor(vg, nvgRGBA(160, 170, 200, 200))
        nvgText(vg, leftX, screenH * 0.40 + 30, "Lv." .. p.level .. " | " .. p.linesCleared .. " lines")

        -- 排行榜
        local rightX = screenW * 0.7
        local lb = getCurrentLeaderboard()

        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local lbTitle = gameMode == "timed" and "TOP 10 (常规)" or "TOP 10 (无尽)"
        nvgText(vg, rightX, screenH * 0.15, lbTitle)

        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local startY = screenH * 0.22
        local rowH = screenH * 0.065

        for i, entry in ipairs(lb) do
            local y = startY + (i - 1) * rowH
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFontSize(vg, 16)
            if i <= 3 then
                local rankColors = {{255, 215, 0, 255}, {192, 192, 192, 255}, {205, 127, 50, 255}}
                nvgFillColor(vg, nvgRGBA(table.unpack(rankColors[i])))
            else
                nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
            end
            nvgText(vg, rightX - 80, y, "#" .. i)

            nvgFontSize(vg, 18)
            nvgFillColor(vg, nvgRGBA(240, 240, 255, 230))
            nvgText(vg, rightX - 50, y, tostring(entry.score))

            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(120, 130, 160, 160))
            nvgText(vg, rightX + 30, y + 2, "Lv." .. (entry.level or 1) .. " " .. (entry.time or ""))
        end
    end

    -- 按钮
    local btnCX = gameMode == "versus" and screenW / 2 or screenW * 0.3
    local btnW = 180
    local btnH = 42
    local gap = 16
    local btn1Y = screenH * 0.58 - btnH - gap / 2
    local btn2Y = screenH * 0.58 + gap / 2

    local sel1 = (gameoverSelection == 1)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnCX - btnW / 2, btn1Y, btnW, btnH, 6)
    nvgFillColor(vg, sel1 and nvgRGBA(0, 160, 220, 230) or nvgRGBA(40, 45, 65, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, sel1 and nvgRGBA(80, 220, 255, 255) or nvgRGBA(70, 80, 110, 180))
    nvgStrokeWidth(vg, sel1 and 2 or 1)
    nvgStroke(vg)
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, sel1 and 255 or 170))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, btnCX, btn1Y + btnH / 2, "重新开始")
    if sel1 then
        nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(vg, btnCX - btnW / 2 - 8, btn1Y + btnH / 2, ">")
    end

    local sel2 = (gameoverSelection == 2)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, btnCX - btnW / 2, btn2Y, btnW, btnH, 6)
    nvgFillColor(vg, sel2 and nvgRGBA(100, 60, 160, 230) or nvgRGBA(40, 45, 65, 200))
    nvgFill(vg)
    nvgStrokeColor(vg, sel2 and nvgRGBA(180, 120, 255, 255) or nvgRGBA(70, 80, 110, 180))
    nvgStrokeWidth(vg, sel2 and 2 or 1)
    nvgStroke(vg)
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, sel2 and 255 or 170))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, btnCX, btn2Y + btnH / 2, "回到首页")
    if sel2 then
        nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(vg, btnCX - btnW / 2 - 8, btn2Y + btnH / 2, ">")
    end

    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(140, 150, 180, 160))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, btnCX, btn2Y + btnH + 20, "↑↓ 选择 | Enter/Space 确认")
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function HandleRender(eventType, eventData)
    local vg = nvgContext
    if not vg then return end

    local dpr = graphics:GetDPR()
    screenW = graphics:GetWidth() / dpr
    screenH = graphics:GetHeight() / dpr

    nvgBeginFrame(vg, screenW, screenH, dpr)

    -- 背景
    local bgPaint = nvgLinearGradient(vg, 0, 0, 0, screenH,
        nvgRGBA(12, 12, 30, 255), nvgRGBA(5, 5, 15, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    if gameState == "menu" then
        drawMenu(vg)
    elseif gameState == "playing" then
        if gameMode == "versus" then
            drawVersusMode(vg)
        else
            drawSinglePlayer(vg)
        end
    elseif gameState == "gameover" then
        drawGameOver(vg)
    end

    nvgEndFrame(vg)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 空格键手动边缘检测
    local spaceIsDown = input:GetKeyDown(KEY_SPACE)
    if spaceIsDown and not spaceWasDown then
        if gameState == "menu" then
            local modes = {"timed", "endless", "versus"}
            startGame(modes[menuSelection])
        elseif gameState == "gameover" then
            if gameoverSelection == 1 then
                startGame(gameMode)
            else
                gameState = "menu"
            end
        end
    end
    spaceWasDown = spaceIsDown

    updateGame(dt)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if gameState == "menu" then
        if key == KEY_UP or key == KEY_W then
            menuSelection = menuSelection - 1
            if menuSelection < 1 then menuSelection = 3 end
        elseif key == KEY_DOWN or key == KEY_S then
            menuSelection = menuSelection + 1
            if menuSelection > 3 then menuSelection = 1 end
        elseif key == KEY_RETURN or key == KEY_SPACE then
            local modes = {"timed", "endless", "versus"}
            startGame(modes[menuSelection])
        end
        return
    end

    if gameState == "gameover" then
        if key == KEY_UP or key == KEY_W then
            gameoverSelection = gameoverSelection == 1 and 2 or 1
        elseif key == KEY_DOWN or key == KEY_S then
            gameoverSelection = gameoverSelection == 2 and 1 or 2
        elseif key == KEY_RETURN or key == KEY_SPACE then
            if gameoverSelection == 1 then
                startGame(gameMode)
            else
                gameState = "menu"
            end
        end
        return
    end

    -- === 游戏中的操作 ===
    if gameMode == "versus" then
        -- 双人模式：P1用WASD+Q/E+Tab, P2用方向键+./,+空格
        local p1 = players[1]
        local p2 = players[2]

        -- P1 操作 (WASD + Q顺时针 + E逆时针 + Tab硬降)
        if key == KEY_A then
            actionMoveLeft(p1)
            p1.moveDir = -1; p1.moveTimer = 0; p1.moveHeld = true
        elseif key == KEY_D then
            actionMoveRight(p1)
            p1.moveDir = 1; p1.moveTimer = 0; p1.moveHeld = true
        elseif key == KEY_W then
            actionRotateCW(p1)
        elseif key == KEY_E then
            actionRotateCCW(p1)
        elseif key == KEY_S then
            p1.fastDrop = true
        elseif key == KEY_J then
            actionHardDrop(p1)
        end

        -- P2 操作 (方向键 + X顺时针 + Z逆时针 + 空格硬降)
        if key == KEY_LEFT then
            actionMoveLeft(p2)
            p2.moveDir = -1; p2.moveTimer = 0; p2.moveHeld = true
        elseif key == KEY_RIGHT then
            actionMoveRight(p2)
            p2.moveDir = 1; p2.moveTimer = 0; p2.moveHeld = true
        elseif key == KEY_UP then
            actionRotateCW(p2)
        elseif key == KEY_DOWN then
            p2.fastDrop = true
        elseif key == KEY_0 then
            actionHardDrop(p2)
        end
    else
        -- 单人模式
        local p = players[1]
        if key == KEY_LEFT then
            actionMoveLeft(p)
            p.moveDir = -1; p.moveTimer = 0; p.moveHeld = true
        elseif key == KEY_RIGHT then
            actionMoveRight(p)
            p.moveDir = 1; p.moveTimer = 0; p.moveHeld = true
        elseif key == KEY_UP or key == KEY_X then
            actionRotateCW(p)
        elseif key == KEY_Z then
            actionRotateCCW(p)
        elseif key == KEY_DOWN then
            p.fastDrop = true
        elseif key == KEY_SPACE then
            actionHardDrop(p)
        end
    end
end

function HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if gameState ~= "playing" then return end

    if gameMode == "versus" then
        local p1 = players[1]
        local p2 = players[2]

        -- P1
        if key == KEY_S then
            p1.fastDrop = false
        elseif key == KEY_A then
            if p1.moveDir == -1 then p1.moveDir = 0; p1.moveHeld = false end
        elseif key == KEY_D then
            if p1.moveDir == 1 then p1.moveDir = 0; p1.moveHeld = false end
        end

        -- P2
        if key == KEY_DOWN then
            p2.fastDrop = false
        elseif key == KEY_LEFT then
            if p2.moveDir == -1 then p2.moveDir = 0; p2.moveHeld = false end
        elseif key == KEY_RIGHT then
            if p2.moveDir == 1 then p2.moveDir = 0; p2.moveHeld = false end
        end
    else
        local p = players[1]
        if key == KEY_DOWN then
            p.fastDrop = false
        elseif key == KEY_LEFT then
            if p.moveDir == -1 then p.moveDir = 0; p.moveHeld = false end
        elseif key == KEY_RIGHT then
            if p.moveDir == 1 then p.moveDir = 0; p.moveHeld = false end
        end
    end
end

function HandleMouseClick(eventType, eventData)
    local dpr = graphics:GetDPR()
    local mx = input.mousePosition.x / dpr
    local my = input.mousePosition.y / dpr

    if gameState == "menu" then
        local cx = screenW / 2
        local btnW = 240
        local btnH = 50
        local gap = 16
        local startY = screenH * 0.42

        for i = 1, 3 do
            local btnY = startY + (i - 1) * (btnH + gap)
            if mx >= cx - btnW / 2 and mx <= cx + btnW / 2 and my >= btnY and my <= btnY + btnH then
                local modes = {"timed", "endless", "versus"}
                startGame(modes[i])
                return
            end
        end
    elseif gameState == "gameover" then
        local btnCX = gameMode == "versus" and screenW / 2 or screenW * 0.3
        local btnW = 180
        local btnH = 42
        local gap = 16
        local btn1Y = screenH * 0.58 - btnH - gap / 2
        local btn2Y = screenH * 0.58 + gap / 2
        local btnLeft = btnCX - btnW / 2

        if mx >= btnLeft and mx <= btnLeft + btnW then
            if my >= btn1Y and my <= btn1Y + btnH then
                startGame(gameMode)
            elseif my >= btn2Y and my <= btn2Y + btnH then
                gameState = "menu"
            end
        end
    end
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title

    SampleStart()
    SampleInitMouseMode(MM_FREE)

    nvgContext = nvgCreate(1)
    if not nvgContext then
        print("ERROR: 无法创建 NanoVG 上下文")
        return
    end
    if nvgCreateFont(nvgContext, "sans", "Fonts/MiSans-Regular.ttf") == -1 then
        print("ERROR: 无法加载字体")
        return
    end

    math.randomseed(os.time())
    loadLeaderboard()

    SubscribeToEvent(nvgContext, "NanoVGRender", "HandleRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("KeyUp", "HandleKeyUp")
    SubscribeToEvent("MouseButtonDown", "HandleMouseClick")

    print("=== Pentris PC 已启动 ===")
end

function Stop()
    if nvgContext then
        nvgDelete(nvgContext)
        nvgContext = nil
    end
end
