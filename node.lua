gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local http = require "http"
local font

-- Configuration variables
local rss_url = "https://www.tagesschau.de/infoservices/alle-meldungen-100~rss2.xml"
local scroll_speed = 120
local text_size = 40
local text_color = {r=1, g=1, b=1, a=1}
local ticker_height = 80
local update_interval = 300
local separator = " +++ "
local position = "bottom"
local default_text = "RSS feed not available"

-- State variables
local rss_items = {}
local scroll_offset = 0
local last_update = 0
local total_width = 0

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

        -- Decode HTML entities
        title = decode_html_entities(title)

        if title ~= "" then
            table.insert(items, title)
        end
    end

    return items
end

-- Fetch and parse RSS feed
local function update_news()
    http.get(rss_url, function(response)
        if response.status == 200 then
            local items = parse_rss(response.body)

            if #items > 0 then
                rss_items = items
                print("Loaded " .. #rss_items .. " RSS items")
            else
                print("No items found in RSS feed")
                rss_items = {}
            end
        else
            print("Failed to fetch RSS feed. Status: " .. tostring(response.status))
            rss_items = {}
        end
    end)
end

-- Configuration update handler
util.data_mapper{
    rss_url = function(val)
        rss_url = val
        last_update = 0  -- Force immediate update
    end,
    speed = function(val)
        scroll_speed = val
    end,
    size = function(val)
        text_size = val
        font = resource.load_font("default-font.ttf", text_size)
    end,
    color = function(val)
        text_color = val
    end,
    ticker_height = function(val)
        ticker_height = val
    end,
    update_interval = function(val)
        update_interval = val
    end,
    separator = function(val)
        separator = val
    end,
    position = function(val)
        position = val
    end,
    default_text = function(val)
        default_text = val
    end,
}

function node.render()
    -- Initialize font if not loaded
    if not font then
        font = resource.load_font("default-font.ttf", text_size)
    end

    -- Update RSS feed periodically
    local now = sys.now()
    if now - last_update > update_interval then
        update_news()
        last_update = now
    end

    -- Build display text
    local display_text
    if #rss_items > 0 then
        display_text = table.concat(rss_items, separator) .. separator
    else
        display_text = default_text .. "   "
    end

    -- Calculate text width
    local text_width = font:width(display_text, text_size)

    -- Duplicate text for seamless scrolling
    display_text = display_text .. display_text

    -- Calculate ticker position based on configuration
    local ticker_y
    if position == "top" then
        ticker_y = 0
    else
        ticker_y = HEIGHT - ticker_height
    end

    -- Update scroll position
    scroll_offset = scroll_offset + scroll_speed * sys.frame_duration()

    -- Reset scroll when text has scrolled completely
    if scroll_offset > text_width then
        scroll_offset = 0
    end

    -- Render ticker
    gl.pushMatrix()
    gl.translate(0, ticker_y)

    -- Draw scrolling text
    local x_pos = WIDTH - scroll_offset
    font:write(x_pos, (ticker_height - text_size) / 2, display_text,
               text_size, text_color.r, text_color.g, text_color.b, text_color.a)

    gl.popMatrix()
end
