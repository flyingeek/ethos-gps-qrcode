local SpeedataQR = {}

system.compile("lib/qrencode.lua")
local qrencode = assert(loadfile("lib/qrencode.luac", "b", _ENV))()

local function matrix_to_render_data(matrix, scale, quiet)
  local size = #matrix
  local rows = {}

  for y = 1, size do
    local runs = {}
    local start_x = nil

    for x = 1, size + 1 do
      local is_black = x <= size and matrix[x][y] > 0

      if is_black then
        if not start_x then
          start_x = x
        end
      elseif start_x then
        runs[#runs + 1] = {
          x = start_x,
          width = x - start_x,
        }
        start_x = nil
      end
    end

    rows[y] = runs
  end

  local full = size + quiet * 2
  return {
    rows = rows,
    size = size,
    scale = scale,
    quiet = quiet,
    width = full * scale,
    height = full * scale,
  }
end

local function clear_job(widget)
  widget.job = nil
  collectgarbage("collect")
end

function SpeedataQR.process_qr_step(widget)
  local job = widget.job
  if not job then return end

  if job.step == 1 then
    if type(job.url) ~= "string" or job.url == "" then
      print("QR encode error: payload must be a non-empty string")
      widget.bitmap = nil
      widget.qr = nil
      clear_job(widget)
      return
    end

    local ok, matrix_or_err = qrencode.qrcode(job.url, job.ec_level, job.mode)
    if not ok then
      print("QR encode error: " .. matrix_or_err)
      widget.bitmap = nil
      widget.qr = nil
      clear_job(widget)
      return
    end

    job.matrix = matrix_or_err
    job.version = (#job.matrix - 17) // 4
    job.step = 2
    return
  end

  if job.step == 2 then
    widget.bitmap = nil
    widget.qr = matrix_to_render_data(job.matrix, job.scale or 4, job.quiet or 4)
    job.matrix = nil
    job.step = 3
    return
  end

  if job.step == 3 then
    clear_job(widget)
  end
end

function SpeedataQR.encode(str, ec_level, mode)
  local ok, matrix_or_err = qrencode.qrcode(str, ec_level, mode)
  if not ok then return nil, matrix_or_err end
  return matrix_or_err
end

return {
  SpeedataQR = SpeedataQR
}