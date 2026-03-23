local ethosVersion = system.getVersion()
local runningInSimulator = ethosVersion.simulation

local icon = lcd.loadMask("gps-qrcode.png")
system.compile("lib/init.lua")
local L = assert(loadfile("lib/init.luac", "b")({
    -- those parameters are accessible under the L namespace
    isUTF8Compatible=tonumber(ethosVersion.major .. ethosVersion.minor) >= 17,
    debug=runningInSimulator,
}, "L")) -- here "L" is the namespace used in the lib files
local __ = L.translate
local log = L.log
local debug = L.debug
local generateQRCodeButton
local generateQRCodeLabel
local progressDialog
local QR

local function create()
    QR = assert(loadfile("lib/ethos-qrencode.luac", "b")())
    local data = {
        job=nil,
        qr=nil,
        latSrc=nil,
        lonSrc=nil,
        lat=nil,
        lon=nil,
        qrlat=nil,
        qrlon=nil,
        enabled=false,
        error=nil,
    }
    local line = form.addLine("")
    local slots = form.getFieldSlots(line, {50, 0})
    generateQRCodeLabel = form.addStaticText(line, {x=10, y=slots[2].y, w=slots[2].x, h=slots[2].h}, __("waitingForGPSSignal"))
    generateQRCodeButton = form.addButton(line, slots[2], {
        text=__("generateQRCode"),
        press=function()
            progressDialog = form.openProgressDialog(__("progressTitle"), __("progressText"))
            progressDialog:closeAllowed(false)
            if generateQRCodeButton then generateQRCodeButton:enable(false) end
            data.qr = nil
            data.error = nil
            data.qrlat = data.lat
            data.qrlon = data.lon
            data.qrurl = string.format("https://www.google.com/maps?q=%.6f,%.6f&t=h", data.qrlat, data.qrlon)
            collectgarbage("collect")
            data.job = {
                str = data.qrurl,
                step = 1,
            }
            end
    })
    generateQRCodeButton:enable(false) -- will be enabled when we get GPS coordinates in wakeup()
    return data
end

local function cleanJob(widget)
    widget.job = nil
    collectgarbage("collect")
    lcd.invalidate()
    if progressDialog then progressDialog:close() progressDialog = nil end
end

local function wakeup(widget)
    if not widget then return end
    local lat, lon, refreshLabel
    if widget.latSrc == nil then
        widget.latSrc = system.getSource({name="GPS", options=OPTION_LATITUDE})
    end
     if widget.lonSrc == nil then
        widget.lonSrc = system.getSource({name="GPS", options=OPTION_LONGITUDE})
    end
    if widget.latSrc and widget.latSrc.value then
        lat = widget.latSrc:value()
        if (lat and not widget.lat) or (lat and widget.lat and (lat - widget.lat > 0.00001 or widget.lat - lat > 0.00001)) then
            refreshLabel = true
        end
        widget.lat = lat
    end
    if widget.lonSrc and widget.lonSrc.value then
        lon = widget.lonSrc:value()
        if (lon and not widget.lon) or (lon and widget.lon and (lon - widget.lon > 0.00001 or widget.lon - lon > 0.00001)) then
            refreshLabel = true
        end
        widget.lon = lon
    end
    if not widget.enabled and generateQRCodeButton and widget.lat and widget.lon and widget.lat ~= widget.qrlat and widget.lon ~= widget.qrlon then
        generateQRCodeButton:enable(true)
        widget.enabled = true
    elseif widget.enabled and generateQRCodeButton and (not widget.lat or not widget.lon or widget.lat == widget.qrlat and widget.lon == widget.qrlon) then
        generateQRCodeButton:enable(false)
        widget.enabled = false
    end
    if refreshLabel and generateQRCodeLabel then
        generateQRCodeLabel:value(string.format("Lat: %.6f, Lon: %.6f", widget.lat, widget.lon))
    end
    if widget.job then
        local now =os.clock()
        local step = widget.job.step
        if debug then log("Processing QR code, step " .. step) end
        if progressDialog then progressDialog:value(step * 10) end
        if step < 10 then
            local ok, msg = QR.process_qr_step(widget.job)
            if ok == nil then
                log("QR code processing error: " .. msg, L.ANSI_RED)
                widget.qrlat = nil
                widget.qrlon = nil
                widget.error = msg
                cleanJob(widget)
            end
        elseif step == 10 then
            widget.qr = QR.prepare_qr_render(widget.job.matrix,5)
            widget.job.step = step + 1
        elseif step == 11 then
            cleanJob(widget)
        end
        if debug then log("QR code processing step " .. step .. " took " .. (os.clock() - now)*1000 .. " ms") end
    end
end

-- Render the QR code. Call from your Ethos widget paint() function.
-- origin_x, origin_y: top-left pixel position of the QR code.
-- Calls lcd.drawFilledRectangle once per black run (batches consecutive black cells).
local function render_qr(r, origin_x, origin_y)
    local now = os.clock()
    local rows = r.rows
    local cell_size = r.cell_size
    local size = r.size
    local margin = 4
    lcd.color(COLOR_WHITE)
    lcd.drawFilledRectangle(origin_x - margin, origin_y - margin, size * cell_size + 2 * margin, size * cell_size + 2 * margin)
    lcd.color(COLOR_BLACK)
    for y = 1, size do
        local py = origin_y + (y - 1) * cell_size
        local row = rows[y]
        for i = 1, #row, 2 do
            lcd.drawFilledRectangle(origin_x + row[i], py, row[i + 1], cell_size)
        end
    end
    if debug then log("QR render took " .. (os.clock() - now)*1000 .. " ms") end
end

local function paint(widget)
    if not widget then return end
    local w,h = lcd.getWindowSize()
    if widget.qr then
        local cell_size = widget.qr.cell_size
        local size = widget.qr.size
        local x0 = widget.x0 or (w - size * cell_size) / 2
        local text = widget.qrurl
        lcd.font(FONT_S)
        local tw, th = lcd.getTextSize(text)
        local y0 = widget.y0 or (form.height() + (h - size * cell_size - form.height() - th - 10 - 8) / 2)
        render_qr(widget.qr, x0, y0)
        lcd.color(lcd.themeColor(THEME_DEFAULT_COLOR))
        lcd.drawText(x0 + (size * cell_size) / 2, y0 + size * cell_size + 8 + 10, text, TEXT_CENTERED)
    elseif widget.error then
        lcd.color(COLOR_RED)
        lcd.drawText(w/2, h/2, "Error: " .. tostring(widget.error), TEXT_CENTERED)
    else
        lcd.drawText(w/2, h/2, __("findYourModel"), TEXT_CENTERED)
    end
end

local function init()
    system.registerSystemTool({name="GPS QR Code", icon=icon, create=create, wakeup=wakeup, paint=paint})
end

return {init=init}
