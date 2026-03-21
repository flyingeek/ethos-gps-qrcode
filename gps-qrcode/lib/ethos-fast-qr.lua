-- ethos_fast_qr_v2.lua
-- Fast + scannable QR encoder (Lua 5.4, Ethos-safe)

local QR = {}

--==================================================
-- GF(256)
--==================================================
local gf_exp, gf_log = {}, {}
do
  local x = 1
  for i = 0,255 do
    gf_exp[i] = x
    gf_log[x] = i
    x = x << 1
    if x & 0x100 ~= 0 then x = x ~ 0x11d end
  end
  for i=256,511 do gf_exp[i] = gf_exp[i-256] end
end

local function gf_mul(a,b)
  if a==0 or b==0 then return 0 end
  return gf_exp[(gf_log[a]+gf_log[b])%255]
end

--==================================================
-- Versions (L level)
--==================================================
local versions = {
  [1]={size=21,data=19,ecc=7,align=nil},
  [2]={size=25,data=34,ecc=10,align={7,19}},
  [3]={size=29,data=55,ecc=15,align={7,22}},
  [4]={size=33,data=80,ecc=20,align={7,26}},
}

local function max_payload_bytes(v)
  return ((v.data * 8) - 12) // 8
end

local function resolve_version(str, version)
  if type(str) ~= "string" then
    return nil, nil, "payload must be a string"
  end

  if version ~= nil then
    local v = versions[version]
    if not v then
      return nil, nil, "bad version"
    end

    local max_len = max_payload_bytes(v)
    if #str > max_len then
      return nil, nil, "payload too large for version " .. version .. " (" .. #str .. " > " .. max_len .. " bytes)"
    end

    return version, v
  end

  for candidate = 1, 4 do
    local v = versions[candidate]
    if #str <= max_payload_bytes(v) then
      return candidate, v
    end
  end

  return nil, nil, "payload too large for supported QR versions (" .. #str .. " bytes)"
end

--==================================================
-- Bit buffer
--==================================================
local function new_bytes(n)
  local t={} for i=1,n do t[i]=0 end return t
end

local function put_bits(buf,pos,val,count)
  for i=count-1,0,-1 do
    local bit=(val>>i)&1
    local byte=(pos>>3)+1
    local shift=7-(pos&7)
    if bit~=0 then buf[byte]=buf[byte]|(1<<shift) end
    pos=pos+1
  end
  return pos
end

--==================================================
-- Generator cache
--==================================================
local generators={}
local function get_generator(n)
  if generators[n] then return generators[n] end
  local poly={1}
  for i=1,n do
    local next={}
    for j=1,#poly+1 do next[j]=0 end
    for j=1,#poly do
      next[j]=next[j] ~ gf_mul(poly[j], gf_exp[i-1])
      next[j+1]=next[j+1] ~ poly[j]
    end
    poly=next
  end
  generators[n]=poly
  return poly
end

--==================================================
-- Reed-Solomon
--==================================================
local function rs_encode(data,ecc_len)
  local gen=get_generator(ecc_len)
  local res={}
  for i=1,ecc_len do res[i]=0 end

  for i=1,#data do
    local factor=data[i] ~ res[1]
    for j=1,ecc_len-1 do
      res[j]=res[j+1] ~ gf_mul(gen[j],factor)
    end
    res[ecc_len]=gf_mul(gen[ecc_len],factor)
  end
  return res
end

--==================================================
-- Encode bytes
--==================================================
local function encode_bytes(str,v)
  if type(str) ~= "string" then return nil, "payload must be a string" end
  if not v then return nil, "missing version data" end

  local max_len = max_payload_bytes(v)
  if #str > max_len then
    return nil, "payload too large for version capacity (" .. #str .. " > " .. max_len .. " bytes)"
  end

  local max=v.data*8
  local buf=new_bytes(v.data)
  local pos=0

  pos=put_bits(buf,pos,0x4,4)
  pos=put_bits(buf,pos,#str,8)

  for i=1,#str do
    pos=put_bits(buf,pos,str:byte(i),8)
  end

  local remain=max-pos
  if remain>0 then pos=put_bits(buf,pos,0,math.min(4,remain)) end
  while (pos&7)~=0 do pos=put_bits(buf,pos,0,1) end

  local pad={0xEC,0x11}
  local i=1
  while (pos>>3)<v.data do
    buf[(pos>>3)+1]=pad[i]
    pos=pos+8
    i=3-i
  end
  return buf
end

--==================================================
-- Matrix
--==================================================
local function new_matrix(n)
  local m={}
  for y=1,n do
    m[y]={}
    for x=1,n do m[y][x]=-1 end
  end
  return m
end

local function new_reserved(n)
  local reserved={}
  for y=1,n do
    reserved[y]={}
    for x=1,n do reserved[y][x]=false end
  end
  return reserved
end

local function set_function_module(m,reserved,x,y,value)
  if m[y] and m[y][x] ~= nil then
    m[y][x]=value
    reserved[y][x]=true
  end
end

local function add_finder(m,reserved,x,y)
  for dy=-1,7 do
    for dx=-1,7 do
      local xx,yy=x+dx,y+dy
      if m[yy] and m[yy][xx] then
        local v=(dx>=0 and dx<=6 and (dy==0 or dy==6)) or
                (dy>=0 and dy<=6 and (dx==0 or dx==6)) or
                (dx>=2 and dx<=4 and dy>=2 and dy<=4)
        set_function_module(m,reserved,xx,yy,v and 1 or 0)
      end
    end
  end
end

local function add_timing(m,reserved)
  local n=#m
  for i=9,n-8 do
    local b=(i&1)==0 and 1 or 0
    if not reserved[7][i] then set_function_module(m,reserved,i,7,b) end
    if not reserved[i][7] then set_function_module(m,reserved,7,i,b) end
  end
end

local function add_alignment(m,reserved,positions)
  if not positions then return end
  for _,y in ipairs(positions) do
    for _,x in ipairs(positions) do
      if not reserved[y][x] then
        for dy=-2,2 do
          for dx=-2,2 do
            local xx,yy=x+dx,y+dy
            local v=math.max(math.abs(dx),math.abs(dy))~=1
            set_function_module(m,reserved,xx,yy,v and 1 or 0)
          end
        end
      end
    end
  end
end

local function reserve_format_areas(m,reserved)
  local n=#m

  for x=1,6 do set_function_module(m,reserved,x,9,0) end
  set_function_module(m,reserved,8,9,0)
  set_function_module(m,reserved,9,9,0)

  for y=1,6 do set_function_module(m,reserved,9,y,0) end
  set_function_module(m,reserved,9,8,0)
  set_function_module(m,reserved,9,9,0)

  for y=n-6,n do set_function_module(m,reserved,9,y,0) end
  for x=n-7,n do set_function_module(m,reserved,x,9,0) end
end

local function add_dark_module(m,reserved)
  set_function_module(m,reserved,9,#m-7,1)
end

--==================================================
-- Data placement
--==================================================
local function place_data(m,reserved,data)
  local n=#m
  local bit=0
  local dir=-1
  local x=n

  while x>0 do
    if x==7 then x=x-1 end
    for y=(dir==-1 and n or 1),(dir==-1 and 1 or n),dir do
      for dx=0,1 do
        local xx=x-dx
        if not reserved[y][xx] then
          local byte=data[(bit>>3)+1]
          local b=0
          if byte then
            b=(byte>>(7-(bit&7)))&1
          end
          m[y][xx]=b
          bit=bit+1
        end
      end
    end
    x=x-2
    dir=-dir
  end
end

--==================================================
-- Masks
--==================================================
local function mask_bit(mask,x,y)
  x = x - 1
  y = y - 1

  if mask==0 then return ((x+y)&1)==0 end
  if mask==1 then return (y&1)==0 end
  if mask==2 then return (x%3)==0 end
  if mask==3 then return ((x+y)%3)==0 end
  if mask==4 then return (((y>>1)+(x//3))&1)==0 end
  if mask==5 then return ((x*y)%2+(x*y)%3)==0 end
  if mask==6 then return ((((x*y)%2+(x*y)%3)&1)==0) end
  if mask==7 then return ((((x+y)%2+(x*y)%3)&1)==0) end
end

local function apply_mask(m,reserved,mask)
  local n=#m
  for y=1,n do
    for x=1,n do
      if not reserved[y][x] and mask_bit(mask,x,y) then
        m[y][x]=m[y][x] ~ 1
      end
    end
  end
end

--==================================================
-- Penalty (simplified)
--==================================================
local function score(m)
  local n=#m
  local s=0

  for y=1,n do
    local run=1
    for x=2,n do
      if m[y][x]==m[y][x-1] then
        run=run+1
        if run>=5 then s=s+3 end
      else run=1 end
    end
  end

  return s
end

--==================================================
-- Format bits
--==================================================
local format_table={
  [0]="111011111000100",
  [1]="111001011110011",
  [2]="111110110101010",
  [3]="111100010011101",
  [4]="110011000101111",
  [5]="110001100011000",
  [6]="110110001000001",
  [7]="110100101110110",
}

local function add_format(m,reserved,mask)
  local bits=format_table[mask]
  local n=#m

  local function bit_at(index)
    return bits:sub(index,index) == "1" and 1 or 0
  end

  for i=1,7 do set_function_module(m,reserved,9,n-i+1,bit_at(i)) end
  for i=8,9 do set_function_module(m,reserved,9,17-i,bit_at(i)) end
  for i=10,15 do set_function_module(m,reserved,9,16-i,bit_at(i)) end

  for i=1,6 do set_function_module(m,reserved,i,9,bit_at(i)) end
  set_function_module(m,reserved,8,9,bit_at(7))
  for i=8,15 do set_function_module(m,reserved,n-15+i,9,bit_at(i)) end
end

-- Convert QR matrix to 1-bit bitmap
local function matrix_to_render_data(matrix, scale, quiet)
  local size = #matrix
  local rows = {}

  for y = 1, size do
    local row = matrix[y]
    local runs = {}
    local start_x = nil

    for x = 1, size + 1 do
      local is_black = x <= size and row[x] == 1

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

function QR.process_qr_step(widget)
  local job = widget.job
  if not job then return end

  -- STEP 1: encode data
  if job.step == 1 then
    local version, v, err = resolve_version(job.url, job.version)
    if not version then
      print("QR encode error: " .. err)
      widget.job = nil
      widget.bitmap = nil
      return
    end

    job.version = version
    job.v = v
    print("Encoding URL: " .. job.url .. " (version " .. job.version .. ")")

    local data, encode_err = encode_bytes(job.url, job.v)
    if not data then
      print("QR encode error: " .. encode_err)
      widget.job = nil
      widget.bitmap = nil
      return
    end

    job.data = data
    job.step = 2
    return
  end

  -- STEP 2: ECC
  if job.step == 2 then
    job.ecc = rs_encode(job.data, job.v.ecc)

    job.full = {}
    for i=1,#job.data do job.full[#job.full+1]=job.data[i] end
    for i=1,#job.ecc do job.full[#job.full+1]=job.ecc[i] end

    job.step = 3
    return
  end

  -- STEP 3: init mask loop
  if job.step == 3 then
    job.mask = 0
    job.step = 4
    return
  end

  -- STEP 4: process ONE mask per frame
  if job.step == 4 then
    local mask = job.mask

    local m = new_matrix(job.v.size)
    local reserved = new_reserved(job.v.size)

    add_finder(m,reserved,1,1)
    add_finder(m,reserved,job.v.size-6,1)
    add_finder(m,reserved,1,job.v.size-6)
    add_timing(m,reserved)
    add_alignment(m,reserved,job.v.align)
    reserve_format_areas(m,reserved)
    add_dark_module(m,reserved)

    place_data(m, reserved, job.full)
    apply_mask(m, reserved, mask)
    add_format(m, reserved, mask)

    local sc = score(m)

    if sc < job.best_score then
      job.best_score = sc
      job.best_matrix = m
    end

    job.mask = job.mask + 1

    if job.mask > 7 then
      job.step = 5
    end

    return
  end

  -- STEP 5: bitmap conversion
  if job.step == 5 then
    widget.bitmap = nil
    widget.qr = matrix_to_render_data(job.best_matrix, 4, 4)
    job.best_matrix = nil
    job.full = nil
    job.step = 6
    return
  end

  -- STEP 6: GC cleanup
  if job.step == 6 then
    job = nil
    widget.job = nil
    collectgarbage("collect")
    return
  end
end
--==================================================
-- Main
--==================================================
function QR.encode(str,version)
  local _, v, err = resolve_version(str, version)
  if not v then return nil, err end

  local data, encode_err = encode_bytes(str,v)
  if not data then return nil, encode_err end
  local ecc=rs_encode(data,v.ecc)

  local full={}
  for i=1,#data do full[#full+1]=data[i] end
  for i=1,#ecc do full[#full+1]=ecc[i] end

  local best_m,best_score=nil,1e9

  for mask=0,7 do
    local m=new_matrix(v.size)
    local reserved=new_reserved(v.size)

    add_finder(m,reserved,1,1)
    add_finder(m,reserved,v.size-6,1)
    add_finder(m,reserved,1,v.size-6)
    add_timing(m,reserved)
    add_alignment(m,reserved,v.align)
    reserve_format_areas(m,reserved)
    add_dark_module(m,reserved)

    place_data(m,reserved,full)
    apply_mask(m,reserved,mask)
    add_format(m,reserved,mask)

    local sc=score(m)
    if sc<best_score then
      best_score=sc
      best_m=m
    end
  end

  return best_m
end

return {
    QR = QR
}
