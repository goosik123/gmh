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
local SCRIPT_VERSION = "1.0.3"
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
        tab_effects_enabled = true,
        window_glow_enabled = true,
        theme = 1,
        custom_avatar_url = "",
        asp_enabled = false, -- ASP
        asp_value = 1.25,
        watermark_enabled = true,
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
    }
}

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

local function get_theme()
    local target_idx = session_cfg.settings.theme or 1
    if target_idx ~= theme_cur_idx and themes[target_idx] then
        -- start a fresh transition from whatever is currently on screen,
        -- so switching themes again mid-transition doesn't cause a jump
        theme_from = theme_last_blended
        theme_to = themes[target_idx]
        theme_transition_start = os.clock()
        theme_cur_idx = target_idx
    end

    local elapsed = os.clock() - theme_transition_start
    local k = THEME_TRANSITION_DURATION > 0 and math.min(1.0, elapsed / THEME_TRANSITION_DURATION) or 1.0
    k = ease_out_cubic(k)

    local blended
    if k >= 1.0 then
        blended = theme_to
    else
        blended = {
            name = theme_to.name,
            text = lerp_vec4(theme_from.text, theme_to.text, k),
            text_muted = lerp_vec4(theme_from.text_muted, theme_to.text_muted, k),
            accent = lerp_color3(theme_from.accent, theme_to.accent, k),
            bg_idle = lerp_color3(theme_from.bg_idle, theme_to.bg_idle, k),
            bg_hover = lerp_color3(theme_from.bg_hover, theme_to.bg_hover, k),
            bg_act = lerp_color3(theme_from.bg_act, theme_to.bg_act, k),
            bor_idle = lerp_color3(theme_from.bor_idle, theme_to.bor_idle, k),
            bor_hover = lerp_color3(theme_from.bor_hover, theme_to.bor_hover, k),
            bor_act = lerp_color3(theme_from.bor_act, theme_to.bor_act, k)
        }
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
    hotkey_listening = false
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


local asp_original_a, asp_original_b
local asp_captured = false

local function capture_asp_original()
    if asp_captured then return end
    asp_captured = true
    pcall(function() asp_original_a = memory.getfloat(0xC3EFA4, true) end)
    pcall(function() asp_original_b = memory.getfloat(0xC17044, true) end)
end

local function apply_asp(value)
    if not value then value = 1.0 end
    capture_asp_original()
    -- основной адрес аспекта (после NOP патчей в main)
    memory.setfloat(0xC3EFA4, value, true)
    -- доп. адреса, которые некоторые клиенты/фиксы перезаписывают
    pcall(function()
        memory.setfloat(0xC17044, value, true)
    end)
end

local function disable_asp()
    capture_asp_original()
    -- возвращаем настоящее исходное значение, а не выдуманную "1.0" —
    -- иначе экран остаётся сжатым, если родной аспект игры не равен 1.0
    memory.setfloat(0xC3EFA4, asp_original_a or 1.0, true)
    pcall(function()
        memory.setfloat(0xC17044, asp_original_b or 1.0, true)
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

local particles = {}
local PARTICLE_COUNT = 35
local CONNECT_DIST = 75.0

local function init_particles()
    particles = {}
    for i = 1, PARTICLE_COUNT do
        table.insert(particles, {
            x = math.random(10, 710),
            y = math.random(10, 410),
            speedX = (math.random() - 0.5) * 0.4,
            speedY = (math.random() - 0.5) * 0.4,
            radius = 1.5
        })
    end
end

local function draw_particle_grid(draw_list, pos, size, global_alpha)
    local target_fade = session_cfg.settings.particles_enabled and 1.0 or 0.0
    particles_fade_alpha = lerp(particles_fade_alpha, target_fade, 0.05)
    
    if particles_fade_alpha < 0.001 then return end
    
    local combined_alpha = global_alpha * particles_fade_alpha
    local t = get_theme()

    for i, p in ipairs(particles) do
        p.x = p.x + p.speedX
        p.y = p.y + p.speedY

        if p.x < 0 then p.x = size.x end
        if p.x > size.x then p.x = 0 end
        if p.y < 0 then p.y = size.y end
        if p.y > size.y then p.y = 0 end

        local px = pos.x + p.x
        local py = pos.y + p.y

        for j = i + 1, #particles do
            local p2 = particles[j]
            local dx = p.x - p2.x
            local dy = p.y - p2.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < CONNECT_DIST then
                local alpha = (1.0 - (dist / CONNECT_DIST)) * 0.25 * combined_alpha
                local line_color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bor_hover[1], t.bor_hover[2], t.bor_hover[3], alpha))
                draw_list:AddLine(imgui.ImVec2(px, py), imgui.ImVec2(pos.x + p2.x, pos.y + p2.y), line_color, 1.0)
            end
        end

        local dot_color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 0.35 * combined_alpha))
        draw_list:AddCircleFilled(imgui.ImVec2(px, py), p.radius, dot_color)
    end
end

-- === WM (watermark) particles: отдельная, независимая от меню, система частиц ===
local wm_particles = {}
local WM_PARTICLE_COUNT = 10
local WM_CONNECT_DIST = 26.0
local wm_particles_fade_alpha = session_cfg.settings.particles_enabled and 1.0 or 0.0

local function init_wm_particles(w, h)
    wm_particles = {}
    for i = 1, WM_PARTICLE_COUNT do
        table.insert(wm_particles, {
            x = math.random(0, math.max(1, math.floor(w))),
            y = math.random(0, math.max(1, math.floor(h))),
            speedX = (math.random() - 0.5) * 0.25,
            speedY = (math.random() - 0.5) * 0.25,
            radius = 1.0
        })
    end
end

local function draw_wm_particles(draw_list, pos, size, global_alpha, t)
    local target_fade = session_cfg.settings.particles_enabled and 1.0 or 0.0
    wm_particles_fade_alpha = lerp(wm_particles_fade_alpha, target_fade, 0.06)

    if wm_particles_fade_alpha < 0.001 then return end
    if #wm_particles == 0 then init_wm_particles(size.x, size.y) end

    local combined_alpha = global_alpha * wm_particles_fade_alpha

    for i, p in ipairs(wm_particles) do
        p.x = p.x + p.speedX
        p.y = p.y + p.speedY

        if p.x < 0 then p.x = size.x end
        if p.x > size.x then p.x = 0 end
        if p.y < 0 then p.y = size.y end
        if p.y > size.y then p.y = 0 end

        local px = pos.x + p.x
        local py = pos.y + p.y

        for j = i + 1, #wm_particles do
            local p2 = wm_particles[j]
            local dx = p.x - p2.x
            local dy = p.y - p2.y
            local dist = math.sqrt(dx * dx + dy * dy)

            if dist < WM_CONNECT_DIST then
                local alpha = (1.0 - (dist / WM_CONNECT_DIST)) * 0.22 * combined_alpha
                local line_color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.bor_hover[1], t.bor_hover[2], t.bor_hover[3], alpha))
                draw_list:AddLine(imgui.ImVec2(px, py), imgui.ImVec2(pos.x + p2.x, pos.y + p2.y), line_color, 1.0)
            end
        end

        local dot_color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 0.30 * combined_alpha))
        draw_list:AddCircleFilled(imgui.ImVec2(px, py), p.radius, dot_color)
    end
end

local function draw_window_glow(pos, size, alpha)
    local target_glow = session_cfg.settings.window_glow_enabled and 1.0 or 0.0
    glow_anim_alpha = lerp(glow_anim_alpha, target_glow, 0.08)

    if glow_anim_alpha < 0.001 then return end

    local draw_list = imgui.GetBackgroundDrawList()
    local time = os.clock() * 3.0
    local pulse = math.sin(time) * 0.5 + 0.5
    local glow_alpha = (0.3 + pulse * 0.5) * alpha * glow_anim_alpha
    local t = get_theme()

    for i = 3, 1, -1 do
        local offset = i * 2.0
        local p_min = imgui.ImVec2(pos.x - offset, pos.y - offset)
        local p_max = imgui.ImVec2(pos.x + size.x + offset, pos.y + size.y + offset)
        local current_alpha = glow_alpha / (i * 1.2)
        local color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], current_alpha))
        
        draw_list:AddRect(p_min, p_max, color, 12.0 + offset, 15, 2.0)
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
    if auth.account_map and auth.account_map[nick] then
        return auth.account_map[nick] == password
    end
    for _, acc in ipairs(auth.accounts) do
        if acc.nick == nick and acc.password == password then return true end
    end
    return false
end

local function load_accounts(on_loaded)
    if auth.downloading then return end
    auth.downloading = true
    auth.loaded = false
    auth.accounts = {}
    auth.account_map = {}
    auth.download_start = os.clock()

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
                auth.loaded = (#auth.accounts > 0)
            end
            auth.downloading = false
            if on_loaded then on_loaded() end
        elseif status == 4 or status == 5 then
            auth.downloading = false
            if not auth.loaded and on_loaded then on_loaded() end
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
        draw_particle_grid(draw_list, pos, size, auth.alpha)

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

function menu.draw()
    if is_update_locked() then
        menu.show = false
    end
    menu.alpha = lerp(menu.alpha, menu.show and 1.0 or 0.0, 0.12)
    if menu.alpha < 0.01 then return end
    
    local t = get_theme()

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

    local dynamic_win_width = math.max(860, math.max(content_elements_width_top, total_bottom_width) + base_margins)

    apply_window_position(dynamic_win_width, 480)

    if imgui.Begin('##menu', nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar) then
        local draw_list = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        local mouse_pos = imgui.GetMousePos()
        
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
                    menu.current_tab = i
                    if menu.current_tab > 3 then menu.current_tab = 3 end
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

        local bottom_bar_h = 100
        local is_hovering_bottom_zone = (mouse_pos.x >= pos.x and mouse_pos.x <= pos.x + size.x and mouse_pos.y >= pos.y + size.y - 70 and mouse_pos.y <= pos.y + size.y)
        
        if imgui.IsAnyItemActive() then
            if mouse_pos.y >= pos.y + size.y - 120 then
                is_hovering_bottom_zone = true
            end
        end
        
        menu.bottombar_alpha = lerp(menu.bottombar_alpha, is_hovering_bottom_zone and 1.0 or 0.0, 0.04)
        local target_content_alpha = (is_hovering_bottom_zone and menu.bottombar_alpha > 0.9) and 1.0 or 0.0
        menu.bottom_content_alpha = lerp(menu.bottom_content_alpha, target_content_alpha, 0.40)
        
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

            if menu.bottom_content_alpha > 0.01 then
                local current_content_alpha = menu.alpha * menu.bottom_content_alpha
                
                local b_start_x = (size.x - total_bottom_width) / 2
                local total_content_h = (input_anim_w > 1.0) and (b_avatar_sz + 6 + 24) or b_avatar_sz
                local b_base_y = (size.y - bottom_bar_h) + (bottom_bar_h - total_content_h) / 2

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

        if title_alpha > 0.01 then
            imgui.SetCursorPos(imgui.ImVec2(25, title_y_offset))
            imgui.SetWindowFontScale(1.2)
            local active_tab_data = tabs_titles[menu.current_tab]
            local active_title = active_tab_data.name
            imgui.TextColored(imgui.ImVec4(t.text.x, t.text.y, t.text.z, t.text.w * menu.alpha * title_alpha), active_title)
            imgui.SetWindowFontScale(1.0)
        end

        local content_area_y = lerp(55, 75, menu.sidebar_alpha)
        local bottom_offset = lerp(15, bottom_bar_h + 10, menu.bottombar_alpha)
        local content_area_h = size.y - content_area_y - bottom_offset

        imgui.SetCursorPos(imgui.ImVec2(25, content_area_y))
        imgui.BeginChild("##content_area", imgui.ImVec2(size.x - 50, content_area_h), false, imgui.WindowFlags.NoScrollbar)
        
        if menu.current_tab == 1 then
            imgui.TextColored(t.text_muted, u8"Добро пожаловать в MHG. Здесь появятся быстрые действия и статус.")

            imgui.Dummy(imgui.ImVec2(0, 14))
            imgui.TextColored(t.text_muted, u8"Клавиши на экране:")
            imgui.Dummy(imgui.ImVec2(0, 5))

            local kb_btn_size = imgui.ImVec2(218, 32)
            local kb_spacing_x = 10

            -- === Чекбокс: Keyboard ===
            local p_kb = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##mhg_keyboard_chk", kb_btn_size) then
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

            draw_list:AddRectFilled(p_kb, imgui.ImVec2(p_kb.x + kb_btn_size.x, p_kb.y + kb_btn_size.y),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(kb_bg_r, kb_bg_g, kb_bg_b, kb_bg_a * menu.alpha)), 6.0)
            draw_list:AddRect(p_kb, imgui.ImVec2(p_kb.x + kb_btn_size.x, p_kb.y + kb_btn_size.y),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(kb_br_r, kb_br_g, kb_br_b, kb_br_a * menu.alpha)), 6.0, 15, 1.2)

            local kb_lbl = u8"Keyboard"
            local kb_lbl_sz = imgui.CalcTextSize(kb_lbl)
            local kb_txt_val = lerp(lerp(0.65, 0.85, KB.chk_hover), 1.00, KB.chk_fill)
            draw_list:AddText(imgui.ImVec2(p_kb.x + (kb_btn_size.x - kb_lbl_sz.x) / 2, p_kb.y + (kb_btn_size.y - kb_lbl_sz.y) / 2),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, kb_txt_val * menu.alpha)), kb_lbl)

            -- === Дополнительные кнопки (появляются плавно) ===
            local reveal_target = session_cfg.settings.keyboard_enabled and 1.0 or 0.0
            KB.panel_reveal = lerp(KB.panel_reveal, reveal_target, 0.14)
            local rv = KB.panel_reveal

            if rv > 0.01 then
                local rv_alpha = menu.alpha * rv

                -- === Блокировать C ===
                imgui.SameLine(0, kb_spacing_x)
                local p_bc = imgui.GetCursorScreenPos()
                p_bc = imgui.ImVec2(p_bc.x, p_bc.y + lerp(10, 0, rv))

                if imgui.InvisibleButton("##mhg_block_c_chk", kb_btn_size) and rv > 0.85 then
                    session_cfg.settings.keyboard_block_c = not session_cfg.settings.keyboard_block_c
                    inicfg.save(session_cfg, CONFIG_FILE)
                end

                KB.bc_hover = lerp(KB.bc_hover, imgui.IsItemHovered() and 1.0 or 0.0, 0.14)
                KB.bc_fill = lerp(KB.bc_fill, session_cfg.settings.keyboard_block_c and 1.0 or 0.0, 0.12)

                local bc_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], KB.bc_hover), t.bg_act[1], KB.bc_fill)
                local bc_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], KB.bc_hover), t.bg_act[2], KB.bc_fill)
                local bc_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], KB.bc_hover), t.bg_act[3], KB.bc_fill)
                local bc_bg_a = lerp(lerp(0.20, 0.45, KB.bc_hover), 0.75, KB.bc_fill)
                local bc_br_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], KB.bc_hover), t.bor_act[1], KB.bc_fill)
                local bc_br_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], KB.bc_hover), t.bor_act[2], KB.bc_fill)
                local bc_br_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], KB.bc_hover), t.bor_act[3], KB.bc_fill)
                local bc_br_a = lerp(lerp(0.25, 0.60, KB.bc_hover), 0.95, KB.bc_fill)

                draw_list:AddRectFilled(p_bc, imgui.ImVec2(p_bc.x + kb_btn_size.x, p_bc.y + kb_btn_size.y),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bc_bg_r, bc_bg_g, bc_bg_b, bc_bg_a * rv_alpha)), 6.0)
                draw_list:AddRect(p_bc, imgui.ImVec2(p_bc.x + kb_btn_size.x, p_bc.y + kb_btn_size.y),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bc_br_r, bc_br_g, bc_br_b, bc_br_a * rv_alpha)), 6.0, 15, 1.2)

                local bc_lbl = u8"Блокировать C"
                local bc_lbl_sz = imgui.CalcTextSize(bc_lbl)
                local bc_txt_val = lerp(lerp(0.65, 0.85, KB.bc_hover), 1.00, KB.bc_fill)
                draw_list:AddText(imgui.ImVec2(p_bc.x + (kb_btn_size.x - bc_lbl_sz.x) / 2, p_bc.y + (kb_btn_size.y - bc_lbl_sz.y) / 2),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, bc_txt_val * rv_alpha)), bc_lbl)

                -- === Изменить положение ===
                imgui.SameLine(0, kb_spacing_x)
                local p_ed = imgui.GetCursorScreenPos()
                p_ed = imgui.ImVec2(p_ed.x, p_ed.y + lerp(10, 0, rv))

                if imgui.InvisibleButton("##mhg_kb_move_btn", kb_btn_size) and rv > 0.85 then
                    KB.edit = not KB.edit
                    if not KB.edit then
                        KB.drag_id = nil
                        if KB.save_layout then KB.save_layout() end
                    end
                end

                KB.ed_hover = lerp(KB.ed_hover, imgui.IsItemHovered() and 1.0 or 0.0, 0.14)
                KB.ed_fill = lerp(KB.ed_fill, KB.edit and 1.0 or 0.0, 0.12)

                local ed_bg_r = lerp(lerp(t.bg_idle[1], t.bg_hover[1], KB.ed_hover), t.bg_act[1], KB.ed_fill)
                local ed_bg_g = lerp(lerp(t.bg_idle[2], t.bg_hover[2], KB.ed_hover), t.bg_act[2], KB.ed_fill)
                local ed_bg_b = lerp(lerp(t.bg_idle[3], t.bg_hover[3], KB.ed_hover), t.bg_act[3], KB.ed_fill)
                local ed_bg_a = lerp(lerp(0.20, 0.45, KB.ed_hover), 0.75, KB.ed_fill)
                local ed_br_r = lerp(lerp(t.bor_idle[1], t.bor_hover[1], KB.ed_hover), t.bor_act[1], KB.ed_fill)
                local ed_br_g = lerp(lerp(t.bor_idle[2], t.bor_hover[2], KB.ed_hover), t.bor_act[2], KB.ed_fill)
                local ed_br_b = lerp(lerp(t.bor_idle[3], t.bor_hover[3], KB.ed_hover), t.bor_act[3], KB.ed_fill)
                local ed_br_a = lerp(lerp(0.25, 0.60, KB.ed_hover), 0.95, KB.ed_fill)

                draw_list:AddRectFilled(p_ed, imgui.ImVec2(p_ed.x + kb_btn_size.x, p_ed.y + kb_btn_size.y),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ed_bg_r, ed_bg_g, ed_bg_b, ed_bg_a * rv_alpha)), 6.0)
                draw_list:AddRect(p_ed, imgui.ImVec2(p_ed.x + kb_btn_size.x, p_ed.y + kb_btn_size.y),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(ed_br_r, ed_br_g, ed_br_b, ed_br_a * rv_alpha)), 6.0, 15, 1.2)

                local ed_lbl = KB.edit and u8"Готово" or u8"Изменить"
                local ed_lbl_sz = imgui.CalcTextSize(ed_lbl)
                local ed_txt_val = lerp(lerp(0.65, 0.85, KB.ed_hover), 1.00, KB.ed_fill)
                draw_list:AddText(imgui.ImVec2(p_ed.x + (kb_btn_size.x - ed_lbl_sz.x) / 2, p_ed.y + (kb_btn_size.y - ed_lbl_sz.y) / 2),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, ed_txt_val * rv_alpha)), ed_lbl)

                imgui.Dummy(imgui.ImVec2(0, 8))
                if KB.edit then
                    imgui.TextColored(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, t.text_muted.w * rv),
                        u8"Тащите любую клавишу мышью, колесо меняет её размер. ESC — выйти.")
                else
                    imgui.TextColored(imgui.ImVec4(t.text_muted.x, t.text_muted.y, t.text_muted.z, t.text_muted.w * rv),
                        u8"«Блокировать C» отключает приседание в игре, но не мешает писать в чат.")
                end
            end
        elseif menu.current_tab == 2 then
            imgui.TextColored(t.text_muted, u8"ASP:")
            imgui.Dummy(imgui.ImVec2(0, 5))

            local settings_btn_size = imgui.ImVec2(218, 32)

            -- === ASP enable ===
            local p_asp_chk = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_asp_enabled_chk", settings_btn_size) then
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

            draw_list:AddRectFilled(p_asp_chk, imgui.ImVec2(p_asp_chk.x + settings_btn_size.x, p_asp_chk.y + settings_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(a_bg_r, a_bg_g, a_bg_b, a_bg_a * menu.alpha)), 6.0)
            draw_list:AddRect(p_asp_chk, imgui.ImVec2(p_asp_chk.x + settings_btn_size.x, p_asp_chk.y + settings_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(a_bor_r, a_bor_g, a_bor_b, a_bor_a * menu.alpha)), 6.0, 15, 1.2)

            local asp_lbl = u8"ASP"
            local asp_lbl_sz = imgui.CalcTextSize(asp_lbl)
            local asp_lbl_pos = imgui.ImVec2(p_asp_chk.x + (settings_btn_size.x - asp_lbl_sz.x) / 2, p_asp_chk.y + (settings_btn_size.y - asp_lbl_sz.y) / 2)
            local asp_text_val = lerp(lerp(0.65, 0.85, asp_chk_hover_alpha), 1.00, asp_fill_val)
            draw_list:AddText(asp_lbl_pos, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, asp_text_val * menu.alpha)), asp_lbl)

            asp_reveal = lerp(asp_reveal, session_cfg.settings.asp_enabled and 1.0 or 0.0, 0.14)
            local arv = asp_reveal

            if arv > 0.01 then
                local arv_alpha = menu.alpha * arv

                imgui.SameLine(0, 10)
                local p_sl = imgui.GetCursorPos()
                imgui.SetCursorPos(imgui.ImVec2(p_sl.x, p_sl.y + lerp(10, 0, arv)))
                CustomSliderFloat("##asp_slider", "ASP", asp_val_buf, 0.5, 2.0, settings_btn_size, arv)

                if session_cfg.settings.asp_enabled and session_cfg.settings.asp_value ~= asp_val_buf[0] then
                    session_cfg.settings.asp_value = asp_val_buf[0]
                    apply_asp(asp_val_buf[0])
                    inicfg.save(session_cfg, CONFIG_FILE)
                end

                imgui.SameLine(0, 10)

                local reset_btn_size = imgui.ImVec2(80, 32)
                local p_rst_cur = imgui.GetCursorPos()
                imgui.SetCursorPos(imgui.ImVec2(p_rst_cur.x, p_rst_cur.y + lerp(10, 0, arv)))
                local p_reset = imgui.GetCursorScreenPos()
                if imgui.InvisibleButton("##asp_reset_btn", reset_btn_size) and arv > 0.85 then
                    asp_val_buf[0] = 1.25
                    session_cfg.settings.asp_value = 1.25
                    apply_asp(1.25)
                    inicfg.save(session_cfg, CONFIG_FILE)
                end

                local is_reset_hovered = imgui.IsItemHovered()
                reset_btn_hover_alpha = lerp(reset_btn_hover_alpha, is_reset_hovered and 1.0 or 0.0, 0.14)

                local r_bg_r = lerp(t.bg_idle[1], t.bg_hover[1], reset_btn_hover_alpha)
                local r_bg_g = lerp(t.bg_idle[2], t.bg_hover[2], reset_btn_hover_alpha)
                local r_bg_b = lerp(t.bg_idle[3], t.bg_hover[3], reset_btn_hover_alpha)
                local r_bg_a = lerp(0.20, 0.65, reset_btn_hover_alpha)

                local r_bor_r = lerp(t.bor_idle[1], t.bor_hover[1], reset_btn_hover_alpha)
                local r_bor_g = lerp(t.bor_idle[2], t.bor_hover[2], reset_btn_hover_alpha)
                local r_bor_b = lerp(t.bor_idle[3], t.bor_hover[3], reset_btn_hover_alpha)
                local r_bor_a = lerp(0.25, 0.95, reset_btn_hover_alpha)

                draw_list:AddRectFilled(p_reset, imgui.ImVec2(p_reset.x + reset_btn_size.x, p_reset.y + reset_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r_bg_r, r_bg_g, r_bg_b, r_bg_a * arv_alpha)), 6.0)
                draw_list:AddRect(p_reset, imgui.ImVec2(p_reset.x + reset_btn_size.x, p_reset.y + reset_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(r_bor_r, r_bor_g, r_bor_b, r_bor_a * arv_alpha)), 6.0, 15, 1.2)

                local reset_txt = u8"Сброс"
                local r_txt_sz = imgui.CalcTextSize(reset_txt)
                local r_txt_pos = imgui.ImVec2(p_reset.x + (reset_btn_size.x - r_txt_sz.x) / 2, p_reset.y + (reset_btn_size.y - r_txt_sz.y) / 2)
                draw_list:AddText(r_txt_pos, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, lerp(0.65, 1.00, reset_btn_hover_alpha) * arv_alpha)), reset_txt)
            end
        elseif menu.current_tab == 3 then
            local settings_btn_size = imgui.ImVec2(218, 32)

            imgui.TextColored(t.text_muted, u8"Клавиша открытия меню:")
            imgui.Dummy(imgui.ImVec2(0, 5))

            local p_hk = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_hotkey_btn", settings_btn_size) then
                menu.hotkey_listening = true
            end

            local is_hk_hovered = imgui.IsItemHovered()
            hotkey_btn_hover_alpha = lerp(hotkey_btn_hover_alpha, (is_hk_hovered or menu.hotkey_listening) and 1.0 or 0.0, 0.14)

            local hk_min = p_hk
            local hk_max = imgui.ImVec2(p_hk.x + settings_btn_size.x, p_hk.y + settings_btn_size.y)
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

            local hk_str = menu.hotkey_listening and u8"Нажмите клавишу..." or get_key_name(session_cfg.settings.open_key)
            local hk_txt_sz = imgui.CalcTextSize(hk_str)
            local hk_txt_pos = imgui.ImVec2(hk_min.x + (settings_btn_size.x - hk_txt_sz.x) / 2, hk_min.y + (settings_btn_size.y - hk_txt_sz.y) / 2)
            local hk_text_val = lerp(lerp(0.65, 0.85, hotkey_btn_hover_alpha), 1.00, hk_fill_val)
            draw_list:AddText(hk_txt_pos, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, hk_text_val * menu.alpha)), hk_str)

            imgui.Dummy(imgui.ImVec2(0, 14))
            imgui.TextColored(t.text_muted, u8"Тема оформления:")
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

            imgui.TextColored(t.text_muted, u8"Эффекты интерфейса:")
            imgui.Dummy(imgui.ImVec2(0, 5))

            local settings_spacing_x = 10

            -- Particles
            local p_chk = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_particles_chk", settings_btn_size) then
                session_cfg.settings.particles_enabled = not session_cfg.settings.particles_enabled
                inicfg.save(session_cfg, CONFIG_FILE)
            end

            local is_chk_hovered = imgui.IsItemHovered()
            checkbox_hover_alpha = lerp(checkbox_hover_alpha, is_chk_hovered and 1.0 or 0.0, 0.14)
            
            local c_min = p_chk
            local c_max = imgui.ImVec2(p_chk.x + settings_btn_size.x, p_chk.y + settings_btn_size.y)
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
            local chk_txt_pos = imgui.ImVec2(c_min.x + (settings_btn_size.x - chk_txt_sz.x) / 2, c_min.y + (settings_btn_size.y - chk_txt_sz.y) / 2)
            local chk_text_col_val = lerp(lerp(0.65, 0.85, checkbox_hover_alpha), 1.00, chk_fill_val)
            local c_text_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, chk_text_col_val * menu.alpha))
            draw_list:AddText(chk_txt_pos, c_text_col, status_str)

            imgui.SameLine(0, settings_spacing_x)

            -- Watermark (вместо переключателя анимации вкладок)
            local p_wmset = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_watermark_chk", settings_btn_size) then
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

            draw_list:AddRectFilled(p_wmset, imgui.ImVec2(p_wmset.x + settings_btn_size.x, p_wmset.y + settings_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(w_bg_r, w_bg_g, w_bg_b, w_bg_a * menu.alpha)), 6.0)
            draw_list:AddRect(p_wmset, imgui.ImVec2(p_wmset.x + settings_btn_size.x, p_wmset.y + settings_btn_size.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(w_bor_r, w_bor_g, w_bor_b, w_bor_a * menu.alpha)), 6.0, 15, 1.2)

            local wm_lbl = u8"Watermark"
            local wm_lbl_sz = imgui.CalcTextSize(wm_lbl)
            local wm_lbl_pos = imgui.ImVec2(p_wmset.x + (settings_btn_size.x - wm_lbl_sz.x) / 2, p_wmset.y + (settings_btn_size.y - wm_lbl_sz.y) / 2)
            local wm_text_val = lerp(lerp(0.65, 0.85, wm_hover_alpha), 1.00, wm_fill_val)
            draw_list:AddText(wm_lbl_pos, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, wm_text_val * menu.alpha)), wm_lbl)

            imgui.SameLine(0, settings_spacing_x)

            -- Glow
            local p_glow = imgui.GetCursorScreenPos()
            if imgui.InvisibleButton("##custom_glow_chk", settings_btn_size) then
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

            draw_list:AddRectFilled(p_glow, imgui.ImVec2(p_glow.x + settings_btn_size.x, p_glow.y + settings_btn_size.y), g_bg_col, 6.0)
            draw_list:AddRect(p_glow, imgui.ImVec2(p_glow.x + settings_btn_size.x, p_glow.y + settings_btn_size.y), g_bor_col, 6.0, 15, 1.2)

            local glow_status_str = u8"Свечение окна"
            local glow_txt_sz = imgui.CalcTextSize(glow_status_str)
            local glow_txt_pos = imgui.ImVec2(p_glow.x + (settings_btn_size.x - glow_txt_sz.x) / 2, p_glow.y + (settings_btn_size.y - glow_txt_sz.y) / 2)
            local glow_text_val = lerp(lerp(0.65, 0.85, glow_btn_hover_alpha), 1.00, glow_fill_val)
            local glow_text_col = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.text.x, t.text.y, t.text.z, glow_text_val * menu.alpha))
            draw_list:AddText(glow_txt_pos, glow_text_col, glow_status_str)

        end

        imgui.EndChild()
        imgui.End()
    end
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

local watermark_frame = imgui.OnFrame(
    function()
        local target = (session_cfg.settings.watermark_enabled ~= false) and 1.0 or 0.0
        wm_overlay_alpha = lerp(wm_overlay_alpha, target, 0.08)
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

        imgui.SetNextWindowPos(imgui.ImVec2(sw - 12, 10), imgui.Cond.Always, imgui.ImVec2(1.0, 0.0))
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

            -- glow вокруг WM (если включено в настройках)
            if session_cfg.settings.window_glow_enabled then
                local time = os.clock() * 2.5
                local pulse = math.sin(time) * 0.5 + 0.5
                local glow_a = (0.18 + pulse * 0.22) * a
                for i = 2, 1, -1 do
                    local off = i * 1.5
                    local gcol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], glow_a / i))
                    dl:AddRect(
                        imgui.ImVec2(pmin.x - off, pmin.y - off),
                        imgui.ImVec2(pmax.x + off, pmax.y + off),
                        gcol, 7.0 + off, 15, 1.25
                    )
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

            local accent_line = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent[1], t.accent[2], t.accent[3], 0.55 * a))
            dl:AddLine(
                imgui.ImVec2(pmin.x + 6, pmin.y + 1),
                imgui.ImVec2(pmax.x - 6, pmin.y + 1),
                accent_line, 1.25
            )

            -- частицы внутри WM (если включены)
            if session_cfg.settings.particles_enabled then
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
        imgui.PopStyleColor(1)
        imgui.PopStyleVar(4)
    end
)
watermark_frame.HideCursor = true

-- =========================================================
-- ===============  ЭКРАННАЯ КЛАВИАТУРА (KB)  ==============
-- =========================================================

local KB_UNIT  = 36          -- базовая высота/ширина клавиши
local KB_GAP   = 6
local KB_PITCH = KB_UNIT + KB_GAP

local KB_MOUSE_W = 52
local KB_SCALE_MIN, KB_SCALE_MAX = 0.6, 2.2

-- Каждая клавиша — самостоятельный элемент: своя позиция и свой масштаб.
-- dx/dy — смещение относительно левого верхнего угла раскладки по умолчанию.
local KB_KEYS = {
    { id = "Q",     label = "Q",     dx = 0,            dy = 0,            bw = KB_UNIT },
    { id = "W",     label = "W",     dx = KB_PITCH,     dy = 0,            bw = KB_UNIT },
    { id = "E",     label = "E",     dx = KB_PITCH * 2, dy = 0,            bw = KB_UNIT },
    { id = "A",     label = "A",     dx = 0,            dy = KB_PITCH,     bw = KB_UNIT },
    { id = "S",     label = "S",     dx = KB_PITCH,     dy = KB_PITCH,     bw = KB_UNIT },
    { id = "D",     label = "D",     dx = KB_PITCH * 2, dy = KB_PITCH,     bw = KB_UNIT },
    { id = "SHIFT", label = "SHIFT", dx = 0,            dy = KB_PITCH * 2, bw = KB_PITCH + KB_UNIT },
    { id = "C",     label = "C",     dx = KB_PITCH * 2, dy = KB_PITCH * 2, bw = KB_UNIT },
    { id = "SPACE", label = "SPACE", dx = 0,            dy = KB_PITCH * 3, bw = KB_PITCH * 2 + KB_UNIT },
    { id = "LMB",   label = u8"ЛКМ", dx = KB_PITCH * 3 + 14,                       dy = 0,        bw = KB_MOUSE_W },
    { id = "RMB",   label = u8"ПКМ", dx = KB_PITCH * 3 + 14 + KB_MOUSE_W + KB_GAP, dy = 0,        bw = KB_MOUSE_W },
    { id = "WUP",   glyph = "up",    dx = KB_PITCH * 3 + 14,                       dy = KB_PITCH, bw = KB_MOUSE_W },
    { id = "WDN",   glyph = "down",  dx = KB_PITCH * 3 + 14 + KB_MOUSE_W + KB_GAP, dy = KB_PITCH, bw = KB_MOUSE_W },
}

KB = {
    alpha      = 0.0,   -- общая прозрачность оверлея
    edit       = false, -- режим правки (перетаскивание + масштаб)
    edit_alpha = 0.0,
    drag_id    = nil,
    drag_dx    = 0.0,
    drag_dy    = 0.0,
    block_anim = 0.0,   -- анимация перечёркивания C
    glow       = 0.0,   -- анимация свечения
    wheel_up   = -10.0,
    wheel_down = -10.0,
    state      = {},    -- фактическое состояние клавиш (обновляется в main)
    anim       = {},    -- сглаженное состояние для отрисовки
    layout     = {},    -- layout[id] = {x=, y=, s=}
    hover      = {},
    -- анимации кнопок в меню
    chk_hover = 0.0, chk_fill = 0.0,
    bc_hover  = 0.0, bc_fill  = 0.0,
    ed_hover  = 0.0, ed_fill  = 0.0,
    panel_reveal = 0.0
}

for _, k in ipairs(KB_KEYS) do
    KB.anim[k.id] = 0.0
    KB.state[k.id] = false
    KB.hover[k.id] = 0.0
end

-- === раскладка: "id:x:y:scale;..." в settings.keyboard_layout ===

local function kb_default_layout()
    local sw, sh = getScreenResolution()
    local total_w = KB_PITCH * 3 + 14 + KB_MOUSE_W * 2 + KB_GAP
    local total_h = KB_PITCH * 3 + KB_UNIT
    local base_x = math.floor(sw * 0.5 - total_w * 0.5)
    local base_y = math.floor(sh - total_h - 90)
    local out = {}
    for _, k in ipairs(KB_KEYS) do
        out[k.id] = { x = base_x + k.dx, y = base_y + k.dy, s = 1.0 }
    end
    return out
end

local function kb_save_layout()
    local parts = {}
    for _, k in ipairs(KB_KEYS) do
        local l = KB.layout[k.id]
        if l then
            parts[#parts + 1] = string.format("%s:%d:%d:%.2f", k.id, math.floor(l.x), math.floor(l.y), l.s)
        end
    end
    session_cfg.settings.keyboard_layout = table.concat(parts, ";")
    inicfg.save(session_cfg, CONFIG_FILE)
end

local function kb_load_layout()
    KB.layout = kb_default_layout()
    local raw = tostring(session_cfg.settings.keyboard_layout or "")
    for id, sx, sy, ss in raw:gmatch("([%w_]+):(-?%d+):(-?%d+):([%d%.]+)") do
        local l = KB.layout[id]
        if l then
            l.x = tonumber(sx) or l.x
            l.y = tonumber(sy) or l.y
            l.s = math.max(KB_SCALE_MIN, math.min(tonumber(ss) or 1.0, KB_SCALE_MAX))
        end
    end
end

KB.save_layout = kb_save_layout
kb_load_layout()

-- опрос клавиш (вызывается из main, а не из потока отрисовки)
local function kb_poll()
    local blocked_input = sampIsChatInputActive() or sampIsDialogActive()
        or menu.show or auth.show or update_ui.show or KB.edit

    local function down(vk)
        if blocked_input then return false end
        return isKeyDown(vk)
    end

    KB.state.Q     = down(vkeys.VK_Q)
    KB.state.W     = down(vkeys.VK_W)
    KB.state.E     = down(vkeys.VK_E)
    KB.state.A     = down(vkeys.VK_A)
    KB.state.S     = down(vkeys.VK_S)
    KB.state.D     = down(vkeys.VK_D)
    KB.state.C     = down(vkeys.VK_C)
    KB.state.SHIFT = down(vkeys.VK_SHIFT)
    KB.state.SPACE = down(vkeys.VK_SPACE)
    KB.state.LMB   = down(vkeys.VK_LBUTTON)
    KB.state.RMB   = down(vkeys.VK_RBUTTON)

    local now = os.clock()
    KB.state.WUP = (now - KB.wheel_up) < 0.13
    KB.state.WDN = (now - KB.wheel_down) < 0.13
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

        for _, k in ipairs(KB_KEYS) do
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
        local pulse = 0.5 + 0.5 * (math.sin(os.clock() * 3.4) * 0.5 + 0.5)

        for _, k in ipairs(KB_KEYS) do
            local l = KB.layout[k.id]
            if not l then
                l = { x = 40, y = 40, s = 1.0 }
                KB.layout[k.id] = l
            end

            local kw = k.bw * l.s
            local kh = KB_UNIT * l.s

            l.x = math.max(0, math.min(l.x, sw - kw))
            l.y = math.max(0, math.min(l.y, sh - kh))

            imgui.SetNextWindowPos(imgui.ImVec2(l.x, l.y), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(kw, kh), imgui.Cond.Always)

            if imgui.Begin("##mhg_kb_" .. k.id, nil, flags) then
                local dl = imgui.GetWindowDrawList()
                local wpos = imgui.GetWindowPos()

                local p = KB.anim[k.id] or 0.0
                local is_hovered = KB.edit and imgui.IsWindowHovered()
                KB.hover[k.id] = lerp(KB.hover[k.id] or 0.0,
                    (is_hovered or KB.drag_id == k.id) and 1.0 or 0.0, 0.16)
                local hv = KB.hover[k.id]

                local press = p * 1.5 * l.s
                local pmin = imgui.ImVec2(wpos.x + press * 0.5, wpos.y + press)
                local pmax = imgui.ImVec2(wpos.x + kw - press * 0.5, wpos.y + kh - press * 0.5)
                local rounding = 6.0 * l.s

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
                    imgui.ImVec4(br_r, br_g, br_b, br_a * a)), rounding, 15, 1.25 * l.s)

                -- акцентная рамка в режиме правки
                if KB.edit_alpha > 0.01 then
                    local ea = (0.22 + 0.28 * pulse + 0.45 * hv) * KB.edit_alpha * a
                    dl:AddRect(imgui.ImVec2(pmin.x - 2, pmin.y - 2), imgui.ImVec2(pmax.x + 2, pmax.y + 2),
                        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
                            t.accent[1], t.accent[2], t.accent[3], ea)), rounding + 2, 15, 1.5)
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
                    local s = 6.5 * l.s
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
                    imgui.SetWindowFontScale(l.s)
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
                    local inset = 6.0 * l.s
                    local hx = (pmax.x - pmin.x - inset * 2) * 0.5 * KB.block_anim
                    local hy = (pmax.y - pmin.y - inset * 2) * 0.5 * KB.block_anim
                    dl:AddLine(imgui.ImVec2(cx - hx, cy - hy), imgui.ImVec2(cx + hx, cy + hy), cross, 2.2 * l.s)
                    dl:AddLine(imgui.ImVec2(cx + hx, cy - hy), imgui.ImVec2(cx - hx, cy + hy), cross, 2.2 * l.s)
                    dl:AddRect(pmin, pmax, imgui.ColorConvertFloat4ToU32(
                        imgui.ImVec4(cr, cg, cb, 0.70 * ba)), rounding, 15, 1.4 * l.s)
                end

                -- правка: перетаскивание и масштаб колесом
                if KB.edit then
                    if is_hovered and wheel ~= 0.0 then
                        local ccx = l.x + kw * 0.5
                        local ccy = l.y + kh * 0.5
                        l.s = math.max(KB_SCALE_MIN, math.min(l.s + wheel * 0.08, KB_SCALE_MAX))
                        -- масштабируем относительно центра клавиши
                        l.x = ccx - (k.bw * l.s) * 0.5
                        l.y = ccy - (KB_UNIT * l.s) * 0.5
                        layout_changed = true
                    end

                    if KB.drag_id == nil then
                        if is_hovered and imgui.IsMouseClicked(0) then
                            KB.drag_id = k.id
                            KB.drag_dx = mp.x - wpos.x
                            KB.drag_dy = mp.y - wpos.y
                        end
                    elseif KB.drag_id == k.id then
                        if imgui.IsMouseDown(0) then
                            l.x = math.max(0, math.min(mp.x - KB.drag_dx, sw - kw))
                            l.y = math.max(0, math.min(mp.y - KB.drag_dy, sh - kh))
                        else
                            KB.drag_id = nil
                            layout_changed = true
                        end
                    end
                end

                imgui.End()
            end
        end

        -- подсказка в режиме правки (без подложки, только текст)
        if KB.edit_alpha > 0.01 then
            local hint = u8"ЛКМ — перетащить клавишу, колесо — размер. ESC — выйти."
            local hsz = imgui.CalcTextSize(hint)
            local hw, hh = hsz.x + 6, hsz.y + 6
            imgui.SetNextWindowPos(imgui.ImVec2(sw * 0.5 - hw * 0.5, 40), imgui.Cond.Always)
            imgui.SetNextWindowSize(imgui.ImVec2(hw, hh), imgui.Cond.Always)
            if imgui.Begin("##mhg_kb_hint", nil, base_flags + imgui.WindowFlags.NoInputs) then
                local dl = imgui.GetWindowDrawList()
                local wpos = imgui.GetWindowPos()
                local ha = KB.edit_alpha * a
                -- лёгкая обводка, чтобы текст читался на любом фоне
                local shadow = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0, 0, 0, 0.75 * ha))
                for ox = -1, 1 do
                    for oy = -1, 1 do
                        if ox ~= 0 or oy ~= 0 then
                            dl:AddText(imgui.ImVec2(wpos.x + 3 + ox, wpos.y + 3 + oy), shadow, hint)
                        end
                    end
                end
                dl:AddText(imgui.ImVec2(wpos.x + 3, wpos.y + 3), imgui.ColorConvertFloat4ToU32(
                    imgui.ImVec4(t.text.x, t.text.y, t.text.z, ha)), hint)
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
            pcall(function() thisScript():reload() end)
        end)
    end)
end

local function check_update()
    -- single source of truth: read SCRIPT_VERSION straight out of the script
    -- that will actually be installed, instead of a separate version.txt that
    -- can drift out of sync with it.
    local tmp = mhg_dir .. "\\version_check.lua"

    local function handle_content(remote)
        if not remote or #remote < 200 then
            pcall(os.remove, tmp)
            return
        end

        local ver = remote:match('SCRIPT_VERSION%s*=%s*"([%d%.]+)"')
        if not ver then
            pcall(os.remove, tmp)
            return
        end
        if parse_version(ver) <= parse_version(SCRIPT_VERSION) then
            pcall(os.remove, tmp)
            return
        end

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
    downloadUrlToFile(SCRIPT_URL .. "?t=" .. os.time(), tmp, function(id, status)
        local function try_read()
            local f = io.open(tmp, "rb")
            if not f then return false end
            local content = f:read("*a")
            f:close()
            if content and #content > 200 then
                handle_content(content)
                return true
            end
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
        draw_particle_grid(draw_list, pos, size, update_ui.alpha)

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
            tab_effects_enabled = true,
            window_glow_enabled = true,
            theme = 1,
            custom_avatar_url = "",
            asp_enabled = false,
            asp_value = 1.25,
            watermark_enabled = true,
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
        if session_cfg.session.is_logged then
            local current_nick = get_my_nick()
            if session_cfg.session.saved_nick == current_nick and check_account(current_nick, session_cfg.session.saved_password) then
            else
                session_cfg.session.is_logged = false
                session_cfg.session.saved_nick = ""
                session_cfg.session.saved_password = ""
                inicfg.save(session_cfg, CONFIG_FILE)
            end
        end
    end)

    check_update()
    local next_update_check = os.clock() + UPDATE_CHECK_INTERVAL

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

        if auth.downloading and auth.download_start > 0 and (os.clock() - auth.download_start) > 12.0 then
            auth.downloading = false
            if #auth.accounts > 0 then
                auth.loaded = true
            end
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
        elseif isKeyJustPressed(session_cfg.settings.open_key or vkeys.VK_F12) and not sampIsChatInputActive() and not sampIsDialogActive() then
            open_mhg()
        end

        if KB.edit and not (auth.show or menu.show or update_ui.show) and isKeyJustPressed(vkeys.VK_ESCAPE) then
            KB.edit = false
            KB.drag_id = nil
            kb_save_layout()
            consumeWindowMessage(true, false)
        end

        if (auth.show or menu.show or update_ui.show) and isKeyJustPressed(vkeys.VK_ESCAPE) then
            if update_ui.show and (update_ui.stage == "loading" or update_ui.stage == "success") then
                -- cannot close during update
            else
                close_all()
                consumeWindowMessage(true, false)
            end
        end
    end
end