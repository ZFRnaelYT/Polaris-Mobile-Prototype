local function newCharacterController(player,runService)
    local self={ghost=false,flying=false,closed=false}
    local current,parts,collision,visual=nil,{}, {},{}
    local flightLink,charLink,highlight,attachment,hover,autoRotate
    local function restore(values,key)
        for obj,value in pairs(values) do pcall(function() obj[key]=value end) end
        return {}
    end
    local function cosmetic(part)
        if self.ghost and not part:FindFirstAncestorOfClass("Tool") and part.Name~="HumanoidRootPart" then
            if visual[part]==nil then visual[part]=part.LocalTransparencyModifier end
            part.LocalTransparencyModifier=math.max(visual[part],0.6)
        end
    end
    local function add(obj)
        if obj:IsA("BasePart") then
            parts[obj]=true;cosmetic(obj)
            if self.flying then if collision[obj]==nil then collision[obj]=obj.CanCollide end;obj.CanCollide=false end
        end
    end
    function self:setFlying(value)
        if self.closed then return end
        self.flying=value
        if not value then
            if flightLink then flightLink:Disconnect();flightLink=nil end
            if hover then hover:Destroy();hover=nil end
            if attachment then attachment:Destroy();attachment=nil end
            collision=restore(collision,"CanCollide")
            local h=current and current:FindFirstChildOfClass("Humanoid")
            if h and autoRotate~=nil then h.AutoRotate=autoRotate end
            autoRotate=nil;return
        end
        if flightLink then return end
        local root=current and current:FindFirstChild("HumanoidRootPart")
        local h=current and current:FindFirstChildOfClass("Humanoid")
        assert(root and h and h.Health>0 and not root.Anchored,"Personnage indisponible/ancre")
        autoRotate=h.AutoRotate;h.AutoRotate=false
        attachment=Instance.new("Attachment");attachment.Name="PolarisFlightAttachment";attachment.Parent=root
        hover=Instance.new("LinearVelocity");hover.Name="PolarisFlightHover";hover.Attachment0=attachment
        hover.RelativeTo=Enum.ActuatorRelativeTo.World;hover.VectorVelocity=Vector3.zero
        hover.ForceLimitsEnabled=false;hover.Parent=root
        local function apply()
            for part in pairs(parts) do
                if part.Parent and part:IsDescendantOf(current) then
                    if collision[part]==nil then collision[part]=part.CanCollide end
                    part.CanCollide=false
                else
                    if collision[part]~=nil then pcall(function() part.CanCollide=collision[part] end) end
                    collision[part]=nil;parts[part]=nil
                end
            end
            if root.Parent then root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero end
        end
        apply();flightLink=runService.PreSimulation:Connect(apply)
    end
    function self:setGhost(value)
        self.ghost=value
        if highlight then highlight:Destroy();highlight=nil end
        if not value then visual=restore(visual,"LocalTransparencyModifier");return end
        for part in pairs(parts) do cosmetic(part) end
        if current then
            highlight=Instance.new("Highlight");highlight.Name="PolarisPhantom";highlight.Adornee=current
            highlight.FillColor=Color3.fromRGB(119,202,255);highlight.OutlineColor=Color3.fromRGB(216,243,255)
            highlight.FillTransparency=0.82;highlight.OutlineTransparency=0.35
            highlight.DepthMode=Enum.HighlightDepthMode.Occluded;highlight.Parent=current
        end
    end
    local function attach(c)
        self:setFlying(false);visual=restore(visual,"LocalTransparencyModifier")
        if charLink then charLink:Disconnect() end
        if highlight then highlight:Destroy();highlight=nil end
        current=c;parts={}
        if c then for _,obj in ipairs(c:GetDescendants()) do add(obj) end;charLink=c.DescendantAdded:Connect(add) end
        self:setGhost(self.ghost)
    end
    local added=player.CharacterAdded:Connect(attach)
    local removed=player.CharacterRemoving:Connect(function() attach(nil) end)
    attach(player.Character)
    function self:close()
        if self.closed then return end
        self:setFlying(false);self:setGhost(false)
        self.closed=true;if charLink then charLink:Disconnect() end;added:Disconnect();removed:Disconnect()
    end
    return self
end

local function newMovement(player,services,config,report,clock)
    clock=clock or os.clock
    local self={root=nil,goal=nil,raw=nil,tween=nil,blocked=nil,closed=false}
    local controller=services.characterController
    local deadline,lastProgress,best,lastPosition=0,0,0,nil
    local speedUsed=0
    local corrections=0
    local function character()
        local c=player.Character;local h=c and c:FindFirstChildOfClass("Humanoid")
        local r=c and c:FindFirstChild("HumanoidRootPart")
        if c and h and r and h.Health>0 and not r.Anchored then return c,h,r end
    end
    function self:free(cf)
        local c,_,r=character();if not c then return true end
        local bcf,size=c:GetBoundingBox()
        -- Bound the query, rather than silently shrinking a large avatar.
        if size.X>40 or size.Y>40 or size.Z>40 then return false end
        local volume=cf*r.CFrame:ToObjectSpace(bcf)
        local params=OverlapParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={c};params.MaxParts=0;params.RespectCanCollide=true
        for _,part in ipairs(workspace:GetPartBoundsInBox(volume,size,params)) do if part.CanCollide then return false end end
        -- Conservative voxel check also rejects terrain occupancy; only on arrival/stop.
        local terrain=workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            local half=size/2
            local region=Region3.new(volume.Position-half,volume.Position+half):ExpandToGrid(4)
            local materials,occupancy=terrain:ReadVoxels(region,4)
            for x,plane in ipairs(occupancy) do for y,row in ipairs(plane) do for z,value in ipairs(row) do
                if value>0.25 and materials[x][y][z]~=Enum.Material.Water then return false end
            end end end
        end
        return true
    end
    function self:exit(cf)
        if self:free(cf) then return cf end
        local max=config.exitRadius or 10
        for radius=2,max,2 do
            for _,dir in ipairs({Vector3.new(0,1,0),Vector3.new(1,0,0),Vector3.new(-1,0,0),
                Vector3.new(0,0,1),Vector3.new(0,0,-1),Vector3.new(0,-1,0)}) do
                local candidate=cf+dir*radius
                if self:free(candidate) then return candidate end
            end
        end
    end
    local function cancel() if self.tween then self.tween:Cancel();self.tween=nil end end
    function self:handoff()
        cancel();self.goal=nil;self.raw=nil
        -- Keep ghost/hover while the next task selects its destination.
        return true
    end
    function self:stop(retry)
        if self.blocked and not retry then return false end
        cancel();self.goal=nil;self.raw=nil
        local _,h,r=character()
        if r and controller.flying then
            local safe=self:exit(r.CFrame)
            if not safe then
                self.blocked="Aucune sortie libre a moins de "..(config.exitRadius or 10).." studs. Vol suspendu; collisions non restaurees."
                report(self.blocked);return false
            end
            r.CFrame=safe
        end
        controller:setFlying(false)
        if r then r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero end
        if h then h:Move(Vector3.zero) end
        self.root=nil;self.blocked=nil;return true
    end
    function self:moveTo(cf,tolerance)
        assert(not self.closed,"Mouvement ferme")
        if self.blocked then error(self.blocked) end
        local _,h,r=character()
        if not r then self:stop();return false end
        if h.SeatPart and h.SeatPart:IsA("VehicleSeat") then
            if not self:stop() then error(self.blocked) end
            h.Sit=false;return false
        end
        local now=clock()
        local speed=math.clamp(tonumber(config.speed) or 220,80,320)
        if speed==speedUsed and self.root==r and self.raw and (self.raw.Position-cf.Position).Magnitude<4 then
            local remaining=(r.Position-self.goal.Position).Magnitude
            if remaining<=math.min(tolerance or 3,1.5) then
                if not self:stop() then error(self.blocked) end
                return true
            end
            if remaining<best-0.75 then best=remaining;lastProgress=now end
            if lastPosition and (r.Position-lastPosition).Magnitude>speed*0.6+8 and remaining>best+5 then corrections=corrections+1 end
            lastPosition=r.Position
            if corrections>=2 or now-lastProgress>5 or now>deadline then
                local reason=corrections>=2 and "Corrections serveur suspectees" or "Progression non confirmee (serveur/physique)"
                self:stop();error(reason.." : tache arretee, aucun forcage du trajet")
            end
            return false
        end
        self:handoff()
        local goal=self:exit(cf)
        if not goal then self:stop();error("Destination occupee, aucune sortie proche") end
        self.root,self.raw,self.goal=r,cf,goal
        local distance=(r.Position-goal.Position).Magnitude
        if distance<1.5 then return self:stop() end
        controller:setFlying(true)
        speedUsed=speed
        deadline=now+distance/speed+12;lastProgress=now;best=distance;lastPosition=r.Position;corrections=0
        self.tween=services.TweenService:Create(r,TweenInfo.new(math.max(0.15,distance/speed),Enum.EasingStyle.Linear),{CFrame=goal})
        self.tween:Play();return false
    end
    function self:close(force)
        if self.closed then return true end
        local safe
        if force then local ok,value=pcall(self.stop,self);safe=ok and value else safe=self:stop() end
        if not safe and not force then return false end
        self.closed=true
        if safe then return true end
        -- The UI and all tasks close immediately. Only collision recovery survives
        -- an impossible exit; no target selection, attacks, requests or tween remain.
        cancel();self.goal=nil;self.raw=nil;self.deferred=true
        controller:setGhost(false)
        local oldCharacter=player.Character
        local root=oldCharacter and oldCharacter:FindFirstChild("HumanoidRootPart")
        local token=Instance.new("BindableEvent");token.Name="PolarisSafetyCleanup"
        token:SetAttribute("PolarisBlocked",true);token.Parent=player:FindFirstChild("PlayerGui")
        local cleanupLinks={};local finished,busy=false,false
        local function finish()
            if finished then return end
            finished=true;self.deferred=false
            for _,link in ipairs(cleanupLinks) do link:Disconnect() end
            controller:close();token:SetAttribute("PolarisBlocked",false);token:Destroy()
        end
        local function recover(explicit)
            if finished or busy then return end
            if player.Character~=oldCharacter or not root or not root.Parent then finish();return end
            local h=oldCharacter:FindFirstChildOfClass("Humanoid")
            if not h or h.Health<=0 then finish();return end
            busy=true
            local ok,result=pcall(function()
                if not explicit and not self:free(root.CFrame) then return false end
                return self:stop(true)
            end)
            busy=false
            if ok and result then finish() end
        end
        cleanupLinks[#cleanupLinks+1]=token.Event:Connect(function() recover(true) end)
        cleanupLinks[#cleanupLinks+1]=player.CharacterRemoving:Connect(function(c) if c==oldCharacter then finish() end end)
        if root then
            local lastCheck=-math.huge
            cleanupLinks[#cleanupLinks+1]=root:GetPropertyChangedSignal("CFrame"):Connect(function()
                local now=clock();if now-lastCheck>=1 then lastCheck=now;recover(false) end
            end)
            cleanupLinks[#cleanupLinks+1]=root.Destroying:Connect(finish)
        end
        local began,lastPoll=clock(),-math.huge
        local probe
        probe=services.Run.PreSimulation:Connect(function()
            local now=clock()
            if now-began>=10 then probe:Disconnect();return end
            if now-lastPoll>=.5 then lastPoll=now;recover(false) end
        end)
        cleanupLinks[#cleanupLinks+1]=probe
        warn("[Polaris] Menu ferme et actions arretees. Aucune sortie libre proche : protection des collisions conservee jusqu'a une position libre ou au respawn. Aucun trajet ne continue.")
        return true
    end
    return self
end
