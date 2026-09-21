local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
local vkeys = require 'vkeys'
local inicfg = require 'inicfg'
local lfs = require 'lfs'
local memory = require 'memory'

local vk_name_by_code = {}
for vk_name, vk_code in pairs(vkeys) do
    if type(vk_code) == "number" and not vk_name_by_code[vk_code] then
        vk_name_by_code[vk_code] = vk_name:gsub("^VK_", "")
    end
end

local function get_key_name(vk_code)
    if not vk_code then return "F12" end
    return vk_name_by_code[vk_code] or ("0x" .. string.format("%02X", vk_code))
end

-- Список клавиш для выбора внутри окна (вместо ожидания нажатия клавиши на клавиатуре).
-- Берём все известные модулю vkeys коды, кроме ESC (он используется для отмены).
local KB_PICKER_VKS = {}
for vk_code in pairs(vk_name_by_code) do
    if vk_code ~= vkeys.VK_ESCAPE then
        table.insert(KB_PICKER_VKS, vk_code)
    end
end
table.sort(KB_PICKER_VKS)

encoding.default = 'UTF-8'
u8 = encoding.UTF8

ffi.cdef[[
    short GetKeyState(int nVirtKey);
    unsigned long GetWindowThreadProcessId(intptr_t hWnd, unsigned long* lpdwProcessId);
    intptr_t GetForegroundWindow();
    intptr_t GetKeyboardLayout(unsigned long idThread);
]]

local mhg_dir = getWorkingDirectory() .. "\\MHG"
local config_dir = getWorkingDirectory() .. "\\config\\MHG"

if not lfs.attributes(mhg_dir, "mode") then lfs.mkdir(mhg_dir) end
if not lfs.attributes(config_dir, "mode") then lfs.mkdir(config_dir) end

local GITHUB_URL = "https://raw.githubusercontent.com/goosik123/gmh/main/accounts.txt"
local ACCOUNTS_FILE = mhg_dir .. "\\arz_accounts.txt"
local AVATAR_FILE = mhg_dir .. "\\mhg_avatar.jpg"
local CONFIG_FILE = "MHG\\MHG_session.ini"

-- === Auto-update (GitHub) ===
local SCRIPT_VERSION = "1.0.2"
local SCRIPT_URL = "https://raw.githubusercontent.com/goosik123/gmh/main/MafiaHelperByGoose.lua"
local UPDATE_CHECK_INTERVAL = 10 -- секунд между авто-проверками обновления

local session_cfg = inicfg.load({
    session = {
        is_logged = false,
        saved_nick = "",
        saved_password = ""
    },
    settings = {
        particles_enabled = true,
        particles_style = 1,      -- 1 сеть, 2 снег, 3 пузыри, 4 светлячки, 5 звёзды, 6 дождь
        particles_density = 1.0,  -- множитель количества
        particles_speed = 1.0,    -- множитель скорости
        particles_dir_enabled = false, -- кастомное направление полёта (pad)
        particles_dir_x = 0.0,    -- направление полёта частиц: -1..1, (0,0) = стоят на месте
        particles_dir_y = 0.0,
        tab_effects_enabled = true,
        window_glow_enabled = true,
        window_glow_style = 1,     -- 1 пульс, 2 дыхание, 3 радуга, 4 змейка
        window_glow_speed = 1.0,
        theme = 1,
        custom_avatar_url = "",
        asp_enabled = false, -- ASP
        asp_value = 1.25,
        watermark_enabled = true,
        watermark_x = -1,      -- положение Watermark: -1 = по умолчанию (правый верхний угол)
        watermark_y = -1,
        watermark_halign = 2,  -- 0 = левый край, 1 = по центру, 2 = правый край
        watermark_valign = 0,  -- 0 = верх, 1 = низ
        watermark_show_fps = true,
        watermark_show_ping = true,
        watermark_show_pl = true,
        open_key = vkeys.VK_F12,
        keyboard_enabled = false,
        keyboard_block_c = false,
        keyboard_layout = ""
    }
}, CONFIG_FILE)

local avatar_url_buf = imgui.new.char[256]()
if session_cfg.settings.custom_avatar_url then
    ffi.copy(avatar_url_buf, session_cfg.settings.custom_avatar_url)
end

local asp_val_buf = imgui.new.float[1](session_cfg.settings.asp_value or 1.25)
local asp_chk_hover_alpha = 0.0
local reset_btn_hover_alpha = 0.0

local show_avatar_url = false 
local input_anim_w = 0.0

local themes = {
    [1] = {
        name = u8"Фиолетовый",
        text = imgui.ImVec4(0.78, 0.55, 1.00, 1.00),
        text_muted = imgui.ImVec4(0.55, 0.40, 0.75, 0.75),
        accent = {0.78, 0.55, 1.00},
        bg_idle = {0.10, 0.08, 0.15},
        bg_hover = {0.22, 0.14, 0.40},
        bg_act = {0.30, 0.15, 0.58},
        bor_idle = {0.18, 0.14, 0.30},
        bor_hover = {0.50, 0.30, 0.80},
        bor_act = {0.78, 0.45, 1.00}
    },
    [2] = {
        name = u8"Серый",
        text = imgui.ImVec4(0.95, 0.95, 0.95, 1.00),
        text_muted = imgui.ImVec4(0.70, 0.70, 0.70, 0.75),
        accent = {0.95, 0.95, 0.95},
        bg_idle = {0.10, 0.10, 0.10},
        bg_hover = {0.22, 0.22, 0.22},
        bg_act = {0.30, 0.30, 0.30},
        bor_idle = {0.18, 0.18, 0.18},
        bor_hover = {0.50, 0.50, 0.50},
        bor_act = {0.80, 0.80, 0.80}
    },
    [3] = {
        name = u8"Бирюзовый",
        text = imgui.ImVec4(0.25, 0.88, 0.82, 1.00),
        text_muted = imgui.ImVec4(0.20, 0.60, 0.55, 0.75),
        accent = {0.25, 0.88, 0.82},
        bg_idle = {0.08, 0.12, 0.12},
        bg_hover = {0.12, 0.25, 0.24},
        bg_act = {0.15, 0.35, 0.33},
        bor_idle = {0.12, 0.20, 0.20},
        bor_hover = {0.20, 0.50, 0.48},
        bor_act = {0.25, 0.75, 0.70}
    },
    [4] = {
        name = u8"Зелёный",
        text = imgui.ImVec4(0.40, 0.90, 0.40, 1.00),
        text_muted = imgui.ImVec4(0.30, 0.60, 0.30, 0.75),
        accent = {0.40, 0.90, 0.40},
        bg_idle = {0.08, 0.12, 0.08},
        bg_hover = {0.14, 0.28, 0.14},
        bg_act = {0.20, 0.45, 0.20},
        bor_idle = {0.14, 0.20, 0.14},
        bor_hover = {0.30, 0.55, 0.30},
        bor_act = {0.40, 0.80, 0.40}
    },
    [5] = {
        name = u8"Жёлтый",
        text = imgui.ImVec4(1.00, 0.82, 0.20, 1.00),
        text_muted = imgui.ImVec4(0.70, 0.58, 0.15, 0.75),
        accent = {1.00, 0.82, 0.20},
        bg_idle = {0.14, 0.12, 0.08},
        bg_hover = {0.33, 0.27, 0.12},
        bg_act = {0.48, 0.38, 0.15},
        bor_idle = {0.24, 0.20, 0.12},
        bor_hover = {0.65, 0.52, 0.20},
        bor_act = {1.00, 0.80, 0.20}
    },
    [6] = {
        name = u8"Красный",
        text = imgui.ImVec4(1.00, 0.35, 0.35, 1.00),
        text_muted = imgui.ImVec4(0.70, 0.25, 0.25, 0.75),
        accent = {1.00, 0.35, 0.35},
        bg_idle = {0.15, 0.08, 0.08},
        bg_hover = {0.35, 0.14, 0.14},
        bg_act = {0.52, 0.18, 0.18},
        bor_idle = {0.28, 0.12, 0.12},
        bor_hover = {0.70, 0.25, 0.25},
        bor_act = {1.00, 0.30, 0.30}
    },
    [7] = {
        name = u8"Коричневый",
        text = imgui.ImVec4(0.88, 0.68, 0.45, 1.00),
        text_muted = imgui.ImVec4(0.62, 0.46, 0.30, 0.75),
        accent = {0.82, 0.58, 0.32},
        bg_idle = {0.14, 0.09, 0.05},
        bg_hover = {0.32, 0.20, 0.11},
        bg_act = {0.45, 0.28, 0.14},
        bor_idle = {0.26, 0.17, 0.10},
        bor_hover = {0.58, 0.37, 0.19},
        bor_act = {0.88, 0.58, 0.26}
    },
    [8] = {
        name = u8"Розовый",
        text = imgui.ImVec4(1.00, 0.55, 0.80, 1.00),
        text_muted = imgui.ImVec4(0.75, 0.35, 0.58, 0.75),
        accent = {1.00, 0.45, 0.75},
        bg_idle = {0.16, 0.06, 0.12},
        bg_hover = {0.36, 0.14, 0.28},
        bg_act = {0.52, 0.18, 0.40},
        bor_idle = {0.26, 0.12, 0.20},
        bor_hover = {0.72, 0.28, 0.54},
        bor_act = {1.00, 0.40, 0.72}
    },
    [9] = {
        name = u8"Радужный",
        -- базовые цвета используются только как отправная точка перехода;
        -- пока эта тема активна, get_theme() поверх них крутит радужный HSV-цикл
        text = imgui.ImVec4(1.00, 0.35, 0.35, 1.00),
        text_muted = imgui.ImVec4(0.70, 0.25, 0.25, 0.75),
        accent = {1.00, 0.35, 0.35},
        bg_idle = {0.10, 0.08, 0.10},
        bg_hover = {0.24, 0.14, 0.24},
        bg_act = {0.36, 0.18, 0.36},
        bor_idle = {0.18, 0.12, 0.18},
        bor_hover = {0.55, 0.25, 0.55},
        bor_act = {1.00, 0.30, 0.30},
        rainbow = true
    }
}

local RAINBOW_THEME_IDX = 9

local function hsv_to_rgb(h, s, v)
    h = h % 1.0
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local tt = v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, tt, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, tt
    elseif i == 3 then return p, q, v
    elseif i == 4 then return tt, p, v
    else return v, p, q end
end

local THEME_TRANSITION_DURATION = 0.35 -- seconds

local function ease_out_cubic(k)
    local inv = 1.0 - k
    return 1.0 - inv * inv * inv
end

local function lerp_color3(a, b, k)
    return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

local function lerp_vec4(a, b, k)
    return imgui.ImVec4(
        a.x + (b.x - a.x) * k,
        a.y + (b.y - a.y) * k,
        a.z + (b.z - a.z) * k,
        a.w + (b.w - a.w) * k
    )
end

local theme_cur_idx = session_cfg.settings.theme or 1
local theme_from = themes[theme_cur_idx]
local theme_to = themes[theme_cur_idx]
local theme_transition_start = os.clock()
local theme_last_blended = themes[theme_cur_idx]

-- живой кадр радужной палитры (новая таблица каждый вызов — themes[] не трогаем)
local function build_rainbow_theme()
    local hue = (os.clock() * 0.12) % 1.0
    local ar, ag, ab = hsv_to_rgb(hue, 0.78, 1.00)
    local br, bg_, bb = hsv_to_rgb(hue, 0.55, 0.16)
    local hr, hg, hb = hsv_to_rgb(hue, 0.55, 0.34)
    local acr, acg, acb = hsv_to_rgb(hue, 0.55, 0.50)
    local bri, brg, brb = hsv_to_rgb(hue, 0.45, 0.22)
    local brh, brgh, brbh = hsv_to_rgb(hue, 0.55, 0.55)
    local base = themes[RAINBOW_THEME_IDX]
    return {
        name = base and base.name or u8"Радужный",
        rainbow = true,
        text = imgui.ImVec4(ar, ag, ab, 1.00),
        text_muted = imgui.ImVec4(ar * 0.75, ag * 0.75, ab * 0.75, 0.75),
        accent = { ar, ag, ab },
        bg_idle = { br, bg_, bb },
        bg_hover = { hr, hg, hb },
        bg_act = { acr, acg, acb },
        bor_idle = { bri, brg, brb },
        bor_hover = { brh, brgh, brbh },
        bor_act = { ar, ag, ab }
    }
end

local function blend_themes(from, to, k)
    return {
        name = to.name,
        rainbow = to.rainbow,
        text = lerp_vec4(from.text, to.text, k),
        text_muted = lerp_vec4(from.text_muted, to.text_muted, k),
        accent = lerp_color3(from.accent, to.accent, k),
        bg_idle = lerp_color3(from.bg_idle, to.bg_idle, k),
        bg_hover = lerp_color3(from.bg_hover, to.bg_hover, k),
        bg_act = lerp_color3(from.bg_act, to.bg_act, k),
        bor_idle = lerp_color3(from.bor_idle, to.bor_idle, k),
        bor_hover = lerp_color3(from.bor_hover, to.bor_hover, k),
        bor_act = lerp_color3(from.bor_act, to.bor_act, k)
    }
end

local function get_theme()
    local target_idx = session_cfg.settings.theme or 1
    if target_idx ~= theme_cur_idx and themes[target_idx] then
        -- старт перехода с того, что сейчас на экране (без скачка при повторном переключении)
        theme_from = theme_last_blended
        theme_to = themes[target_idx]
        theme_transition_start = os.clock()
        theme_cur_idx = target_idx
    end

    local elapsed = os.clock() - theme_transition_start
    local k = THEME_TRANSITION_DURATION > 0 and math.min(1.0, elapsed / THEME_TRANSITION_DURATION) or 1.0
    k = ease_out_cubic(k)

    local blended
    local to_is_rainbow = theme_to and theme_to.rainbow

    if to_is_rainbow then
        -- цель — живой HSV-кадр, а не статичный красный из themes[9].
        -- иначе в конце перехода был резкий прыжок «красный → текущий hue» (мигание).
        local live = build_rainbow_theme()
        if k >= 1.0 then
            blended = live
        else
            blended = blend_themes(theme_from, live, k)
        end
    else
        if k >= 1.0 then
            blended = theme_to
        else
            blended = blend_themes(theme_from, theme_to, k)
        end
    end

    theme_last_blended = blended
    return blended
end

local auth = {
    show = false,
    alpha = 0.0,
    password = imgui.new.char[256](),
    status = u8'Ожидание...',
    accounts = {},
    account_map = {},
    loaded = false,
    downloading = false,
    download_start = 0.0,
    stage = 'idle',
    timer = 0.0,
    stage_alpha = 0.0
}

local update_ui = {
    show = false,
    alpha = 0.0,
    remote_ver = "",
    stage = 'idle',
    timer = 0.0,
    stage_alpha = 0.0,
    btn_alpha = 0.0,
    pending = nil,
    load_progress = 0.0,
    available = false
}

local function is_update_locked()
    -- lock until update is applied (even if window was closed)
    return update_ui and update_ui.available == true
end

local force_show_update  -- forward declaration (defined after menu)
local KB                 -- forward declaration (экранная клавиатура, определяется ниже)

local menu = {
    show = false,
    alpha = 0.0,
    current_tab = 1,
    sidebar_alpha = 0.0,
    bottombar_alpha = 0.0,
    bottom_content_alpha = 0.0,
    content_y_anim = 25.0,
    -- плавность смены вкладок: fade + лёгкий сдвиг контента
    tab_content_alpha = 1.0,
    tab_content_y = 0.0,
    title_fade = 1.0,
    title_tab = 1,
    hotkey_listening = false,
    -- положение окна меню (нужно, чтобы перетаскивание WM не начиналось "сквозь" меню)
    win_x = 0, win_y = 0, win_w = 0, win_h = 0,
    -- правка положения Watermark
    wm = { edit = false, edit_alpha = 0.0, drag = false, drag_dx = 0.0, drag_dy = 0.0,
           reveal = 0.0 }, -- WM включён: кнопка сужается, появляется шестерёнка
    -- отдельное окно настроек (открывается шестерёнкой у Keyboard / ASP / Watermark)
    pop = { id = nil, shown = nil, anim = 0.0, content_t = 0.0, x = 0, y = 0, w = 0, h = 0,
            tabs = { kb = 1, asp = 2, wm = 3, pt = 3, glow = 3 } }, -- вкладка, к которой относится окно
    pt_reveal = 0.0,                   -- частицы включены: кнопка сужается, появляется шестерёнка
    pt_dens = imgui.new.float[1](1.0), -- буферы ползунков окна настроек частиц
    pt_speed = imgui.new.float[1](1.0),
    glow_reveal = 0.0,                 -- свечение включено: кнопка сужается, появляется шестерёнка
    glow_speed = imgui.new.float[1](1.0),
    btn_anim = {},
    text_anim = {},                    -- плавное появление подписей
}

local user_avatar_texture = nil

local function get_my_nick()
    if not isSampAvailable() then return 'Unknown' end
    local result, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if result then
        local nick = sampGetPlayerNickname(id)
        if nick then return nick:gsub("%b[]", "") end
    end
    return 'Unknown'
end

local function load_user_avatar()
    local url = session_cfg.settings.custom_avatar_url
    if url and url ~= "" then
        if not doesFileExist(AVATAR_FILE) then
            downloadUrlToFile(url, AVATAR_FILE, function(id, status)
                if status == 6 then
                    pcall(function()
                        user_avatar_texture = imgui.CreateTextureFromFile(AVATAR_FILE)
                    end)
                end
            end)
        else
            if not user_avatar_texture then
                pcall(function()
                    user_avatar_texture = imgui.CreateTextureFromFile(AVATAR_FILE)
                end)
            end
        end
    else
        user_avatar_texture = nil
        if doesFileExist(AVATAR_FILE) then
            os.remove(AVATAR_FILE)
        end
    end
end

local btn_active_alpha = 0.0
local close_hover_alpha = 0.0
local tab_hover_alphas = {0.0, 0.0, 0.0}
local tab_fill_progress = {1.0, 0.0, 0.0}
local checkbox_hover_alpha = 0.0
local fx_btn_hover_alpha = 0.0
local glow_btn_hover_alpha = 0.0
local hotkey_btn_hover_alpha = 0.0
local logout_hover_alpha = 0.0
local action_btn_hover_alpha = 0.0
local eye_hover_alpha = 0.0
local wm_hover_alpha = 0.0
local slider_hover_alphas = {}
-- Fill progress for smooth checkbox/radio animations
local asp_fill_progress = session_cfg.settings.asp_enabled and 1.0 or 0.0
local asp_reveal = session_cfg.settings.asp_enabled and 1.0 or 0.0
local particles_fill_progress = session_cfg.settings.particles_enabled and 1.0 or 0.0
local tabfx_fill_progress = session_cfg.settings.tab_effects_enabled and 1.0 or 0.0
local glow_fill_progress = session_cfg.settings.window_glow_enabled and 1.0 or 0.0
local wm_fill_progress = (session_cfg.settings.watermark_enabled ~= false) and 1.0 or 0.0
local wm_overlay_alpha = (session_cfg.settings.watermark_enabled ~= false) and 1.0 or 0.0
local wm_anim_w = 0.0
local wm_anim_h = 0.0
local theme_fill_progress = {1.0, 0.0, 0.0, 0.0, 0.0, 0.0}
if session_cfg.settings.theme then
    for i = 1, 6 do
        theme_fill_progress[i] = (session_cfg.settings.theme == i) and 1.0 or 0.0
    end
end
local particles_fade_alpha = session_cfg.settings.particles_enabled and 1.0 or 0.0
local glow_anim_alpha = session_cfg.settings.window_glow_enabled and 1.0 or 0.0
local shake_timer = 0.0

-- Пресеты положения Watermark: halign 0/1/2 = слева/по центру/справа,
-- valign 0/1 = сверху/снизу. Отступ от края экрана — как у положения по умолчанию.
-- Для valign=1 watermark_y хранит нижний край WM; для halign=1 watermark_x — центр экрана.
local WM_PRESET_MARGIN_X = 12
local WM_PRESET_MARGIN_Y = 10
local function apply_wm_preset(halign, valign)
    local cfg = session_cfg.settings
    local sw, sh = getScreenResolution()
    cfg.watermark_halign = halign
    cfg.watermark_valign = valign
    cfg.watermark_right = (halign == 2) and 1 or 0
    if halign == 0 then
        cfg.watermark_x = WM_PRESET_MARGIN_X
    elseif halign == 2 then
        cfg.watermark_x = sw - WM_PRESET_MARGIN_X
    else
        cfg.watermark_x = math.floor(sw * 0.5)
    end
    if valign == 0 then
        cfg.watermark_y = WM_PRESET_MARGIN_Y
    else
        cfg.watermark_y = sh - WM_PRESET_MARGIN_Y
    end
    menu.wm.drag = false
    menu.wm.edit = false
    inicfg.save(session_cfg, CONFIG_FILE)
end

local asp_original_a, asp_original_b
local asp_captured = false

local function capture_asp_original()
    if asp_captured then return end
    asp_captured = true
    -- читаем РОВНО то, что сейчас в клиенте (до любого apply_asp).
    -- Не подставляем width/height: у SA по этим адресам не «чистый» aspect экрана,
    -- из‑за этого при выключении экран и становился вытянутым.
    pcall(function() asp_original_a = memory.getfloat(0xC3EFA4, true) end)
    pcall(function() asp_original_b = memory.getfloat(0xC17044, true) end)
    if type(asp_original_a) ~= "number" or asp_original_a < 0.3 or asp_original_a > 3.5 then
        asp_original_a = 1.0
    end
    if type(asp_original_b) ~= "number" or asp_original_b < 0.3 or asp_original_b > 3.5 then
        asp_original_b = asp_original_a
    end
end

local function get_asp_native()
    capture_asp_original()
    return asp_original_a or 1.0, asp_original_b or asp_original_a or 1.0
end

local function apply_asp(value)
    if not value then value = 1.0 end
    capture_asp_original()
    memory.setfloat(0xC3EFA4, value, true)
    pcall(function()
        memory.setfloat(0xC17044, value, true)
    end)
end

local function disable_asp()
    -- возвращаем именно те значения, что были до включения ASP
    local a, b = get_asp_native()
    memory.setfloat(0xC3EFA4, a, true)
    pcall(function()
        memory.setfloat(0xC17044, b, true)
    end)
end

local function lerp(a, b, speed)
    return a + (b - a) * speed
end

local function CustomSliderFloat(str_id, label, p_val, v_min, v_max, size, alpha_mult)
    size = size or imgui.ImVec2(218, 32)
    alpha_mult = alpha_mult or 1.0
    local sl_alpha = menu.alpha * alpha_mult
    slider_hover_alphas[str_id] = slider_hover_alphas[str_id] or 0.0

    local p_slider = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()
    local t = get_theme()

    imgui.InvisibleButton(str_id, size)
    local is_hovered = imgui.IsItemHovered()
    local is_active = imgui.IsItemActive()

    if is_active then
        local mouse_x = imgui.GetIO().MousePos.x
        local rel_x = math.max(0.0, math.min(size.x, mouse_x - p_slider.x))
        local frac = rel_x / size.x
        p_val[0] = v_min + frac * (v_max - v_min)
    end

    slider_hover_alphas[str_id] = lerp(slider_hover_alphas[str_id], (is_hovered or is_active) and 1.0 or 0.0, 0.14)
    local hover_p = slider_hover_alphas[str_id]

    local s_min = p_slider
    local s_max = imgui.ImVec2(p_slider.x + size.x, p_slider.y + size.y)

    local bg_r = lerp(t.bg_idle[1], t.bg_hover[1], hover_p)
    local bg_g = lerp(t.bg_idle[2], t.bg_hover[2], hover_p)
    local bg_b = lerp(t.bg_idle[3], t.bg_hover[3], hover_p)
    local bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bg_r, bg_g, bg_b, 0.40 * sl_alpha))

    local frac = (p_val[0] - v_min) / (v_max - v_min)
    frac = math.max(0.0, math.min(1.0, frac))
    local fill_w = size.x * frac
    local fill_max = imgui.ImVec2(p_slider.x + fill_w, p_slider.y + size.y)

    local fill_r = lerp(t.bg_hover[1], t.bg_act[1], is_active and 1.0 or 0.7)
    local fill_g = lerp(t.bg_hover[2], t.bg_act[2], is_active and 1.0 or 0.7)
    local fill_b = lerp(t.bg_hover[3], t.bg_act[3], is_active and 1.0 or 0.7)
    local fill_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(fill_r, fill_g, fill_b, 0.65 * sl_alpha))

    local bor_r = lerp(t.bor_idle[1], t.bor_hover[1], hover_p)
    local bor_g = lerp(t.bor_idle[2], t.bor_hover[2], hover_p)
    local bor_b = lerp(t.bor_idle[3], t.bor_hover[3], hover_p)
    if is_active then
        bor_r, bor_g, bor_b = t.bor_act[1], t.bor_act[2], t.bor_act[3]
    end
    local bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bor_r, bor_g, bor_b, lerp(0.25, 0.95, hover_p) * sl_alpha))

    draw_list:AddRectFilled(s_min, s_max, bg_col, 6.0)
    if fill_w > 0 then
        draw_list:AddRectFilled(s_min, fill_max, fill_col, 6.0)
    end
    draw_list:AddRect(s_min, s_max, bor_col, 6.0, 15, 1.2)

    local display_str = string.format("%s: %.2f", label, p_val[0])
    local txt_sz = imgui.CalcTextSize(display_str)
    local txt_pos = imgui.ImVec2(s_min.x + (size.x - txt_sz.x) / 2, s_min.y + (size.y - txt_sz.y) / 2)
    local txt_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, lerp(0.65, 1.00, hover_p) * sl_alpha))
    draw_list:AddText(txt_pos, txt_col, display_str)
end

-- Круговой регулятор направления частиц: точка внутри круга, направление от центра
-- к точке задаёт направление полёта частиц. Точка в центре — частицы стоят на месте.
-- cfg[key_x]/cfg[key_y] хранят координаты точки в диапазоне -1..1.
local function CustomDirectionPad(str_id, cfg, key_x, key_y, diameter, alpha_mult)
    alpha_mult = alpha_mult or 1.0
    local a = menu.alpha * alpha_mult
    slider_hover_alphas[str_id] = slider_hover_alphas[str_id] or 0.0

    local size = imgui.ImVec2(diameter, diameter)
    local p = imgui.GetCursorScreenPos()
    local draw_list = imgui.GetWindowDrawList()
    local t = get_theme()
    local radius = diameter * 0.5
    local cx, cy = p.x + radius, p.y + radius

    imgui.InvisibleButton(str_id, size)
    local is_hovered = imgui.IsItemHovered()
    local is_active = imgui.IsItemActive()

    local dx, dy = cfg[key_x] or 0.0, cfg[key_y] or 0.0

    if is_active then
        local mp = imgui.GetIO().MousePos
        local rx, ry = (mp.x - cx) / (radius - 6), (mp.y - cy) / (radius - 6)
        local mag = math.sqrt(rx * rx + ry * ry)
        if mag > 1.0 then rx, ry = rx / mag, ry / mag end
        if mag < 0.06 then rx, ry = 0.0, 0.0 end -- лёгкий "магнит" к центру
        dx, dy = rx, ry
        if math.abs((cfg[key_x] or 0.0) - dx) > 0.001 or math.abs((cfg[key_y] or 0.0) - dy) > 0.001 then
            cfg[key_x], cfg[key_y] = dx, dy
            inicfg.save(session_cfg, CONFIG_FILE)
        end
    end

    slider_hover_alphas[str_id] = lerp(slider_hover_alphas[str_id], (is_hovered or is_active) and 1.0 or 0.0, 0.14)
    local hover_p = slider_hover_alphas[str_id]

    local bg_r = lerp(t.bg_idle[1], t.bg_hover[1], hover_p)
    local bg_g = lerp(t.bg_idle[2], t.bg_hover[2], hover_p)
    local bg_b = lerp(t.bg_idle[3], t.bg_hover[3], hover_p)
    draw_list:AddCircleFilled(imgui.ImVec2(cx, cy), radius,
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bg_r, bg_g, bg_b, 0.40 * a)), 32)

    local bor_r = lerp(t.bor_idle[1], t.bor_hover[1], hover_p)
    local bor_g = lerp(t.bor_idle[2], t.bor_hover[2], hover_p)
    local bor_b = lerp(t.bor_idle[3], t.bor_hover[3], hover_p)
    if is_active then bor_r, bor_g, bor_b = t.bor_act[1], t.bor_act[2], t.bor_act[3] end
    draw_list:AddCircle(imgui.ImVec2(cx, cy), radius,
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bor_r, bor_g, bor_b, lerp(0.35, 0.95, hover_p) * a)), 32, 1.2)

    -- метка центра (частицы стоят на месте)
    draw_list:AddCircle(imgui.ImVec2(cx, cy), 3.0,
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, 0.55 * a)), 12, 1.0)

    -- линия от центра к точке + сама точка
    local dot_x, dot_y = cx + dx * (radius - 6), cy + dy * (radius - 6)
    local line_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 0.55 * a))
    draw_list:AddLine(imgui.ImVec2(cx, cy), imgui.ImVec2(dot_x, dot_y), line_col, 1.4)
    local dot_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], a))
    draw_list:AddCircleFilled(imgui.ImVec2(dot_x, dot_y), 5.0, dot_col, 16)
    draw_list:AddCircle(imgui.ImVec2(dot_x, dot_y), 5.0,
        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.6 * a)), 16, 1.0)

    imgui.Dummy(imgui.ImVec2(0, 2))
end

local function toggle_menu()
    if is_update_locked() then
        force_show_update()
        return
    end
    if auth.show then
        auth.show = false
        return
    end
    menu.show = not menu.show
    if menu.show then
        menu.sidebar_alpha = 0.0
        menu.bottombar_alpha = 0.0
        menu.bottom_content_alpha = 0.0
        menu.content_y_anim = 25.0
        load_user_avatar()
    end
end

imgui.OnInitialize(function()
    local io = imgui.GetIO()
    local font_path = os.getenv("WINDIR") .. "\\Fonts\\tahoma.ttf"
    if doesFileExist(font_path) then
        io.Fonts:AddFontFromFileTTF(font_path, 14.0, nil, io.Fonts:GetGlyphRangesCyrillic())
    else
        io.Fonts:AddFontDefault()
    end
    load_user_avatar()
end)

local function is_caps_active()
    return bit.band(ffi.C.GetKeyState(vkeys.VK_CAPITAL), 1) ~= 0
end

local function get_keyboard_layout_name()
    local hwnd = ffi.C.GetForegroundWindow()
    local thread_id = ffi.C.GetWindowThreadProcessId(hwnd, nil)
    local layout = ffi.C.GetKeyboardLayout(thread_id)
    local lang_id = bit.band(tonumber(ffi.cast("uintptr_t", layout)), 0xFFFF)
    
    if lang_id == 0x0419 then return "RU"
    elseif lang_id == 0x0409 then return "EN" end
    return "??"
end

-- =========================================================
-- ================  ЧАСТИЦЫ (несколько видов)  =============
-- =========================================================
-- Один движок на все поверхности (меню, окно входа, окно обновления, окно настроек, Watermark):
-- у каждой поверхности своё поле частиц. Вид, количество и скорость берутся из настроек
-- (settings.particles_style / particles_density / particles_speed).
local PT = {
    -- порядок = номер вида в настройках
    styles = { u8"Сеть", u8"Снег", u8"Пузыри", u8"Светлячки", u8"Звёзды", u8"Дождь" },
    -- base — число частиц при плотности 1.0, link — дальность связей (вид "Сеть"),
    -- k — масштаб размера, spd — множитель скорости, a — множитель прозрачности
    presets = {
        menu   = { base = 35, link = 75, k = 1.0, spd = 1.0, a = 1.0 },
        auth   = { base = 18, link = 62, k = 1.0, spd = 1.0, a = 1.0 },
        update = { base = 18, link = 62, k = 1.0, spd = 1.0, a = 1.0 },
        popup  = { base = 14, link = 55, k = 0.9, spd = 1.0, a = 0.9 },
        wm     = { base = 10, link = 26, k = 0.7, spd = 0.8, a = 0.9 },
    },
    fields = {}
}

function PT.col(r, g, b, a)
    return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r, g, b, a))
end

function PT.spawn(style, w, h)
    local rnd = math.random
    local x, y = rnd() * w, rnd() * h
    if style == 1 then      -- сеть
        return { x = x, y = y, vx = (rnd() - 0.5) * 0.4, vy = (rnd() - 0.5) * 0.4, r = 1.5 }
    elseif style == 2 then  -- снег
        return { bx = x, x = x, y = y, vy = 0.25 + rnd() * 0.45, amp = 3 + rnd() * 8,
                 fq = 0.5 + rnd() * 0.9, ph = rnd() * 6.28, r = 1.0 + rnd() * 1.6 }
    elseif style == 3 then  -- пузыри
        return { bx = x, x = x, y = y, vy = -(0.15 + rnd() * 0.35), amp = 2 + rnd() * 4,
                 fq = 0.6 + rnd() * 0.8, ph = rnd() * 6.28, r = 2.0 + rnd() * 3.5 }
    elseif style == 4 then  -- светлячки
        return { x = x, y = y, ang = rnd() * 6.28, sp = 0.12 + rnd() * 0.25,
                 ph = rnd() * 6.28, fq = 0.8 + rnd() * 1.4, r = 1.1 + rnd() * 1.0 }
    elseif style == 5 then  -- звёзды
        return { x = x, y = y, vx = 0.02 + rnd() * 0.06, ph = rnd() * 6.28,
                 fq = 0.7 + rnd() * 1.6, r = 1.4 + rnd() * 2.0 }
    end
    -- дождь
    local vy = 2.2 + rnd() * 2.6
    return { x = rnd() * (w + 40) - 20, y = y, vy = vy, vx = vy * 0.22, len = 7 + rnd() * 8 }
end

function PT.draw(surface, draw_list, pos, size, global_alpha)
    local cfg = session_cfg.settings
    local pr = PT.presets[surface] or PT.presets.menu
    local f = PT.fields[surface]
    if not f then
        f = { list = {}, style = 0, fade = cfg.particles_enabled and 1.0 or 0.0 }
        PT.fields[surface] = f
    end

    f.fade = lerp(f.fade, cfg.particles_enabled and 1.0 or 0.0, 0.06)
    if f.fade < 0.001 then return end

    local style = math.max(1, math.min(math.floor(cfg.particles_style or 1), #PT.styles))
    local density = math.max(0.1, math.min(cfg.particles_density or 1.0, 3.0))
    local spd = math.max(0.1, math.min(cfg.particles_speed or 1.0, 3.0)) * pr.spd
    local w, h = size.x, size.y

    -- кастомное направление только если включён чекбокс; иначе — родное движение стиля
    local dir_on = cfg.particles_dir_enabled and true or false
    local dir_x = dir_on and (cfg.particles_dir_x or 0.0) or 0.0
    local dir_y = dir_on and (cfg.particles_dir_y or 0.0) or 0.0
    local dir_mag = math.sqrt(dir_x * dir_x + dir_y * dir_y)
    local drift = 0.55 * spd
    local dx_off = dir_x * drift
    local dy_off = dir_y * drift
    -- при включённом направлении и точке в центре — частицы стоят;
    -- при выключенном направлении motion_k = 1 (обычная анимация стиля)
    local motion_k = (not dir_on) and 1.0 or ((dir_mag < 0.06) and 0.0 or 1.0)

    -- смена вида пересоздаёт частицы, смена количества — добавляет/убирает по одной
    if f.style ~= style then
        f.list = {}
        f.style = style
    end
    local want = math.max(1, math.floor(pr.base * density + 0.5))
    while #f.list > want do table.remove(f.list) end
    while #f.list < want do f.list[#f.list + 1] = PT.spawn(style, w, h) end

    local t = get_theme()
    local ac, bh = t.accent, t.bor_hover
    local ca = global_alpha * f.fade * pr.a
    local col = PT.col
    local now = os.clock()
    local rnd = math.random
    local L = f.list
    local V2 = imgui.ImVec2

    if style == 1 then
        -- сеть: точки, соединённые линиями
        for i, p in ipairs(L) do
            p.x = p.x + (p.vx * spd * motion_k) + dx_off
            p.y = p.y + (p.vy * spd * motion_k) + dy_off
            if p.x < 0 then p.x = w end
            if p.x > w then p.x = 0 end
            if p.y < 0 then p.y = h end
            if p.y > h then p.y = 0 end

            local px, py = pos.x + p.x, pos.y + p.y
            for j = i + 1, #L do
                local p2 = L[j]
                local dx, dy = p.x - p2.x, p.y - p2.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < pr.link then
                    draw_list:AddLine(V2(px, py), V2(pos.x + p2.x, pos.y + p2.y),
                        col(bh[1], bh[2], bh[3], (1.0 - dist / pr.link) * 0.25 * ca), 1.0)
                end
            end
            draw_list:AddCircleFilled(V2(px, py), p.r * pr.k, col(ac[1], ac[2], ac[3], 0.35 * ca))
        end

    elseif style == 2 then
        -- снег: мягко покачиваются и падают (+ направление)
        local sr, sg, sb = ac[1] * 0.4 + 0.6, ac[2] * 0.4 + 0.6, ac[3] * 0.4 + 0.6
        for _, p in ipairs(L) do
            p.y = p.y + (p.vy * spd * motion_k) + dy_off
            p.bx = p.bx + dx_off
            if p.y > h + 4 then
                p.y = -4
                p.bx = rnd() * w
            elseif p.y < -4 then
                p.y = h + 4
                p.bx = rnd() * w
            end
            if p.bx < 0 then p.bx = w end
            if p.bx > w then p.bx = 0 end
            p.x = p.bx + math.sin(now * p.fq + p.ph) * p.amp * motion_k
            draw_list:AddCircleFilled(V2(pos.x + p.x, pos.y + p.y), p.r * pr.k,
                col(sr, sg, sb, (0.22 + p.r * 0.14) * ca))
        end

    elseif style == 3 then
        -- пузыри: всплывают, слегка виляя; контур + блик (+ направление)
        for _, p in ipairs(L) do
            p.y = p.y + (p.vy * spd * motion_k) + dy_off
            p.bx = p.bx + dx_off
            if p.y < -p.r * 2 then
                p.y = h + p.r * 2
                p.bx = rnd() * w
            elseif p.y > h + p.r * 2 then
                p.y = -p.r * 2
                p.bx = rnd() * w
            end
            if p.bx < 0 then p.bx = w end
            if p.bx > w then p.bx = 0 end
            p.x = p.bx + math.sin(now * p.fq + p.ph) * p.amp * motion_k
            local r = p.r * pr.k
            local c = V2(pos.x + p.x, pos.y + p.y)
            draw_list:AddCircleFilled(c, r, col(ac[1], ac[2], ac[3], 0.05 * ca))
            draw_list:AddCircle(c, r, col(ac[1], ac[2], ac[3], 0.38 * ca), 16, 1.0)
            draw_list:AddCircleFilled(V2(c.x - r * 0.35, c.y - r * 0.35), math.max(0.6, r * 0.16),
                col(1, 1, 1, 0.45 * ca))
        end

    elseif style == 4 then
        -- светлячки: блуждают и мерцают, вокруг — мягкое свечение (+ направление)
        local fr, fg, fb = ac[1] * 0.4 + 0.6, ac[2] * 0.4 + 0.55, ac[3] * 0.4 + 0.2
        for _, p in ipairs(L) do
            p.ang = p.ang + (rnd() - 0.5) * 0.25 * motion_k
            p.x = p.x + math.cos(p.ang) * p.sp * spd * motion_k + dx_off
            p.y = p.y + math.sin(p.ang) * p.sp * spd * motion_k + dy_off
            if p.x < 0 then p.x = w end
            if p.x > w then p.x = 0 end
            if p.y < 0 then p.y = h end
            if p.y > h then p.y = 0 end

            local tw = 0.5 + 0.5 * math.sin(now * p.fq + p.ph)
            local r = p.r * pr.k
            local c = V2(pos.x + p.x, pos.y + p.y)
            draw_list:AddCircleFilled(c, r * 3.4, col(fr, fg, fb, 0.08 * tw * ca))
            draw_list:AddCircleFilled(c, r * 1.9, col(fr, fg, fb, 0.14 * tw * ca))
            draw_list:AddCircleFilled(c, r, col(fr, fg, fb, (0.25 + 0.65 * tw) * ca))
        end

    elseif style == 5 then
        -- звёзды: медленно дрейфуют и мерцают четырёхлучевым блеском (+ направление)
        local sr, sg, sb = ac[1] * 0.4 + 0.6, ac[2] * 0.4 + 0.6, ac[3] * 0.4 + 0.6
        for _, p in ipairs(L) do
            p.x = p.x + (p.vx * spd * motion_k) + dx_off
            p.y = p.y + dy_off
            if p.x > w + 4 then
                p.x = -4
                p.y = rnd() * h
            elseif p.x < -4 then
                p.x = w + 4
                p.y = rnd() * h
            end
            if p.y > h + 4 then p.y = -4 end
            if p.y < -4 then p.y = h + 4 end
            local tw = 0.5 + 0.5 * math.sin(now * p.fq + p.ph)
            local r = p.r * pr.k * (0.6 + 0.6 * tw)
            local a1 = (0.18 + 0.62 * tw) * ca
            local c = col(sr, sg, sb, a1)
            local px, py = pos.x + p.x, pos.y + p.y
            draw_list:AddLine(V2(px - r * 1.6, py), V2(px + r * 1.6, py), c, 1.0)
            draw_list:AddLine(V2(px, py - r * 1.6), V2(px, py + r * 1.6), c, 1.0)
            draw_list:AddCircleFilled(V2(px, py), math.max(0.7, r * 0.35), col(1, 1, 1, a1))
        end

    else
        -- дождь: наклонные быстрые штрихи; при dir_on скорость полностью от pad
        for _, p in ipairs(L) do
            local mvx, mvy
            if dir_on then
                if dir_mag < 0.06 then
                    mvx, mvy = 0.0, 0.0
                else
                    -- направление pad задаёт вектор падения (нормализованный * базовая скорость дождя)
                    local base = (2.2 + (p.vy or 2.5) * 0.15)
                    mvx = dir_x * base
                    mvy = dir_y * base
                    -- если почти горизонтально — всё равно чуть тянем по Y, чтобы штрих был виден
                    if math.abs(mvy) < 0.35 then
                        mvy = (mvy >= 0 and 0.35 or -0.35)
                    end
                end
            else
                mvx = p.vx
                mvy = p.vy
            end
            p.x = p.x + mvx * spd
            p.y = p.y + mvy * spd
            if p.y > h + p.len then
                p.y = -p.len
                p.x = rnd() * (w + 40) - 20
            elseif p.y < -p.len then
                p.y = h + p.len
                p.x = rnd() * (w + 40) - 20
            end
            if p.x > w + 20 then p.x = -20 end
            if p.x < -20 then p.x = w + 20 end
            local px, py = pos.x + p.x, pos.y + p.y
            local len = p.len * pr.k
            local mag = math.sqrt(mvx * mvx + mvy * mvy)
            local tx, ty = 0.0, len
            if mag > 0.001 then
                tx = (mvx / mag) * len
                ty = (mvy / mag) * len
            end
            -- штрих рисуем против направления движения (хвост капли)
            draw_list:AddLine(V2(px, py), V2(px - tx, py - ty),
                col(bh[1], bh[2], bh[3], 0.30 * ca), 1.0)
        end
    end
end

local function init_particles()
    PT.fields = {}
end

-- окна меню / входа / обновления / настроек (surface: "menu" | "auth" | "update" | "popup")
local function draw_particle_grid(draw_list, pos, size, global_alpha, surface)
    PT.draw(surface or "menu", draw_list, pos, size, global_alpha)
end

-- Watermark: отдельное поле частиц (мельче и медленнее)
local function draw_wm_particles(draw_list, pos, size, global_alpha, t)
    PT.draw("wm", draw_list, pos, size, global_alpha)
end

-- Режимы свечения окон: 1 пульс (оригинал), 2 дыхание, 3 радуга, 4 змейка
local GLOW_STYLES = {
    u8"Пульс",
    u8"Дыхание",
    u8"Радуга",
    u8"Змейка",
}

-- точка на периметре прямоугольника (d — длина от левого верхнего угла, по часовой)
local function glow_perimeter_point(x, y, w, h, d)
    local per = 2.0 * (w + h)
    if per < 1.0 then return x, y end
    d = d % per
    if d < 0 then d = d + per end
    if d <= w then
        return x + d, y
    end
    d = d - w
    if d <= h then
        return x + w, y + d
    end
    d = d - h
    if d <= w then
        return x + w - d, y + h
    end
    d = d - w
    return x, y + h - d
end

local function draw_window_glow(pos, size, alpha)
    local cfg = session_cfg.settings
    local target_glow = cfg.window_glow_enabled and 1.0 or 0.0
    glow_anim_alpha = lerp(glow_anim_alpha, target_glow, 0.08)

    if glow_anim_alpha < 0.001 then return end

    local draw_list = imgui.GetBackgroundDrawList()
    local t = get_theme()
    local style = math.max(1, math.min(math.floor(cfg.window_glow_style or 1), #GLOW_STYLES))
    local speed = math.max(0.2, math.min(cfg.window_glow_speed or 1.0, 3.0))
    local a = alpha * glow_anim_alpha
    local now = os.clock()

    -- при радужной теме свечение НЕ радужное: нейтральный белый, режим «Радуга» → пульс
    local ar, ag, ab
    if t.rainbow then
        ar, ag, ab = 0.95, 0.95, 1.0
        if style == 3 then style = 1 end
    else
        ar, ag, ab = t.accent[1], t.accent[2], t.accent[3]
    end

    if style == 1 then
        -- пульс — исходное свечение
        local pulse = math.sin(now * 3.0 * speed) * 0.5 + 0.5
        local glow_alpha = (0.3 + pulse * 0.5) * a
        for i = 3, 1, -1 do
            local offset = i * 2.0
            local p_min = imgui.ImVec2(pos.x - offset, pos.y - offset)
            local p_max = imgui.ImVec2(pos.x + size.x + offset, pos.y + size.y + offset)
            local current_alpha = glow_alpha / (i * 1.2)
            local color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ar, ag, ab, current_alpha))
            draw_list:AddRect(p_min, p_max, color, 12.0 + offset, 15, 2.0)
        end

    elseif style == 2 then
        -- дыхание: медленный in/out + лёгкое расширение
        local breath = math.sin(now * 1.4 * speed) * 0.5 + 0.5
        local expand = 1.0 + breath * 0.35
        for i = 3, 1, -1 do
            local offset = i * 2.2 * expand
            local p_min = imgui.ImVec2(pos.x - offset, pos.y - offset)
            local p_max = imgui.ImVec2(pos.x + size.x + offset, pos.y + size.y + offset)
            local la = a * (0.18 + breath * 0.40) / (i * 1.25)
            draw_list:AddRect(p_min, p_max,
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ar, ag, ab, la)),
                12.0 + offset, 15, 1.8)
        end

    elseif style == 3 then
        -- радуга: слои со сдвигом hue (только если тема НЕ радужная)
        local base_hue = (now * 0.15 * speed) % 1.0
        for i = 4, 1, -1 do
            local offset = i * 2.1
            local hr, hg, hb = hsv_to_rgb((base_hue + i * 0.08) % 1.0, 0.78, 1.00)
            local p_min = imgui.ImVec2(pos.x - offset, pos.y - offset)
            local p_max = imgui.ImVec2(pos.x + size.x + offset, pos.y + size.y + offset)
            local la = a * 0.38 / (i * 1.1)
            draw_list:AddRect(p_min, p_max,
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(hr, hg, hb, la)),
                12.0 + offset, 15, 2.0)
        end

    else
        -- змейка: яркий сегмент бежит по периметру окна
        local pad = 3.0
        local x, y = pos.x - pad, pos.y - pad
        local w, h = size.x + pad * 2, size.y + pad * 2
        local per = 2.0 * (w + h)
        if per > 1.0 then
            local head = (now * 120.0 * speed) % per
            local body_len = per * 0.22
            local segs = 28
            local prev_x, prev_y = glow_perimeter_point(x, y, w, h, head)
            for s = 1, segs do
                local d = head - (s / segs) * body_len
                local px, py = glow_perimeter_point(x, y, w, h, d)
                local fade = 1.0 - (s / segs)
                fade = fade * fade
                local thick = 1.2 + fade * 2.4
                local col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ar, ag, ab, (0.15 + 0.85 * fade) * a))
                draw_list:AddLine(imgui.ImVec2(prev_x, prev_y), imgui.ImVec2(px, py), col, thick)
                prev_x, prev_y = px, py
            end
            -- голова змейки
            local hx, hy = glow_perimeter_point(x, y, w, h, head)
            draw_list:AddCircleFilled(imgui.ImVec2(hx, hy), 3.2,
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ar, ag, ab, 0.95 * a)), 12)
            draw_list:AddCircleFilled(imgui.ImVec2(hx, hy), 5.5,
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ar, ag, ab, 0.22 * a)), 12)
        end
    end
end

local function draw_spinner(draw_list, center, radius, thickness, color)
    local time = os.clock() * 6.0
    local num_segments = 30
    local start_angle = time
    local end_angle = time + (math.pi * 1.4)
    
    draw_list:PathClear()
    for i = 0, num_segments do
        local a = start_angle + (i / num_segments) * (end_angle - start_angle)
        draw_list:PathLineTo(imgui.ImVec2(center.x + math.cos(a) * radius, center.y + math.sin(a) * radius))
    end
    draw_list:PathStroke(color, false, thickness)
end

local function check_account(nick, password)
    if not nick or nick == "" or not password or password == "" then return false end
    if auth.account_map and auth.account_map[nick] then
        return auth.account_map[nick] == password
    end
    for _, acc in ipairs(auth.accounts) do
        if acc.nick == nick and acc.password == password then return true end
    end
    return false
end

-- выкинуть в окно авторизации (аккаунт удалён / пароль не совпал / ник сменился)
local function force_logout()
    session_cfg.session.is_logged = false
    session_cfg.session.saved_nick = ""
    session_cfg.session.saved_password = ""
    inicfg.save(session_cfg, CONFIG_FILE)
    menu.show = false
    if menu.pop then menu.pop.id = nil end
    auth.show = true
    auth.stage = 'idle'
    auth.stage_alpha = 0.0
    ffi.fill(auth.password, ffi.sizeof(auth.password))
    shake_timer = 0.0
end

-- true = сессия ок; false = разлогинили.
-- если список ещё не загружен — не трогаем (нет сети / идёт загрузка).
local function validate_logged_session()
    if not session_cfg.session.is_logged then return true end
    if not auth.loaded then return true end
    local nick = get_my_nick()
    local saved_nick = session_cfg.session.saved_nick or ""
    local saved_pass = session_cfg.session.saved_password or ""
    if saved_nick == "" or nick ~= saved_nick or not check_account(saved_nick, saved_pass) then
        force_logout()
        return false
    end
    return true
end

local AUTH_RECHECK_INTERVAL = 45.0 -- сек: периодически тянем список и проверяем сессию

local function load_accounts(on_loaded)
    if auth.downloading then return end
    auth.downloading = true
    auth.download_start = os.clock()
    -- локальный кэш читаем только как fallback, пока качается свежий список;
    -- после успешной загрузки карта полностью заменяется содержимым с GitHub

    downloadUrlToFile(GITHUB_URL .. "?nocache=" .. os.time(), ACCOUNTS_FILE, function(id, status, progress)
        if status == 6 then
            auth.accounts = {}
            auth.account_map = {}
            local file = io.open(ACCOUNTS_FILE, "r")
            if file then
                for line in file:lines() do
                    line = line:gsub("[\r\n]", ""):match("^%s*(.-)%s*$")
                    if line ~= "" and not line:find("^#") then
                        local nick, password = line:match("^(.-):(.+)$")
                        if nick and password then
                            table.insert(auth.accounts, {nick = nick, password = password})
                            auth.account_map[nick] = password
                        end
                    end
                end
                file:close()
            end
            auth.loaded = (#auth.accounts > 0)
            auth.downloading = false
            -- после каждого успешного обновления списка — проверка сессии
            validate_logged_session()
            if on_loaded then on_loaded() end
        elseif status == 4 or status == 5 then
            -- сеть/ошибка: подхватываем локальный кэш, если ещё пусто
            if not auth.loaded and doesFileExist(ACCOUNTS_FILE) then
                auth.accounts = {}
                auth.account_map = {}
                local file = io.open(ACCOUNTS_FILE, "r")
                if file then
                    for line in file:lines() do
                        line = line:gsub("[\r\n]", ""):match("^%s*(.-)%s*$")
                        if line ~= "" and not line:find("^#") then
                            local nick, password = line:match("^(.-):(.+)$")
                            if nick and password then
                                table.insert(auth.accounts, {nick = nick, password = password})
                                auth.account_map[nick] = password
                            end
                        end
                    end
                    file:close()
                    auth.loaded = (#auth.accounts > 0)
                end
            end
            auth.downloading = false
            if auth.loaded then
                validate_logged_session()
            end
            if on_loaded then on_loaded() end
        end
    end)
end

local function apply_window_position(w, h)
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.Always)
end

local function close_all()
    auth.show = false
    menu.show = false
    -- can hide update window, but available stays true -> cannot open menu
    if update_ui and update_ui.stage ~= "loading" and update_ui.stage ~= "success" then
        update_ui.show = false
    end
end

force_show_update = function()
    if not update_ui.available then return end
    if update_ui.stage == "loading" or update_ui.stage == "success" then
        update_ui.show = true
        return
    end
    update_ui.show = true
    update_ui.stage = "idle"
    update_ui.stage_alpha = 0.0
    update_ui.btn_alpha = 0.0
    auth.show = false
    menu.show = false
end

local function open_mhg()
    -- if update required: always show update window instead of menu/auth
    if is_update_locked() then
        force_show_update()
        return
    end
    if auth.show then
        close_all()
        return
    end
    if session_cfg.session.is_logged then
        -- перед открытием меню ещё раз сверяем аккаунт со списком
        if auth.loaded and not validate_logged_session() then
            return
        end
        toggle_menu()
    else
        auth.show = true
        auth.stage = 'idle'
        auth.stage_alpha = 0.0
        ffi.fill(auth.password, ffi.sizeof(auth.password))
        shake_timer = 0.0
    end
end


local function draw_close_button(win_width, alpha)
    local t = get_theme()
    imgui.SetCursorPosX(win_width - 26)
    imgui.SetCursorPosY(8)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * alpha))
    
    if imgui.Button("X##close", imgui.ImVec2(18, 18)) then close_all() end
    imgui.PopStyleColor(4)
end

function auth.draw()
    if is_update_locked() then
        auth.show = false
    end
    auth.alpha = lerp(auth.alpha, auth.show and 1.0 or 0.0, 0.12)
    if auth.alpha < 0.01 then return end
    
    local t = get_theme()

    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, auth.alpha)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 0)

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.07, 0.08, 0.11, 0.98))
    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.12, 0.13, 0.17, 1.0))
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.16, 0.17, 0.22, 1.0))
    imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0.18, 0.20, 0.26, 1.0))
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w))

    apply_window_position(340, 230)

    if imgui.Begin('##auth', nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar) then
        local draw_list = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        
        draw_window_glow(pos, size, auth.alpha)
        draw_particle_grid(draw_list, pos, size, auth.alpha, "auth")

        draw_close_button(340, auth.alpha)

        local now = os.clock()
        auth.stage_alpha = lerp(auth.stage_alpha, 1.0, 0.1)

        if auth.stage == 'loading' then
            if now - auth.timer >= 0.55 then
                auth.stage = 'success'
                auth.stage_alpha = 0.0
                auth.timer = now
            end
        elseif auth.stage == 'success' then
            if now - auth.timer >= 0.7 then
                auth.show = false
                menu.show = true
                menu.sidebar_alpha = 0.0
                menu.bottombar_alpha = 0.0
                menu.bottom_content_alpha = 0.0
                menu.content_y_anim = 25.0
                auth.stage = 'idle'
                auth.stage_alpha = 0.0
                ffi.fill(auth.password, ffi.sizeof(auth.password))
            end
        end

        local current_stage_alpha = auth.alpha * auth.stage_alpha

        if auth.stage == 'idle' then
            imgui.Dummy(imgui.ImVec2(0, 16))
            imgui.SetWindowFontScale(1.25)
            local title = u8'Авторизация'
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(title).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * current_stage_alpha), title)
            imgui.SetWindowFontScale(1.0)

            imgui.Dummy(imgui.ImVec2(0, 20))
            imgui.PushItemWidth(-1)
            imgui.InputText('##pass', auth.password, ffi.sizeof(auth.password), imgui.InputTextFlags.Password)
            imgui.PopItemWidth()

            imgui.Dummy(imgui.ImVec2(0, 14))
            local btn_text = auth.loaded and u8'Войти' or u8'Загрузка...'
            local base_size = imgui.ImVec2(240, 40)
            
            local shake_offset_x = 0.0
            if shake_timer > 0 then
                shake_timer = shake_timer - 1
                shake_offset_x = math.sin(shake_timer * 3.0) * 6.0 * (shake_timer / 15.0)
            end

            imgui.SetCursorPosX((340 - base_size.x) / 2 + shake_offset_x)
            local p = imgui.GetCursorScreenPos()
            local has_text = ffi.string(auth.password):len() > 0

            if imgui.InvisibleButton('##custom_login_btn', base_size) then
                if auth.loaded and has_text then
                    local pass = u8:decode(ffi.string(auth.password))
                    local nick = get_my_nick()

                    if check_account(nick, pass) then
                        session_cfg.session.is_logged = true
                        session_cfg.session.saved_nick = nick
                        session_cfg.session.saved_password = pass
                        inicfg.save(session_cfg, CONFIG_FILE)

                        auth.stage = 'loading'
                        auth.stage_alpha = 0.0
                        auth.timer = os.clock()
                    else
                        shake_timer = 15
                        ffi.fill(auth.password, ffi.sizeof(auth.password))
                    end
                end
            end

            local is_active = imgui.IsItemActive()
            local target_active = has_text and 1.0 or 0.0
            btn_active_alpha = lerp(btn_active_alpha, target_active, 0.12)

            local p_min = p
            local p_max = imgui.ImVec2(p.x + base_size.x, p.y + base_size.y)
            local rounding = 10.0

            local bg_r = lerp(t.bg_idle[1], t.bg_hover[1], btn_active_alpha)
            local bg_g = lerp(t.bg_idle[2], t.bg_hover[2], btn_active_alpha)
            local bg_b = lerp(t.bg_idle[3], t.bg_hover[3], btn_active_alpha)
            local bg_a = lerp(0.20, 0.65, btn_active_alpha)

            local border_r = lerp(t.bor_idle[1], t.bor_hover[1], btn_active_alpha)
            local border_g = lerp(t.bor_idle[2], t.bor_hover[2], btn_active_alpha)
            local border_b = lerp(t.bor_idle[3], t.bor_hover[3], btn_active_alpha)
            local border_a = lerp(0.20, 0.95, btn_active_alpha)

            if is_active and has_text then
                bg_r, bg_g, bg_b, bg_a = t.bg_act[1], t.bg_act[2], t.bg_act[3], 0.50
                border_r, border_g, border_b, border_a = t.bor_act[1], t.bor_act[2], t.bor_act[3], 1.00
            end

            local bg_color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bg_r, bg_g, bg_b, bg_a * current_stage_alpha))
            local border_color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(border_r, border_g, border_b, border_a * current_stage_alpha))

            draw_list:AddRectFilled(p_min, p_max, bg_color, rounding)
            draw_list:AddRect(p_min, p_max, border_color, rounding, 15, 1.2)

            local text_size = imgui.CalcTextSize(btn_text)
            local text_pos = imgui.ImVec2(p_min.x + (base_size.x - text_size.x) / 2, p_min.y + (base_size.y - text_size.y) / 2)
            local text_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, lerp(0.30, 1.00, btn_active_alpha) * current_stage_alpha))
            draw_list:AddText(text_pos, text_col, btn_text)

            imgui.SetCursorPosY(195)
            imgui.SetWindowFontScale(0.82)
            local info_str = string.format("%s %s  |  Caps Lock: %s", u8'Язык:', get_keyboard_layout_name(), is_caps_active() and u8'Вкл' or u8'Выкл')
            local info_w = imgui.CalcTextSize(info_str).x
            imgui.SetCursorPosX((340 - info_w) / 2)
            imgui.TextColored(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, t.text_muted.w * current_stage_alpha), info_str)
            imgui.SetWindowFontScale(1.0)

        elseif auth.stage == 'loading' then
            imgui.Dummy(imgui.ImVec2(0, 45))
            local spinner_center = imgui.ImVec2(pos.x + 170, pos.y + 90)
            local spinner_color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], current_stage_alpha))
            draw_spinner(draw_list, spinner_center, 18.0, 3.0, spinner_color)
            imgui.Dummy(imgui.ImVec2(0, 30))
            imgui.SetWindowFontScale(1.1)
            local txt = u8'Проверка аккаунта...'
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(txt).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * current_stage_alpha), txt)
            imgui.SetWindowFontScale(1.0)

        elseif auth.stage == 'success' then
            imgui.Dummy(imgui.ImVec2(0, 45))
            local circle_center = imgui.ImVec2(pos.x + 170, pos.y + 90)
            local circle_radius = 18.0
            local fill = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bg_act[1], t.bg_act[2], t.bg_act[3], 0.70 * current_stage_alpha))
            local border = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], current_stage_alpha))
            
            draw_list:AddCircleFilled(circle_center, circle_radius, fill)
            draw_list:AddCircle(circle_center, circle_radius, border, 20, 1.5)

            local p1 = imgui.ImVec2(circle_center.x - 6.0, circle_center.y - 1.0)
            local p2 = imgui.ImVec2(circle_center.x - 1.5, circle_center.y + 4.5)
            local p3 = imgui.ImVec2(circle_center.x + 6.5, circle_center.y - 4.5)
            local white_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 1.0, 1.0, current_stage_alpha))
            draw_list:AddLine(p1, p2, white_col, 2.5)
            draw_list:AddLine(p2, p3, white_col, 2.5)

            imgui.Dummy(imgui.ImVec2(0, 30))
            imgui.SetWindowFontScale(1.1)
            local txt = u8'Успешно!'
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(txt).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * current_stage_alpha), txt)
            imgui.SetWindowFontScale(1.0)
        end
        imgui.End()
    end
    imgui.PopStyleColor(5)
    imgui.PopStyleVar(5)
end

-- Текст ожидания назначения клавиши.
-- base — строка без точек; dots — ровно 3 символа (чтобы ширина не прыгала);
-- pulse — 0.35..1.0 для яркости текста.
local function waiting_key_anim(prefix)
    prefix = prefix or u8"Нажмите клавишу"
    local t = os.clock()
    -- фаза 0..2: подсвечиваем одну из трёх точек по кругу
    local phase = math.floor(t * 4.0) % 3
    local chars = { ".", ".", "." }
    -- активная точка ярче за счёт замены на более «жирную»
    chars[phase + 1] = ":"
    local dots = chars[1] .. chars[2] .. chars[3]
    -- более заметный пульс яркости
    local pulse = 0.40 + 0.60 * (0.5 + 0.5 * math.sin(t * 5.0))
    return prefix, dots, pulse
end

-- полный лейбл «Нажмите клавишу...» с анимированными точками
local function waiting_key_label(prefix)
    local base, dots, pulse = waiting_key_anim(prefix)
    return base .. dots, pulse
end

-- Плавное появление подписи (muted/обычный текст) с лёгким сдвигом вверх.
-- alpha_mult — доп. множитель; StyleVar.Alpha окна уже учитывается imgui.
function menu.anim_text(str_id, text, col, alpha_mult)
    alpha_mult = alpha_mult or 1.0
    local st = menu.text_anim[str_id]
    if not st then
        st = { a = 0.0 }
        menu.text_anim[str_id] = st
    end
    st.a = lerp(st.a, 1.0, 0.12)
    local k = ease_out_cubic(st.a)
    local c = col or get_theme().text_muted
    local a = (c.w or 1.0) * alpha_mult * k
    local y_off = (1.0 - k) * 6.0
    imgui.Dummy(imgui.ImVec2(0.1, y_off))
    imgui.TextColored(imgui.ImVec4(c.x, c.y, c.z, a), text)
end

-- Кнопка в стиле меню (та же анимация наведения/заливки, что и у остальных).
-- active — подсвеченное состояние, dim — приглушённая недоступная кнопка,
-- danger — красная кнопка (удаление). Возвращает true при клике.
function menu.button(str_id, label, size, active, alpha_mult, dim, danger)
    alpha_mult = alpha_mult or 1.0
    local t = get_theme()
    local dl = imgui.GetWindowDrawList()
    local st = menu.btn_anim[str_id]
    if not st then
        st = { hover = 0.0, fill = 0.0, appear = 0.0, press = 0.0 }
        menu.btn_anim[str_id] = st
    end

    local p = imgui.GetCursorScreenPos()
    local clicked = imgui.InvisibleButton(str_id, size)
    local hovered = imgui.IsItemHovered() and not dim
    local held = imgui.IsItemActive() and not dim
    st.hover = lerp(st.hover, hovered and 1.0 or 0.0, 0.16)
    st.fill = lerp(st.fill, active and 1.0 or 0.0, 0.12)
    st.appear = lerp(st.appear, 1.0, 0.13)
    st.press = lerp(st.press, held and 1.0 or 0.0, 0.22)

    local h, f = st.hover, st.fill
    local ap = ease_out_cubic(math.max(0.0, math.min(st.appear, 1.0)))
    local pr = st.press
    -- появление: снизу + fade; при нажатии — лёгкое «вдавливание»
    local y_slide = (1.0 - ap) * 8.0
    local inset = pr * 1.2
    local a = menu.alpha * alpha_mult * (dim and 0.45 or 1.0) * ap
    local p1 = imgui.ImVec2(p.x + inset, p.y + y_slide + inset)
    local p2 = imgui.ImVec2(p.x + size.x - inset, p.y + size.y + y_slide - inset * 0.5)

    -- анимация ожидания клавиши (по id кнопки — без сравнения кириллицы/кодировок)
    local text_pulse = 1.0
    local draw_label = label
    local is_wait_btn = (str_id == "##pop_kb_add" and active)
    if is_wait_btn then
        local base, dots, pulse = waiting_key_anim(u8"Нажмите клавишу")
        draw_label = base .. dots
        text_pulse = pulse
        a = menu.alpha * ap -- фон не пульсирует от alpha_mult
    end

    local bg_r, bg_g, bg_b, bg_a, br_r, br_g, br_b, br_a, tx_a
    if danger then
        bg_r, bg_g, bg_b = lerp(t.bg_idle[1], 0.45, h), lerp(t.bg_idle[2], 0.12, h), lerp(t.bg_idle[3], 0.12, h)
        bg_a = lerp(0.20, 0.75, h)
        br_r, br_g, br_b = lerp(t.bor_idle[1], 0.85, h), lerp(t.bor_idle[2], 0.25, h), lerp(t.bor_idle[3], 0.25, h)
        br_a = lerp(0.25, 0.95, h)
        tx_a = lerp(0.75, 1.00, h)
    else
        bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], h), t.bg_act[1], f)
        bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], h), t.bg_act[2], f)
        bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], h), t.bg_act[3], f)
        bg_a = lerp(lerp(0.20, 0.45, h), 0.75, f)
        br_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], h), t.bor_act[1], f)
        br_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], h), t.bor_act[2], f)
        br_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], h), t.bor_act[3], f)
        br_a = lerp(lerp(0.25, 0.60, h), 0.95, f)
        tx_a = lerp(lerp(0.65, 0.85, h), 1.00, f)
    end

    dl:AddRectFilled(p1, p2, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bg_r, bg_g, bg_b, bg_a * a)), 6.0)
    dl:AddRect(p1, p2, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(br_r, br_g, br_b, br_a * a)), 6.0, 15, 1.2)

    -- точки рисуем отдельно: «бегущая» яркая точка среди трёх
    if is_wait_btn then
        local base, dots, pulse = waiting_key_anim(u8"Нажмите клавишу")
        local base_sz = imgui.CalcTextSize(base)
        local dots_sz = imgui.CalcTextSize("...")
        local total_w = base_sz.x + dots_sz.x
        local tx = p1.x + (p2.x - p1.x - total_w) / 2
        local ty = p1.y + (p2.y - p1.y - base_sz.y) / 2
        local base_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, tx_a * a * pulse))
        dl:AddText(imgui.ImVec2(tx, ty), base_col, base)
        local tclock = os.clock()
        local phase = math.floor(tclock * 4.0) % 3
        local dx = tx + base_sz.x
        for i = 0, 2 do
            local bright = (i == phase) and 1.0 or 0.25
            local dcol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, tx_a * a * bright))
            local ch = "."
            local csz = imgui.CalcTextSize(ch)
            dl:AddText(imgui.ImVec2(dx, ty), dcol, ch)
            dx = dx + csz.x
        end
    else
        local lsz = imgui.CalcTextSize(draw_label)
        dl:AddText(imgui.ImVec2(p1.x + (p2.x - p1.x - lsz.x) / 2, p1.y + (p2.y - p1.y - lsz.y) / 2),
            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, tx_a * a * text_pulse)), draw_label)
    end

    return clicked
end

-- Квадратная кнопка с шестерёнкой (рисуется вручную). active — панель настроек раскрыта:
-- шестерёнка при этом плавно поворачивается. alpha_mult — общая прозрачность/масштаб иконки.
function menu.gear_button(str_id, size, active, alpha_mult)
    alpha_mult = alpha_mult or 1.0
    local t = get_theme()
    local dl = imgui.GetWindowDrawList()
    local st = menu.btn_anim[str_id]
    if not st then
        st = { hover = 0.0, fill = 0.0, appear = 0.0 }
        menu.btn_anim[str_id] = st
    end

    local p = imgui.GetCursorScreenPos()
    local clicked = imgui.InvisibleButton(str_id, size)
    st.hover = lerp(st.hover, imgui.IsItemHovered() and 1.0 or 0.0, 0.16)
    st.fill = lerp(st.fill, active and 1.0 or 0.0, 0.12)
    st.appear = lerp(st.appear, 1.0, 0.14)

    local h, f = st.hover, st.fill
    local ap = ease_out_cubic(st.appear)
    local a = menu.alpha * alpha_mult * ap
    local p2 = imgui.ImVec2(p.x + size.x, p.y + size.y)

    dl:AddRectFilled(p, p2, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
        lerp(lerp(t.bg_idle[1], t.bg_hover[1], h), t.bg_act[1], f),
        lerp(lerp(t.bg_idle[2], t.bg_hover[2], h), t.bg_act[2], f),
        lerp(lerp(t.bg_idle[3], t.bg_hover[3], h), t.bg_act[3], f),
        lerp(lerp(0.20, 0.45, h), 0.75, f) * a)), 6.0)
    dl:AddRect(p, p2, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
        lerp(lerp(t.bor_idle[1], t.bor_hover[1], h), t.bor_act[1], f),
        lerp(lerp(t.bor_idle[2], t.bor_hover[2], h), t.bor_act[2], f),
        lerp(lerp(t.bor_idle[3], t.bor_hover[3], h), t.bor_act[3], f),
        lerp(lerp(0.25, 0.60, h), 0.95, f) * a)), 6.0, 15, 1.2)

    -- шестерёнка: 8 зубцов + кольцо с отверстием. 8 зубцов симметричны через 45°,
    -- поэтому поворот на 90° в конце анимации выглядит как исходное положение.
    local cx, cy = p.x + size.x / 2, p.y + size.y / 2
    local r = 9.5 * alpha_mult
    local ang = f * math.pi / 2
    local col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z,
        lerp(0.65, 1.00, math.max(h, f)) * a))
    for i = 0, 7 do
        local a0 = ang + i * math.pi / 4
        local ca, sa = math.cos(a0), math.sin(a0)
        dl:AddLine(imgui.ImVec2(cx + ca * r * 0.7, cy + sa * r * 0.7),
            imgui.ImVec2(cx + ca * r, cy + sa * r), col, r * 0.36)
    end
    dl:AddCircle(imgui.ImVec2(cx, cy), r * 0.62, col, 24, r * 0.42)

    return clicked
end

function menu.toggle_popup(id)
    -- (не через "cond and nil or id": nil ложно, и такая запись всегда возвращала бы id)
    if menu.pop.id == id then
        menu.pop.id = nil
    else
        menu.pop.id = id
    end
end

-- курсор над меню или его окном настроек (чтобы клики не "проваливались" к оверлеям под ними)
function menu.mouse_over_ui(mx, my)
    if menu.alpha > 0.05 and mx >= menu.win_x and mx <= menu.win_x + menu.win_w
        and my >= menu.win_y and my <= menu.win_y + menu.win_h then
        return true
    end
    local P = menu.pop
    return P.anim > 0.05 and mx >= P.x and mx <= P.x + P.w and my >= P.y and my <= P.y + P.h
end

-- Отдельное окно настроек: появляется сбоку от меню (справа, а если не влезает — слева)
-- и следует за ним. Содержимое зависит от того, чья шестерёнка нажата (kb / asp / wm).
function menu.draw_popup()
    local P = menu.pop
    local cfg = session_cfg.settings

    -- закрываем, если функцию выключили, сменили вкладку или закрыли меню
    local enabled = {
        kb = cfg.keyboard_enabled,
        asp = cfg.asp_enabled,
        wm = cfg.watermark_enabled,
        pt = cfg.particles_enabled,
        glow = cfg.window_glow_enabled,
    }
    if P.id and (not enabled[P.id] or menu.current_tab ~= P.tabs[P.id] or not menu.show) then
        P.id = nil
    end
    -- окно закрыто — сбрасываем режим правки Keyboard и ожидание хоткея
    if not P.id or P.id ~= "kb" then
        if KB.awaiting_new_key then KB.awaiting_new_key = false end
        if (not P.id or P.shown == "kb") and KB.edit then
            KB.edit = false
            KB.drag_id = nil
            if KB.save_layout then KB.save_layout() end
        end
    end
    if P.id and P.shown ~= P.id then
        P.shown = P.id
        P.anim = 0.0
        P.content_t = 0.0
        -- кнопки попапа появляются заново при каждом открытии
        for k, st in pairs(menu.btn_anim) do
            if type(k) == "string" and k:sub(1, 6) == "##pop_" then
                st.appear = 0.0
            end
        end
        for k, st in pairs(menu.text_anim) do
            if type(k) == "string" and k:sub(1, 6) == "##pop_" then
                st.a = 0.0
            end
        end
    end
    P.anim = lerp(P.anim, P.id and 1.0 or 0.0, 0.14)
    P.content_t = lerp(P.content_t or 0.0, (P.id and P.anim > 0.35) and 1.0 or 0.0, 0.12)
    if P.anim < 0.01 or not P.shown then
        P.anim = 0.0
        P.content_t = 0.0
        P.shown = nil
        return
    end

    local t = get_theme()
    local sw, sh = getScreenResolution()
    local an = P.anim
    local a = menu.alpha * an

    local POP_W, PAD_X, PAD_Y = 292, 16, 14
    local CONTENT_W = POP_W - PAD_X * 2
    local full = imgui.ImVec2(CONTENT_W, 32)

    local x = menu.win_x + menu.win_w + 10
    local dir = -1
    if x + POP_W > sw then
        x = menu.win_x - 10 - POP_W
        dir = 1
    end
    x = math.max(0, math.min(x, sw - POP_W)) + dir * (1.0 - an) * 16
    local y = math.max(0, math.min(menu.win_y + 20, sh - math.max(P.h, 1) - 10))

    imgui.SetNextWindowPos(imgui.ImVec2(x, y), imgui.Cond.Always)

    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, a)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(PAD_X, PAD_Y))
    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove
        + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse + imgui.WindowFlags.AlwaysAutoResize
        + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoFocusOnAppearing

    if imgui.Begin("##mhg_popup", nil, flags) then
        local dl = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        P.x, P.y, P.w, P.h = pos.x, pos.y, size.x, size.y

        draw_window_glow(pos, size, a)
        draw_particle_grid(dl, pos, size, a, "popup")

        -- заголовок (плавное появление вместе с контентом)
        local titles = { kb = "Keyboard", asp = "ASP", wm = "Watermark", pt = u8"Частицы", glow = u8"Свечение" }
        local ct = ease_out_cubic(P.content_t or an)
        imgui.Dummy(imgui.ImVec2(CONTENT_W, 0))
        imgui.SetWindowFontScale(1.1)
        imgui.TextColored(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * a * ct),
            titles[P.shown] .. u8" — настройки")
        imgui.SetWindowFontScale(1.0)
        local ly = imgui.GetCursorScreenPos().y + 2
        local line_w = CONTENT_W * ct
        dl:AddLine(imgui.ImVec2(pos.x + PAD_X, ly), imgui.ImVec2(pos.x + PAD_X + line_w, ly),
            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 0.55 * a * ct)), 1.2)
        imgui.Dummy(imgui.ImVec2(0, 8))

        local ready = an > 0.85 -- пока окно "въезжает", клики игнорируем

        if P.shown == "wm" then
            menu.anim_text("##pop_wm_lbl", u8"Быстрое положение:", t.text_muted, ct)
            imgui.Dummy(imgui.ImVec2(0, 4))

            -- 6 пресетов: углы + верх/низ по центру (без самого центра экрана)
            -- текстовые подписи вместо unicode-стрелок (шрифт рисует их как «?»)
            local presets = {
                { u8"ВЛ", 0, 0 }, { u8"ВЦ", 1, 0 }, { u8"ВП", 2, 0 },
                { u8"НЛ", 0, 1 }, { u8"НЦ", 1, 1 }, { u8"НП", 2, 1 },
            }
            local gap = 8
            local cell = (CONTENT_W - gap * 2) / 3
            local cell_sz = imgui.ImVec2(cell, 32)
            local cur_h = cfg.watermark_halign
            local cur_v = cfg.watermark_valign
            local has_pos = (cfg.watermark_x or -1) >= 0 and (cfg.watermark_y or -1) >= 0
            -- дефолт = правый верхний угол (ВП)
            local is_default_pos = (not has_pos) or (cur_h == 2 and cur_v == 0)

            for i, pr in ipairs(presets) do
                local is_active = (is_default_pos and pr[2] == 2 and pr[3] == 0)
                    or (has_pos and not is_default_pos and cur_h == pr[2] and cur_v == pr[3])
                if menu.button("##pop_wm_preset_" .. i, pr[1], cell_sz, is_active, an) and ready then
                    if pr[2] == 2 and pr[3] == 0 then
                        -- ВП = положение по умолчанию
                        cfg.watermark_x = -1
                        cfg.watermark_y = -1
                        cfg.watermark_right = 1
                        cfg.watermark_halign = 2
                        cfg.watermark_valign = 0
                        menu.wm.drag = false
                        menu.wm.edit = false
                        inicfg.save(session_cfg, CONFIG_FILE)
                    else
                        apply_wm_preset(pr[2], pr[3])
                    end
                end
                if i % 3 ~= 0 then
                    imgui.SameLine(0, gap)
                else
                    imgui.Dummy(imgui.ImVec2(0, 4))
                end
            end

            imgui.Dummy(imgui.ImVec2(0, 4))
            local wm_edit_lbl = menu.wm.edit and u8"Готово" or u8"Изменить положение"
            if menu.button("##pop_wm_edit", wm_edit_lbl, full, menu.wm.edit, an) and ready then
                menu.wm.edit = not menu.wm.edit
                if not menu.wm.edit then
                    menu.wm.drag = false
                    inicfg.save(session_cfg, CONFIG_FILE)
                end
            end

            -- сброс только если положение не дефолтное (не правый верх)
            if not is_default_pos then
                imgui.Dummy(imgui.ImVec2(0, 4))
                if menu.button("##pop_wm_reset", u8"Сбросить положение", full, false, an) and ready then
                    cfg.watermark_x = -1
                    cfg.watermark_y = -1
                    cfg.watermark_right = 1
                    cfg.watermark_halign = 2
                    cfg.watermark_valign = 0
                    menu.wm.drag = false
                    inicfg.save(session_cfg, CONFIG_FILE)
                end
            end

        elseif P.shown == "asp" then
            local reset_w = 90
            local slider_size = imgui.ImVec2(CONTENT_W - 10 - reset_w, 32)
            CustomSliderFloat("##asp_slider", "ASP", asp_val_buf, 0.5, 2.0, slider_size, an)
            if cfg.asp_enabled and cfg.asp_value ~= asp_val_buf[0] then
                cfg.asp_value = asp_val_buf[0]
                apply_asp(asp_val_buf[0])
                inicfg.save(session_cfg, CONFIG_FILE)
            end

            imgui.SameLine(0, 10)
            if menu.button("##pop_asp_reset", u8"Сброс", imgui.ImVec2(reset_w, 32), false, an) and ready then
                -- сброс к родному аспекту SAMP (захвачен до первого применения ASP)
                local default_val = get_asp_native()
                asp_val_buf[0] = default_val
                cfg.asp_value = default_val
                apply_asp(default_val)
                inicfg.save(session_cfg, CONFIG_FILE)
            end

        elseif P.shown == "pt" then
            menu.anim_text("##pop_pt_lbl", u8"Тип частиц:", t.text_muted, ct)
            imgui.Dummy(imgui.ImVec2(0, 2))

            local half = imgui.ImVec2((CONTENT_W - 10) / 2, 32)
            local cur_style = math.max(1, math.min(math.floor(cfg.particles_style or 1), #PT.styles))
            for i, name in ipairs(PT.styles) do
                if menu.button("##pop_pt_style_" .. i, name, half, cur_style == i, an) and ready then
                    cfg.particles_style = i
                    inicfg.save(session_cfg, CONFIG_FILE)
                end
                if i % 2 == 1 and i < #PT.styles then
                    imgui.SameLine(0, 10)
                else
                    imgui.Dummy(imgui.ImVec2(0, 4))
                end
            end

            imgui.Dummy(imgui.ImVec2(0, 6))
            -- чекбокс: кастомное направление полёта (pad активен только когда включён)
            local dir_on = cfg.particles_dir_enabled and true or false
            if menu.button("##pop_pt_dir_en", u8"Направление полёта", full, dir_on, an) and ready then
                cfg.particles_dir_enabled = not dir_on
                inicfg.save(session_cfg, CONFIG_FILE)
            end
            if cfg.particles_dir_enabled then
                imgui.Dummy(imgui.ImVec2(0, 4))
                local pad_d = 84
                imgui.SetCursorPosX(imgui.GetCursorPosX() + (CONTENT_W - pad_d) / 2)
                CustomDirectionPad("##pop_pt_dir", cfg, "particles_dir_x", "particles_dir_y", pad_d, an)
                imgui.TextColored(t.text_muted, u8"Точка по центру — частицы стоят на месте")
            end
            imgui.Dummy(imgui.ImVec2(0, 6))

            local pt_reset_w = 70
            local pt_slider_w = imgui.ImVec2(CONTENT_W - 10 - pt_reset_w, 32)

            menu.pt_dens[0] = cfg.particles_density or 1.0
            CustomSliderFloat("##pop_pt_density", u8"Количество", menu.pt_dens, 0.3, 2.5, pt_slider_w, an)
            if math.abs(menu.pt_dens[0] - (cfg.particles_density or 1.0)) > 0.001 then
                cfg.particles_density = menu.pt_dens[0]
                inicfg.save(session_cfg, CONFIG_FILE)
            end
            imgui.SameLine(0, 10)
            local dens_is_default = math.abs((cfg.particles_density or 1.0) - 1.0) < 0.001
            if menu.button("##pop_pt_density_reset", u8"Сброс", imgui.ImVec2(pt_reset_w, 32), false, an, dens_is_default)
                and ready and not dens_is_default then
                cfg.particles_density = 1.0
                menu.pt_dens[0] = 1.0
                inicfg.save(session_cfg, CONFIG_FILE)
            end
            imgui.Dummy(imgui.ImVec2(0, 4))

            menu.pt_speed[0] = cfg.particles_speed or 1.0
            CustomSliderFloat("##pop_pt_speed", u8"Скорость", menu.pt_speed, 0.3, 2.5, pt_slider_w, an)
            if math.abs(menu.pt_speed[0] - (cfg.particles_speed or 1.0)) > 0.001 then
                cfg.particles_speed = menu.pt_speed[0]
                inicfg.save(session_cfg, CONFIG_FILE)
            end
            imgui.SameLine(0, 10)
            local speed_is_default = math.abs((cfg.particles_speed or 1.0) - 1.0) < 0.001
            if menu.button("##pop_pt_speed_reset", u8"Сброс", imgui.ImVec2(pt_reset_w, 32), false, an, speed_is_default)
                and ready and not speed_is_default then
                cfg.particles_speed = 1.0
                menu.pt_speed[0] = 1.0
                inicfg.save(session_cfg, CONFIG_FILE)
            end

        elseif P.shown == "kb" then
            -- режим правки всегда активен, пока открыто окно настроек Keyboard
            if not KB.edit then KB.edit = true end

            -- добавить клавишу по хоткею (анимация текста — внутри menu.button по id)
            local add_active = KB.awaiting_new_key and true or false
            local add_lbl = add_active and u8"Нажмите клавишу..." or u8"+ Добавить клавишу"
            if menu.button("##pop_kb_add", add_lbl, full, add_active, an) and ready then
                KB.awaiting_new_key = not KB.awaiting_new_key
            end

            -- панель выбранной клавиши: размер, сброс размера, удаление
            if KB.selected_id then
                local sel_key = nil
                for _, kk in ipairs(KB.keys) do
                    if kk.id == KB.selected_id then
                        sel_key = kk
                        break
                    end
                end

                if sel_key then
                    imgui.Dummy(imgui.ImVec2(0, 6))
                    imgui.TextColored(t.text_muted, u8"Выбрана: " .. (sel_key.label or sel_key.id))
                    imgui.Dummy(imgui.ImVec2(0, 2))

                    KB.size_buf[0] = sel_key.s
                    CustomSliderFloat("##mhg_kb_size_slider", u8"Размер", KB.size_buf, KB.SCALE_MIN, KB.SCALE_MAX, full, an)
                    if math.abs(KB.size_buf[0] - sel_key.s) > 0.001 then
                        sel_key.s = math.max(KB.SCALE_MIN, math.min(KB.size_buf[0], KB.SCALE_MAX))
                        KB.save_layout()
                    end
                    imgui.Dummy(imgui.ImVec2(0, 4))

                    local half = imgui.ImVec2((CONTENT_W - 10) / 2, 32)
                    local is_default_size = math.abs(sel_key.s - 1.0) < 0.001
                    if menu.button("##pop_kb_size_reset", u8"Сброс", half, false, an, is_default_size)
                        and ready and not is_default_size then
                        sel_key.s = 1.0
                        KB.size_buf[0] = 1.0
                        KB.save_layout()
                    end
                    imgui.SameLine(0, 10)
                    if menu.button("##pop_kb_del", u8"Удалить", half, false, an, false, true) and ready then
                        KB.remove_key(sel_key.id)
                    end
                else
                    KB.selected_id = nil
                end
            end

        elseif P.shown == "glow" then
            menu.anim_text("##pop_glow_lbl", u8"Режим свечения:", t.text_muted, ct)
            imgui.Dummy(imgui.ImVec2(0, 2))

            local half = imgui.ImVec2((CONTENT_W - 10) / 2, 32)
            local cur_style = math.max(1, math.min(math.floor(cfg.window_glow_style or 1), #GLOW_STYLES))
            for i, name in ipairs(GLOW_STYLES) do
                if menu.button("##pop_glow_style_" .. i, name, half, cur_style == i, an) and ready then
                    cfg.window_glow_style = i
                    inicfg.save(session_cfg, CONFIG_FILE)
                end
                if i % 2 == 1 and i < #GLOW_STYLES then
                    imgui.SameLine(0, 10)
                else
                    imgui.Dummy(imgui.ImVec2(0, 4))
                end
            end

            imgui.Dummy(imgui.ImVec2(0, 6))
            local gl_reset_w = 70
            local gl_slider_w = imgui.ImVec2(CONTENT_W - 10 - gl_reset_w, 32)

            menu.glow_speed[0] = cfg.window_glow_speed or 1.0
            CustomSliderFloat("##pop_glow_speed", u8"Скорость", menu.glow_speed, 0.2, 3.0, gl_slider_w, an)
            if math.abs(menu.glow_speed[0] - (cfg.window_glow_speed or 1.0)) > 0.001 then
                cfg.window_glow_speed = menu.glow_speed[0]
                inicfg.save(session_cfg, CONFIG_FILE)
            end
            imgui.SameLine(0, 10)
            local spd_def = math.abs((cfg.window_glow_speed or 1.0) - 1.0) < 0.001
            if menu.button("##pop_glow_spd_rst", u8"Сброс", imgui.ImVec2(gl_reset_w, 32), false, an, spd_def)
                and ready and not spd_def then
                cfg.window_glow_speed = 1.0
                menu.glow_speed[0] = 1.0
                inicfg.save(session_cfg, CONFIG_FILE)
            end
        end
    end
    imgui.End()
    imgui.PopStyleVar(2)
end

function menu.draw()
    if is_update_locked() then
        menu.show = false
    end
    local was_hidden = menu.alpha < 0.01
    menu.alpha = lerp(menu.alpha, menu.show and 1.0 or 0.0, 0.11)
    if menu.show and was_hidden then
        -- при открытии меню контент и заголовок выезжают заново
        menu.tab_content_alpha = 0.0
        menu.tab_content_y = 16.0
        menu.title_fade = 0.0
        for k, st in pairs(menu.btn_anim) do
            if type(k) == "string" then st.appear = 0.0 end
        end
        for k, st in pairs(menu.text_anim) do
            if type(k) == "string" then st.a = 0.0 end
        end
    end
    if menu.alpha < 0.01 then
        menu.pop.id = nil
        menu.pop.anim = 0.0
        menu.pop.content_t = 0.0
        KB.awaiting_new_key = false
        return
    end
    
    local t = get_theme()

    -- Ширина строки из 3 стандартных кнопок (218px) с отступами 10px —
    -- по этой сетке уже выровнены строки темы и эффектов интерфейса.
    -- Используем её как общий ориентир, чтобы ВСЕ строки кнопок в меню
    -- (клавиатура, ASP, хоткей и т.д.) заканчивались на одной правой границе.
    local ROW_W = 218 * 3 + 10 * 2

    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, menu.alpha)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 0)

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.07, 0.08, 0.11, 0.98))
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * menu.alpha))

    local current_user_nick = session_cfg.session.saved_nick ~= "" and session_cfg.session.saved_nick or get_my_nick()
    local nick_sz = imgui.CalcTextSize(current_user_nick).x
    
    local tabs = {
        { name = u8"Основное" },
        { name = u8"Дополнительно" },
        { name = u8"Настройки" }
    }
    
    local tab_btn_w = 120
    local tab_btn_h = 28
    local tab_spacing = 8
    local close_btn_w = 28
    local close_spacing = 10
    local base_margins = 50

    local content_elements_width_top = (#tabs * tab_btn_w) + ((#tabs - 1) * tab_spacing) + close_spacing + close_btn_w
    
    local b_avatar_sz = 32
    local b_spacing = 10
    local logout_btn_w = 65
    local eye_btn_w = 70 
    local wm_btn_w = 75
    local target_input_w = 172 

    local current_input_text = ffi.string(avatar_url_buf)
    local has_link_inserted = (current_input_text ~= "")
    
    local target_w_val = show_avatar_url and target_input_w or 0.0
    input_anim_w = lerp(input_anim_w, target_w_val, 0.18)

    local top_row_w = eye_btn_w + b_spacing + b_avatar_sz + b_spacing + nick_sz + b_spacing + logout_btn_w
    local bottom_row_w = (input_anim_w > 1.0 and (input_anim_w + 6) or 0.0) + 75
    local total_bottom_width = math.max(top_row_w, bottom_row_w)

    -- Скроллбар контент-области убран, резерв под него больше не нужен.
    local dynamic_win_width = math.max(ROW_W, content_elements_width_top, total_bottom_width) + base_margins

    apply_window_position(dynamic_win_width, 480)

    if imgui.Begin('##menu', nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse) then
        local draw_list = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        local mouse_pos = imgui.GetMousePos()
        menu.win_x, menu.win_y, menu.win_w, menu.win_h = pos.x, pos.y, size.x, size.y
        
        draw_window_glow(pos, size, menu.alpha)
        draw_particle_grid(draw_list, pos, size, menu.alpha)

        local is_hovering_top_zone = (mouse_pos.x >= pos.x and mouse_pos.x <= pos.x + size.x and mouse_pos.y >= pos.y and mouse_pos.y <= pos.y + 60)
        local top_bar_h = 50
        
        if mouse_pos.y >= pos.y + size.y - 70 then
            is_hovering_top_zone = false
        end

        menu.sidebar_alpha = lerp(menu.sidebar_alpha, is_hovering_top_zone and 1.0 or 0.0, 0.12)
        
        if menu.sidebar_alpha > 0.001 then
            local line_y = pos.y + lerp(20, top_bar_h, menu.sidebar_alpha)
            local line_x1 = pos.x + 20
            local line_x2 = pos.x + size.x - 20
            local segments = 80
            local step = (line_x2 - line_x1) / segments
            local time_offset = os.clock() * 3.0
            
            for s = 0, segments - 1 do
                local sx1 = line_x1 + s * step
                local sx2 = line_x1 + (s + 1) * step
                local progress = (s + 0.5) / segments
                local wave = math.sin(time_offset - (s * 0.15)) * 0.5 + 0.5
                local fade_mult = math.sin(progress * math.pi) * (0.3 + wave * 0.7)
                
                local col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bor_hover[1], t.bor_hover[2], t.bor_hover[3], fade_mult * menu.alpha * menu.sidebar_alpha))
                draw_list:AddLine(imgui.ImVec2(sx1, line_y), imgui.ImVec2(sx2, line_y), col, 1.2)
            end
            
            local start_x = (size.x - content_elements_width_top) / 2
            local menu_y_offset = lerp(-25, 12, menu.sidebar_alpha)
            local current_panel_alpha = menu.alpha * menu.sidebar_alpha
            
            imgui.SetCursorPos(imgui.ImVec2(start_x, menu_y_offset))
            
            for i, tab in ipairs(tabs) do
                local p_tab = imgui.GetCursorScreenPos()
                
                if imgui.InvisibleButton("##top_tab_" .. i, imgui.ImVec2(tab_btn_w, tab_btn_h)) then
                    local new_tab = i
                    if new_tab > 3 then new_tab = 3 end
                    if menu.current_tab ~= new_tab then
                        menu.current_tab = new_tab
                        menu.tab_content_alpha = 0.0
                        menu.tab_content_y = 14.0
                        menu.title_fade = 0.0
                        menu.title_tab = new_tab
                        -- кнопки/подписи вкладки появятся заново
                        for k, st in pairs(menu.btn_anim) do
                            if type(k) == "string" and (k:find("##mhg_") or k:find("##custom_") or k:find("##pop_")) then
                                st.appear = 0.0
                            end
                        end
                        for k, st in pairs(menu.text_anim) do
                            if type(k) == "string" then st.a = 0.0 end
                        end
                    end
                end

                local is_hovered = imgui.IsItemHovered()
                local is_active = (menu.current_tab == i)

                tab_hover_alphas[i] = lerp(tab_hover_alphas[i], is_hovered and 1.0 or 0.0, 0.14)
                local target_fill = is_active and 1.0 or 0.0
                tab_fill_progress[i] = lerp(tab_fill_progress[i], target_fill, 0.10)

                local t_min = p_tab
                local t_max = imgui.ImVec2(p_tab.x + tab_btn_w, p_tab.y + tab_btn_h)
                local fill_p = tab_fill_progress[i]
                local hover_p = tab_hover_alphas[i]

                local effects_enabled = true -- анимация вкладок всегда включена

                local t_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], hover_p), t.bg_act[1], fill_p)
                local t_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], hover_p), t.bg_act[2], fill_p)
                local t_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], hover_p), t.bg_act[3], fill_p)
                local t_bg_a = lerp(lerp(0.20, 0.45, hover_p), 0.75, fill_p)

                local t_bor_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], hover_p), t.bor_act[1], fill_p)
                local t_bor_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], hover_p), t.bor_act[2], fill_p)
                local t_bor_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], hover_p), t.bor_act[3], fill_p)
                local t_bor_a = lerp(lerp(0.25, 0.60, hover_p), 0.95, fill_p)

                local t_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t_bg_r, t_bg_g, t_bg_b, t_bg_a * current_panel_alpha))
                local t_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t_bor_r, t_bor_g, t_bor_b, t_bor_a * current_panel_alpha))
                
                if effects_enabled and fill_p > 0.01 then
                    local line_w = tab_btn_w * fill_p
                    local lx1 = t_min.x + (tab_btn_w - line_w) / 2
                    local lx2 = lx1 + line_w
                    local ly = t_max.y + 2
                    local ind_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], fill_p * current_panel_alpha))
                    draw_list:AddLine(imgui.ImVec2(lx1, ly), imgui.ImVec2(lx2, ly), ind_col, 2.0)
                end

                draw_list:AddRectFilled(t_min, t_max, t_bg_col, 6.0)
                draw_list:AddRect(t_min, t_max, t_bor_col, 6.0, 15, 1.2)

                local full_label = tab.name
                local t_sz = imgui.CalcTextSize(full_label)
                local t_pos = imgui.ImVec2(t_min.x + (tab_btn_w - t_sz.x) / 2, t_min.y + (tab_btn_h - t_sz.y) / 2)
                local text_col_val = lerp(lerp(0.65, 0.85, hover_p), 1.00, fill_p)
                local t_text_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, text_col_val * current_panel_alpha))
                draw_list:AddText(t_pos, t_text_col, full_label)

                imgui.SameLine(0, tab_spacing)
            end

            local close_btn_size = imgui.ImVec2(close_btn_w, tab_btn_h)
            local p_close = imgui.GetCursorScreenPos()

            if imgui.InvisibleButton("##custom_close_btn", close_btn_size) then
                close_all()
            end

            local is_close_hovered = imgui.IsItemHovered()
            close_hover_alpha = lerp(close_hover_alpha, is_close_hovered and 1.0 or 0.0, 0.14)

            local c_min = p_close
            local c_max = imgui.ImVec2(p_close.x + close_btn_size.x, p_close.y + close_btn_size.y)

            local c_bg_r = lerp(t.bg_idle[1], t.bg_hover[1], close_hover_alpha)
            local c_bg_g = lerp(t.bg_idle[2], t.bg_hover[2], close_hover_alpha)
            local c_bg_b = lerp(t.bg_idle[3], t.bg_hover[3], close_hover_alpha)
            local c_bg_a = lerp(0.20, 0.65, close_hover_alpha)

            local c_bor_r = lerp(t.bor_idle[1], t.bor_hover[1], close_hover_alpha)
            local c_bor_g = lerp(t.bor_idle[2], t.bor_hover[2], close_hover_alpha)
            local c_bor_b = lerp(t.bor_idle[3], t.bor_hover[3], close_hover_alpha)
            local c_bor_a = lerp(0.25, 0.95, close_hover_alpha)

            local c_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(c_bg_r, c_bg_g, c_bg_b, c_bg_a * current_panel_alpha))
            local c_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(c_bor_r, c_bor_g, c_bor_b, c_bor_a * current_panel_alpha))

            draw_list:AddRectFilled(c_min, c_max, c_bg_col, 6.0)
            draw_list:AddRect(c_min, c_max, c_bor_col, 6.0, 15, 1.1)

            local close_text = "X"
            local ct_size = imgui.CalcTextSize(close_text)
            local ct_pos = imgui.ImVec2(c_min.x + (close_btn_size.x - ct_size.x) / 2, c_min.y + (close_btn_size.y - ct_size.y) / 2)
            local ct_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, lerp(0.65, 1.00, close_hover_alpha) * current_panel_alpha))
            draw_list:AddText(ct_pos, ct_col, close_text)
        end

        -- Высота нижней панели: одна строка (аватар/ник/выход) или две, когда открыто поле ссылки.
        -- Растёт плавно вместе с полем, чтобы панель не "прыгала".
        local bottom_input_t = math.max(0.0, math.min(1.0, input_anim_w / target_input_w))
        local bottom_bar_h = lerp(64, 100, bottom_input_t)

        -- Зона наведения работает как у верхней панели: полоса у края окна, а пока панель открыта —
        -- зона растягивается на всю её высоту (гистерезис). Раньше зона была фиксированной (70px),
        -- а панель с полем ссылки поднималась до 100px: курсор выходил из зоны, и панель мигала/закрывалась.
        local bottom_trigger_h = 60
        local bottom_zone_h = (menu.bottombar_alpha > 0.15) and (bottom_bar_h + 10) or bottom_trigger_h
        local is_hovering_bottom_zone = (mouse_pos.x >= pos.x and mouse_pos.x <= pos.x + size.x
            and mouse_pos.y >= pos.y + size.y - bottom_zone_h and mouse_pos.y <= pos.y + size.y)

        -- Пока в поле ссылки печатают — панель держится открытой (флаг выставляется ниже, при отрисовке поля).
        if menu.bottom_input_active then
            is_hovering_bottom_zone = true
        end
        menu.bottom_input_active = false

        menu.bottombar_alpha = lerp(menu.bottombar_alpha, is_hovering_bottom_zone and 1.0 or 0.0, 0.12)

        if menu.bottombar_alpha > 0.001 then
            local b_line_y = pos.y + size.y - lerp(15, bottom_bar_h, menu.bottombar_alpha)
            local b_line_x1 = pos.x + 20
            local b_line_x2 = pos.x + size.x - 20
            local segments = 80
            local step = (b_line_x2 - b_line_x1) / segments
            local time_offset = os.clock() * 3.0
            
            for s = 0, segments - 1 do
                local sx1 = b_line_x1 + s * step
                local sx2 = b_line_x1 + (s + 1) * step
                local progress = (s + 0.5) / segments
                local wave = math.sin(time_offset - (s * 0.15)) * 0.5 + 0.5
                local fade_mult = math.sin(progress * math.pi) * (0.3 + wave * 0.7)
                
                local col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bor_hover[1], t.bor_hover[2], t.bor_hover[3], fade_mult * menu.alpha * menu.bottombar_alpha))
                draw_list:AddLine(imgui.ImVec2(sx1, b_line_y), imgui.ImVec2(sx2, b_line_y), col, 1.2)
            end

            if menu.bottombar_alpha > 0.01 then
                local current_content_alpha = menu.alpha * menu.bottombar_alpha
                
                local b_start_x = (size.x - total_bottom_width) / 2
                local total_content_h = lerp(b_avatar_sz, b_avatar_sz + 6 + 24, bottom_input_t)
                -- как у верхней панели: содержимое выезжает к своему месту (сверху там -25 -> 12, здесь снизу +25 -> 0)
                local bottom_slide = lerp(25, 0, menu.bottombar_alpha)
                local b_base_y = (size.y - bottom_bar_h) + (bottom_bar_h - total_content_h) / 2 + bottom_slide

                local top_row_offset_x = b_start_x + (total_bottom_width - top_row_w) / 2
                imgui.SetCursorPos(imgui.ImVec2(top_row_offset_x, b_base_y))

                local p_eye = imgui.GetCursorScreenPos()
                local eye_btn_sz = imgui.ImVec2(eye_btn_w, b_avatar_sz)

                if imgui.InvisibleButton("##custom_eye_btn", eye_btn_sz) then
                    show_avatar_url = not show_avatar_url
                end

                local is_eye_hovered = imgui.IsItemHovered()
                eye_hover_alpha = lerp(eye_hover_alpha, is_eye_hovered and 1.0 or 0.0, 0.14)

                local ey_min = p_eye
                local ey_max = imgui.ImVec2(p_eye.x + eye_btn_sz.x, p_eye.y + eye_btn_sz.y)
                local ey_bg_r = lerp(t.bg_idle[1], t.bg_hover[1], eye_hover_alpha)
                local ey_bg_g = lerp(t.bg_idle[2], t.bg_hover[2], eye_hover_alpha)
                local ey_bg_b = lerp(t.bg_idle[3], t.bg_hover[3], eye_hover_alpha)
                local ey_bg_a = lerp(0.12, 0.45, eye_hover_alpha)
                local ey_bor_r = lerp(t.bor_idle[1], t.bor_hover[1], eye_hover_alpha)
                local ey_bor_g = lerp(t.bor_idle[2], t.bor_hover[2], eye_hover_alpha)
                local ey_bor_b = lerp(t.bor_idle[3], t.bor_hover[3], eye_hover_alpha)
                local ey_bor_a = lerp(0.18, 0.80, eye_hover_alpha)

                local ey_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ey_bg_r, ey_bg_g, ey_bg_b, ey_bg_a * current_content_alpha))
                local ey_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ey_bor_r, ey_bor_g, ey_bor_b, ey_bor_a * current_content_alpha))

                draw_list:AddRectFilled(ey_min, ey_max, ey_bg_col, 6.0)
                draw_list:AddRect(ey_min, ey_max, ey_bor_col, 6.0, 15, 1.1)

                local eye_text
                if show_avatar_url then
                    eye_text = u8"Скрыть"
                else
                    eye_text = has_link_inserted and u8"Изменить" or u8"Аватар"
                end

                local eyt_sz = imgui.CalcTextSize(eye_text)
                local eyt_pos = imgui.ImVec2(ey_min.x + (eye_btn_sz.x - eyt_sz.x) / 2, ey_min.y + (eye_btn_sz.y - eyt_sz.y) / 2)
                local eyt_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, lerp(0.50, 0.90, eye_hover_alpha) * current_content_alpha))
                draw_list:AddText(eyt_pos, eyt_col, eye_text)

                imgui.SameLine(0, b_spacing)

                local p_avatar = imgui.GetCursorScreenPos()
                local rounding = 0.0 
                local av_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bor_idle[1], t.bor_idle[2], t.bor_idle[3], 0.95 * current_content_alpha))

                if user_avatar_texture then
                    draw_list:AddRectFilled(imgui.ImVec2(p_avatar.x, p_avatar.y), imgui.ImVec2(p_avatar.x + b_avatar_sz, p_avatar.y + b_avatar_sz), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, current_content_alpha)), rounding)
                    draw_list:PushClipRect(imgui.ImVec2(p_avatar.x, p_avatar.y), imgui.ImVec2(p_avatar.x + b_avatar_sz, p_avatar.y + b_avatar_sz), true)
                    draw_list:AddImage(user_avatar_texture, imgui.ImVec2(p_avatar.x, p_avatar.y), imgui.ImVec2(p_avatar.x + b_avatar_sz, p_avatar.y + b_avatar_sz), imgui.ImVec2(0, 0), imgui.ImVec2(1, 1), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, current_content_alpha)))
                    draw_list:PopClipRect()
                    draw_list:AddRect(imgui.ImVec2(p_avatar.x, p_avatar.y), imgui.ImVec2(p_avatar.x + b_avatar_sz, p_avatar.y + b_avatar_sz), av_bor_col, rounding, 15, 1.5)
                else
                    local av_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bg_idle[1], t.bg_idle[2], t.bg_idle[3], 0.75 * current_content_alpha))
                    draw_list:AddRectFilled(imgui.ImVec2(p_avatar.x, p_avatar.y), imgui.ImVec2(p_avatar.x + b_avatar_sz, p_avatar.y + b_avatar_sz), av_bg_col, rounding)
                    draw_list:AddRect(imgui.ImVec2(p_avatar.x, p_avatar.y), imgui.ImVec2(p_avatar.x + b_avatar_sz, p_avatar.y + b_avatar_sz), av_bor_col, rounding, 15, 1.5)
                    local av_text = u8"+"
                    local av_sz = imgui.CalcTextSize(av_text)
                    draw_list:AddText(imgui.ImVec2(p_avatar.x + (b_avatar_sz - av_sz.x)/2, p_avatar.y + (b_avatar_sz - av_sz.y)/2), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, current_content_alpha)), av_text)
                end
                
                imgui.Dummy(imgui.ImVec2(b_avatar_sz, b_avatar_sz))
                imgui.SameLine(0, b_spacing)
                
                local p_nick = imgui.GetCursorScreenPos()
                local nick_txt_pos = imgui.ImVec2(p_nick.x, p_nick.y + (b_avatar_sz - imgui.CalcTextSize(current_user_nick).y) / 2)
                local nick_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, current_content_alpha))
                draw_list:AddText(nick_txt_pos, nick_col, current_user_nick)
                imgui.Dummy(imgui.ImVec2(nick_sz, b_avatar_sz))
                imgui.SameLine(0, b_spacing)
                
                imgui.SetCursorPosY(b_base_y + (b_avatar_sz - 24) / 2)
                local p_logout = imgui.GetCursorScreenPos()
                local logout_btn_sz = imgui.ImVec2(logout_btn_w, 24)

                if imgui.InvisibleButton("##custom_logout_btn", logout_btn_sz) then
                    session_cfg.session.is_logged = false
                    session_cfg.session.saved_nick = ""
                    session_cfg.session.saved_password = ""
                    inicfg.save(session_cfg, CONFIG_FILE)
                    
                    menu.show = false
                    auth.show = true
                    auth.stage = 'idle'
                    auth.stage_alpha = 0.0
                    auth.loaded = false
                    ffi.fill(auth.password, ffi.sizeof(auth.password))
                    shake_timer = 0.0
                    
                    load_accounts()
                end

                local is_logout_hovered = imgui.IsItemHovered()
                logout_hover_alpha = lerp(logout_hover_alpha, is_logout_hovered and 1.0 or 0.0, 0.14)

                local lo_min = p_logout
                local lo_max = imgui.ImVec2(p_logout.x + logout_btn_sz.x, p_logout.y + logout_btn_sz.y)
                -- Яркая кнопка выхода (красный акцент)
                local lo_bg_r = lerp(0.55, 0.90, logout_hover_alpha)
                local lo_bg_g = lerp(0.12, 0.18, logout_hover_alpha)
                local lo_bg_b = lerp(0.12, 0.18, logout_hover_alpha)
                local lo_bg_a = lerp(0.55, 0.90, logout_hover_alpha)
                local lo_bor_r = lerp(0.85, 1.00, logout_hover_alpha)
                local lo_bor_g = lerp(0.25, 0.35, logout_hover_alpha)
                local lo_bor_b = lerp(0.25, 0.35, logout_hover_alpha)
                local lo_bor_a = lerp(0.70, 1.00, logout_hover_alpha)

                local lo_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(lo_bg_r, lo_bg_g, lo_bg_b, lo_bg_a * current_content_alpha))
                local lo_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(lo_bor_r, lo_bor_g, lo_bor_b, lo_bor_a * current_content_alpha))

                draw_list:AddRectFilled(lo_min, lo_max, lo_bg_col, 6.0)
                draw_list:AddRect(lo_min, lo_max, lo_bor_col, 6.0, 15, 1.4)

                local logout_text = u8"Выйти"
                local lot_sz = imgui.CalcTextSize(logout_text)
                local lot_pos = imgui.ImVec2(lo_min.x + (logout_btn_sz.x - lot_sz.x) / 2, lo_min.y + (logout_btn_sz.y - lot_sz.y) / 2)
                local lot_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.00, 0.92, 0.92, lerp(0.85, 1.00, logout_hover_alpha) * current_content_alpha))
                draw_list:AddText(lot_pos, lot_col, logout_text)

                local bottom_row_offset_x = b_start_x + (total_bottom_width - bottom_row_w) / 2
                imgui.SetCursorPos(imgui.ImVec2(bottom_row_offset_x, b_base_y + b_avatar_sz + 6))

                imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, current_content_alpha)

                if input_anim_w > 1.0 then
                    imgui.PushItemWidth(input_anim_w)
                    imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(t.bg_idle[1], t.bg_idle[2], t.bg_idle[3], 0.12 * current_content_alpha))
                    imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(t.bg_hover[1], t.bg_hover[2], t.bg_hover[3], 0.35 * current_content_alpha))
                    imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(t.bg_act[1], t.bg_act[2], t.bg_act[3], 0.50 * current_content_alpha))
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text.x, t.text.y, t.text.z, 0.85 * current_content_alpha))

                    imgui.InputTextWithHint("##avatar_url_btm", u8"Вставь ссылку на аватар...", avatar_url_buf, ffi.sizeof(avatar_url_buf))
                    menu.bottom_input_active = imgui.IsItemActive()
                    
                    if session_cfg.settings.custom_avatar_url ~= current_input_text then
                        session_cfg.settings.custom_avatar_url = current_input_text
                        inicfg.save(session_cfg, CONFIG_FILE)
                        if doesFileExist(AVATAR_FILE) then os.remove(AVATAR_FILE) end
                        user_avatar_texture = nil
                        load_user_avatar()
                    end

                    imgui.PopStyleColor(4)
                    imgui.PopItemWidth()
                    imgui.SameLine(0, 6)

                    local has_text_in_input = current_input_text ~= ""
                    local action_btn_text = has_text_in_input and u8"Очистить" or u8"Обновить"
                    
                    local p_action = imgui.GetCursorScreenPos()
                    local action_btn_sz = imgui.ImVec2(75, 24)

                    if imgui.InvisibleButton("##custom_action_btn", action_btn_sz) then
                        if has_text_in_input then
                            ffi.fill(avatar_url_buf, ffi.sizeof(avatar_url_buf))
                            session_cfg.settings.custom_avatar_url = ""
                            inicfg.save(session_cfg, CONFIG_FILE)
                            if doesFileExist(AVATAR_FILE) then os.remove(AVATAR_FILE) end
                            user_avatar_texture = nil
                            load_user_avatar()
                            show_avatar_url = false
                        else
                            load_user_avatar()
                        end
                    end

                    local is_action_hovered = imgui.IsItemHovered()
                    action_btn_hover_alpha = lerp(action_btn_hover_alpha, is_action_hovered and 1.0 or 0.0, 0.14)

                    local ac_min = p_action
                    local ac_max = imgui.ImVec2(p_action.x + action_btn_sz.x, p_action.y + action_btn_sz.y)
                    local ac_bg_r = lerp(t.bg_idle[1], t.bg_hover[1], action_btn_hover_alpha)
                    local ac_bg_g = lerp(t.bg_idle[2], t.bg_hover[2], action_btn_hover_alpha)
                    local ac_bg_b = lerp(t.bg_idle[3], t.bg_hover[3], action_btn_hover_alpha)
                    local ac_bg_a = lerp(0.12, 0.45, action_btn_hover_alpha)
                    local ac_bor_r = lerp(t.bor_idle[1], t.bor_hover[1], action_btn_hover_alpha)
                    local ac_bor_g = lerp(t.bor_idle[2], t.bor_hover[2], action_btn_hover_alpha)
                    local ac_bor_b = lerp(t.bor_idle[3], t.bor_hover[3], action_btn_hover_alpha)
                    local ac_bor_a = lerp(0.18, 0.80, action_btn_hover_alpha)

                    local ac_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ac_bg_r, ac_bg_g, ac_bg_b, ac_bg_a * current_content_alpha))
                    local ac_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ac_bor_r, ac_bor_g, ac_bor_b, ac_bor_a * current_content_alpha))

                    draw_list:AddRectFilled(ac_min, ac_max, ac_bg_col, 6.0)
                    draw_list:AddRect(ac_min, ac_max, ac_bor_col, 6.0, 15, 1.1)

                    local act_sz = imgui.CalcTextSize(action_btn_text)
                    local act_pos = imgui.ImVec2(ac_min.x + (action_btn_sz.x - act_sz.x) / 2, ac_min.y + (action_btn_sz.y - act_sz.y) / 2)
                    local act_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, lerp(0.50, 0.90, action_btn_hover_alpha) * current_content_alpha))
                    draw_list:AddText(act_pos, act_col, action_btn_text)
                end

                imgui.PopStyleVar()
            end
        end

        local tabs_titles = {
            { name = u8"Основное" },
            { name = u8"Дополнительно" },
            { name = u8"Настройки" }
        }
        
        local title_alpha = 1.0 - menu.sidebar_alpha
        local title_y_offset = lerp(25, 45, menu.sidebar_alpha)
        menu.title_fade = lerp(menu.title_fade, 1.0, 0.14)
        local title_k = ease_out_cubic(menu.title_fade)

        if title_alpha > 0.01 then
            imgui.SetCursorPos(imgui.ImVec2(25, title_y_offset + (1.0 - title_k) * 8.0))
            imgui.SetWindowFontScale(1.2)
            local active_tab_data = tabs_titles[menu.current_tab]
            local active_title = active_tab_data.name
            imgui.TextColored(imgui.ImVec4(t.text.x, t.text.y, t.text.z,
                t.text.w * menu.alpha * title_alpha * title_k), active_title)
            imgui.SetWindowFontScale(1.0)
        end

        local content_area_y = lerp(55, 75, menu.sidebar_alpha)
        local bottom_offset = lerp(15, bottom_bar_h + 10, menu.bottombar_alpha)
        local content_area_h = size.y - content_area_y - bottom_offset

        menu.tab_content_alpha = lerp(menu.tab_content_alpha, 1.0, 0.13)
        menu.tab_content_y = lerp(menu.tab_content_y, 0.0, 0.13)
        local tab_k = ease_out_cubic(menu.tab_content_alpha)
        local tab_y = menu.tab_content_y

        imgui.SetCursorPos(imgui.ImVec2(25, content_area_y + tab_y))
        -- NoScrollbar: ползунок прокрутки убран; колесом мыши контент по-прежнему прокручивается.
        imgui.BeginChild("##content_area", imgui.ImVec2(size.x - 50, content_area_h - tab_y), false, imgui.WindowFlags.NoScrollbar)
        -- ВАЖНО: берём draw_list заново уже внутри child'а. Раньше здесь использовался
        -- draw_list родительского окна, из-за чего вручную нарисованные прямоугольники
        -- кнопок не обрезались по границе child'а и "налезали" на нижнюю панель при её
        -- подъёме.
        local draw_list = imgui.GetWindowDrawList()
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, menu.alpha * tab_k)

        if menu.current_tab == 1 then
            menu.anim_text("##tab1_kb_lbl", u8"Клавиши на экране:", t.text_muted, 1.0)
            imgui.Dummy(imgui.ImVec2(0, 5))

            local kb_btn_size = imgui.ImVec2(218, 32)
            local kb_spacing_x = 10

            -- === Чекбокс: Keyboard ===
            -- Пока Keyboard включён, кнопка сужается, а справа появляется шестерёнка: по ней открывается
            -- отдельное окно настроек. Ширина ряда не меняется.
            KB.panel_reveal = lerp(KB.panel_reveal, session_cfg.settings.keyboard_enabled and 1.0 or 0.0, 0.14)
            local rv = KB.panel_reveal
            local kb_chk_size = imgui.ImVec2(kb_btn_size.x - (32 + kb_spacing_x) * rv, kb_btn_size.y)
            local p_kb = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##mhg_keyboard_chk", kb_chk_size) then
                session_cfg.settings.keyboard_enabled = not session_cfg.settings.keyboard_enabled
                if not session_cfg.settings.keyboard_enabled then
                    KB.edit = false
                end
                inicfg.save(session_cfg, CONFIG_FILE)
            end

            KB.chk_hover = lerp(KB.chk_hover, imgui.IsItemHovered() and 1.0 or 0.0, 0.14)
            KB.chk_fill = lerp(KB.chk_fill, session_cfg.settings.keyboard_enabled and 1.0 or 0.0, 0.12)

            local kb_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], KB.chk_hover), t.bg_act[1], KB.chk_fill)
            local kb_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], KB.chk_hover), t.bg_act[2], KB.chk_fill)
            local kb_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], KB.chk_hover), t.bg_act[3], KB.chk_fill)
            local kb_bg_a = lerp(lerp(0.20, 0.45, KB.chk_hover), 0.75, KB.chk_fill)
            local kb_br_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], KB.chk_hover), t.bor_act[1], KB.chk_fill)
            local kb_br_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], KB.chk_hover), t.bor_act[2], KB.chk_fill)
            local kb_br_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], KB.chk_hover), t.bor_act[3], KB.chk_fill)
            local kb_br_a = lerp(lerp(0.25, 0.60, KB.chk_hover), 0.95, KB.chk_fill)

            draw_list:AddRectFilled(p_kb, imgui.ImVec2(p_kb.x + kb_chk_size.x, p_kb.y + kb_chk_size.y),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(kb_bg_r, kb_bg_g, kb_bg_b, kb_bg_a * menu.alpha)), 6.0)
            draw_list:AddRect(p_kb, imgui.ImVec2(p_kb.x + kb_chk_size.x, p_kb.y + kb_chk_size.y),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(kb_br_r, kb_br_g, kb_br_b, kb_br_a * menu.alpha)), 6.0, 15, 1.2)

            local kb_lbl = u8"Keyboard"
            local kb_lbl_sz = imgui.CalcTextSize(kb_lbl)
            local kb_txt_val = lerp(lerp(0.65, 0.85, KB.chk_hover), 1.00, KB.chk_fill)
            draw_list:AddText(imgui.ImVec2(p_kb.x + (kb_chk_size.x - kb_lbl_sz.x) / 2, p_kb.y + (kb_chk_size.y - kb_lbl_sz.y) / 2),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, kb_txt_val * menu.alpha)), kb_lbl)

            if rv > 0.01 then
                imgui.SameLine(0, kb_spacing_x * rv)
                if menu.gear_button("##mhg_kb_gear_btn", imgui.ImVec2(32 * rv, kb_btn_size.y), menu.pop.id == "kb", rv) and rv > 0.85 then
                    menu.toggle_popup("kb")
                end
            end

            imgui.Dummy(imgui.ImVec2(0, 10))
            menu.anim_text("##tab1_block_lbl", u8"Блокировка клавиш:", t.text_muted, 1.0)
            imgui.Dummy(imgui.ImVec2(0, 5))
            if menu.button("##mhg_kb_blockc_main", u8"Блокировать C", kb_btn_size,
                session_cfg.settings.keyboard_block_c) then
                session_cfg.settings.keyboard_block_c = not session_cfg.settings.keyboard_block_c
                inicfg.save(session_cfg, CONFIG_FILE)
            end
        elseif menu.current_tab == 2 then
            menu.anim_text("##tab2_asp_lbl", u8"Соотношение экрана: ASP", t.text_muted, 1.0)
            imgui.Dummy(imgui.ImVec2(0, 5))

            local settings_btn_size = imgui.ImVec2(218, 32)

            -- === ASP enable ===
            -- Как у Keyboard: пока ASP включён, кнопка сужается, справа появляется шестерёнка с настройками.
            asp_reveal = lerp(asp_reveal, session_cfg.settings.asp_enabled and 1.0 or 0.0, 0.14)
            local arv = asp_reveal
            local asp_btn_size = imgui.ImVec2(settings_btn_size.x - (32 + 10) * arv, settings_btn_size.y)
            local p_asp_chk = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_asp_enabled_chk", asp_btn_size) then
                session_cfg.settings.asp_enabled = not session_cfg.settings.asp_enabled
                if session_cfg.settings.asp_enabled then
                    apply_asp(session_cfg.settings.asp_value or 1.25)
                else
                    disable_asp()
                end
                inicfg.save(session_cfg, CONFIG_FILE)
            end

            local is_asp_chk_hovered = imgui.IsItemHovered()
            asp_chk_hover_alpha = lerp(asp_chk_hover_alpha, is_asp_chk_hovered and 1.0 or 0.0, 0.14)

            local asp_is_enabled = session_cfg.settings.asp_enabled
            local asp_target = asp_is_enabled and 1.0 or 0.0
            asp_fill_progress = lerp(asp_fill_progress, asp_target, 0.12)
            local asp_fill_val = asp_fill_progress

            local a_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], asp_chk_hover_alpha), t.bg_act[1], asp_fill_val)
            local a_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], asp_chk_hover_alpha), t.bg_act[2], asp_fill_val)
            local a_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], asp_chk_hover_alpha), t.bg_act[3], asp_fill_val)
            local a_bg_a = lerp(lerp(0.20, 0.45, asp_chk_hover_alpha), 0.75, asp_fill_val)

            local a_bor_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], asp_chk_hover_alpha), t.bor_act[1], asp_fill_val)
            local a_bor_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], asp_chk_hover_alpha), t.bor_act[2], asp_fill_val)
            local a_bor_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], asp_chk_hover_alpha), t.bor_act[3], asp_fill_val)
            local a_bor_a = lerp(lerp(0.25, 0.60, asp_chk_hover_alpha), 0.95, asp_fill_val)

            draw_list:AddRectFilled(p_asp_chk, imgui.ImVec2(p_asp_chk.x + asp_btn_size.x, p_asp_chk.y + asp_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(a_bg_r, a_bg_g, a_bg_b, a_bg_a * menu.alpha)), 6.0)
            draw_list:AddRect(p_asp_chk, imgui.ImVec2(p_asp_chk.x + asp_btn_size.x, p_asp_chk.y + asp_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(a_bor_r, a_bor_g, a_bor_b, a_bor_a * menu.alpha)), 6.0, 15, 1.2)

            local asp_lbl = u8"ASP"
            local asp_lbl_sz = imgui.CalcTextSize(asp_lbl)
            local asp_lbl_pos = imgui.ImVec2(p_asp_chk.x + (asp_btn_size.x - asp_lbl_sz.x) / 2, p_asp_chk.y + (asp_btn_size.y - asp_lbl_sz.y) / 2)
            local asp_text_val = lerp(lerp(0.65, 0.85, asp_chk_hover_alpha), 1.00, asp_fill_val)
            draw_list:AddText(asp_lbl_pos, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, asp_text_val * menu.alpha)), asp_lbl)

            if arv > 0.01 then
                imgui.SameLine(0, 10 * arv)
                if menu.gear_button("##mhg_asp_gear_btn", imgui.ImVec2(32 * arv, settings_btn_size.y), menu.pop.id == "asp", arv) and arv > 0.85 then
                    menu.toggle_popup("asp")
                end
            end
        elseif menu.current_tab == 3 then
            local settings_btn_size = imgui.ImVec2(218, 32)
            local hotkey_btn_size = imgui.ImVec2(ROW_W, 32) -- во всю ширину, как ряды ниже

            menu.anim_text("##tab3_hk_lbl", u8"Клавиша открытия меню:", t.text_muted, 1.0)
            imgui.Dummy(imgui.ImVec2(0, 5))

            local p_hk = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_hotkey_btn", hotkey_btn_size) then
                menu.hotkey_listening = true
            end

            local is_hk_hovered = imgui.IsItemHovered()
            hotkey_btn_hover_alpha = lerp(hotkey_btn_hover_alpha, (is_hk_hovered or menu.hotkey_listening) and 1.0 or 0.0, 0.14)

            local hk_min = p_hk
            local hk_max = imgui.ImVec2(p_hk.x + hotkey_btn_size.x, p_hk.y + hotkey_btn_size.y)
            local hk_fill_val = menu.hotkey_listening and 1.0 or 0.0
            local hk_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], hotkey_btn_hover_alpha), t.bg_act[1], hk_fill_val)
            local hk_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], hotkey_btn_hover_alpha), t.bg_act[2], hk_fill_val)
            local hk_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], hotkey_btn_hover_alpha), t.bg_act[3], hk_fill_val)
            local hk_bg_a = lerp(lerp(0.20, 0.45, hotkey_btn_hover_alpha), 0.75, hk_fill_val)
            local hk_bor_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], hotkey_btn_hover_alpha), t.bor_act[1], hk_fill_val)
            local hk_bor_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], hotkey_btn_hover_alpha), t.bor_act[2], hk_fill_val)
            local hk_bor_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], hotkey_btn_hover_alpha), t.bor_act[3], hk_fill_val)
            local hk_bor_a = lerp(lerp(0.25, 0.60, hotkey_btn_hover_alpha), 0.95, hk_fill_val)

            draw_list:AddRectFilled(hk_min, hk_max, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(hk_bg_r, hk_bg_g, hk_bg_b, hk_bg_a * menu.alpha)), 6.0)
            draw_list:AddRect(hk_min, hk_max, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(hk_bor_r, hk_bor_g, hk_bor_b, hk_bor_a * menu.alpha)), 6.0, 15, 1.2)

            local hk_text_val = lerp(lerp(0.65, 0.85, hotkey_btn_hover_alpha), 1.00, hk_fill_val)
            if menu.hotkey_listening then
                -- анимированные точки + пульс текста
                local base, _, pulse = waiting_key_anim(u8"Нажмите клавишу")
                local base_sz = imgui.CalcTextSize(base)
                local dots_sz = imgui.CalcTextSize("...")
                local total_w = base_sz.x + dots_sz.x
                local tx = hk_min.x + (hotkey_btn_size.x - total_w) / 2
                local ty = hk_min.y + (hotkey_btn_size.y - base_sz.y) / 2
                local col_base = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, hk_text_val * menu.alpha * pulse))
                draw_list:AddText(imgui.ImVec2(tx, ty), col_base, base)
                local phase = math.floor(os.clock() * 4.0) % 3
                local dx = tx + base_sz.x
                for i = 0, 2 do
                    local bright = (i == phase) and 1.0 or 0.25
                    local dcol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, hk_text_val * menu.alpha * bright))
                    local csz = imgui.CalcTextSize(".")
                    draw_list:AddText(imgui.ImVec2(dx, ty), dcol, ".")
                    dx = dx + csz.x
                end
            else
                local hk_str = get_key_name(session_cfg.settings.open_key)
                local hk_txt_sz = imgui.CalcTextSize(hk_str)
                local hk_txt_pos = imgui.ImVec2(hk_min.x + (hotkey_btn_size.x - hk_txt_sz.x) / 2, hk_min.y + (hotkey_btn_size.y - hk_txt_sz.y) / 2)
                draw_list:AddText(hk_txt_pos, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, hk_text_val * menu.alpha)), hk_str)
            end

            imgui.Dummy(imgui.ImVec2(0, 14))
            menu.anim_text("##tab3_theme_lbl", u8"Тема оформления:", t.text_muted, 1.0)
            imgui.Dummy(imgui.ImVec2(0, 5))

            local theme_btn_size = imgui.ImVec2(218, 32)
            local theme_spacing_x = 10
            
            for i, theme_data in ipairs(themes) do
                local p_theme = imgui.GetCursorScreenPos()
                local is_selected = (session_cfg.settings.theme == i)
                
                if imgui.InvisibleButton("##custom_theme_btn_" .. i, theme_btn_size) then
                    session_cfg.settings.theme = i
                    inicfg.save(session_cfg, CONFIG_FILE)
                end

                local is_theme_hovered = imgui.IsItemHovered()
                local theme_target = is_selected and 1.0 or 0.0
                theme_fill_progress[i] = lerp(theme_fill_progress[i] or 0.0, theme_target, 0.12)
                local theme_fill_val = theme_fill_progress[i]
                
                local th_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], is_theme_hovered and 1.0 or 0.0), t.bg_act[1], theme_fill_val)
                local th_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], is_theme_hovered and 1.0 or 0.0), t.bg_act[2], theme_fill_val)
                local th_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], is_theme_hovered and 1.0 or 0.0), t.bg_act[3], theme_fill_val)
                local th_bg_a = lerp(lerp(0.20, 0.45, is_theme_hovered and 1.0 or 0.0), 0.75, theme_fill_val)

                local th_bor_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], is_theme_hovered and 1.0 or 0.0), t.bor_act[1], theme_fill_val)
                local th_bor_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], is_theme_hovered and 1.0 or 0.0), t.bor_act[2], theme_fill_val)
                local th_bor_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], is_theme_hovered and 1.0 or 0.0), t.bor_act[3], theme_fill_val)
                local th_bor_a = lerp(lerp(0.25, 0.60, is_theme_hovered and 1.0 or 0.0), 0.95, theme_fill_val)

                local th_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(th_bg_r, th_bg_g, th_bg_b, th_bg_a * menu.alpha))
                local th_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(th_bor_r, th_bor_g, th_bor_b, th_bor_a * menu.alpha))

                draw_list:AddRectFilled(p_theme, imgui.ImVec2(p_theme.x + theme_btn_size.x, p_theme.y + theme_btn_size.y), th_bg_col, 6.0)
                draw_list:AddRect(p_theme, imgui.ImVec2(p_theme.x + theme_btn_size.x, p_theme.y + theme_btn_size.y), th_bor_col, 6.0, 15, 1.2)

                local th_txt_sz = imgui.CalcTextSize(theme_data.name)
                local th_txt_pos = imgui.ImVec2(p_theme.x + 12, p_theme.y + (theme_btn_size.y - th_txt_sz.y) / 2)
                local th_text_val = lerp(lerp(0.65, 0.85, is_theme_hovered and 1.0 or 0.0), 1.00, theme_fill_val)
                local th_text_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, th_text_val * menu.alpha))
                draw_list:AddText(th_txt_pos, th_text_col, theme_data.name)

                local circle_center = imgui.ImVec2(p_theme.x + theme_btn_size.x - 20, p_theme.y + theme_btn_size.y / 2)
                draw_list:AddCircle(circle_center, 6.0, th_bor_col, 12, 1.2)
                if is_selected then
                    local accent_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], menu.alpha))
                    draw_list:AddCircleFilled(circle_center, 3.5, accent_col, 12)
                end

                if i % 3 ~= 0 then
                    imgui.SameLine(0, theme_spacing_x)
                else
                    imgui.Dummy(imgui.ImVec2(0, 8))
                end
            end
            imgui.Dummy(imgui.ImVec2(0, 10))

            menu.anim_text("##tab3_fx_lbl", u8"Эффекты интерфейса:", t.text_muted, 1.0)
            imgui.Dummy(imgui.ImVec2(0, 5))

            local settings_spacing_x = 10

            -- Particles
            -- Как у Watermark: пока частицы включены, кнопка сужается, справа появляется шестерёнка с настройками.
            menu.pt_reveal = lerp(menu.pt_reveal, session_cfg.settings.particles_enabled and 1.0 or 0.0, 0.14)
            local prv = menu.pt_reveal
            local pt_btn_size = imgui.ImVec2(settings_btn_size.x - (32 + settings_spacing_x) * prv, settings_btn_size.y)
            local p_chk = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_particles_chk", pt_btn_size) then
                session_cfg.settings.particles_enabled = not session_cfg.settings.particles_enabled
                inicfg.save(session_cfg, CONFIG_FILE)
            end

            local is_chk_hovered = imgui.IsItemHovered()
            checkbox_hover_alpha = lerp(checkbox_hover_alpha, is_chk_hovered and 1.0 or 0.0, 0.14)
            
            local c_min = p_chk
            local c_max = imgui.ImVec2(p_chk.x + pt_btn_size.x, p_chk.y + pt_btn_size.y)
            local is_enabled = session_cfg.settings.particles_enabled
            local chk_target = is_enabled and 1.0 or 0.0
            particles_fill_progress = lerp(particles_fill_progress, chk_target, 0.12)
            local chk_fill_val = particles_fill_progress
            
            local c_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], checkbox_hover_alpha), t.bg_act[1], chk_fill_val)
            local c_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], checkbox_hover_alpha), t.bg_act[2], chk_fill_val)
            local c_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], checkbox_hover_alpha), t.bg_act[3], chk_fill_val)
            local c_bg_a = lerp(lerp(0.20, 0.45, checkbox_hover_alpha), 0.75, chk_fill_val)

            local c_bor_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], checkbox_hover_alpha), t.bor_act[1], chk_fill_val)
            local c_bor_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], checkbox_hover_alpha), t.bor_act[2], chk_fill_val)
            local c_bor_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], checkbox_hover_alpha), t.bor_act[3], chk_fill_val)
            local c_bor_a = lerp(lerp(0.25, 0.60, checkbox_hover_alpha), 0.95, chk_fill_val)

            local c_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(c_bg_r, c_bg_g, c_bg_b, c_bg_a * menu.alpha))
            local c_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(c_bor_r, c_bor_g, c_bor_b, c_bor_a * menu.alpha))

            draw_list:AddRectFilled(c_min, c_max, c_bg_col, 6.0)
            draw_list:AddRect(c_min, c_max, c_bor_col, 6.0, 15, 1.2)

            local status_str = u8"Частицы"
            local chk_txt_sz = imgui.CalcTextSize(status_str)
            local chk_txt_pos = imgui.ImVec2(c_min.x + (pt_btn_size.x - chk_txt_sz.x) / 2, c_min.y + (pt_btn_size.y - chk_txt_sz.y) / 2)
            local chk_text_col_val = lerp(lerp(0.65, 0.85, checkbox_hover_alpha), 1.00, chk_fill_val)
            local c_text_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, chk_text_col_val * menu.alpha))
            draw_list:AddText(chk_txt_pos, c_text_col, status_str)

            if prv > 0.01 then
                imgui.SameLine(0, settings_spacing_x * prv)
                if menu.gear_button("##mhg_pt_gear_btn", imgui.ImVec2(32 * prv, settings_btn_size.y), menu.pop.id == "pt", prv) and prv > 0.85 then
                    menu.toggle_popup("pt")
                end
            end

            imgui.SameLine(0, settings_spacing_x)

            -- Watermark (вместо переключателя анимации вкладок).
            -- Пока WM включён, кнопка сужается, а в освободившемся месте появляется шестерёнка с настройками WM.
            -- Суммарная ширина ряда не меняется, поэтому соседняя кнопка (Свечение окна) остаётся на месте.
            local wm_gear_w = 32
            menu.wm.reveal = lerp(menu.wm.reveal, session_cfg.settings.watermark_enabled and 1.0 or 0.0, 0.14)
            local wrv = menu.wm.reveal
            local wm_btn_size = imgui.ImVec2(settings_btn_size.x - (wm_gear_w + settings_spacing_x) * wrv, settings_btn_size.y)
            local p_wmset = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_watermark_chk", wm_btn_size) then
                session_cfg.settings.watermark_enabled = not session_cfg.settings.watermark_enabled
                inicfg.save(session_cfg, CONFIG_FILE)
            end

            local is_wmset_hovered = imgui.IsItemHovered()
            wm_hover_alpha = lerp(wm_hover_alpha, is_wmset_hovered and 1.0 or 0.0, 0.14)
            local wm_target_set = session_cfg.settings.watermark_enabled and 1.0 or 0.0
            wm_fill_progress = lerp(wm_fill_progress, wm_target_set, 0.12)
            local wm_fill_val = wm_fill_progress

            local w_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], wm_hover_alpha), t.bg_act[1], wm_fill_val)
            local w_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], wm_hover_alpha), t.bg_act[2], wm_fill_val)
            local w_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], wm_hover_alpha), t.bg_act[3], wm_fill_val)
            local w_bg_a = lerp(lerp(0.20, 0.45, wm_hover_alpha), 0.75, wm_fill_val)
            local w_bor_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], wm_hover_alpha), t.bor_act[1], wm_fill_val)
            local w_bor_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], wm_hover_alpha), t.bor_act[2], wm_fill_val)
            local w_bor_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], wm_hover_alpha), t.bor_act[3], wm_fill_val)
            local w_bor_a = lerp(lerp(0.25, 0.60, wm_hover_alpha), 0.95, wm_fill_val)

            draw_list:AddRectFilled(p_wmset, imgui.ImVec2(p_wmset.x + wm_btn_size.x, p_wmset.y + wm_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(w_bg_r, w_bg_g, w_bg_b, w_bg_a * menu.alpha)), 6.0)
            draw_list:AddRect(p_wmset, imgui.ImVec2(p_wmset.x + wm_btn_size.x, p_wmset.y + wm_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(w_bor_r, w_bor_g, w_bor_b, w_bor_a * menu.alpha)), 6.0, 15, 1.2)

            local wm_lbl = u8"Watermark"
            local wm_lbl_sz = imgui.CalcTextSize(wm_lbl)
            local wm_lbl_pos = imgui.ImVec2(p_wmset.x + (wm_btn_size.x - wm_lbl_sz.x) / 2, p_wmset.y + (wm_btn_size.y - wm_lbl_sz.y) / 2)
            local wm_text_val = lerp(lerp(0.65, 0.85, wm_hover_alpha), 1.00, wm_fill_val)
            draw_list:AddText(wm_lbl_pos, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, wm_text_val * menu.alpha)), wm_lbl)

            if wrv > 0.01 then
                imgui.SameLine(0, settings_spacing_x * wrv)
                local wm_gear_size = imgui.ImVec2(wm_gear_w * wrv, settings_btn_size.y)
                if menu.gear_button("##mhg_wm_gear_btn", wm_gear_size, menu.pop.id == "wm", wrv) and wrv > 0.85 then
                    menu.toggle_popup("wm")
                end
            end

            imgui.SameLine(0, settings_spacing_x)

            -- Glow: при включении кнопка сужается, справа шестерёнка с режимами/настройками
            menu.glow_reveal = lerp(menu.glow_reveal, session_cfg.settings.window_glow_enabled and 1.0 or 0.0, 0.14)
            local grv = menu.glow_reveal
            local glow_btn_size = imgui.ImVec2(settings_btn_size.x - (32 + settings_spacing_x) * grv, settings_btn_size.y)
            local p_glow = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_glow_chk", glow_btn_size) then
                session_cfg.settings.window_glow_enabled = not session_cfg.settings.window_glow_enabled
                inicfg.save(session_cfg, CONFIG_FILE)
            end

            local is_glow_hovered = imgui.IsItemHovered()
            glow_btn_hover_alpha = lerp(glow_btn_hover_alpha, is_glow_hovered and 1.0 or 0.0, 0.14)

            local glow_is_enabled = session_cfg.settings.window_glow_enabled
            local glow_target = glow_is_enabled and 1.0 or 0.0
            glow_fill_progress = lerp(glow_fill_progress, glow_target, 0.12)
            local glow_fill_val = glow_fill_progress

            local g_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], glow_btn_hover_alpha), t.bg_act[1], glow_fill_val)
            local g_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], glow_btn_hover_alpha), t.bg_act[2], glow_fill_val)
            local g_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], glow_btn_hover_alpha), t.bg_act[3], glow_fill_val)
            local g_bg_a = lerp(lerp(0.20, 0.45, glow_btn_hover_alpha), 0.75, glow_fill_val)

            local g_bor_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], glow_btn_hover_alpha), t.bor_act[1], glow_fill_val)
            local g_bor_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], glow_btn_hover_alpha), t.bor_act[2], glow_fill_val)
            local g_bor_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], glow_btn_hover_alpha), t.bor_act[3], glow_fill_val)
            local g_bor_a = lerp(lerp(0.25, 0.60, glow_btn_hover_alpha), 0.95, glow_fill_val)

            local g_bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(g_bg_r, g_bg_g, g_bg_b, g_bg_a * menu.alpha))
            local g_bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(g_bor_r, g_bor_g, g_bor_b, g_bor_a * menu.alpha))

            draw_list:AddRectFilled(p_glow, imgui.ImVec2(p_glow.x + glow_btn_size.x, p_glow.y + glow_btn_size.y), g_bg_col, 6.0)
            draw_list:AddRect(p_glow, imgui.ImVec2(p_glow.x + glow_btn_size.x, p_glow.y + glow_btn_size.y), g_bor_col, 6.0, 15, 1.2)

            local glow_status_str = u8"Свечение окна"
            local glow_txt_sz = imgui.CalcTextSize(glow_status_str)
            local glow_txt_pos = imgui.ImVec2(p_glow.x + (glow_btn_size.x - glow_txt_sz.x) / 2, p_glow.y + (glow_btn_size.y - glow_txt_sz.y) / 2)
            local glow_text_val = lerp(lerp(0.65, 0.85, glow_btn_hover_alpha), 1.00, glow_fill_val)
            local glow_text_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, glow_text_val * menu.alpha))
            draw_list:AddText(glow_txt_pos, glow_text_col, glow_status_str)

            if grv > 0.01 then
                imgui.SameLine(0, settings_spacing_x * grv)
                if menu.gear_button("##mhg_glow_gear_btn", imgui.ImVec2(32 * grv, settings_btn_size.y), menu.pop.id == "glow", grv) and grv > 0.85 then
                    menu.toggle_popup("glow")
                end
            end

        end

        imgui.PopStyleVar(1)
        imgui.EndChild()
        imgui.End()
    end

    menu.draw_popup()

    imgui.PopStyleColor(2)
    imgui.PopStyleVar(5)
end

-- === Watermark overlay ===

-- packet loss (показывается в WM только при значении >= 1)
local function get_packet_loss()
    if not isSampAvailable() then return 0 end
    local res, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not res then return 0 end

    local ok, val = pcall(function()
        if type(sampGetPlayerPacketLoss) == 'function' then
            return sampGetPlayerPacketLoss(id)
        end
        return nil
    end)
    if ok and type(val) == 'number' then
        return math.floor(val + 0.5)
    end

    ok, val = pcall(function()
        if type(sampGetPlayerPacketLossPercent) == 'function' then
            return sampGetPlayerPacketLossPercent(id)
        end
        return nil
    end)
    if ok and type(val) == 'number' then
        return math.floor(val + 0.5)
    end

    -- fallback: RakNet statistics (packetlossLastSecond), если доступен интерфейс
    ok, val = pcall(function()
        if type(sampGetRakclientInterface) ~= 'function' then return nil end
        local iface = sampGetRakclientInterface()
        if iface == nil or iface == 0 then return nil end
        -- типичный оффсет float packetlossLastSecond в статистике (эвристика)
        local ptr = memory.getuint32(iface, true)
        if not ptr or ptr == 0 then return nil end
        local loss = memory.getfloat(ptr + 0x34C, true) -- часто встречается на R1/R3
        if type(loss) == 'number' and loss >= 0 and loss <= 100 then
            return loss
        end
        return nil
    end)
    if ok and type(val) == 'number' then
        return math.floor(val + 0.5)
    end

    return 0
end

local watermark_frame
watermark_frame = imgui.OnFrame(
    function()
        local wm_on = (session_cfg.settings.watermark_enabled ~= false)
        wm_overlay_alpha = lerp(wm_overlay_alpha, wm_on and 1.0 or 0.0, 0.08)
        if not wm_on then
            menu.wm.edit = false
            menu.wm.drag = false
        end

        -- в режиме правки нужен курсор и блокировка управления игроком
        watermark_frame.HideCursor = not menu.wm.edit
        watermark_frame.LockPlayer = menu.wm.edit

        return wm_overlay_alpha > 0.01 and not isGamePaused()
    end,
    function()
        local t = get_theme()
        local sw, sh = getScreenResolution()
        local a = wm_overlay_alpha

        local fps = math.floor(imgui.GetIO().Framerate)
        local nick = get_my_nick()
        local ping = 0
        if isSampAvailable() then
            local res, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if res then
                ping = sampGetPlayerPing(id)
            end
        end
        local pc_time = os.date("%H:%M")
        local pl = get_packet_loss()

        local parts = {
            "MHG",
            nick,
            string.format("%d fps", fps),
            string.format("%d ms", ping)
        }
        if pl >= 1 then
            table.insert(parts, string.format("PL %d%%", pl))
        end
        table.insert(parts, pc_time)

        -- gap between items + width of vertical separator line zone
        local item_gap = 4.0
        local sep_zone = 5.0  -- space reserved for | between items

        local content_w = 0.0
        local content_h = 0.0
        local part_widths = {}
        for i, part in ipairs(parts) do
            local psz = imgui.CalcTextSize(part)
            part_widths[i] = psz.x
            content_w = content_w + psz.x
            if psz.y > content_h then content_h = psz.y end
            if i < #parts then
                content_w = content_w + item_gap + sep_zone + item_gap
            end
        end

        local pad_x, pad_y = 12.0, 6.0
        local target_w = content_w + pad_x * 2
        local target_h = content_h + pad_y * 2

        -- smooth resize when FPS digits / PL appear
        if wm_anim_w < 1.0 then
            wm_anim_w = target_w
            wm_anim_h = target_h
        else
            wm_anim_w = lerp(wm_anim_w, target_w, 0.12)
            wm_anim_h = lerp(wm_anim_h, target_h, 0.12)
        end

        local win_w = wm_anim_w
        local win_h = wm_anim_h

        -- === положение WM ===
        -- watermark_x < 0 — по умолчанию (правый верхний угол).
        -- Иначе: halign 0/1/2 = левый край / центр экрана / правый край;
        --        valign 0/1 = верхний край / нижний край.
        -- При смене ширины WM «растёт» от закреплённого края (или от центра).
        local W = menu.wm
        local cfg = session_cfg.settings
        W.edit_alpha = lerp(W.edit_alpha, W.edit and 1.0 or 0.0, 0.14)

        local wm_x, wm_y
        if (cfg.watermark_x or -1) >= 0 and (cfg.watermark_y or -1) >= 0 then
            local ax, ay = cfg.watermark_x, cfg.watermark_y
            local halign = cfg.watermark_halign
            if halign == nil then
                halign = (cfg.watermark_right ~= 0) and 2 or 0
            end
            local valign = cfg.watermark_valign or 0

            if halign == 1 then
                wm_x = ax - win_w * 0.5
            elseif halign == 2 or (cfg.watermark_right ~= 0 and halign ~= 0) then
                wm_x = ax - win_w
            else
                wm_x = ax
            end
            if valign == 1 then
                wm_y = ay - win_h
            else
                wm_y = ay
            end
            wm_x = math.max(0, math.min(wm_x, sw - win_w))
            wm_y = math.max(0, math.min(wm_y, sh - win_h))
        else
            -- по умолчанию: правый верхний угол
            wm_x = math.max(0, sw - 12 - win_w)
            wm_y = 10
        end

        -- правка: перетаскивание ЛКМ
        if W.edit then
            local mp = imgui.GetMousePos()
            if not W.drag then
                local over_menu = menu.mouse_over_ui(mp.x, mp.y)
                if imgui.IsMouseClicked(0) and not over_menu
                    and mp.x >= wm_x and mp.x <= wm_x + win_w and mp.y >= wm_y and mp.y <= wm_y + win_h then
                    W.drag = true
                    W.drag_dx = mp.x - wm_x
                    W.drag_dy = mp.y - wm_y
                end
            end
            if W.drag then
                if imgui.IsMouseDown(0) then
                    wm_x = math.max(0, math.min(mp.x - W.drag_dx, sw - win_w))
                    wm_y = math.max(0, math.min(mp.y - W.drag_dy, sh - win_h))
                    -- зона привязки: левая / центральная / правая треть по X, верх / низ по Y
                    local cx = wm_x + win_w * 0.5
                    local cy = wm_y + win_h * 0.5
                    local halign
                    if cx < sw * 0.33 then
                        halign = 0
                    elseif cx > sw * 0.67 then
                        halign = 2
                    else
                        halign = 1
                    end
                    local valign = (cy > sh * 0.5) and 1 or 0
                    cfg.watermark_halign = halign
                    cfg.watermark_valign = valign
                    cfg.watermark_right = (halign == 2) and 1 or 0
                    if halign == 0 then
                        cfg.watermark_x = math.floor(wm_x)
                    elseif halign == 2 then
                        cfg.watermark_x = math.floor(wm_x + win_w)
                    else
                        cfg.watermark_x = math.floor(cx)
                    end
                    if valign == 0 then
                        cfg.watermark_y = math.floor(wm_y)
                    else
                        cfg.watermark_y = math.floor(wm_y + win_h)
                    end
                else
                    W.drag = false
                    inicfg.save(session_cfg, CONFIG_FILE)
                end
            end
        else
            W.drag = false
        end

        imgui.SetNextWindowPos(imgui.ImVec2(wm_x, wm_y), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(win_w, win_h), imgui.Cond.Always)

        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, a)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))

        local wm_flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoInputs

        if imgui.Begin("##watermark_overlay", nil, wm_flags) then
            local dl = imgui.GetWindowDrawList()
            local pos = imgui.GetWindowPos()
            local pmin = imgui.ImVec2(pos.x, pos.y)
            local pmax = imgui.ImVec2(pos.x + win_w, pos.y + win_h)

            -- glow вокруг WM (упрощённо под режим + скорость)
            if session_cfg.settings.window_glow_enabled then
                local gcfg = session_cfg.settings
                local gstyle = math.max(1, math.min(math.floor(gcfg.window_glow_style or 1), #GLOW_STYLES))
                local gspd = math.max(0.2, math.min(gcfg.window_glow_speed or 1.0, 3.0))
                local time = os.clock() * 2.5 * gspd
                local pulse = math.sin(time) * 0.5 + 0.5
                -- при радужной теме свечение нейтральное (не радужное)
                local gr, gg, gb
                if t.rainbow then
                    gr, gg, gb = 0.95, 0.95, 1.0
                    if gstyle == 3 then gstyle = 1 end
                else
                    gr, gg, gb = t.accent[1], t.accent[2], t.accent[3]
                    if gstyle == 3 then
                        gr, gg, gb = hsv_to_rgb((os.clock() * 0.15 * gspd) % 1.0, 0.80, 1.00)
                    end
                end
                if gstyle == 4 then
                    -- змейка на WM
                    local pad = 2.0
                    local x, y = pmin.x - pad, pmin.y - pad
                    local w, h = win_w + pad * 2, win_h + pad * 2
                    local per = 2.0 * (w + h)
                    if per > 1.0 then
                        local head = (os.clock() * 100.0 * gspd) % per
                        local body_len = per * 0.28
                        local segs = 18
                        local prev_x, prev_y = glow_perimeter_point(x, y, w, h, head)
                        for s = 1, segs do
                            local d = head - (s / segs) * body_len
                            local px, py = glow_perimeter_point(x, y, w, h, d)
                            local fade = 1.0 - (s / segs)
                            fade = fade * fade
                            local col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(gr, gg, gb, (0.12 + 0.75 * fade) * a))
                            dl:AddLine(imgui.ImVec2(prev_x, prev_y), imgui.ImVec2(px, py), col, 1.0 + fade * 1.8)
                            prev_x, prev_y = px, py
                        end
                    end
                else
                    local glow_a = (0.16 + pulse * 0.22) * a
                    for i = 2, 1, -1 do
                        local off = i * 1.5
                        local gcol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(gr, gg, gb, glow_a / i))
                        dl:AddRect(
                            imgui.ImVec2(pmin.x - off, pmin.y - off),
                            imgui.ImVec2(pmax.x + off, pmax.y + off),
                            gcol, 7.0 + off, 15, 1.25
                        )
                    end
                end
            end

            -- фон
            local bg = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.05, 0.06, 0.09, 0.92 * a))
            dl:AddRectFilled(pmin, pmax, bg, 7.0)

            -- частицы на WM (если включено в настройках)
            dl:PushClipRect(pmin, pmax, true)
            draw_wm_particles(dl, pmin, imgui.ImVec2(win_w, win_h), a, t)
            dl:PopClipRect()

            local bor = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bor_hover[1], t.bor_hover[2], t.bor_hover[3], 0.65 * a))
            dl:AddRect(pmin, pmax, bor, 7.0, 15, 1.15)

            if W.edit_alpha > 0.01 then
                local edit_pulse = 0.5 + 0.5 * math.sin(os.clock() * 3.4)
                local edit_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
                    t.accent[1], t.accent[2], t.accent[3], (0.40 + 0.50 * edit_pulse) * W.edit_alpha * a))
                dl:AddRect(imgui.ImVec2(pmin.x - 2, pmin.y - 2), imgui.ImVec2(pmax.x + 2, pmax.y + 2),
                    edit_col, 8.5, 15, W.drag and 2.4 or 1.6)
            end

            local accent_line = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 0.55 * a))
            dl:AddLine(
                imgui.ImVec2(pmin.x + 6, pmin.y + 1),
                imgui.ImVec2(pmax.x - 6, pmin.y + 1),
                accent_line, 1.25
            )

            -- частицы внутри WM (если включены)
            if session_cfg.settings.particles_enabled and (cfg.particles_style or 1) == 1 then
                local time = os.clock()
                for i = 1, 5 do
                    local px = pmin.x + 4 + ((time * 12 + i * 41) % math.max(1, win_w - 8))
                    local py = pmin.y + 3 + ((time * 7 + i * 29) % math.max(1, win_h - 6))
                    local dot = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 0.14 * a))
                    dl:AddCircleFilled(imgui.ImVec2(px, py), 1.1, dot)
                end
            end

            local x = pos.x + pad_x
            local y = pos.y + (win_h - content_h) * 0.5
            local accent_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], a))
            local text_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, a))
            local muted_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, a * 0.85))
            local pl_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.42, 0.32, a))
            local sep_time = os.clock()
            local sep_pulse = 0.55 + 0.25 * (math.sin(sep_time * 2.2) * 0.5 + 0.5)
            local sep_grow = 0.72 + 0.28 * (math.sin(sep_time * 1.6) * 0.5 + 0.5)

            for i, part in ipairs(parts) do
                if i > 1 then
                    x = x + item_gap
                    -- animated vertical separator
                    local line_x = x + sep_zone * 0.5
                    local full_y1 = pos.y + pad_y * 0.55
                    local full_y2 = pos.y + win_h - pad_y * 0.55
                    local mid_y = (full_y1 + full_y2) * 0.5
                    local half = (full_y2 - full_y1) * 0.5 * sep_grow
                    local line_y1 = mid_y - half
                    local line_y2 = mid_y + half
                    local phase = (i * 0.7 + sep_time * 2.0)
                    local alpha_wave = 0.35 + 0.30 * (math.sin(phase) * 0.5 + 0.5)
                    local sep_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
                        t.accent[1], t.accent[2], t.accent[3], alpha_wave * sep_pulse * a
                    ))
                    dl:AddLine(imgui.ImVec2(line_x, line_y1), imgui.ImVec2(line_x, line_y2), sep_col, 1.15)
                    x = x + sep_zone + item_gap
                end
                local col = text_col
                if i == 1 then
                    col = accent_col
                elseif pl >= 1 and part:find("^PL ") then
                    col = pl_col
                end
                dl:AddText(imgui.ImVec2(x, y), col, part)
                x = x + part_widths[i]
            end

            imgui.End()
        end

        -- подсказка в режиме правки (без подложки, только текст)
        if W.edit_alpha > 0.01 then
            local hint = u8"ЛКМ — перетащить Watermark. ESC — выйти."
            local hsz = imgui.CalcTextSize(hint)
            local hw, hh = hsz.x + 6, hsz.y + 6
            imgui.SetNextWindowPos(imgui.ImVec2(sw * 0.5 - hw * 0.5, 40), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(hw, hh), imgui.Cond.Always)
            local hint_flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar
                + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoSavedSettings
                + imgui.WindowFlags.NoBringToFrontOnFocus + imgui.WindowFlags.NoBackground
                + imgui.WindowFlags.NoInputs
            if imgui.Begin("##mhg_wm_hint", nil, hint_flags) then
                local hdl = imgui.GetWindowDrawList()
                local hpos = imgui.GetWindowPos()
                local ha = W.edit_alpha
                local shadow = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0, 0, 0, 0.75 * ha))
                for ox = -1, 1 do
                    for oy = -1, 1 do
                        if ox ~= 0 or oy ~= 0 then
                            hdl:AddText(imgui.ImVec2(hpos.x + 3 + ox, hpos.y + 3 + oy), shadow, hint)
                        end
                    end
                end
                hdl:AddText(imgui.ImVec2(hpos.x + 3, hpos.y + 3), imgui.ColorConvertFloat4ToU32(
                    imgui.ImVec4(t.text.x, t.text.y, t.text.z, ha)), hint)
                imgui.End()
            end
        end

        imgui.PopStyleColor(1)
        imgui.PopStyleVar(4)
    end
)
watermark_frame.HideCursor = true

-- =========================================================
-- ===============  ЭКРАННАЯ КЛАВИАТУРА (KB)  ==============
-- =========================================================
--
-- Клавиши хранятся одним списком KB.keys. Каждый элемент — самостоятельный
-- виджет: своя позиция, свой размер и (для добавленных пользователем клавиш)
-- свой virtual-key код. Список полностью редактируемый в режиме правки:
-- клавиши можно добавлять по хоткею, перетаскивать, менять размер колесом
-- или ползунком в меню и удалять (кнопкой ✕ на клавише, кнопкой "Удалить"
-- в меню или клавишей Delete).

local KB_UNIT  = 36          -- базовая высота/ширина клавиши
local KB_GAP   = 6
local KB_PITCH = KB_UNIT + KB_GAP

local KB_MOUSE_W = 52
local KB_SCALE_MIN, KB_SCALE_MAX = 0.5, 2.5

-- Статичное описание клавиш по умолчанию: id, vk-код, подпись/глиф,
-- ширина и смещение относительно левого верхнего угла раскладки.
local KB_DEFAULT_DEFS = {
    { id = "Q",     label = "Q",     vk = vkeys.VK_Q,       dx = 0,            dy = 0,            bw = KB_UNIT },
    { id = "W",     label = "W",     vk = vkeys.VK_W,       dx = KB_PITCH,     dy = 0,            bw = KB_UNIT },
    { id = "E",     label = "E",     vk = vkeys.VK_E,       dx = KB_PITCH * 2, dy = 0,            bw = KB_UNIT },
    { id = "A",     label = "A",     vk = vkeys.VK_A,       dx = 0,            dy = KB_PITCH,     bw = KB_UNIT },
    { id = "S",     label = "S",     vk = vkeys.VK_S,       dx = KB_PITCH,     dy = KB_PITCH,     bw = KB_UNIT },
    { id = "D",     label = "D",     vk = vkeys.VK_D,       dx = KB_PITCH * 2, dy = KB_PITCH,     bw = KB_UNIT },
    { id = "SHIFT", label = "SHIFT", vk = vkeys.VK_SHIFT,   dx = 0,            dy = KB_PITCH * 2, bw = KB_PITCH + KB_UNIT },
    { id = "C",     label = "C",     vk = vkeys.VK_C,       dx = KB_PITCH * 2, dy = KB_PITCH * 2, bw = KB_UNIT },
    { id = "SPACE", label = "SPACE", vk = vkeys.VK_SPACE,   dx = 0,            dy = KB_PITCH * 3, bw = KB_PITCH * 2 + KB_UNIT },
    { id = "LMB",   label = u8"ЛКМ", vk = vkeys.VK_LBUTTON, dx = KB_PITCH * 3 + 14,                       dy = 0,        bw = KB_MOUSE_W },
    { id = "RMB",   label = u8"ПКМ", vk = vkeys.VK_RBUTTON, dx = KB_PITCH * 3 + 14 + KB_MOUSE_W + KB_GAP, dy = 0,        bw = KB_MOUSE_W },
    { id = "WUP",   glyph = "up",    vk = nil,              dx = KB_PITCH * 3 + 14,                       dy = KB_PITCH, bw = KB_MOUSE_W },
    { id = "WDN",   glyph = "down",  vk = nil,              dx = KB_PITCH * 3 + 14 + KB_MOUSE_W + KB_GAP, dy = KB_PITCH, bw = KB_MOUSE_W },
}

local KB_DEFAULT_BY_ID = {}
for _, def in ipairs(KB_DEFAULT_DEFS) do KB_DEFAULT_BY_ID[def.id] = def end

KB = {
    alpha        = 0.0,   -- общая прозрачность оверлея
    edit         = false, -- режим правки (перетаскивание, размер, добавление/удаление)
    edit_alpha   = 0.0,
    drag_id      = nil,
    drag_dx      = 0.0,
    drag_dy      = 0.0,
    selected_id  = nil,       -- выбранная клавиша (для ползунка размера/удаления)
    awaiting_new_key = false, -- ждём нажатия клавиши для добавления на оверлей
    block_anim   = 0.0,   -- анимация перечёркивания C
    glow         = 0.0,   -- анимация свечения
    wheel_up     = -10.0,
    wheel_down   = -10.0,
    keys         = {},    -- {id, kind="b"/"c", vk, label, glyph, bw, x, y, s}
    state        = {},    -- фактическое состояние клавиш (обновляется в main)
    anim         = {},    -- сглаженное состояние для отрисовки
    hover        = {},
    size_buf     = imgui.new.float[1](1.0), -- буфер ползунка размера выбранной клавиши
    SCALE_MIN    = KB_SCALE_MIN, -- продублировано на таблице KB: menu.draw объявлена
    SCALE_MAX    = KB_SCALE_MAX, -- выше по файлу и не видит локальные KB_SCALE_MIN/MAX
    -- анимации кнопок в меню
    chk_hover = 0.0, chk_fill = 0.0,
    bc_hover  = 0.0, bc_fill  = 0.0,
    ed_hover  = 0.0, ed_fill  = 0.0,
    add_hover = 0.0, add_fill = 0.0,
    del_hover = 0.0,
    rst_hover = 0.0,
    panel_reveal = 0.0
}

-- === раскладка: "id:kind:vk:x:y:scale;..." в settings.keyboard_layout ===
-- kind: "b" — встроенная клавиша (label/glyph берутся из KB_DEFAULT_DEFS),
--       "c" — добавленная пользователем (label вычисляется из vk).

local function kb_default_keys()
    local sw, sh = getScreenResolution()
    local total_w = KB_PITCH * 3 + 14 + KB_MOUSE_W * 2 + KB_GAP
    local total_h = KB_PITCH * 3 + KB_UNIT
    local base_x = math.floor(sw * 0.5 - total_w * 0.5)
    local base_y = math.floor(sh - total_h - 90)
    local out = {}
    for _, def in ipairs(KB_DEFAULT_DEFS) do
        out[#out + 1] = {
            id = def.id, kind = "b", vk = def.vk, label = def.label, glyph = def.glyph,
            bw = def.bw, x = base_x + def.dx, y = base_y + def.dy, s = 1.0
        }
    end
    return out
end

local function kb_reindex_runtime()
    KB.state, KB.anim, KB.hover = {}, {}, {}
    for _, k in ipairs(KB.keys) do
        KB.state[k.id] = false
        KB.anim[k.id] = 0.0
        KB.hover[k.id] = 0.0
    end
end

local function kb_save_layout()
    local parts = {}
    for _, k in ipairs(KB.keys) do
        parts[#parts + 1] = string.format("%s:%s:%d:%d:%d:%.2f",
            k.id, k.kind, k.vk or 0, math.floor(k.x), math.floor(k.y), k.s)
    end
    -- пустой список — это осознанный выбор пользователя (удалил все клавиши),
    -- а не "настройка ещё ни разу не сохранялась". Различаем эти случаи через
    -- метку EMPTY, иначе при следующей загрузке пустой список подменится
    -- дефолтной раскладкой (баг: удалённые клавиши возвращались после Ctrl+R).
    session_cfg.settings.keyboard_layout = (#parts > 0) and table.concat(parts, ";") or "EMPTY"
    inicfg.save(session_cfg, CONFIG_FILE)
end

local function kb_load_layout()
    local raw = tostring(session_cfg.settings.keyboard_layout or "")
    if raw == "EMPTY" then
        KB.keys = {}
        kb_reindex_runtime()
        return
    end
    local keys = {}
    for id, kind, vk, sx, sy, ss in raw:gmatch("([%w_]+):([bc]):(%d+):(%-?%d+):(%-?%d+):([%d%.]+)") do
        vk = tonumber(vk) or 0
        local s = math.max(KB_SCALE_MIN, math.min(tonumber(ss) or 1.0, KB_SCALE_MAX))
        local x, y = tonumber(sx) or 0, tonumber(sy) or 0
        if kind == "b" then
            local def = KB_DEFAULT_BY_ID[id]
            if def then
                keys[#keys + 1] = { id = id, kind = "b", vk = def.vk, label = def.label,
                    glyph = def.glyph, bw = def.bw, x = x, y = y, s = s }
            end
        elseif vk > 0 then
            keys[#keys + 1] = { id = id, kind = "c", vk = vk, label = get_key_name(vk),
                glyph = nil, bw = KB_UNIT, x = x, y = y, s = s }
        end
    end
    -- raw == "" означает, что настройка ещё ни разу не сохранялась (первый запуск).
    -- Если распарсить не получилось (битые/старые данные), тоже откатываемся к дефолту.
    -- Намеренно пустой список ("удалил все клавиши") обрабатывается меткой EMPTY выше.
    KB.keys = (#keys > 0) and keys or kb_default_keys()
    kb_reindex_runtime()
end

KB.save_layout = kb_save_layout

-- добавить новую клавишу по её vk-коду (если уже есть — просто выделить её)
local function kb_add_key(vk)
    for _, k in ipairs(KB.keys) do
        if k.vk == vk then
            KB.selected_id = k.id
            return
        end
    end

    local sw, sh = getScreenResolution()
    local function id_taken(check_id)
        for _, k in ipairs(KB.keys) do
            if k.id == check_id then return true end
        end
        return false
    end
    local id, n = "K" .. tostring(vk), 0
    while id_taken(id) do
        n = n + 1
        id = "K" .. tostring(vk) .. "_" .. n
    end

    -- bw сразу = KB_UNIT: если оставить nil, первый кадр CalcTextSize вне окна
    -- может вернуть мусор и клавиша на долю секунды рисуется огромной
    local new_key = {
        id = id, kind = "c", vk = vk, label = get_key_name(vk), glyph = nil, bw = KB_UNIT,
        x = math.floor(sw * 0.5 - KB_UNIT * 0.5), y = math.floor(sh * 0.5 - KB_UNIT * 0.5), s = 1.0
    }
    table.insert(KB.keys, new_key)
    KB.state[id], KB.anim[id], KB.hover[id] = false, 0.0, 0.0
    KB.selected_id = id
    KB.edit = true
    kb_save_layout()
end

local function kb_remove_key(id)
    if not id then return end
    for i, k in ipairs(KB.keys) do
        if k.id == id then
            table.remove(KB.keys, i)
            break
        end
    end
    KB.state[id], KB.anim[id], KB.hover[id] = nil, nil, nil
    if KB.selected_id == id then KB.selected_id = nil end
    if KB.drag_id == id then KB.drag_id = nil end
    kb_save_layout()
end

KB.add_key = kb_add_key
KB.remove_key = kb_remove_key

kb_load_layout()

-- опрос клавиш (вызывается из main, а не из потока отрисовки)
local function kb_poll()
    local blocked_input = sampIsChatInputActive() or sampIsDialogActive()
        or menu.show or auth.show or update_ui.show or KB.edit or KB.awaiting_new_key

    local now = os.clock()
    for _, k in ipairs(KB.keys) do
        if k.id == "WUP" then
            KB.state.WUP = (now - KB.wheel_up) < 0.13
        elseif k.id == "WDN" then
            KB.state.WDN = (now - KB.wheel_down) < 0.13
        elseif k.vk then
            KB.state[k.id] = (not blocked_input) and isKeyDown(k.vk) or false
        end
    end
end

local keyboard_frame
keyboard_frame = imgui.OnFrame(
    function()
        local on = session_cfg.settings.keyboard_enabled and true or false
        KB.alpha = lerp(KB.alpha, on and 1.0 or 0.0, 0.10)
        if not on and KB.edit then KB.edit = false end

        -- в режиме правки нужен курсор и блокировка управления игроком
        keyboard_frame.HideCursor = not KB.edit
        keyboard_frame.LockPlayer = KB.edit

        return KB.alpha > 0.01 and not isGamePaused()
    end,
    function()
        local t = get_theme()
        local a = KB.alpha
        local sw, sh = getScreenResolution()

        KB.edit_alpha = lerp(KB.edit_alpha, KB.edit and 1.0 or 0.0, 0.14)
        KB.block_anim = lerp(KB.block_anim, session_cfg.settings.keyboard_block_c and 1.0 or 0.0, 0.14)
        KB.glow = lerp(KB.glow, session_cfg.settings.window_glow_enabled and 1.0 or 0.0, 0.08)

        for _, k in ipairs(KB.keys) do
            local target = KB.state[k.id] and 1.0 or 0.0
            -- нажатие мгновеннее, отпускание плавнее
            KB.anim[k.id] = lerp(KB.anim[k.id] or 0.0, target, target > 0.5 and 0.45 or 0.16)
        end

        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, a)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0.0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0.0)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))

        local base_flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar
            + imgui.WindowFlags.NoFocusOnAppearing + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoBringToFrontOnFocus + imgui.WindowFlags.NoBackground

        local flags = base_flags
        if not KB.edit then
            flags = flags + imgui.WindowFlags.NoInputs
        end

        local mp = imgui.GetMousePos()
        local wheel = KB.edit and imgui.GetIO().MouseWheel or 0.0
        local layout_changed = false
        local pending_delete = nil
        local pulse = 0.5 + 0.5 * (math.sin(os.clock() * 3.4) * 0.5 + 0.5)

        for _, k in ipairs(KB.keys) do
            -- ширина: пока не посчитали внутри окна — KB_UNIT (без вспышки огромной клавиши)
            if not k.bw or k.bw <= 0 then
                k.bw = KB_UNIT
            end

            local kw = k.bw * k.s
            local kh = KB_UNIT * k.s

            k.x = math.max(0, math.min(k.x, sw - kw))
            k.y = math.max(0, math.min(k.y, sh - kh))

            imgui.SetNextWindowPos(imgui.ImVec2(k.x, k.y), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(kw, kh), imgui.Cond.Always)

            if imgui.Begin("##mhg_kb_" .. k.id, nil, flags) then
                -- авто-ширина по тексту только внутри окна и только один раз
                if k.kind == "c" and not k._auto_w then
                    imgui.SetWindowFontScale(1.0)
                    local lbl_sz = imgui.CalcTextSize(k.label or "?")
                    local want = math.max(KB_UNIT, math.min((lbl_sz and lbl_sz.x or 0) + 16, 140))
                    if math.abs(want - k.bw) > 0.5 then
                        k.bw = want
                        kw = k.bw * k.s
                        imgui.SetWindowSize(imgui.ImVec2(kw, kh))
                    end
                    k._auto_w = true
                end

                local dl = imgui.GetWindowDrawList()
                local wpos = imgui.GetWindowPos()

                local p = KB.anim[k.id] or 0.0
                local is_hovered = KB.edit and imgui.IsWindowHovered()
                KB.hover[k.id] = lerp(KB.hover[k.id] or 0.0,
                    (is_hovered or KB.drag_id == k.id) and 1.0 or 0.0, 0.16)
                local hv = KB.hover[k.id]
                local is_selected = KB.edit and KB.selected_id == k.id

                local press = p * 1.5 * k.s
                local pmin = imgui.ImVec2(wpos.x + press * 0.5, wpos.y + press)
                local pmax = imgui.ImVec2(wpos.x + kw - press * 0.5, wpos.y + kh - press * 0.5)
                local rounding = 6.0 * k.s

                -- свечение вокруг клавиши (настройка "Свечение окна")
                if KB.glow > 0.001 then
                    local ga = (0.26 + pulse * 0.34) * a * KB.glow
                    for i = 3, 1, -1 do
                        local off = i * 2.0
                        dl:AddRect(imgui.ImVec2(pmin.x - off, pmin.y - off),
                                   imgui.ImVec2(pmax.x + off, pmax.y + off),
                            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
                                t.accent[1], t.accent[2], t.accent[3], ga / (i * 1.2))),
                            rounding + off, 15, 1.8)
                    end
                end

                -- свечение нажатия
                if p > 0.02 then
                    for i = 2, 1, -1 do
                        local off = i * 2.0
                        dl:AddRect(imgui.ImVec2(pmin.x - off, pmin.y - off),
                                   imgui.ImVec2(pmax.x + off, pmax.y + off),
                            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
                                t.accent[1], t.accent[2], t.accent[3], (0.22 * p / i) * a)),
                            rounding + off, 15, 1.2)
                    end
                end

                local mix_bg = math.max(p, hv * 0.55)
                local mix_br = math.max(p, hv)

                local bg_r = lerp(t.bg_idle[1], t.bg_act[1], mix_bg)
                local bg_g = lerp(t.bg_idle[2], t.bg_act[2], mix_bg)
                local bg_b = lerp(t.bg_idle[3], t.bg_act[3], mix_bg)
                local bg_a = lerp(0.55, 0.92, mix_bg)

                local br_r = lerp(t.bor_idle[1], t.bor_act[1], mix_br)
                local br_g = lerp(t.bor_idle[2], t.bor_act[2], mix_br)
                local br_b = lerp(t.bor_idle[3], t.bor_act[3], mix_br)
                local br_a = lerp(0.50, 1.00, mix_br)

                dl:AddRectFilled(pmin, pmax, imgui.ColorConvertFloat4ToU32(
                    imgui.ImVec4(bg_r, bg_g, bg_b, bg_a * a)), rounding)
                dl:AddRect(pmin, pmax, imgui.ColorConvertFloat4ToU32(
                    imgui.ImVec4(br_r, br_g, br_b, br_a * a)), rounding, 15, 1.25 * k.s)

                -- акцентная рамка в режиме правки
                if KB.edit_alpha > 0.01 then
                    local ea = (0.22 + 0.28 * pulse + 0.45 * hv) * KB.edit_alpha * a
                    dl:AddRect(imgui.ImVec2(pmin.x - 2, pmin.y - 2), imgui.ImVec2(pmax.x + 2, pmax.y + 2),
                        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
                            t.accent[1], t.accent[2], t.accent[3], ea)), rounding + 2, 15, 1.5)
                end
                -- белая рамка выбранной клавиши (для ползунка размера/удаления в меню)
                if is_selected then
                    dl:AddRect(imgui.ImVec2(pmin.x - 3, pmin.y - 3), imgui.ImVec2(pmax.x + 3, pmax.y + 3),
                        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, (0.55 + 0.25 * pulse) * a)),
                        rounding + 3, 15, 1.4)
                end

                local cx = (pmin.x + pmax.x) * 0.5
                local cy = (pmin.y + pmax.y) * 0.5
                local txt_a = lerp(0.72, 1.00, math.max(p, hv * 0.5)) * a

                local is_blocked_c = (k.id == "C" and KB.block_anim > 0.01)
                if is_blocked_c then
                    txt_a = txt_a * lerp(1.0, 0.45, KB.block_anim)
                end

                if k.glyph then
                    -- треугольник колеса мыши масштабируется вместе с клавишей
                    local s = 6.5 * k.s
                    local col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, txt_a))
                    if k.glyph == "up" then
                        dl:AddTriangleFilled(imgui.ImVec2(cx, cy - s), imgui.ImVec2(cx - s, cy + s * 0.75),
                                             imgui.ImVec2(cx + s, cy + s * 0.75), col)
                    else
                        dl:AddTriangleFilled(imgui.ImVec2(cx, cy + s), imgui.ImVec2(cx - s, cy - s * 0.75),
                                             imgui.ImVec2(cx + s, cy - s * 0.75), col)
                    end
                elseif k.label then
                    -- текст через imgui, чтобы он масштабировался вместе с клавишей
                    imgui.SetWindowFontScale(k.s)
                    local tsz = imgui.CalcTextSize(k.label)
                    imgui.SetCursorPos(imgui.ImVec2((kw - tsz.x) * 0.5 + press * 0.5,
                                                    (kh - tsz.y) * 0.5 + press * 0.5))
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text.x, t.text.y, t.text.z, txt_a))
                    imgui.TextUnformatted(k.label)
                    imgui.PopStyleColor(1)
                    imgui.SetWindowFontScale(1.0)
                end

                -- перечёркивание заблокированной C: цвет окна, но темнее
                if is_blocked_c then
                    local ba = KB.block_anim * a
                    local dark = 0.45
                    local cr, cg, cb = t.accent[1] * dark, t.accent[2] * dark, t.accent[3] * dark
                    local cross = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(cr, cg, cb, 0.95 * ba))
                    local inset = 6.0 * k.s
                    local hx = (pmax.x - pmin.x - inset * 2) * 0.5 * KB.block_anim
                    local hy = (pmax.y - pmin.y - inset * 2) * 0.5 * KB.block_anim
                    dl:AddLine(imgui.ImVec2(cx - hx, cy - hy), imgui.ImVec2(cx + hx, cy + hy), cross, 2.2 * k.s)
                    dl:AddLine(imgui.ImVec2(cx + hx, cy - hy), imgui.ImVec2(cx - hx, cy + hy), cross, 2.2 * k.s)
                    dl:AddRect(pmin, pmax, imgui.ColorConvertFloat4ToU32(
                        imgui.ImVec4(cr, cg, cb, 0.70 * ba)), rounding, 15, 1.4 * k.s)
                end

                -- правка: кнопка удаления (✕), перетаскивание и масштаб колесом
                local del_clicked = false
                if KB.edit and (is_hovered or is_selected) then
                    local del_r = 8.0 * k.s
                    local del_cx = pmax.x - del_r - 2
                    local del_cy = pmin.y + del_r + 2
                    local ddx, ddy = mp.x - del_cx, mp.y - del_cy
                    local del_hover = (ddx * ddx + ddy * ddy) <= (del_r + 3) * (del_r + 3)

                    dl:AddCircleFilled(imgui.ImVec2(del_cx, del_cy), del_r,
                        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.85, 0.25, 0.25, (del_hover and 0.95 or 0.62) * a)))
                    local cs = del_r * 0.5
                    local cross_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, a))
                    dl:AddLine(imgui.ImVec2(del_cx - cs, del_cy - cs), imgui.ImVec2(del_cx + cs, del_cy + cs), cross_col, 1.6)
                    dl:AddLine(imgui.ImVec2(del_cx - cs, del_cy + cs), imgui.ImVec2(del_cx + cs, del_cy - cs), cross_col, 1.6)

                    if del_hover and imgui.IsMouseClicked(0) then
                        pending_delete = k.id
                        del_clicked = true
                    end
                end

                if KB.edit and not del_clicked then
                    if is_hovered and imgui.IsMouseClicked(0) then
                        KB.selected_id = k.id
                    end

                    if is_hovered and wheel ~= 0.0 then
                        local ccx = k.x + kw * 0.5
                        local ccy = k.y + kh * 0.5
                        k.s = math.max(KB_SCALE_MIN, math.min(k.s + wheel * 0.08, KB_SCALE_MAX))
                        -- масштабируем относительно центра клавиши
                        k.x = ccx - (k.bw * k.s) * 0.5
                        k.y = ccy - (KB_UNIT * k.s) * 0.5
                        layout_changed = true
                        KB.selected_id = k.id
                    end

                    if KB.drag_id == nil then
                        if is_hovered and imgui.IsMouseClicked(0) then
                            KB.drag_id = k.id
                            KB.drag_dx = mp.x - wpos.x
                            KB.drag_dy = mp.y - wpos.y
                        end
                    elseif KB.drag_id == k.id then
                        if imgui.IsMouseDown(0) then
                            k.x = math.max(0, math.min(mp.x - KB.drag_dx, sw - kw))
                            k.y = math.max(0, math.min(mp.y - KB.drag_dy, sh - kh))
                        else
                            KB.drag_id = nil
                            layout_changed = true
                        end
                    end
                end

                imgui.End()
            end
        end

        if pending_delete then
            kb_remove_key(pending_delete)
        end

        -- подсказка в режиме правки (без подложки, только текст)
        if KB.edit_alpha > 0.01 then
            local wait_hint = KB.awaiting_new_key and true or false
            local base_hint = u8"Нажмите клавишу, чтобы добавить"
            local suffix_hint = u8"  ESC — отмена"
            local hint = wait_hint
                and (base_hint .. "..." .. suffix_hint)
                or u8"ЛКМ — выбрать/перетащить, колесо — размер, ✕ или Delete — удалить. ESC — выйти."
            local hsz = imgui.CalcTextSize(hint)
            local hw, hh = hsz.x + 6, hsz.y + 6
            imgui.SetNextWindowPos(imgui.ImVec2(sw * 0.5 - hw * 0.5, 40), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(hw, hh), imgui.Cond.Always)
            if imgui.Begin("##mhg_kb_hint", nil, base_flags + imgui.WindowFlags.NoInputs) then
                local dl = imgui.GetWindowDrawList()
                local wpos = imgui.GetWindowPos()
                local ha = KB.edit_alpha * a
                local shadow = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0, 0, 0, 0.75 * ha))
                for ox = -1, 1 do
                    for oy = -1, 1 do
                        if ox ~= 0 or oy ~= 0 then
                            dl:AddText(imgui.ImVec2(wpos.x + 3 + ox, wpos.y + 3 + oy), shadow, hint)
                        end
                    end
                end
                if wait_hint then
                    local phase = math.floor(os.clock() * 4.0) % 3
                    local x = wpos.x + 3
                    local y = wpos.y + 3
                    local pulse = 0.40 + 0.60 * (0.5 + 0.5 * math.sin(os.clock() * 5.0))
                    dl:AddText(imgui.ImVec2(x, y),
                        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, ha * pulse)), base_hint)
                    x = x + imgui.CalcTextSize(base_hint).x
                    for i = 0, 2 do
                        local bright = (i == phase) and 1.0 or 0.28
                        dl:AddText(imgui.ImVec2(x, y),
                            imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, ha * bright)), ".")
                        x = x + imgui.CalcTextSize(".").x
                    end
                    dl:AddText(imgui.ImVec2(x, y),
                        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, ha * pulse)), suffix_hint)
                else
                    dl:AddText(imgui.ImVec2(wpos.x + 3, wpos.y + 3),
                        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, ha)), hint)
                end
                imgui.End()
            end
        end

        imgui.PopStyleColor(1)
        imgui.PopStyleVar(4)

        if layout_changed then kb_save_layout() end
    end
)
keyboard_frame.HideCursor = true

-- блокировка C + отслеживание колеса мыши
function onWindowMessage(msg, wparam, lparam)
    -- WM_MOUSEWHEEL
    if msg == 0x020A and session_cfg.settings.keyboard_enabled then
        local wp = wparam
        if wp < 0 then wp = wp + 4294967296 end
        local delta = math.floor(wp / 65536) % 65536
        if delta > 32767 then delta = delta - 65536 end
        if delta > 0 then
            KB.wheel_up = os.clock()
        elseif delta < 0 then
            KB.wheel_down = os.clock()
        end
        return
    end

    -- блокировка клавиши C в игре (в чате/диалогах C работает как обычно)
    if session_cfg.settings.keyboard_enabled and session_cfg.settings.keyboard_block_c
        and wparam == vkeys.VK_C then
        if msg == 0x100 or msg == 0x101 or msg == 0x104 or msg == 0x105 then
            if not sampIsChatInputActive() and not sampIsDialogActive()
                and not menu.show and not auth.show and not update_ui.show then
                consumeWindowMessage(true, false)
            end
        end
    end
end

init_particles()

local frame = imgui.OnFrame(
    function() return auth.show or menu.show or update_ui.show or auth.alpha > 0.01 or menu.alpha > 0.01 or update_ui.alpha > 0.01 end,
    function() auth.draw(); menu.draw(); update_ui.draw() end
)
frame.LockPlayer = true
frame.HideCursor = false


local function parse_version(s)
    s = tostring(s or "")
    s = s:gsub("\r", ""):gsub("\n", "")
    s = s:match("^%s*(.-)%s*$") or s
    local a, b, c = s:match("^(%d+)%.(%d+)%.(%d+)$")
    if not a then
        a, b = s:match("^(%d+)%.(%d+)$")
        c = 0
    end
    if not a then return 0 end
    return tonumber(a) * 10000 + tonumber(b or 0) * 100 + tonumber(c or 0)
end

local function copy_file_bin(src, dst)
    local ok, err = pcall(function()
        local i = io.open(src, "rb")
        if not i then error("open src") end
        local content = i:read("*a")
        i:close()
        if not content or #content < 100 then error("empty") end
        local o = io.open(dst, "wb")
        if not o then error("open dst") end
        o:write(content)
        o:close()
    end)
    return ok
end

local function schedule_reload()
    -- reload outside of imgui frame to avoid crash
    pcall(function()
        lua_thread.create(function()
            wait(200)
            local ok, err = pcall(function() thisScript():reload() end)
            if ok then
                print("[MHG update] thisScript():reload() called successfully")
            else
                print(("[MHG update] thisScript():reload() FAILED: %s"):format(tostring(err)))
                pcall(function()
                    sampAddChatMessage(
                        u8"[MHG] Файл обновлён, но авто-перезагрузка не удалась. Перезайдите в игру, чтобы применить обновление.",
                        -1
                    )
                end)
            end
        end)
    end)
end

local function check_update()
    -- single source of truth: read SCRIPT_VERSION straight out of the script
    -- that will actually be installed, instead of a separate version.txt that
    -- can drift out of sync with it.
    local tmp = mhg_dir .. "\\version_check.lua"
    print(("[MHG update] check_update() start, local=%s, url=%s"):format(SCRIPT_VERSION, SCRIPT_URL))

    local function handle_content(remote)
        print(("[MHG update] downloaded %d bytes"):format(remote and #remote or -1))

        if not remote or #remote < 200 then
            print("[MHG update] content too small/empty, aborting")
            pcall(os.remove, tmp)
            return
        end

        local ver = remote:match('SCRIPT_VERSION%s*=%s*"([%d%.]+)"')
        if not ver then
            print("[MHG update] could not find SCRIPT_VERSION pattern in downloaded file")
            pcall(os.remove, tmp)
            return
        end
        print(("[MHG update] remote version parsed: %s (local: %s)"):format(ver, SCRIPT_VERSION))
        if parse_version(ver) <= parse_version(SCRIPT_VERSION) then
            print("[MHG update] remote is not newer, no update needed")
            pcall(os.remove, tmp)
            return
        end

        print("[MHG update] update available, showing update window")

        -- keep the bytes we already downloaded so start_script_update()
        -- doesn't have to fetch the same file a second time
        update_ui.cached_script_data = remote
        update_ui.cached_tmp_path = tmp

        update_ui.remote_ver = ver
        update_ui.available = true
        update_ui.stage = "idle"
        update_ui.stage_alpha = 0.0
        update_ui.timer = 0.0
        update_ui.show = true
        auth.show = false
        menu.show = false
    end

    -- the full script is much bigger than the old version.txt, so the download
    -- can legitimately finish under several different status codes; mirror the
    -- same retry approach used by start_script_update() instead of only
    -- trusting status == 6
    local ok_call, err_call = pcall(function()
        downloadUrlToFile(SCRIPT_URL .. "?t=" .. os.time(), tmp, function(id, status)
            print(("[MHG update] downloadUrlToFile callback fired, status=%s"):format(tostring(status)))

            local function try_read()
                local f = io.open(tmp, "rb")
                if not f then
                    print("[MHG update] try_read: could not open temp file")
                    return false
                end
                local content = f:read("*a")
                f:close()
                if content and #content > 200 then
                    handle_content(content)
                    return true
                end
                print(("[MHG update] try_read: file too small (%d bytes)"):format(content and #content or -1))
                return false
            end

            if try_read() then return end

            if status == 6 or status == 5 or status == 2 then
                pcall(function()
                    lua_thread.create(function()
                        wait(400)
                        try_read()
                    end)
                end)
                return
            end

            if status == 3 or status == 4 then
                try_read()
            end
        end)
    end)
    if not ok_call then
        print(("[MHG update] downloadUrlToFile threw an error: %s"):format(tostring(err_call)))
    end
end

local function start_script_update()
    if update_ui.stage == "loading" or update_ui.stage == "success" then return end
    update_ui.stage = "loading"
    update_ui.stage_alpha = 0.0
    update_ui.timer = os.clock()
    update_ui.pending = nil
    update_ui.load_progress = 0.0
    update_ui.script_data = nil
    update_ui.tmp_path = nil

    -- reuse the copy already downloaded while checking for updates, if we still have it
    if update_ui.cached_script_data and #update_ui.cached_script_data > 200 then
        update_ui.script_data = update_ui.cached_script_data
        update_ui.tmp_path = update_ui.cached_tmp_path
        update_ui.pending = "success"
        update_ui.cached_script_data = nil
        update_ui.cached_tmp_path = nil
        return
    end

    local tmp = mhg_dir .. "\\mhg_update_tmp.lua"
    -- download to temp only; keep bytes in memory so we can write after the 5s delay
    downloadUrlToFile(SCRIPT_URL .. "?t=" .. tostring(os.time()), tmp, function(id, status)
        local function try_read()
            local f = io.open(tmp, "rb")
            if not f then return false end
            local content = f:read("*a")
            f:close()
            if content and #content > 200 then
                update_ui.script_data = content
                update_ui.tmp_path = tmp
                update_ui.pending = "success"
                return true
            end
            return false
        end

        -- try read on any completion-like status; also retry shortly after
        if try_read() then return end

        if status == 6 or status == 5 or status == 2 then
            pcall(function()
                lua_thread.create(function()
                    wait(400)
                    if update_ui.stage == "loading" and update_ui.pending == nil then
                        if not try_read() then
                            update_ui.pending = "fail"
                            pcall(os.remove, tmp)
                        end
                    end
                end)
            end)
            return
        end

        if status == 3 or status == 4 then
            -- last chance: file may still exist
            if not try_read() then
                update_ui.pending = "fail"
                pcall(os.remove, tmp)
            end
        end
    end)
end

function update_ui.draw()
    update_ui.alpha = lerp(update_ui.alpha, update_ui.show and 1.0 or 0.0, update_ui.show and 0.12 or 0.06)
    if update_ui.alpha < 0.01 then return end

    local t = get_theme()

    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, update_ui.alpha)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8)
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 0)

    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.07, 0.08, 0.11, 0.98))
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w))

    apply_window_position(340, 230)

    if imgui.Begin("##update_ui", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar) then
        local draw_list = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()

        draw_window_glow(pos, size, update_ui.alpha)
        draw_particle_grid(draw_list, pos, size, update_ui.alpha, "update")

        if update_ui.stage == "idle" or update_ui.stage == "fail" then
            draw_close_button(340, update_ui.alpha)
        end

        local now = os.clock()
        update_ui.stage_alpha = lerp(update_ui.stage_alpha, 1.0, 0.12)
        local sa = update_ui.alpha * update_ui.stage_alpha

        if update_ui.stage == "loading" then
            local elapsed = now - update_ui.timer
            local load_dur = 5.0
            update_ui.load_progress = math.max(0.0, math.min(1.0, elapsed / load_dur))
            -- if download never answered after 5s + grace, fail
            if update_ui.pending == nil and elapsed >= (load_dur + 8.0) then
                update_ui.pending = "fail"
            end
            -- wait full 5s animation; only then apply file + change stage
            if update_ui.pending ~= nil and elapsed >= load_dur then
                local result = update_ui.pending
                update_ui.pending = nil
                if result == "success" and update_ui.script_data and #update_ui.script_data > 200 then
                    local path = thisScript().path
                    local wrote = false
                    local ok = pcall(function()
                        local o = io.open(path, "wb")
                        if not o then error("open") end
                        o:write(update_ui.script_data)
                        o:close()
                        wrote = true
                    end)
                    if not wrote then
                        -- fallback via temp copy
                        if update_ui.tmp_path then
                            wrote = copy_file_bin(update_ui.tmp_path, path)
                        end
                    end
                    if update_ui.tmp_path then
                        pcall(os.remove, update_ui.tmp_path)
                        update_ui.tmp_path = nil
                    end
                    update_ui.script_data = nil
                    update_ui.stage = wrote and "success" or "fail"
                else
                    update_ui.stage = "fail"
                    if update_ui.tmp_path then
                        pcall(os.remove, update_ui.tmp_path)
                        update_ui.tmp_path = nil
                    end
                    update_ui.script_data = nil
                end
                update_ui.stage_alpha = 0.0
                update_ui.timer = now
            end
        elseif update_ui.stage == "success" then
            local elapsed = now - update_ui.timer
            if elapsed >= 3.0 and update_ui.show then
                update_ui.show = false
            end
            if (not update_ui.show) and update_ui.alpha < 0.03 then
                update_ui.stage = "idle"
                schedule_reload()
            end
        elseif update_ui.stage == "fail" then
            local elapsed = now - update_ui.timer
            if elapsed >= 3.0 then
                update_ui.stage = "idle"
                update_ui.stage_alpha = 0.0
            end
        end

        if update_ui.stage == "idle" then
            imgui.Dummy(imgui.ImVec2(0, 18))
            imgui.SetWindowFontScale(1.25)
            local title = u8"Обновление"
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(title).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * sa), title)
            imgui.SetWindowFontScale(1.0)

            imgui.Dummy(imgui.ImVec2(0, 14))
            local info = string.format("v%s -> v%s", SCRIPT_VERSION, update_ui.remote_ver)
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(info).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, t.text_muted.w * sa), info)

            imgui.Dummy(imgui.ImVec2(0, 8))
            local hint = u8"Доступна новая версия скрипта"
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(hint).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, t.text_muted.w * sa), hint)

            imgui.Dummy(imgui.ImVec2(0, 22))
            local base_size = imgui.ImVec2(240, 40)
            imgui.SetCursorPosX((340 - base_size.x) / 2)
            local p = imgui.GetCursorScreenPos()

            if imgui.InvisibleButton("##update_btn", base_size) then
                start_script_update()
            end

            local hovered = imgui.IsItemHovered()
            local active = imgui.IsItemActive()
            update_ui.btn_alpha = lerp(update_ui.btn_alpha, (hovered or active) and 1.0 or 0.55, 0.14)

            local p_min = p
            local p_max = imgui.ImVec2(p.x + base_size.x, p.y + base_size.y)
            local bg_r = lerp(t.bg_idle[1], t.bg_act[1], update_ui.btn_alpha)
            local bg_g = lerp(t.bg_idle[2], t.bg_act[2], update_ui.btn_alpha)
            local bg_b = lerp(t.bg_idle[3], t.bg_act[3], update_ui.btn_alpha)
            local bg_a = lerp(0.25, 0.70, update_ui.btn_alpha)
            local bor_r = lerp(t.bor_idle[1], t.bor_act[1], update_ui.btn_alpha)
            local bor_g = lerp(t.bor_idle[2], t.bor_act[2], update_ui.btn_alpha)
            local bor_b = lerp(t.bor_idle[3], t.bor_act[3], update_ui.btn_alpha)

            draw_list:AddRectFilled(p_min, p_max, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bg_r, bg_g, bg_b, bg_a * sa)), 10.0)
            draw_list:AddRect(p_min, p_max, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bor_r, bor_g, bor_b, lerp(0.3, 1.0, update_ui.btn_alpha) * sa)), 10.0, 15, 1.2)

            local btn_text = u8"Обновить"
            local tsz = imgui.CalcTextSize(btn_text)
            draw_list:AddText(
                imgui.ImVec2(p_min.x + (base_size.x - tsz.x) / 2, p_min.y + (base_size.y - tsz.y) / 2),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, lerp(0.5, 1.0, update_ui.btn_alpha) * sa)),
                btn_text
            )

        elseif update_ui.stage == "loading" then
            -- fixed positions inside 340x230 window (no overlap)
            local cx = pos.x + 170

            -- spinner
            local spinner_center = imgui.ImVec2(cx, pos.y + 58)
            local spinner_color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], sa))
            draw_spinner(draw_list, spinner_center, 15.0, 2.6, spinner_color)

            -- progress bar
            local bar_w, bar_h = 210.0, 7.0
            local bx = pos.x + (340 - bar_w) * 0.5
            local by = pos.y + 95
            local bg_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bg_idle[1], t.bg_idle[2], t.bg_idle[3], 0.65 * sa))
            local fill_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 0.92 * sa))
            local bor_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bor_hover[1], t.bor_hover[2], t.bor_hover[3], 0.50 * sa))
            draw_list:AddRectFilled(imgui.ImVec2(bx, by), imgui.ImVec2(bx + bar_w, by + bar_h), bg_col, 4.0)
            local prog = math.max(0.0, math.min(1.0, update_ui.load_progress or 0))
            local fw = bar_w * math.max(0.025, prog)
            draw_list:AddRectFilled(imgui.ImVec2(bx, by), imgui.ImVec2(bx + fw, by + bar_h), fill_col, 4.0)
            draw_list:AddRect(imgui.ImVec2(bx, by), imgui.ImVec2(bx + bar_w, by + bar_h), bor_col, 4.0, 15, 1.0)

            -- percent under bar
            local pct = string.format("%d%%", math.floor(prog * 100 + 0.5))
            local pct_sz = imgui.CalcTextSize(pct)
            local pct_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, t.text_muted.w * sa))
            draw_list:AddText(imgui.ImVec2(cx - pct_sz.x * 0.5, pos.y + 112), pct_col, pct)

            -- status text under percent
            local txt = u8"Загрузка обновления..."
            local txt_sz = imgui.CalcTextSize(txt)
            local txt_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * sa))
            draw_list:AddText(imgui.ImVec2(cx - txt_sz.x * 0.5, pos.y + 140), txt_col, txt)

        elseif update_ui.stage == "success" then
            local circle_radius = 18.0
            local circle_center = imgui.ImVec2(pos.x + 170, pos.y + 90)
            local fill = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bg_act[1], t.bg_act[2], t.bg_act[3], 0.70 * sa))
            local border = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], sa))
            draw_list:AddCircleFilled(circle_center, circle_radius, fill)
            draw_list:AddCircle(circle_center, circle_radius, border, 20, 1.5)
            local white_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, sa))
            draw_list:AddLine(imgui.ImVec2(circle_center.x - 6, circle_center.y - 1), imgui.ImVec2(circle_center.x - 1.5, circle_center.y + 4.5), white_col, 2.5)
            draw_list:AddLine(imgui.ImVec2(circle_center.x - 1.5, circle_center.y + 4.5), imgui.ImVec2(circle_center.x + 6.5, circle_center.y - 4.5), white_col, 2.5)

            imgui.SetWindowFontScale(1.1)
            local txt = u8"Успешно! Перезагрузка..."
            local txt_sz = imgui.CalcTextSize(txt)
            local txt_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * sa))
            local txt_pos = imgui.ImVec2(circle_center.x - txt_sz.x * 0.5, circle_center.y + circle_radius + 22.0)
            draw_list:AddText(txt_pos, txt_col, txt)
            imgui.SetWindowFontScale(1.0)

        elseif update_ui.stage == "fail" then
            imgui.Dummy(imgui.ImVec2(0, 40))
            imgui.SetWindowFontScale(1.25)
            local title = u8"Ошибка"
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(title).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * sa), title)
            imgui.SetWindowFontScale(1.0)

            imgui.Dummy(imgui.ImVec2(0, 14))
            local txt = u8"Не удалось загрузить обновление"
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(txt).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, t.text_muted.w * sa), txt)

            imgui.Dummy(imgui.ImVec2(0, 8))
            local sub = u8"Попробуйте ещё раз"
            imgui.SetCursorPosX((340 - imgui.CalcTextSize(sub).x) / 2)
            imgui.TextColored(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, t.text_muted.w * sa), sub)
        end

        imgui.End()
    end
    imgui.PopStyleColor(2)
    imgui.PopStyleVar(5)
end

function main()
    while not isSampAvailable() do wait(100) end
    while not sampGetPlayerIdByCharHandle(PLAYER_PED) do wait(100) end

    -- сначала запоминаем родной аспект клиента, потом NOP'ы и любой apply_asp
    capture_asp_original()

    memory.fill(0x6FF452, 0x90, 6, true)
    memory.fill(0x524B7F, 0x90, 2, true)

    session_cfg = inicfg.load({
        session = {
            is_logged = false,
            saved_nick = "",
            saved_password = ""
        },
        settings = {
            particles_enabled = true,
            particles_style = 1,
            particles_density = 1.0,
            particles_speed = 1.0,
            particles_dir_enabled = false,
            particles_dir_x = 0.0,
            particles_dir_y = 0.0,
            tab_effects_enabled = true,
            window_glow_enabled = true,
            window_glow_style = 1,
            window_glow_speed = 1.0,
            theme = 1,
            custom_avatar_url = "",
            asp_enabled = false,
            asp_value = 1.25,
            watermark_enabled = true,
            watermark_x = -1,
            watermark_y = -1,
            watermark_halign = 2,
            watermark_valign = 0,
            watermark_show_fps = true,
            watermark_show_ping = true,
            watermark_show_pl = true,
            open_key = vkeys.VK_F12,
            keyboard_enabled = false,
            keyboard_block_c = false,
            keyboard_layout = ""
        }
    }, CONFIG_FILE)

    asp_val_buf[0] = session_cfg.settings.asp_value or 1.25
    kb_load_layout()

    if doesFileExist(ACCOUNTS_FILE) then
        local file = io.open(ACCOUNTS_FILE, "r")
        if file then
            for line in file:lines() do
                line = line:gsub("[\r\n]", ""):match("^%s*(.-)%s*$")
                if line ~= "" and not line:find("^#") then
                    local nick, password = line:match("^(.-):(.+)$")
                    if nick and password then
                        table.insert(auth.accounts, {nick = nick, password = password})
                        auth.account_map[nick] = password
                    end
                end
            end
            file:close()
            if #auth.accounts > 0 then
                auth.loaded = true
            end
        end
    end

    load_accounts(function()
        validate_logged_session()
    end)

    check_update()
    local next_update_check = os.clock() + UPDATE_CHECK_INTERVAL
    local next_auth_check = os.clock() + AUTH_RECHECK_INTERVAL

    sampRegisterChatCommand('mhg', function()
        open_mhg()
    end)

    while true do
        wait(0)

        -- периодически перепроверяем обновление, а не только при старте/reload скрипта
        if (not update_ui.available) and os.clock() >= next_update_check then
            next_update_check = os.clock() + UPDATE_CHECK_INTERVAL
            check_update()
        end

        -- периодически тянем список аккаунтов: удалённый ник сразу выкидывает в авторизацию
        if os.clock() >= next_auth_check then
            next_auth_check = os.clock() + AUTH_RECHECK_INTERVAL
            load_accounts()
        end

        if auth.downloading and auth.download_start > 0 and (os.clock() - auth.download_start) > 12.0 then
            auth.downloading = false
            if #auth.accounts > 0 then
                auth.loaded = true
            end
            validate_logged_session()
        end

        if session_cfg.settings.asp_enabled then
            apply_asp(session_cfg.settings.asp_value or 1.25)
        end

        if session_cfg.settings.keyboard_enabled then
            kb_poll()
        end

        if menu.hotkey_listening then
            if isKeyJustPressed(vkeys.VK_ESCAPE) then
                menu.hotkey_listening = false
            else
                for vk_code = 1, 254 do
                    if vk_code ~= vkeys.VK_ESCAPE and isKeyJustPressed(vk_code) then
                        session_cfg.settings.open_key = vk_code
                        inicfg.save(session_cfg, CONFIG_FILE)
                        menu.hotkey_listening = false
                        break
                    end
                end
            end
        elseif KB.awaiting_new_key then
            -- ждём хоткей для добавления новой клавиши на оверлей
            if isKeyJustPressed(vkeys.VK_ESCAPE) then
                KB.awaiting_new_key = false
                consumeWindowMessage(true, false)
            else
                for vk_code = 1, 254 do
                    if vk_code ~= vkeys.VK_ESCAPE and isKeyJustPressed(vk_code) then
                        kb_add_key(vk_code)
                        KB.awaiting_new_key = false
                        break
                    end
                end
            end
        elseif isKeyJustPressed(session_cfg.settings.open_key or vkeys.VK_F12) and not sampIsChatInputActive() and not sampIsDialogActive() then
            open_mhg()
        end

        -- удаление выбранной клавиши по хоткею Delete (в режиме правки)
        if KB.edit and KB.selected_id and not KB.awaiting_new_key
            and not (auth.show or menu.show or update_ui.show)
            and isKeyJustPressed(vkeys.VK_DELETE) then
            kb_remove_key(KB.selected_id)
        end

        if menu.wm.edit and not (auth.show or menu.show or update_ui.show) and isKeyJustPressed(vkeys.VK_ESCAPE) then
            menu.wm.edit = false
            menu.wm.drag = false
            inicfg.save(session_cfg, CONFIG_FILE)
            consumeWindowMessage(true, false)
        end

        if KB.edit and not KB.awaiting_new_key and not (auth.show or menu.show or update_ui.show) and isKeyJustPressed(vkeys.VK_ESCAPE) then
            KB.edit = false
            KB.drag_id = nil
            KB.selected_id = nil
            kb_save_layout()
            consumeWindowMessage(true, false)
        end

        if (auth.show or menu.show or update_ui.show) and not KB.awaiting_new_key and isKeyJustPressed(vkeys.VK_ESCAPE) then
            if update_ui.show and (update_ui.stage == "loading" or update_ui.stage == "success") then
                -- cannot close during update
            else
                close_all()
                consumeWindowMessage(true, false)
            end
        end
    end
end
