local api = ...

local M = {}

local size
local active_scroller
local last_update = 0
local update_interval = 300
local rss_items = {}
local http

-- Helper function to decode HTML entities
local function decode_html_entities(text)
    if not text then return "" end
    text = text:gsub("&amp;", "&")
    text = text:gsub("&lt;", "<")
    text = text:gsub("&gt;", ">")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&apos;", "'")
    text = text:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
    text = text:gsub("&#x(%x+);", function(n) return string.char(tonumber(n, 16)) end)
    return text
end

-- Simple XML parser for RSS feeds
local function parse_rss(xml_content)
    local items = {}

    -- Extract all <item> blocks
    for item_block in xml_content:gmatch("<item>(.-)</item>") do
        local title = item_block:match("<title><!%[CDATA%[(.-)%]%]></title>") or
                     item_block:match("<title>(.-)</title>") or ""
        local description = item_block:match("<description><!%[CDATA%[(.-)%]%]></description>") or
                           item_block:match("<description>(.-)</description>") or ""

        -- Strip HTML tags from description
        description = description:gsub("<[^>]+>", "")

        -- Decode HTML entities
        title = decode_html_entities(title)
        description = decode_html_entities(description)

        if title ~= "" then
            table.insert(items, {
                title = title,
                description = description
            })
        end
    end

    return items
end

local function Scroller(items, font, speed)
    local total_w = 0
    for _, item in ipairs(items) do
        total_w = total_w + item.width
    end

    local function draw(now, y, x1, x2)
        -- Handle empty scroller
        if total_w == 0 or #items == 0 then
            return
        end

        local x = math.floor(x1 + (now * -speed) % total_w - total_w)
        local idx = 1

        local render = 0
        while x < x2 do
            local item = items[idx]
            if x + item.width < x1 then
                -- skip: not on screen
            else
                local a = item.color.a
                if item.blink then
                    a = math.min(1, 1-math.sin(now*10)) * a
                end
                render = render + 1
                font:write(
                    x, y, item.text, size,
                    item.color.r, item.color.g, item.color.b, a
                )
            end
            x = x + item.width
            idx = idx + 1
            if idx > #items then
                idx = 1
            end
        end
    end

    return draw
end

active_scroller = Scroller({})

local function update_scroller_from_rss(config)
    local items = {}

    if #rss_items > 0 then
        print("Building scroller with " .. #rss_items .. " RSS items")
        for _, rss_item in ipairs(rss_items) do
            items[#items+1] = {
                text = rss_item.title,
                blink = false,
                color = config.color,
            }
            items[#items+1] = {
                text = config.separator or "   -   ",
                blink = false,
                color = config.color,
            }
        end
    else
        -- Use default text from config or fallback
        local default_text = config.default_text or "Loading RSS feed..."
        print("No RSS items, using default text: " .. default_text)
        items[#items+1] = {
            text = default_text,
            blink = false,
            color = config.color,
        }
    end

    size = config.size
    print("Loading font: " .. tostring(config.font.asset_name))
    local font = resource.load_font(api.localized(
        config.font.asset_name
    ))
    for _, item in ipairs(items) do
        item.width = font:width(item.text, size)
    end
    active_scroller = Scroller(
        items, font, config.speed
    )
    print("Scroller updated with " .. #items .. " items")
end

local function fetch_rss(url, config)
    -- Lazy load http module
    if not http then
        local success, result = pcall(function() return require "http" end)
        if success then
            http = result
        else
            print("HTTP module not available: " .. tostring(result))
            return
        end
    end

    print("Fetching RSS feed from: " .. url)

    http.get(url, function(response)
        if response.status == 200 then
            local items = parse_rss(response.body)

            if #items > 0 then
                rss_items = items
                print("Loaded " .. #rss_items .. " RSS items")
                update_scroller_from_rss(config)
            else
                print("No items found in RSS feed")
                -- Keep rss_items empty, will show default text
                rss_items = {}
                update_scroller_from_rss(config)
            end
        else
            print("Failed to fetch RSS feed. Status: " .. tostring(response.status))
            -- Keep rss_items empty, will show default text
            rss_items = {}
            update_scroller_from_rss(config)
        end
    end)
end

local current_config = nil

function M.updated_config_json(config)
    print("=== RSS Scroller: Config update received ===")
    print("RSS URL: " .. tostring(config.rss_url))
    print("Size: " .. tostring(config.size))
    print("Speed: " .. tostring(config.speed))

    current_config = config
    update_interval = config.update_interval or 300

    -- Update scroller with current RSS items
    update_scroller_from_rss(config)

    -- Fetch RSS feed immediately on config update
    local now = api.wall_time()
    if now - last_update > 10 or last_update == 0 then  -- Avoid too frequent updates
        fetch_rss(config.rss_url, config)
        last_update = now
    end

    print("=== RSS Scroller: Configuration complete ===")
end

local function instance(ctx)
    local function layout(canvas)
        local pos = ctx.child_config.pos or 'bottom'
        local overlap = ctx.child_config.overlap or 'overlap'
        if overlap == 'overlap' then
            return canvas:full()
        elseif pos == 'bottom' then
            return canvas:cut('bottom', size)
        else
            return canvas:cut('top', size)
        end
    end

    local function draw(canvas, target)
        -- Periodically update RSS feed
        local now = api.wall_time()
        if current_config and now - last_update > update_interval then
            fetch_rss(current_config.rss_url, current_config)
            last_update = now
        end

        local pos = ctx.child_config.pos or 'bottom'
        local y
        if pos == "bottom" then
            y = target.y2 - size
        else
            y = target.y1
        end
        active_scroller(api.wall_time(), y, target.x1, target.x2)
    end

    return {
        layout = layout;
        draw = draw;
    }
end

function M.init(ctx)
    return instance(ctx)
end

return M
