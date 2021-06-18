local M = {}
local api = vim.api
local listener_id = "dapui_stack"

local state = require("dapui.state")
local config = require("dapui.config")

local Element = {}

local function reset_state()
  Element.render_receivers = {}
  Element.line_frame_map = {}
end

reset_state()

function Element:render_frames(frames, render_state, indent)
  local visible =
    vim.tbl_filter(
    function(frame)
      return frame.presentationHint ~= "subtle"
    end,
    frames or {}
  )
  for _, frame in pairs(visible) do
    local line_no = render_state:length() + 1
    self.line_frame_map[line_no] = frame

    local new_line = string.rep(" ", indent)

    render_state:add_match("DapUIFrameName", line_no, #new_line + 1, #frame.name)
    new_line = new_line .. frame.name .. " "

    if frame.source ~= nil then
      local file_name = frame.source.name or frame.source.path or "<unknown>"
      local source_name = require("dapui.util").pretty_name(file_name)
      render_state:add_match("DapUISource", line_no, #new_line + 1, #source_name)
      new_line = new_line .. source_name
    end

    if frame.line ~= nil then
      new_line = new_line .. ":"
      render_state:add_match("DapUILineNumber", line_no, #new_line + 1, #tostring(frame.line))
      new_line = new_line .. frame.line
    end

    render_state:add_line(new_line)
  end
end

function Element:render_threads(match_group, threads, render_state)
  local ordered_keys = {}

  for k in pairs(threads) do
    table.insert(ordered_keys, k)
  end
  table.sort(ordered_keys)

  for i = 1, #ordered_keys, 1 do
    local thread = threads[ordered_keys[i]]
    render_state:add_match(match_group, render_state:length() + 1, 1, #thread.name)
    render_state:add_line(thread.name .. ":")
    self:render_frames(state.frames(thread.id), render_state, config.windows().indent)
    if i < #ordered_keys then
      render_state:add_line()
    end
  end
end

function Element:fill_render_state(render_state, stopped_thread)
  if not state.threads() then
    return
  end
  local secondary_threads = {}
  for k, thread in pairs(state.threads()) do
    if thread.id ~= stopped_thread then
      secondary_threads[k] = thread
    end
  end
  self:render_threads("DapUIStoppedThread", {self.threads[stopped_thread]}, render_state)
  render_state:add_line()
  self:render_threads("DapUIThread", secondary_threads, render_state)
end

function Element:render(session)
  if vim.tbl_isempty(self.render_receivers) then
    return
  end
  local render_state = require("dapui.render").init_state()
  self:fill_render_state(render_state, session.stopped_thread_id)
  for buf, reciever in pairs(self.render_receivers) do
    api.nvim_buf_set_option(buf, "modifiable", true)
    reciever(render_state)
    api.nvim_buf_set_option(buf, "modifiable", false)
  end
end

function M.open_frame()
  local cur_line = vim.fn.line(".")
  local current_frame = Element.line_frame_map[cur_line]
  if not current_frame then
    return
  end
  local session = require("dap").session()
  require("dapui.util").jump_to_frame(current_frame, session)
end

function M.setup()
  state.on_refresh(Element.render)
end

M.name = "DAP Stacks"

function M.on_open(buf, render_receiver)
  api.nvim_buf_set_option(buf, "filetype", "dapui_stacks")
  api.nvim_buf_set_option(buf, "modifiable", false)
  pcall(api.nvim_buf_set_name, buf, M.name)
  require("dapui.util").apply_mapping(
    config.mappings().open,
    "<Cmd>lua require('dapui.elements.stacks').open_frame()<CR>",
    buf
  )
  Element.render_receivers[buf] = render_receiver
  Element:render(require("dap").session())
  local dap = require("dap")
  dap.listeners.before.event_terminated[listener_id] = function()
    reset_state()
  end
end

function M.on_close(info)
  Element.render_receivers[info.buffer] = nil
end

return M
