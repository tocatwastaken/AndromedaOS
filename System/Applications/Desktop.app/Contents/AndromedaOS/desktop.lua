--Who knew that learning an ENTIRELY NEW gpu standard kinda sucks?
--I didn't when I decided to switch...
--At least it's not AI slop!

local gpu = _G.Darwin.DriverLoader:GetLoadedDriverByName("GPU"):GetGPU()
print("VRAM constraint: " .. gpu.getMaxMemory())
gpu.refreshSize()
gpu.setSize(16)
gpu.fill(255,255,255)
gpu.sync()
local Windows = {}
local Window = {}
Window.__index = Window
function Window:Create(title, x, y, w, h, allow3d)
    local module = {}
    module.__index = module
    local windowContext
    windowContext = gpu.createWindow(x, y, w, h+6)
    local childContext
    if (allow3d) then
        childContext = windowContext.createWindow3D(2,6,w-2,h-4)
    else
        childContext = windowContext.createWindow(2,6,w-2,h-4)
    end
    function module:GetContext()
        return childContext
    end
    function module:Draw()
        local titleLength = 
        windowContext.fill(72,72,72)
        childContext.sync()
        windowContext.sync()
        gpu.sync()
    end
    table.append(Windows, module)
    return module
end

local test = Window:Create("rat", 20,10,52,52)
test:GetContext().fill(0,0,0)
test:Draw()
gpu.sync()