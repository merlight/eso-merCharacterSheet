local LogTimerBar = ZO_TimerBar:Subclass()
local log = math.log
merCharacterSheet.LogTimerBar = LogTimerBar


function LogTimerBar:New(control)
    local bar = ZO_TimerBar.New(self, control)
    local linearSetValue = bar.status.SetValue

    local function logSetValue(status, value)
        local min, max = status:GetMinMax()
        if value <= min then
            linearSetValue(status, min)
        elseif value >= max then
            linearSetValue(status, max)
        else
            local logval = log(value - min + 1)
            local logmax = log(max - min + 1)
            linearSetValue(status, min + (max - min) * logval / logmax)
        end
    end

    bar.status.SetValue = logSetValue
    return bar
end


function LogTimerBar:Stop()
    if not self:IsStarted() then
        return
    end
    ZO_TimerBar.Stop(self)
    if self.onStop then
        self:onStop()
    end
end
