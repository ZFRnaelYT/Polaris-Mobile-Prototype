local function newEngine(adapter,clock,publish)
    local self={running=false,closed=false,tasks={},sequence={},active=nil,steps=0,prefix="POLARIS : ",since=0}
    local function status(message,severity) if severity or self.lastStatus~=message then self.lastStatus=message;publish(message,severity) end end
    local function invoke(name,...) return pcall(adapter[name],...) end
    function self:add(id,label,priority,interval,background)
        local e={id=id,label=label,priority=priority,interval=interval,background=background or false,
            enabled=false,nextAt=0,failures=0,state="desactivee",reason=""}
        self.tasks[id]=e;table.insert(self.sequence,e)
    end
    function self:release(transfer)
        if not self.active then return true end
        local previous=self.active;self.active=nil
        local ok,result=invoke("suspend",previous.id,transfer)
        previous.state=previous.enabled and "suspendue" or "desactivee"
        if not ok or result==false then
            self.running=false;previous.state="erreur";status("Arret impossible : "..tostring(result),"erreur");return false
        end
        return true
    end
    function self:enable(id,value)
        local e=assert(self.tasks[id],id)
        e.enabled=value;e.failures=0;e.nextAt=0;e.reason="";e.state=value and "en attente" or "desactivee"
        if adapter.setEnabled then adapter.setEnabled(id,value) end
        if not value and self.active==e then self:release(false) end
    end
    function self:start()
        if not self.closed then
            if adapter.resumeRequests then adapter.resumeRequests() end
            self.running=true;status("Demarre")
        end
    end
    function self:pause()
        self.running=false
        if adapter.pauseRequests then adapter.pauseRequests() end
        if self:release(false) then
            if adapter.recover and not adapter.recover() then status("Pause : sortie libre requise") else status("Pause") end
        end
    end
    function self:close(force)
        self:pause()
        if not force and adapter.canClose and not adapter.canClose() then return false end
        for _,e in ipairs(self.sequence) do if e.enabled then self:enable(e.id,false) end end
        self.closed=true;return true
    end
    function self:fail(e,reason)
        e.failures=e.failures+1;e.reason=tostring(reason);e.state="erreur"
        -- A movement refusal is never retried by teleport spam.
        e.enabled=false
        if adapter.setEnabled then adapter.setEnabled(e.id,false) end
        if self.active==e then self:release(false) end
        e.state="erreur"
        status(e.label.." : "..e.reason,"erreur")
    end
    function self:runStep(e,now)
        local ok,done=invoke("step",e.id,now)
        self.steps=self.steps+1
        if not ok then self:fail(e,done);return end
        local s=adapter.taskStatus and adapter.taskStatus(e.id)
        if s then e.state,e.reason=s.state,s.reason end
        if done then
            e.nextAt=now+e.interval
            if self.active==e then self:release(false) end
        end
        if s and s.state=="terminee" then self:enable(e.id,false);e.state="terminee" end
    end
    function self:tick()
        if not self.running or self.closed then return end
        local now=clock();local ready={};local selected
        for _,e in ipairs(self.sequence) do
            if e.enabled and now>=e.nextAt then
                local ok,value=invoke("ready",e.id,now)
                if not ok then self:fail(e,value)
                elseif value then
                    ready[e.id]=true
                    if e.background then self:runStep(e,now)
                    elseif not selected or e.priority>selected.priority then selected=e end
                elseif e~=self.active and e.state~="erreur" and e.state~="terminee" then e.state="en attente" end
            end
        end
        if not self.running then return end
        local active=self.active
        -- Equal-priority tasks do not bounce; a task retains its target for >=1.5 s.
        if active and active.enabled and ready[active.id] and selected~=active and
            (not selected or selected.priority<=active.priority or now-self.since<1.5) then selected=active end
        if selected~=active then
            if not self:release(selected~=nil) then return end
            self.active=selected;self.since=now
        end
        if selected then self:runStep(selected,now);if selected.state~="erreur" then status(self.prefix..selected.label) end
        else status("En attente / aucune cible disponible") end
    end
    return self
end
