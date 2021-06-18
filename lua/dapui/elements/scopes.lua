local M = {}

local Element = {}
local state = require("dapui.state")
local config = require("dapui.config")

local function reset_state()
  Element.render_receiver = {}
  Element.line_variable_map = {}
  Element.expanded_references = {}
end

reset_state()

local function var_from_ref_path(ref_path)
  local var_path_elems = vim.split(ref_path, "/")
  return tonumber(var_path_elems[#var_path_elems])
end

function Element:reference_prefix(ref_path)
  if vim.endswith(ref_path, "/0") then
    return " "
  end
  return config.icons()[self.expanded_references[ref_path] and "expanded" or "collapsed"]
end

function Element:render_variables(ref_path, render_state, indent, expanded)
  expanded[ref_path] = true
  local var_path_elems = vim.split(ref_path, "/")
  local var_ref = tonumber(var_path_elems[#var_path_elems])
  for _, variable in pairs(state.variables(var_ref)) do
    local line_no = render_state:length() + 1
    local var_reference_path = ref_path .. "/" .. variable.variablesReference
    self.line_variable_map[line_no] = var_reference_path

    local new_line = string.rep(" ", indent)
    local prefix = self:reference_prefix(var_reference_path)
    render_state:add_match("DapUIDecoration", line_no, #new_line + 1, 1)
    new_line = new_line .. prefix .. " "

    render_state:add_match("DapUIVariable", line_no, #new_line + 1, #variable.name)
    new_line = new_line .. variable.name

    if #(variable.type or "") > 0 then
      new_line = new_line .. " "
      render_state:add_match("DapUIType", line_no, #new_line + 1, #variable.type)
      new_line = new_line .. variable.type
    end

    if #(variable.value or "") > 0 then
      new_line = new_line .. " = "
      local value_start = #new_line
      new_line = new_line .. variable.value

      for i, line in pairs(vim.split(new_line, "\n")) do
        if i > 1 then
          line = string.rep(" ", value_start - 2) .. line
        end
        render_state:add_line(line)
      end
    else
      render_state:add_line(new_line)
    end

    if self.expanded_references[var_reference_path] and not expanded[var_reference_path] then
      self:render_variables(var_reference_path, render_state, indent + config.windows().indent, expanded)
    end
  end
end

function Element:render_scopes(render_state)
  local expanded = {}
  for i, scope in pairs(state.scopes()) do
    render_state:add_match("DapUIScope", render_state:length() + 1, 1, #scope.name)
    render_state:add_line(scope.name .. ":")
    self:render_variables(tostring(scope.variablesReference), render_state, config().windows.indent, expanded)
    if i < #self.scopes then
      render_state:add_line()
    end
  end
end

function Element:render()
  if vim.tbl_isempty(self.render_receiver) then
    return
  end
  local render_state = require("dapui.render").init_state()
  self:render_scopes(render_state)
  for buf, reciever in pairs(self.render_receiver) do
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    reciever(render_state)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
  end
end

function M.toggle_reference()
  local line = vim.fn.line(".")
  local current_ref_path = Element.line_variable_map[line]
  if not current_ref_path then
    return
  end

  local session = require("dap").session()
  if not session then
    print("No active session to query")
    return
  end

  local current_ref = var_from_ref_path(current_ref_path)

  if Element.expanded_references[current_ref_path] then
    Element.expanded_references[current_ref_path] = nil
    state.stop_monitor(current_ref)
    Element:render()
  else
    Element.expanded_references[current_ref_path] = true
    state.monitor(current_ref)
  end
end

M.name = "DAP Scopes"

function M.on_open(buf, render_receiver)
  vim.api.nvim_buf_set_option(buf, "filetype", "dapui_scopes")
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  pcall(vim.api.nvim_buf_set_name, buf, M.name)
  Element.render_receiver[buf] = render_receiver
  require("dapui.util").apply_mapping(
    config.mappings().expand,
    "<Cmd>lua require('dapui.elements.scopes').toggle_reference()<CR>",
    buf
  )
  Element:render()
end

function M.on_close(info)
  Element.render_receiver[info.buffer] = nil
end

function M.setup()
  state.on_refresh(Element.render)
end

return M
