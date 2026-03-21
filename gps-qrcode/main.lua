local ethosVersion = system.getVersion()
local runningInSimulator = ethosVersion.simulation

local progress = nil
local progressValue = 0

local icon = lcd.loadMask("form.png")
system.compile("lib/init.lua")
local L = assert(loadfile("lib/init.luac", "b")({
    -- those parameters are accessible under the L namespace
    isUTF8Compatible=tonumber(ethosVersion.major .. ethosVersion.minor) >= 17,
}, "L")) -- here "L" is the namespace used in the lib files
local __ = L.translate
local log = L.log
local function create()
    local w, h = lcd.getWindowSize()

    local data = {
        job=nil,
        bitmap=nil,
        qr=nil,
        url=nil,
        text="",
        color=lcd.RGB(100, 50, 50),
        count=1,
        source=nil,
        sensor=nil,
        switch=nil,
        file=nil,
        number=5
    }

    -- local line = form.addLine("TextDialog example")
    -- form.addButton(line, nil, {
    --     text="Press here",
    --     press=function()
    --         form.openDialog({
    --             width=w,
    --             title="Help",
    --             message="Increase D, P, I in order until each wobbles,\nthen back off.\nSet F for a good response in full\nstick flips and rolls.\nIf necessary, tweak P:D ratio\nto set response damping to your liking. Increase O until wobbles occur when jabbing elevator at full collective, back off a bit. Increase B if you want sharper response.\nIncrease D, P, I in order until each wobbles, then back off.\nSet F for a good response in full stick flips and rolls.\nIf necessary, tweak P:D ratio to set response damping to your liking.\nIncrease O until wobbles occur when jabbing elevator at full collective, back off a bit.\nIncrease B if you want sharper response.",
    --             buttons={{label="OK", action=function() return true end}},
    --             wakeup=function()
    --                     lcd.invalidate()
    --                 end,
    --             paint=function()
    --                     local w, h = lcd.getWindowSize()
    --                     local left = w * 0.75 - 10
    --                     local top = 10
    --                     w = w / 4
    --                     h = h / 4
    --                     lcd.drawLine(left, top + h/2, left+w, top + h/2)
    --                     lcd.color(YELLOW)
    --                     for i = 0,w do
    --                         local val = math.sin(i*math.pi/(w/2))
    --                         lcd.drawPoint(left + i, top + val*h/2+h/2)
    --                     end

    --                 end,
    --             options=TEXT_LEFT
    --         })
    --     end})

    -- local line = form.addLine("ProgressDialog example")
    -- form.addTextButton(line, nil, "Press here",
    --   function()
    --     progress = form.openProgressDialog("Progress", "Doing some long job ...")
    --     -- progress:closeAllowed(false)
    --     progress:closeHandler(function() print("Progress dialog closed") end)
    --     progressValue = 0
    --   end)

    local line = form.addLine("GPS Source")
    form.addSensorField(line, nil, function() return data.source end, function(newValue) data.source = newValue end)
    local line = form.addLine("Generate a new QRCODE")
    form.addButton(line, nil, {
        text="Button 1",
        press=function()
            print("Button 1 pressed")
            data.bitmap = nil
            data.qr = nil
            data.x0 = lcd.getWindowSize() / 2
            data.y0 = form.height() + 10
            data.job = {
                url = "https://www.google.com/maps?q=44.714578,-0.716957&t=h",
                step = 1,
                mask = 0,
                best_score = 1e9,
                best_matrix = nil
            }
            end
    })
    return data
end

local function wakeup(widget)
    if widget.job then
        local step = widget.job.step
        log("Processing QR code, step " .. widget.job.step)
        L.QR.process_qr_step(widget)
        if step == 6 then
            log("QR code generation completed")
            lcd.invalidate()
        end
    end
    if progress then
        progressValue = progressValue + 1
        if progressValue > 100 then
            progress:close()
        else
            progress:value(progressValue)
        end
    end
end

local function event(data, category, value, x, y)
    print("Event received:", category, value, x, y)
    return false
end

local function drawQRCodeFast(qr, x0, y0)
    local scale = qr.scale
    local quiet = qr.quiet

    for y = 1, qr.size do
        local py = y0 + (quiet + y - 1) * scale
        local runs = qr.rows[y]

        for i = 1, #runs do
            local run = runs[i]
            lcd.drawFilledRectangle(
                x0 + (quiet + run.x - 1) * scale,
                py,
                run.width * scale,
                scale
            )
        end
    end
end

local function drawQRBackground(qr, x0, y0)
    local margin = qr.scale * 2

    lcd.color(WHITE)
    lcd.drawFilledRectangle(
        x0 - margin,
        y0 - margin,
        qr.width + margin * 2,
        qr.height + margin * 2
    )
    lcd.color(BLACK)
end

local function paint(widget)
    log("Paint called")
    if widget.qr then
        drawQRBackground(widget.qr, widget.x0, widget.y0)
        drawQRCodeFast(widget.qr, widget.x0, widget.y0)
    end
end
local function init()
    system.registerSystemTool({name="fggpsqr", icon=icon, create=create, wakeup=wakeup, paint=paint,event=event})
end

return {init=init}
