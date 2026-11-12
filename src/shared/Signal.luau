--!strict
-- Minimal signal implementation (no BindableEvent, so tables pass by reference).

local Signal = {}
Signal.__index = Signal

export type Connection = { Connected: boolean, Disconnect: (self: Connection) -> () }
export type Signal = typeof(setmetatable({} :: { _handlers: { any } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ()): Connection
	local handlers = self._handlers
	local conn = { Connected = true, _fn = fn }
	function conn.Disconnect(c)
		if not c.Connected then
			return
		end
		c.Connected = false
		local idx = table.find(handlers, c)
		if idx then
			table.remove(handlers, idx)
		end
	end
	table.insert(handlers, conn)
	return conn :: any
end

function Signal.Once(self: Signal, fn: (...any) -> ()): Connection
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal.Fire(self: Signal, ...: any)
	for _, conn in ipairs(table.clone(self._handlers)) do
		if conn.Connected then
			task.spawn(conn._fn, ...)
		end
	end
end

function Signal.Wait(self: Signal): ...any
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.Destroy(self: Signal)
	table.clear(self._handlers)
end

return Signal
