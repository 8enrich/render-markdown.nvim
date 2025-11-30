local Base = require('render-markdown.render.base')
local list = require('render-markdown.lib.list')
local str = require('render-markdown.lib.str')
local ts = require('render-markdown.core.ts')
local env = require('render-markdown.lib.env')

---@class render.md.quote.Data
---@field callout? render.md.request.callout.Value
---@field level integer
---@field icon string
---@field highlight string
---@field repeat_linebreak? boolean
---@field margin number

---@class render.md.render.Quote: render.md.Render
---@field private config render.md.quote.Config
---@field private data render.md.quote.Data
local Render = setmetatable({}, Base)
Render.__index = Render

---@protected
---@return boolean
function Render:setup()
    self.config = self.context.config.quote
    if not self.config.enabled then
        return false
    end
    local level = self.node:level_in('block_quote', 'section')
    local callout = self.context.callout:get(self.node)
    local config = callout and callout.config
    local icon = config and config.quote_icon or self.config.icon
    local highlight = config and config.highlight or self.config.highlight
    local margin = self:get_number(self.config.left_margin)
    self.data = {
        callout = callout,
        level = level,
        icon = assert(list.cycle(icon, level)),
        highlight = assert(list.cycle(highlight, level)),
        repeat_linebreak = self.config.repeat_linebreak or nil,
        margin = margin
    }
    return true
end

---@private
---@param value render.md.paragraph.Number
---@return number
function Render:get_number(value)
    if type(value) == 'function' then
        return value({ text = self.node.text })
    else
        return value
    end
end

---@protected
function Render:run()
    local widths = self.node:widths()
    local width = math.max(vim.fn.max(widths), self.config.min_width)
    local margin = env.win.percent(self.context.win, self.data.margin, width)
    self:padding(self.node.start_row, self.node.end_row - 1, margin)
    self:callout()
    self:markers()
end

---@private
---@param start_row integer
---@param end_row integer
---@param amount integer
function Render:padding(start_row, end_row, amount)
    local line = self:line():pad(amount):get()
    if #line == 0 then
        return
    end
    for row = start_row, end_row do
        self.marks:add(self.config, false, row, 0, {
            priority = 100,
            virt_text = line,
            virt_text_pos = 'inline',
        })
    end
end

---@private
function Render:callout()
    local callout = self.data.callout
    if not callout then
        return
    end
    local node = callout.node
    local config = callout.config
    local title = Render.title(node, config)
    self.marks:over(self.config, 'callout', node, {
        virt_text = { { title or config.rendered, config.highlight } },
        virt_text_pos = 'overlay',
        conceal = title and '' or nil,
    })
end

---@private
---@param node render.md.Node
---@param config render.md.callout.Config
---@return string?
function Render.title(node, config)
    -- https://help.obsidian.md/Editing+and+formatting/Callouts#Change+the+title
    local content = node:parent('inline')
    if content then
        local line = str.split(content.text, '\n', true)[1]
        local prefix = config.raw:lower()
        if #line > #prefix and vim.startswith(line:lower(), prefix) then
            local icon = str.split(config.rendered, ' ', true)[1]
            local title = vim.trim(line:sub(#prefix + 1))
            return icon .. ' ' .. title
        end
    end
    return nil
end

---@private
function Render:markers()
    local query = ts.parse(
        'markdown',
        [[
            (block_quote_marker) @marker
            (block_continuation) @continuation
        ]]
    )
    self.context.view:nodes(self.node:get(), query, function(capture, node)
        if capture == 'marker' then
            -- marker nodes are a single '>' at the start of a block quote
            -- overlay the only range if it is at the current level
            if node:level_in('block_quote', 'section') == self.data.level then
                self:marker(node, 1)
            end
        elseif capture == 'continuation' then
            -- continuation nodes are a group of '>'s inside a block quote
            -- overlay the range of the one at the current level if it exists
            self:marker(node, self.data.level)
        else
            error(('unhandled quote capture: %s'):format(capture))
        end
    end)
end

---@private
---@param node render.md.Node
---@param index integer
function Render:marker(node, index)
    local range = node:find('>')[index]
    if not range then
        return
    end
    self.marks:add(self.config, 'quote', range[1], range[2], {
        end_row = range[3],
        end_col = range[4],
        virt_text = { { self.data.icon, self.data.highlight } },
        virt_text_pos = 'overlay',
        virt_text_repeat_linebreak = self.data.repeat_linebreak,
    })
end

return Render
