local dap = require("dap")
local listener_id = "dapui_state"

local M = {}

local UIState = {}

function UIState:new()
  local state = {
    awaiting_requests = 0,
    variables = {},
    monitored_vars = {},
    scopes = {},
    frames = {},
    threads = {},
    current_frame = {},
    listeners = {}
  }
  setmetatable(state, self)
  self.__index = self
  return state
end

function UIState:refresh(session)
  self.current_frame = session.current_frame
  if not self.current_frame then
    return
  end
  self:refresh_scopes(session)
  self:refresh_threads(session)
end

function UIState:receiver(callback)
  local session = dap.session()
  return function(...)
    callback(...)
    for _, receiver in pairs(self.listeners) do
      receiver(session)
    end
  end
end

function UIState:refresh_scopes(session)
  session:request(
    "scopes",
    {
      frameId = self.current_frame.id
    },
    self:receiver(
      function(err, response)
        if err then
          return
        end
        self.scopes = response.scopes
        local scope_vars = {}
        for _, scope in pairs(response.scopes) do
          scope_vars[#scope_vars + 1] = scope.variablesReference
        end
        vim.schedule(function ()
          self:refresh_variables(session, vim.list_extend(scope_vars, self.monitored_vars))
        end)
      end
    )
  )
end

function UIState:refresh_variables(session, variables)
  for ref, _ in pairs(variables) do
    session:request(
      "variables",
      {variablesReference = ref},
      self:receiver(
        function(err, response)
          print(vim.inspect({err, response}))
          if err then
            return
          end
          self.variables[ref] = response.variables
        end
      )
    )
  end
end

function UIState:refresh_threads(session)
  session:request(
    "threads",
    nil,
    self:receiver(
      function(response, err)
        if err then
          return
        end
        for _, thread in pairs(response.threads) do
          self.threads[thread.id] = thread
        end
        self:refresh_frames(session)
      end
    )
  )
end

function UIState:refresh_frames(session)
  for thread_id, _ in pairs(self.threads) do
    session:request(
      "stackTrace",
      {threadId = thread_id},
      self:receiver(
        function(response, err)
          if err then
            return
          end
          self.frames[thread_id] = response.stackFrames
        end
      )
    )
  end
end

local ui_state = UIState:new()

function M.setup()
  dap.listeners.after.stackTrace[listener_id] = function(session)
    ui_state:refresh(session)
  end

  dap.listeners.after.event_terminated[listener_id] = function()
    ui_state = UIState:new()
  end
end

function M.monitor(var_ref)
  ui_state.monitored_vars[var_ref] = (ui_state.monitored_vars[var_ref] or 0) + 1
  ui_state:refresh(dap.session())
end

function M.stop_monitor(var_ref)
  ui_state.monitored_vars[var_ref] = ui_state.monitored_vars[var_ref] - 1
  if ui_state.monitored_vars[var_ref] then
    ui_state.monitored_vars[var_ref] = nil
  end
end

function M.scopes()
  return ui_state.scopes or {}
end

function M.variables(ref)
  return ui_state.variables[ref] or {}
end

function M.threads()
  return ui_state.threads or {}
end

function M.frames(thread_id)
  return ui_state.frames[thread_id] or {}
end

function M.on_refresh(callback)
  ui_state.listeners[#ui_state.listeners + 1] = callback
end

function M.refresh()
  ui_state:refresh(dap.session())
end

return M
