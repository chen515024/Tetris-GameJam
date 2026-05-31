-- ============================================================================
-- Pentris PC (五连块俄罗斯方块 - 电脑全屏版)
-- 纯键盘操作，棋盘铺满屏幕
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
    -- 方块落地得分：按剩余块数计算（索引=块数）
    SCORE_PER_BLOCKS = {5, 15, 30, 50, 80},  -- 1块=5分, 2块=15, 3块=30, 4块=50, 5块=80
}

-- ============================================================================
-- 五连块定义 (18 种单面五连块)
-- ============================================================================
local PENTOMINOES = {
    { shape = {{1,0},{2,0},{0,1},{1,1},{1,2}}, color = {0, 200, 255, 255} },       -- F
    { shape = {{0,0},{1,0},{1,1},{2,1},{1,2}}, color = {0, 160, 220, 255} },       -- F'
    { shape = {{0,0},{1,0},{2,0},{3,0},{4,0}}, color = {255, 100, 100, 255} },     -- I
    { shape = {{0,0},{0,1},{0,2},{0,3},{1,3}}, color = {255, 165, 0, 255} },       -- L
    { shape = {{1,0},{1,1},{1,2},{1,3},{0,3}}, color = {255, 200, 50, 255} },      -- L'
    { shape = {{0,0},{0,1},{1,1},{1,2},{1,3}}, color = {50, 220, 50, 255} },       -- N
    { shape = {{1,0},{1,1},{0,1},{0,2},{0,3}}, color = {100, 255, 100, 255} },     -- N'
    { shape = {{0,0},{1,0},{0,1},{1,1},{0,2}}, color = {200, 50, 255, 255} },      -- P
    { shape = {{0,0},{1,0},{0,1},{1,1},{1,2}}, color = {160, 80, 255, 255} },      -- P'
    { shape = {{0,0},{1,0},{2,0},{1,1},{1,2}}, color = {255, 50, 150, 255} },      -- T
    { shape = {{0,0},{2,0},{0,1},{1,1},{2,1}}, color = {50, 200, 200, 255} },      -- U
    { shape = {{0,0},{0,1},{0,2},{1,2},{2,2}}, color = {200, 200, 50, 255} },      -- V
    { shape = {{0,0},{0,1},{1,1},{1,2},{2,2}}, color = {255, 120, 50, 255} },      -- W
    { shape = {{1,0},{0,1},{1,1},{2,1},{1,2}}, color = {120, 200, 255, 255} },     -- X
    { shape = {{0,0},{1,0},{2,0},{3,0},{1,1}}, color = {255, 80, 200, 255} },      -- Y
    { shape = {{0,0},{1,0},{2,0},{3,0},{2,1}}, color = {220, 100, 220, 255} },     -- Y'
    { shape = {{0,0},{1,0},{1,1},{1,2},{2,2}}, color = {100, 255, 200, 255} },     -- Z
    { shape = {{1,0},{2,0},{1,1},{1,2},{0,2}}, color = {80, 220, 180, 255} },      -- Z'
}

-- ============================================================================
-- 游戏状态
-- ============================================================================
local nvgContext = nil
local gameState = "menu"  -- menu, playing, gameover

local board = {}
local currentPiece = nil
local nextPiece = nil
local ghostY = 0

local score = 0
local level = 1
local linesCleared = 0
local dropTimer = 0
local fastDrop = false

-- 游戏模式: "timed" = 常规限时, "endless" = 无尽模式
local gameMode = "timed"

-- 时间
local TIME_LIMIT = 180  -- 3分钟（常规模式）
local timeRemaining = TIME_LIMIT
local timeElapsed = 0   -- 已用时间（无尽模式显示）

-- 排行榜（两个模式分开）
local leaderboard_timed = {}
local leaderboard_endless = {}

-- 屏幕与布局
local screenW = 0
local screenH = 0
local cellSize = 0
local boardOffsetX = 0
local boardOffsetY = 0

-- 按键重复
local moveTimer = 0
local moveDir = 0
local MOVE_INITIAL_DELAY = 0.18
local MOVE_REPEAT_DELAY = 0.05
local moveHeld = false

-- 菜单选择
local menuSelection = 1  -- 1=常规模式, 2=无尽模式

-- 随机包
local bag = {}

-- ============================================================================
-- 排行榜存储
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
    if gameMode == "endless" then
        return leaderboard_endless
    end
    return leaderboard_timed
end

local function addScoreToLeaderboard(newScore)
    local lb = getCurrentLeaderboard()
    table.insert(lb, { score = newScore, level = level, lines = linesCleared, time = os.date("%m/%d %H:%M") })
    table.sort(lb, function(a, b) return a.score > b.score end)
    while #lb > 10 do
        table.remove(lb)
    end
    saveLeaderboard()
end

-- ============================================================================
-- 方块操作函数
-- ============================================================================

local function initBoard()
    board = {}
    for r = 1, CONFIG.ROWS do
        board[r] = {}
        for c = 1, CONFIG.COLS do
            board[r][c] = nil
        end
    end
end

local function nextFromBag()
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

local function randomPiece()
    local idx = nextFromBag()
    return createPiece(PENTOMINOES[idx])
end

local function canPlace(piece, px, py)
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

local function lockPiece(piece)
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

local function calcGhostY(piece)
    local gy = piece.y
    while canPlace(piece, piece.x, gy + 1) do
        gy = gy + 1
    end
    return gy
end

local function clearLines()
    local cleared = 0
    local r = CONFIG.ROWS
    while r >= 1 do
        local full = true
        for c = 1, CONFIG.COLS do
            if board[r][c] == nil then
                full = false
                break
            end
        end
        if full then
            table.remove(board, r)
            local newRow = {}
            for c = 1, CONFIG.COLS do
                newRow[c] = nil
            end
            table.insert(board, 1, newRow)
            cleared = cleared + 1
        else
            r = r - 1
        end
    end
    return cleared
end

local function checkGameOver()
    if not canPlace(currentPiece, currentPiece.x, currentPiece.y) then
        return true
    end
    return false
end

--- 旋转时随机丢失一块（最少保留1块）
local function removeRandomBlock(piece)
    if #piece.blocks <= 1 then return end
    local idx = math.random(1, #piece.blocks)
    table.remove(piece.blocks, idx)
end

local function tryRotate(rotated)
    if canPlace(rotated, rotated.x, rotated.y) then
        removeRandomBlock(rotated)
        currentPiece = rotated
        ghostY = calcGhostY(currentPiece)
        return true
    end
    for _, dx in ipairs({-1, 1, -2, 2}) do
        if canPlace(rotated, rotated.x + dx, rotated.y) then
            rotated.x = rotated.x + dx
            removeRandomBlock(rotated)
            currentPiece = rotated
            ghostY = calcGhostY(currentPiece)
            return true
        end
    end
    if canPlace(rotated, rotated.x, rotated.y - 1) then
        rotated.y = rotated.y - 1
        removeRandomBlock(rotated)
        currentPiece = rotated
        ghostY = calcGhostY(currentPiece)
        return true
    end
    return false
end

-- ============================================================================
-- 游戏动作
-- ============================================================================

local function actionMoveLeft()
    if gameState ~= "playing" or not currentPiece then return end
    if canPlace(currentPiece, currentPiece.x - 1, currentPiece.y) then
        currentPiece.x = currentPiece.x - 1
        ghostY = calcGhostY(currentPiece)
    end
end

local function actionMoveRight()
    if gameState ~= "playing" or not currentPiece then return end
    if canPlace(currentPiece, currentPiece.x + 1, currentPiece.y) then
        currentPiece.x = currentPiece.x + 1
        ghostY = calcGhostY(currentPiece)
    end
end

local function actionRotateCW()
    if gameState ~= "playing" or not currentPiece then return end
    local rotated = rotatePiece(currentPiece)
    rotated.x = currentPiece.x
    rotated.y = currentPiece.y
    tryRotate(rotated)
end

local function actionRotateCCW()
    if gameState ~= "playing" or not currentPiece then return end
    local rotated = rotatePieceCCW(currentPiece)
    tryRotate(rotated)
end

local function awardPieceScore(piece)
    local blocks = #piece.blocks
    local idx = math.min(math.max(blocks, 1), 5)
    score = score + CONFIG.SCORE_PER_BLOCKS[idx] * level
end

local function actionHardDrop()
    if gameState ~= "playing" or not currentPiece then return end
    currentPiece.y = ghostY
    awardPieceScore(currentPiece)
    lockPiece(currentPiece)
    local cleared = clearLines()
    if cleared > 0 then
        linesCleared = linesCleared + cleared
        local idx = math.min(cleared, 5)
        score = score + CONFIG.SCORE_PER_LINE[idx] * level
        level = math.floor(linesCleared / 10) + 1
    end
    spawnNext()
    fastDrop = false
end

-- ============================================================================
-- 游戏逻辑
-- ============================================================================

local function endGame()
    gameState = "gameover"
    addScoreToLeaderboard(score)
    print("=== 游戏结束 === 得分: " .. score)
end

local function startGame(mode)
    gameMode = mode or "timed"
    initBoard()
    bag = {}
    score = 0
    level = 1
    linesCleared = 0
    dropTimer = 0
    fastDrop = false
    timeRemaining = TIME_LIMIT
    timeElapsed = 0
    currentPiece = randomPiece()
    nextPiece = randomPiece()
    gameState = "playing"
    ghostY = calcGhostY(currentPiece)
    print("=== Pentris 开始 [" .. gameMode .. "] ===")
end

function spawnNext()
    currentPiece = nextPiece
    nextPiece = randomPiece()
    currentPiece.x = math.floor(CONFIG.COLS / 2) - 2
    currentPiece.y = 1
    if checkGameOver() then
        endGame()
    end
    ghostY = calcGhostY(currentPiece)
end

local function dropInterval()
    return math.max(0.1, CONFIG.BASE_DROP_INTERVAL - (level - 1) * CONFIG.LEVEL_SPEED_FACTOR)
end

local function updateGame(dt)
    if gameState ~= "playing" then return end

    -- 时间处理
    if gameMode == "timed" then
        timeRemaining = timeRemaining - dt
        if timeRemaining <= 0 then
            timeRemaining = 0
            endGame()
            return
        end
    else
        timeElapsed = timeElapsed + dt
    end

    -- 按键长按重复
    if moveDir ~= 0 and moveHeld then
        moveTimer = moveTimer + dt
        if moveTimer >= MOVE_INITIAL_DELAY then
            if moveDir == -1 then actionMoveLeft()
            elseif moveDir == 1 then actionMoveRight() end
            moveTimer = moveTimer - MOVE_REPEAT_DELAY
        end
    end

    -- 下落
    local interval = fastDrop and CONFIG.FAST_DROP_INTERVAL or dropInterval()
    dropTimer = dropTimer + dt

    if dropTimer >= interval then
        dropTimer = 0
        if canPlace(currentPiece, currentPiece.x, currentPiece.y + 1) then
            currentPiece.y = currentPiece.y + 1
        else
            awardPieceScore(currentPiece)
            lockPiece(currentPiece)
            local cleared = clearLines()
            if cleared > 0 then
                linesCleared = linesCleared + cleared
                local idx = math.min(cleared, 5)
                score = score + CONFIG.SCORE_PER_LINE[idx] * level
                level = math.floor(linesCleared / 10) + 1
            end
            spawnNext()
            fastDrop = false
        end
    end
end

-- ============================================================================
-- NanoVG 渲染（全屏铺满）
-- ============================================================================

local function drawCell(vg, x, y, size, color, alpha)
    alpha = alpha or 255
    local r, g, b = color[1], color[2], color[3]
    local margin = 1

    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + margin, y + margin, size - margin * 2, size - margin * 2, 3)
    nvgFillColor(vg, nvgRGBA(r, g, b, alpha))
    nvgFill(vg)

    -- 高光
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + margin, y + size - margin)
    nvgLineTo(vg, x + margin, y + margin)
    nvgLineTo(vg, x + size - margin, y + margin)
    nvgStrokeColor(vg, nvgRGBA(math.min(255, r + 70), math.min(255, g + 70), math.min(255, b + 70), alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 阴影
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + size - margin, y + margin)
    nvgLineTo(vg, x + size - margin, y + size - margin)
    nvgLineTo(vg, x + margin, y + size - margin)
    nvgStrokeColor(vg, nvgRGBA(math.max(0, r - 50), math.max(0, g - 50), math.max(0, b - 50), alpha))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
end

local function drawBoard(vg)
    local cs = cellSize
    local ox = boardOffsetX
    local oy = boardOffsetY

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
            if board[r][c] then
                drawCell(vg, ox + (c-1) * cs, oy + (r-1) * cs, cs, board[r][c])
            end
        end
    end
end

local function drawCurrentPiece(vg)
    if not currentPiece then return end
    local cs = cellSize
    local ox = boardOffsetX
    local oy = boardOffsetY

    -- 影子
    for _, b in ipairs(currentPiece.blocks) do
        local col = currentPiece.x + b[1]
        local row = ghostY + b[2]
        if row >= 1 and row <= CONFIG.ROWS then
            drawCell(vg, ox + (col-1) * cs, oy + (row-1) * cs, cs, currentPiece.color, 40)
        end
    end

    -- 当前方块
    for _, b in ipairs(currentPiece.blocks) do
        local col = currentPiece.x + b[1]
        local row = currentPiece.y + b[2]
        if row >= 1 and row <= CONFIG.ROWS then
            drawCell(vg, ox + (col-1) * cs, oy + (row-1) * cs, cs, currentPiece.color)
        end
    end
end

local function drawSidePanelRight(vg)
    -- 右侧面板：NEXT 预览 + 方块剩余数量
    local panelX = boardOffsetX + CONFIG.COLS * cellSize + 20
    local panelY = boardOffsetY + 10
    local previewSize = cellSize * 0.8

    -- NEXT 标签
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 220))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgText(vg, panelX, panelY, "NEXT")

    -- Next 方块预览
    panelY = panelY + 30
    if nextPiece then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, panelX - 6, panelY - 6, previewSize * 5 + 12, previewSize * 5 + 12, 6)
        nvgFillColor(vg, nvgRGBA(20, 20, 35, 200))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(60, 70, 100, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        for _, b in ipairs(nextPiece.blocks) do
            drawCell(vg, panelX + b[1] * previewSize, panelY + b[2] * previewSize, previewSize, nextPiece.color)
        end
    end

    -- 当前方块剩余块数 + 潜在得分
    panelY = panelY + previewSize * 5 + 30
    if currentPiece then
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, 180))
        nvgText(vg, panelX, panelY, "BLOCKS")

        panelY = panelY + 22
        nvgFontSize(vg, 36)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 255))
        nvgText(vg, panelX, panelY, tostring(#currentPiece.blocks))

        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(120, 120, 140, 160))
        nvgText(vg, panelX + 30, panelY + 12, "/ 5")

        -- 显示当前方块落地可得分数
        panelY = panelY + 50
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(180, 180, 200, 180))
        nvgText(vg, panelX, panelY, "VALUE")

        panelY = panelY + 22
        local blockIdx = math.min(math.max(#currentPiece.blocks, 1), 5)
        local pieceValue = CONFIG.SCORE_PER_BLOCKS[blockIdx] * level
        nvgFontSize(vg, 28)
        -- 颜色根据块数变化：多=绿，少=红
        local valR = math.floor(255 * (1 - (#currentPiece.blocks - 1) / 4))
        local valG = math.floor(255 * ((#currentPiece.blocks - 1) / 4))
        nvgFillColor(vg, nvgRGBA(valR, valG, 80, 255))
        nvgText(vg, panelX, panelY, "+" .. tostring(pieceValue))
    end
end

local function drawSidePanelLeft(vg)
    -- 左侧面板：倒计时、分数、等级、行数、操作说明
    local panelX = boardOffsetX - 20
    local panelY = boardOffsetY + 10

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)

    -- TIME (仅常规模式显示倒计时)
    if gameMode == "timed" then
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
        nvgText(vg, panelX, panelY, "TIME")
        panelY = panelY + 20

        local mins = math.floor(timeRemaining / 60)
        local secs = math.floor(timeRemaining % 60)
        local timeStr = string.format("%d:%02d", mins, secs)
        nvgFontSize(vg, 28)
        -- 时间少于30秒变红闪烁
        if timeRemaining <= 30 then
            local blink = math.floor(timeRemaining * 3) % 2 == 0
            if blink then
                nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
            else
                nvgFillColor(vg, nvgRGBA(255, 120, 80, 255))
            end
        elseif timeRemaining <= 60 then
            nvgFillColor(vg, nvgRGBA(255, 200, 60, 255))
        else
            nvgFillColor(vg, nvgRGBA(80, 255, 180, 255))
        end
        nvgText(vg, panelX, panelY, timeStr)
    end

    -- SCORE
    panelY = panelY + 50
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
    nvgText(vg, panelX, panelY, "SCORE")
    panelY = panelY + 20
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, panelX, panelY, tostring(score))

    -- LEVEL
    panelY = panelY + 50
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
    nvgText(vg, panelX, panelY, "LEVEL")
    panelY = panelY + 20
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(100, 220, 255, 255))
    nvgText(vg, panelX, panelY, tostring(level))

    -- LINES
    panelY = panelY + 50
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(150, 160, 200, 200))
    nvgText(vg, panelX, panelY, "LINES")
    panelY = panelY + 20
    nvgFontSize(vg, 28)
    nvgFillColor(vg, nvgRGBA(100, 255, 150, 255))
    nvgText(vg, panelX, panelY, tostring(linesCleared))

    -- 操作说明
    panelY = panelY + 70
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(100, 110, 140, 150))
    nvgText(vg, panelX, panelY, "← → 移动")
    panelY = panelY + 18
    nvgText(vg, panelX, panelY, "↑ / X 顺时针")
    panelY = panelY + 18
    nvgText(vg, panelX, panelY, "Z 逆时针")
    panelY = panelY + 18
    nvgText(vg, panelX, panelY, "↓ 加速")
    panelY = panelY + 18
    nvgText(vg, panelX, panelY, "空格 硬降")

    -- 旋转丢块提示
    panelY = panelY + 30
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 180, 60, 150))
    nvgText(vg, panelX, panelY, "旋转会随机丢失一块!")
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
    nvgText(vg, screenW / 2, screenH * 0.22, "PENTRIS")

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(180, 180, 220, 200))
    nvgText(vg, screenW / 2, screenH * 0.22 + 45, "五连块俄罗斯方块 · 18种方块")

    -- 特殊规则提示
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(255, 200, 80, 230))
    nvgText(vg, screenW / 2, screenH * 0.22 + 80, "特殊规则: 每次旋转随机丢失一块!")

    -- 模式选择
    local cx = screenW / 2
    local btnY = screenH * 0.52
    local btnW = 220
    local btnH = 50
    local gap = 20

    -- 按钮1: 常规模式
    local btn1Y = btnY - btnH - gap / 2
    local sel1 = (menuSelection == 1)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - btnW / 2, btn1Y, btnW, btnH, 8)
    if sel1 then
        nvgFillColor(vg, nvgRGBA(0, 160, 220, 240))
    else
        nvgFillColor(vg, nvgRGBA(40, 45, 65, 200))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, sel1 and nvgRGBA(80, 220, 255, 255) or nvgRGBA(70, 80, 110, 180))
    nvgStrokeWidth(vg, sel1 and 2.5 or 1.5)
    nvgStroke(vg)

    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, sel1 and 255 or 180))
    nvgText(vg, cx, btn1Y + btnH / 2, "常规模式 (3分钟)")

    -- 选中指示
    if sel1 then
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(vg, cx - btnW / 2 - 10, btn1Y + btnH / 2, ">")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end

    -- 按钮2: 无尽模式
    local btn2Y = btnY + gap / 2
    local sel2 = (menuSelection == 2)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, cx - btnW / 2, btn2Y, btnW, btnH, 8)
    if sel2 then
        nvgFillColor(vg, nvgRGBA(180, 60, 200, 240))
    else
        nvgFillColor(vg, nvgRGBA(40, 45, 65, 200))
    end
    nvgFill(vg)
    nvgStrokeColor(vg, sel2 and nvgRGBA(220, 120, 255, 255) or nvgRGBA(70, 80, 110, 180))
    nvgStrokeWidth(vg, sel2 and 2.5 or 1.5)
    nvgStroke(vg)

    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, sel2 and 255 or 180))
    nvgText(vg, cx, btn2Y + btnH / 2, "无尽模式 (无限时)")

    -- 选中指示
    if sel2 then
        nvgFontSize(vg, 20)
        nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(vg, cx - btnW / 2 - 10, btn2Y + btnH / 2, ">")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    end

    -- 提示
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(160, 170, 200, 200))
    nvgText(vg, cx, btn2Y + btnH + 35, "↑↓ 选择模式 | Enter/Space 确认")

    -- 操控说明
    nvgFontSize(vg, 13)
    nvgFillColor(vg, nvgRGBA(110, 120, 150, 150))
    nvgText(vg, cx, screenH * 0.85, "← → 移动 | ↑/X 顺时针 | Z 逆时针 | ↓ 加速 | 空格 硬降")
end

local function drawGameOver(vg)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillColor(vg, nvgRGBA(8, 8, 18, 230))
    nvgFill(vg)

    nvgFontFace(vg, "sans")
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    -- 左半边：本局结果
    local leftX = screenW * 0.3
    nvgFontSize(vg, 38)
    nvgFillColor(vg, nvgRGBA(255, 60, 60, 255))
    nvgText(vg, leftX, screenH * 0.25, "GAME OVER")

    -- 模式标签
    nvgFontSize(vg, 14)
    if gameMode == "timed" then
        nvgFillColor(vg, nvgRGBA(80, 200, 255, 200))
        nvgText(vg, leftX, screenH * 0.25 + 30, "常规模式")
    else
        nvgFillColor(vg, nvgRGBA(200, 140, 255, 200))
        nvgText(vg, leftX, screenH * 0.25 + 30, "无尽模式")
    end

    -- 结束原因
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(180, 180, 200, 180))
    if gameMode == "timed" and timeRemaining <= 0 then
        nvgText(vg, leftX, screenH * 0.25 + 50, "时间到!")
    else
        nvgText(vg, leftX, screenH * 0.25 + 50, "方块溢出!")
    end

    nvgFontSize(vg, 24)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
    nvgText(vg, leftX, screenH * 0.40, "得分: " .. tostring(score))

    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(160, 170, 200, 200))
    local timeInfo = ""
    if gameMode == "endless" then
        local mins = math.floor(timeElapsed / 60)
        local secs = math.floor(timeElapsed % 60)
        timeInfo = " | " .. string.format("%d:%02d", mins, secs)
    end
    nvgText(vg, leftX, screenH * 0.40 + 30, "Lv." .. level .. " | " .. linesCleared .. " lines" .. timeInfo)

    nvgFontSize(vg, 18)
    nvgFillColor(vg, nvgRGBA(200, 210, 240, 230))
    nvgText(vg, leftX, screenH * 0.57, "按 Enter/Space 返回菜单")

    -- 右半边：排行榜
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

    if #lb == 0 then
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(120, 120, 140, 160))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(vg, rightX, startY, "暂无记录")
    else
        for i, entry in ipairs(lb) do
            local y = startY + (i - 1) * rowH

            -- 排名
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgFontSize(vg, 16)
            if i <= 3 then
                local rankColors = {
                    {255, 215, 0, 255},   -- 金
                    {192, 192, 192, 255},  -- 银
                    {205, 127, 50, 255},   -- 铜
                }
                nvgFillColor(vg, nvgRGBA(table.unpack(rankColors[i])))
            else
                nvgFillColor(vg, nvgRGBA(180, 180, 200, 200))
            end
            nvgText(vg, rightX - 80, y, "#" .. i)

            -- 分数
            nvgFontSize(vg, 18)
            if entry.score == score and i == 1 then
                nvgFillColor(vg, nvgRGBA(255, 255, 100, 255))
            else
                nvgFillColor(vg, nvgRGBA(240, 240, 255, 230))
            end
            nvgText(vg, rightX - 50, y, tostring(entry.score))

            -- 附加信息
            nvgFontSize(vg, 11)
            nvgFillColor(vg, nvgRGBA(120, 130, 160, 160))
            nvgText(vg, rightX + 30, y + 2, "Lv." .. (entry.level or 1) .. " " .. (entry.time or ""))
        end
    end
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

    -- 全屏布局：棋盘尽可能铺满屏幕高度，留边距
    local vertPadding = 20
    local availH = screenH - vertPadding * 2
    local availW = screenW * 0.5  -- 棋盘最多占屏幕一半宽度（两侧留给信息面板）

    local csFromH = math.floor(availH / CONFIG.ROWS)
    local csFromW = math.floor(availW / CONFIG.COLS)
    cellSize = math.min(csFromH, csFromW)

    -- 棋盘居中
    local boardW = CONFIG.COLS * cellSize
    local boardH = CONFIG.ROWS * cellSize
    boardOffsetX = (screenW - boardW) / 2
    boardOffsetY = (screenH - boardH) / 2

    nvgBeginFrame(vg, screenW, screenH, dpr)

    -- 背景渐变
    local bgPaint = nvgLinearGradient(vg, 0, 0, 0, screenH,
        nvgRGBA(12, 12, 30, 255), nvgRGBA(5, 5, 15, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, screenW, screenH)
    nvgFillPaint(vg, bgPaint)
    nvgFill(vg)

    if gameState == "menu" then
        drawMenu(vg)
    elseif gameState == "playing" then
        drawBoard(vg)
        drawCurrentPiece(vg)
        drawSidePanelLeft(vg)
        drawSidePanelRight(vg)
    elseif gameState == "gameover" then
        drawBoard(vg)
        drawCurrentPiece(vg)
        drawGameOver(vg)
    end

    nvgEndFrame(vg)
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    updateGame(dt)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if gameState == "menu" then
        if key == KEY_UP or key == KEY_W then
            menuSelection = menuSelection == 1 and 2 or 1
        elseif key == KEY_DOWN or key == KEY_S then
            menuSelection = menuSelection == 2 and 1 or 2
        elseif key == KEY_RETURN or key == KEY_SPACE then
            local mode = menuSelection == 1 and "timed" or "endless"
            startGame(mode)
        end
        return
    end

    if gameState == "gameover" then
        if key == KEY_RETURN or key == KEY_SPACE then
            gameState = "menu"
        end
        return
    end

    if key == KEY_LEFT then
        actionMoveLeft()
        moveDir = -1
        moveTimer = 0
        moveHeld = true
    elseif key == KEY_RIGHT then
        actionMoveRight()
        moveDir = 1
        moveTimer = 0
        moveHeld = true
    elseif key == KEY_UP or key == KEY_X then
        actionRotateCW()
    elseif key == KEY_Z then
        actionRotateCCW()
    elseif key == KEY_DOWN then
        fastDrop = true
    elseif key == KEY_SPACE then
        actionHardDrop()
    end
end

function HandleKeyUp(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_DOWN then
        fastDrop = false
    elseif key == KEY_LEFT then
        if moveDir == -1 then moveDir = 0; moveHeld = false end
    elseif key == KEY_RIGHT then
        if moveDir == 1 then moveDir = 0; moveHeld = false end
    end
end

function HandleMouseClick(eventType, eventData)
    if gameState == "gameover" then
        gameState = "menu"
    elseif gameState == "menu" then
        -- 检测点击位置是否在按钮上
        local dpr = graphics:GetDPR()
        local mx = input.mousePosition.x / dpr
        local my = input.mousePosition.y / dpr

        local cx = screenW / 2
        local btnY = screenH * 0.52
        local btnW = 220
        local btnH = 50
        local gap = 20

        local btn1Left = cx - btnW / 2
        local btn1Top = btnY - btnH - gap / 2
        local btn2Left = cx - btnW / 2
        local btn2Top = btnY + gap / 2

        if mx >= btn1Left and mx <= btn1Left + btnW and my >= btn1Top and my <= btn1Top + btnH then
            startGame("timed")
        elseif mx >= btn2Left and mx <= btn2Left + btnW and my >= btn2Top and my <= btn2Top + btnH then
            startGame("endless")
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

    -- NanoVG
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

    -- 加载排行榜
    loadLeaderboard()

    -- 事件
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
