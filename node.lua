gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local json = require "json"
local http = require "http"

-- Configuration variables
local rss_url = "https://www.tagesschau.de/infoservices/alle-meldungen-100~rss2.xml"
local scroll_speed = 100
local text_size = 40
local bg_color = {r=0, g=0, b=0}
local bg_alpha = 0.8
local text_color = {r=255, g=255, b=255}
local ticker_height = 80
local update_interval = 300
local separator = " +++ "
local position = "bottom"
local overlap = "overlay"

-- State variables
local news_items = {}
local ticker_text = "Loading RSS feed..."
local scroll_offset = 0
local last_update = -999999  -- Force immediate update on startup
local font

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

-- Fetch and parse RSS feed
local function update_news()
    print("Fetching RSS feed from: " .. rss_url)

    http.get(rss_url, function(response)
        if response.status == 200 then
            local items = parse_rss(response.body)

            if #items > 0 then
                news_items = items

                -- Build ticker text
                local text_parts = {}
                for _, item in ipairs(news_items) do
                    table.insert(text_parts, item.title)
                end

                ticker_text = table.concat(text_parts, separator)

                -- Duplicate text for seamless scrolling
                ticker_text = ticker_text .. separator .. ticker_text

                print("Loaded " .. #news_items .. " news items")
            else
                print("No items found in RSS feed")
            end
        else
            print("Failed to fetch RSS feed. Status: " .. tostring(response.status))
        end
    end)
end

-- Configuration update handler
util.data_mapper{
    rss_url = function(val)
        rss_url = val
        last_update = 0  -- Force immediate update
    end,
    scroll_speed = function(val)
        scroll_speed = val
    end,
    text_size = function(val)
        text_size = val
        font = resource.load_font("silkscreen.ttf", text_size)
    end,
    bg_color_r = function(val)
        bg_color.r = val
    end,
    bg_color_g = function(val)
        bg_color.g = val
    end,
    bg_color_b = function(val)
        bg_color.b = val
    end,
    bg_alpha = function(val)
        bg_alpha = val
    end,
    text_color_r = function(val)
        text_color.r = val
    end,
    text_color_g = function(val)
        text_color.g = val
    end,
    text_color_b = function(val)
        text_color.b = val
    end,
    ticker_height = function(val)
        ticker_height = val
    end,
    update_interval = function(val)
        update_interval = val
    end,
    separator = function(val)
        separator = val
        -- Rebuild ticker text with new separator
        if #news_items > 0 then
            local text_parts = {}
            for _, item in ipairs(news_items) do
                table.insert(text_parts, item.title)
            end
            ticker_text = table.concat(text_parts, separator)
            ticker_text = ticker_text .. separator .. ticker_text
        end
    end,
    position = function(val)
        position = val
    end,
    overlap = function(val)
        overlap = val
    end,
}

-- Initialize
function node.render()
    -- Initialize font if not loaded
    if not font then
        font = resource.load_font("silkscreen.ttf", text_size)
    end

    -- Update RSS feed periodically
    local now = sys.now()
    if now - last_update > update_interval then
        update_news()
        last_update = now
    end

    -- Calculate ticker position based on configuration
    local ticker_y
    if position == "top" then
        ticker_y = 0
    else
        ticker_y = HEIGHT - ticker_height
    end

    -- Render ticker at configured position
    gl.pushMatrix()
    gl.translate(0, ticker_y)

    -- Draw ticker background
    resource.create_colored_texture(
        bg_color.r/255, bg_color.g/255, bg_color.b/255, bg_alpha
    ):draw(0, 0, WIDTH, ticker_height)

    -- Ensure we have text to display
    local display_text = ticker_text
    if display_text == "" or #display_text == 0 then
        display_text = "Waiting for RSS feed..."
    end

    -- Calculate text width
    local text_width = font:width(display_text)

    -- Update scroll position
    scroll_offset = scroll_offset + scroll_speed * (sys.now() - (sys.now() - sys.frame_duration()))

    -- Reset scroll when text has scrolled completely
    if scroll_offset > text_width / 2 then
        scroll_offset = 0
    end

    -- Draw scrolling text
    local x_pos = WIDTH - scroll_offset
    font:write(x_pos, (ticker_height - text_size) / 2, display_text,
               text_size, text_color.r/255, text_color.g/255, text_color.b/255, 1)

    gl.popMatrix()
end
