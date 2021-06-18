local dap = require("dap")
local config = require("dapui.config")
local listener_id = "dapui_state"

local M = {}

local UIState = {}

function UIState:new()
  local state = {
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
  self:refresh_scopes(session)
  self:refresh_monitored_vars(session)
  self:refresh_threads(session)
  for _, callback in pairs(self.listeners) do
    callback()
  end
end

function UIState:refresh_scopes(session)
  session:request(
    "scopes",
    {
      frameId = self.current_frame.id
    },
    function(err, response)
      if err then
        return
      end
      self.scopes = response.scopes
      for _, scope in pairs(response.scopes) do
        self.variables[scope.variablesReference] = scope.variables
      end
    end
  )
end

function UIState:refresh_monitored_vars(session)
  for ref, _ in pairs(self.monitored_vars) do
    session:request(
      "evaluate",
      {variablesReference = ref},
      function(err, response)
        if err then
          return
        end
        self.variables[ref] = response.variables
      end
    )
  end
end

function UIState:refresh_threads(session)
  session:request(
    "threads",
    nil,
    function(response, err)
      if err then
        return
      end
      for _, thread in pairs(response.threads) do
        self.threads[thread.id] = thread
      end
    end
  )
end

function UIState:refresh_frames(session)
  for thread_id, _ in pairs(self.threads) do
    session:request(
      "stackTrace",
      {threadId = thread_id},
      function(response, err)
        if err then
          return
        end
        self.frames[thread_id] = response.stackFrames
      end
    )
  end
end

local ui_state = UIState:new()

function M.setup()
  dap.listeners.after.event_stopped[listener_id] = function(session)
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
